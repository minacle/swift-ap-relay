import Vapor

struct AcceptCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to accept")
        var domain: String
    }

    var help: String { "Accept a pending subscriber" }

    func run(using context: CommandContext, signature: Signature) async throws {
        do {
            let client = try AdminAPIClient(app: context.application)
            let response = try await client.acceptSubscriber(domain: signature.domain)
            context.console.print("Accepted: \(response.domain)")
        } catch let error as AdminAPIError {
            context.console.error(error.description)
        } catch {
            context.console.error("Unexpected error: \(error)")
        }
    }
}
