import Vapor

struct RejectCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to reject")
        var domain: String

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

    var help: String { "Reject a pending subscriber" }

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
            let response = try await client.rejectSubscriber(domain: signature.domain)
            context.console.print("Rejected: \(response.domain)")
        } catch let error as AdminAPIError {
            context.console.error(error.description)
        } catch {
            context.console.error("Unexpected error: \(error)")
        }
    }
}
