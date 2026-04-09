import Fluent
import Vapor

struct AcceptCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to accept")
        var domain: String
    }

    var help: String { "Accept a pending subscriber" }

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

        guard subscriber.state == .pending else {
            context.console.print(
                "Subscriber is not pending (current state: \(subscriber.state.rawValue))"
            )
            return
        }

        subscriber.state = .accepted
        try await subscriber.save(on: app.db)

        try await app.deliveryService.sendAccept(
            to: subscriber.inboxURL,
            followActivityID: subscriber.followActivityID,
            followerActorID: subscriber.actorID,
            followObjectURI: subscriber.followObjectURI
        )

        context.console.print("Accepted: \(signature.domain)")
    }
}
