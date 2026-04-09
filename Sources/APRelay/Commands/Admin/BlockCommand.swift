import Fluent
import Vapor

struct BlockCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to block")
        var domain: String

        @Option(name: "reason", help: "Reason for blocking")
        var reason: String?
    }

    var help: String { "Block a domain" }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application

        let existing = try await BlockedDomain.query(on: app.db)
            .filter(\.$domain == signature.domain)
            .first()

        if existing != nil {
            context.console.print("Domain already blocked: \(signature.domain)")
            return
        }

        let blocked = BlockedDomain(domain: signature.domain, reason: signature.reason)
        try await blocked.save(on: app.db)

        if let subscriber = try await Subscriber.query(on: app.db)
            .filter(\.$domain == signature.domain)
            .first()
        {
            try await subscriber.delete(on: app.db)
            context.console.print("Removed existing subscriber: \(signature.domain)")
        }

        context.console.print("Blocked: \(signature.domain)")
    }
}
