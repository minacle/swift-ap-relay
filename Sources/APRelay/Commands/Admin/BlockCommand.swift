import Vapor

struct BlockCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to block")
        var domain: String

        @Option(name: "reason", help: "Reason for blocking")
        var reason: String?

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

    var help: String { "Block a domain" }

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
