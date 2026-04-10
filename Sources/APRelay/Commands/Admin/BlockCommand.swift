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
        do {
            let client = try AdminAPIClient(app: context.application)
            let response = try await client.blockDomain(
                signature.domain,
                reason: signature.reason
            )
            context.console.print("Blocked: \(response.domain)")
        } catch let error as AdminAPIError where error.isConflict {
            context.console.error("Domain already blocked: \(signature.domain)")
        } catch let error as AdminAPIError {
            context.console.error(error.description)
        } catch {
            context.console.error("Unexpected error: \(error)")
        }
    }
}
