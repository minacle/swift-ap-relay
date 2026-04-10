import Vapor

struct ListSubscribersCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "state", short: "s", help: "Filter by state: pending, accepted, rejected")
        var state: String?
    }

    var help: String { "List all subscribers" }

    func run(using context: CommandContext, signature: Signature) async throws {
        if let state = signature.state, SubscriberState(rawValue: state) == nil {
            context.console.error("Invalid state: \(state). Must be one of: pending, accepted, rejected")
            return
        }

        do {
            let client = try AdminAPIClient(app: context.application)
            let subscribers = try await client.listSubscribers(state: signature.state)
            if subscribers.isEmpty {
                context.console.print("No subscribers found.")
            } else {
                for subscriber in subscribers {
                    context.console.print(
                        "\(subscriber.domain)\t\(subscriber.state.rawValue)\t\(subscriber.inboxURL)"
                    )
                }
            }
        } catch let error as AdminAPIError {
            context.console.error(error.description)
        } catch {
            context.console.error("Unexpected error: \(error)")
        }
    }
}
