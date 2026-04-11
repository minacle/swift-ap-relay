import Vapor

struct UnblockCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "domain", help: "Domain to unblock")
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

    var help: String { "Unblock a domain" }

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
