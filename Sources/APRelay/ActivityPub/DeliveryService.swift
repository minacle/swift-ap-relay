import APRelayCore
import _CryptoExtras
import Dispatch
import Foundation
import Logging
import Metrics
import Tracing
import Vapor

/// Service for delivering signed ActivityPub activities to remote inboxes.
actor DeliveryService {
    private let client: Client
    private let config: RelayConfiguration
    private let privateKey: _RSA.Signing.PrivateKey
    private let httpSignature = HTTPSignature()
    private let logger: Logger

    private static let maxRetries = 5

    // Metrics
    private let deliverySuccessCounter = Counter(
        label: "relay_delivery_total",
        dimensions: [("result", "success")]
    )
    private let deliveryFailureCounter = Counter(
        label: "relay_delivery_total",
        dimensions: [("result", "failure")]
    )
    private let deliveryDuration = Metrics.Timer(label: "relay_delivery_duration_seconds")

    // Graceful shutdown: track in-flight tasks.
    private var inFlightCount = 0
    private var shutdownContinuation: CheckedContinuation<Void, Never>?

    init(
        client: Client,
        config: RelayConfiguration,
        privateKey: _RSA.Signing.PrivateKey,
        logger: Logger
    ) {
        self.client = client
        self.config = config
        self.privateKey = privateKey
        self.logger = logger
    }

    /// Delivers a JSON-encoded activity to a single inbox with retry.
    func deliver(activity: Data, to inboxURL: String) async {
        let start = DispatchTime.now()

        for attempt in 0...Self.maxRetries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
            do {
                try await withSpan("delivery.send") { span in
                    span.attributes["delivery.inbox"] = inboxURL
                    span.attributes["delivery.attempt"] = attempt + 1
                    try await sendRequest(body: activity, to: inboxURL)
                }
                deliverySuccessCounter.increment()
                deliveryDuration.recordInterval(since: start)
                logger.info("Delivered to \(inboxURL)")
                return
            } catch let error as DeliveryError {
                if case .httpError(let code, _) = error, !shouldRetry(statusCode: code) {
                    logger.warning(
                        "Non-retryable HTTP \(code) for \(inboxURL), giving up"
                    )
                    break
                }
                logger.warning(
                    "Delivery attempt \(attempt + 1) failed for \(inboxURL): \(error)"
                )
            } catch {
                logger.warning(
                    "Delivery attempt \(attempt + 1) failed for \(inboxURL): \(error)"
                )
            }
        }
        deliveryFailureCounter.increment()
        deliveryDuration.recordInterval(since: start)
        logger.error("Delivery exhausted retries for \(inboxURL)")
    }

    /// Whether a failed HTTP status code is worth retrying.
    private func shouldRetry(statusCode: UInt) -> Bool {
        if (400...499).contains(statusCode) {
            // Only retry specific client errors that may be transient.
            return [401, 408, 429].contains(statusCode)
        }
        return true
    }

    /// Delivers an activity to multiple inboxes in parallel, excluding the specified origin.
    func broadcast(
        activity: Data,
        to inboxURLs: [String],
        excluding origin: String? = nil
    ) async {
        inFlightCount += 1
        defer { taskCompleted() }

        await withTaskGroup { group in
            for inbox in inboxURLs where inbox != origin {
                group.addTask {
                    await self.deliver(activity: activity, to: inbox)
                }
            }
        }
    }

    /// Waits for all in-flight deliveries to complete.
    func waitForInFlight() async {
        guard inFlightCount > 0 else { return }
        await withCheckedContinuation { continuation in
            shutdownContinuation = continuation
        }
    }

    private func taskCompleted() {
        inFlightCount -= 1
        if inFlightCount == 0, let continuation = shutdownContinuation {
            shutdownContinuation = nil
            continuation.resume()
        }
    }

    /// Sends an Accept activity in response to a Follow.
    func sendAccept(
        to inboxURL: String,
        followActivityID: String,
        followerActorID: String,
        followObjectURI: String? = nil
    ) async throws {
        let objectURI = followObjectURI
            ?? "https://www.w3.org/ns/activitystreams#Public"

        let accept = APActivity(
            context: .default,
            id: "\(config.baseURL)/activities/\(UUID().uuidString)",
            type: "Accept",
            actor: config.actorURL,
            object: .activity(APActivity(
                context: nil,
                id: followActivityID,
                type: "Follow",
                actor: followerActorID,
                object: .uri(objectURI),
                to: nil,
                cc: nil,
                published: nil
            )),
            to: .single(followerActorID),
            cc: nil,
            published: ISO8601DateFormatter().string(from: Date())
        )

        let data = try JSONEncoder().encode(accept)
        try await sendRequest(body: data, to: inboxURL)
    }

    /// Sends a Reject activity in response to a Follow.
    func sendReject(
        to inboxURL: String,
        followActivityID: String,
        followerActorID: String,
        followObjectURI: String? = nil
    ) async throws {
        let objectURI = followObjectURI
            ?? "https://www.w3.org/ns/activitystreams#Public"

        let reject = APActivity(
            context: .default,
            id: "\(config.baseURL)/activities/\(UUID().uuidString)",
            type: "Reject",
            actor: config.actorURL,
            object: .activity(APActivity(
                context: nil,
                id: followActivityID,
                type: "Follow",
                actor: followerActorID,
                object: .uri(objectURI),
                to: nil,
                cc: nil,
                published: nil
            )),
            to: .single(followerActorID),
            cc: nil,
            published: ISO8601DateFormatter().string(from: Date())
        )

        let data = try JSONEncoder().encode(reject)
        try await sendRequest(body: data, to: inboxURL)
    }

    /// Sends a signed HTTP POST to a remote inbox.
    private func sendRequest(body: Data, to inboxURL: String) async throws {
        guard let url = URL(string: inboxURL) else {
            throw DeliveryError.invalidURL(inboxURL)
        }

        let path = url.path + (url.query.map { "?\($0)" } ?? "")
        let host = url.host() ?? ""
        let keyID = "\(config.actorURL)#main-key"

        let headers = httpSignature.sign(
            method: "post",
            path: path,
            host: host,
            body: body,
            privateKey: privateKey,
            keyID: keyID
        )

        let uri = URI(string: inboxURL)
        let response = try await client.post(uri) { req in
            for (name, value) in headers {
                req.headers.replaceOrAdd(name: name, value: value)
            }
            req.body = ByteBuffer(data: body)
        }

        guard (200...299).contains(response.status.code) else {
            throw DeliveryError.httpError(response.status.code, inboxURL)
        }
    }
}

enum DeliveryError: Error {
    case invalidURL(String)
    case httpError(UInt, String)
}

// MARK: - App Storage for DeliveryService

private struct DeliveryServiceKey: StorageKey {
    typealias Value = DeliveryService
}

extension Application {
    var deliveryService: DeliveryService {
        get {
            guard let service = storage[DeliveryServiceKey.self] else {
                fatalError("DeliveryService not configured.")
            }
            return service
        }
        set {
            storage[DeliveryServiceKey.self] = newValue
        }
    }
}

extension Request {
    var deliveryService: DeliveryService {
        application.deliveryService
    }
}
