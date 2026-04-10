import Vapor

struct UnblockCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to unblock")
        var domain: String
    }

    var help: String { "Unblock a domain" }

    func run(using context: CommandContext, signature: Signature) async throws {
        do {
            let client = try AdminAPIClient(app: context.application)
            let response = try await client.unblockDomain(signature.domain)
            context.console.print("Unblocked: \(response.domain)")
        } catch let error as AdminAPIError where error.isNotFound {
            context.console.error("Domain not blocked: \(signature.domain)")
        } catch let error as AdminAPIError {
            context.console.error(error.description)
        } catch {
            context.console.error("Unexpected error: \(error)")
        }
    }
}
