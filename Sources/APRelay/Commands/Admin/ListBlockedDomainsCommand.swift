import Vapor

struct ListBlockedDomainsCommand: AsyncCommand {
    struct Signature: CommandSignature {}

    var help: String { "List all blocked domains" }

    func run(using context: CommandContext, signature: Signature) async throws {
        do {
            let client = try AdminAPIClient(app: context.application)
            let domains = try await client.listBlockedDomains()
            if domains.isEmpty {
                context.console.print("No blocked domains found.")
            } else {
                for domain in domains {
                    let reason = domain.reason ?? "-"
                    context.console.print("\(domain.domain)\t\(reason)")
                }
            }
        } catch let error as AdminAPIError {
            context.console.error(error.description)
        } catch {
            context.console.error("Unexpected error: \(error)")
        }
    }
}
