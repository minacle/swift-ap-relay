import Fluent
import Vapor

struct UnblockCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to unblock")
        var domain: String
    }

    var help: String { "Unblock a domain" }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application

        guard
            let blocked = try await BlockedDomain.query(on: app.db)
                .filter(\.$domain == signature.domain)
                .first()
        else {
            context.console.print("Domain not blocked: \(signature.domain)")
            return
        }

        try await blocked.delete(on: app.db)
        context.console.print("Unblocked: \(signature.domain)")
    }
}
