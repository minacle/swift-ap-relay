import Fluent
import Vapor

struct RejectCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to reject")
        var domain: String
    }

    var help: String { "Reject a pending subscriber" }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application

        guard
            let subscriber = try await Subscriber.query(on: app.db)
                .filter(\.$domain == signature.domain)
                .first()
        else {
            context.console.print("Subscriber not found: \(signature.domain)")
            return
        }

        subscriber.state = .rejected
        try await subscriber.save(on: app.db)

        try await app.deliveryService.sendReject(
            to: subscriber.inboxURL,
            followActivityID: subscriber.followActivityID,
            followerActorID: subscriber.actorID,
            followObjectURI: subscriber.followObjectURI
        )

        context.console.print("Rejected: \(signature.domain)")
    }
}
