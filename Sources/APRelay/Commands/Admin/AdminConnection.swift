import APRelayCore

/// Connection parameters for admin commands to reach the relay server.
struct AdminConnection: Sendable {
    let url: String?
    let hostname: String?
    let port: Int?
    let tls: Bool
    let unixSocket: String?

    /// Resolves the admin API base URL.
    ///
    /// Priority: `--url` > individual flags (`-H`/`-p`/`--tls`) > `config.baseURL`
    func resolvedBaseURL(config: RelayConfiguration) -> String {
        if let url {
            return url.hasSuffix("/") ? String(url.dropLast()) : url
        }
        if let hostname {
            let scheme = tls ? "https" : "http"
            if let port { return "\(scheme)://\(hostname):\(port)" }
            return "\(scheme)://\(hostname)"
        }
        return config.baseURL
    }
}
