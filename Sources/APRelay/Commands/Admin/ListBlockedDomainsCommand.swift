import Vapor

struct ListBlockedDomainsCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "url", help: "Admin API URL (e.g., https://host:port/path)")
        var url: String?
        @Option(name: "hostname", short: "H", help: "Admin API hostname")
        var hostname: String?
        @Option(name: "port", short: "p", help: "Admin API port")
        var port: Int?
        @Flag(name: "tls", help: "Use HTTPS")
        var tls: Bool
        @Option(name: "unix-socket", help: "Unix domain socket path")
        var unixSocket: String?
    }

    var help: String { "List all blocked domains" }

    func run(using context: CommandContext, signature: Signature) async throws {
        let connection = AdminConnection(
            url: signature.url,
            hostname: signature.hostname,
            port: signature.port,
            tls: signature.tls,
            unixSocket: signature.unixSocket
        )
        do {
            let client = try AdminAPIClient(app: context.application, connection: connection)
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
