import Fluent
import Vapor

struct ListSubscribersCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "state", short: "s", help: "Filter by state: pending, accepted, rejected")
        var state: String?
    }

    var help: String { "List all subscribers" }

    func run(using context: CommandContext, signature: Signature) async throws {
        var query = Subscriber.query(on: context.application.db)
        if let state = signature.state, let filter = SubscriberState(rawValue: state) {
            query = query.filter(\.$state == filter)
        }

        let subscribers = try await query.all()
        if subscribers.isEmpty {
            context.console.print("No subscribers found.")
        } else {
            for subscriber in subscribers {
                context.console.print(
                    "\(subscriber.domain)\t\(subscriber.state.rawValue)\t\(subscriber.inboxURL)"
                )
            }
        }
    }
}
