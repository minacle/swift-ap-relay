import Vapor

struct RejectCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to reject")
        var domain: String
    }

    var help: String { "Reject a pending subscriber" }

    func run(using context: CommandContext, signature: Signature) async throws {
        do {
            let client = try AdminAPIClient(app: context.application)
            let response = try await client.rejectSubscriber(domain: signature.domain)
            context.console.print("Rejected: \(response.domain)")
        } catch let error as AdminAPIError {
            context.console.error(error.description)
        } catch {
            context.console.error("Unexpected error: \(error)")
        }
    }
}
