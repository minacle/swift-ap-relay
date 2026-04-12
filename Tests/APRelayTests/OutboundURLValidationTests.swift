import Testing
@testable import APRelay

@Suite("Outbound URL Validation Tests")
struct OutboundURLValidationTests {

    // MARK: - Scheme Validation

    @Test("HTTPS URL is allowed")
    func httpsAllowed() throws {
        try validateOutboundURL("https://example.com/nodeinfo/2.1", allowedPrivateAddresses: [])
    }

    @Test("HTTP URL is allowed")
    func httpAllowed() throws {
        try validateOutboundURL("http://example.com/nodeinfo/2.1", allowedPrivateAddresses: [])
    }

    @Test("gopher scheme is rejected")
    func gopherRejected() throws {
        #expect {
            try validateOutboundURL("gopher://internal:25/", allowedPrivateAddresses: [])
        } throws: { error in
            guard let e = error as? OutboundURLValidationError,
                  case .disallowedScheme(_, scheme: let scheme) = e else { return false }
            return scheme == "gopher"
        }
    }

    @Test("file scheme is rejected")
    func fileRejected() throws {
        #expect {
            try validateOutboundURL("file:///etc/passwd", allowedPrivateAddresses: [])
        } throws: { error in
            guard let e = error as? OutboundURLValidationError,
                  case .disallowedScheme = e else { return false }
            return true
        }
    }

    @Test("URL without scheme is rejected")
    func noSchemeRejected() {
        #expect(throws: OutboundURLValidationError.self) {
            try validateOutboundURL("example.com/path", allowedPrivateAddresses: [])
        }
    }

    // MARK: - Hostname Validation

    @Test("localhost is rejected")
    func localhostRejected() throws {
        #expect {
            try validateOutboundURL("https://localhost/secret", allowedPrivateAddresses: [])
        } throws: { error in
            guard let e = error as? OutboundURLValidationError,
                  case .reservedHost(_, host: let host) = e else { return false }
            return host == "localhost"
        }
    }

    @Test("subdomain of localhost is rejected")
    func subLocalhostRejected() throws {
        #expect {
            try validateOutboundURL("https://sub.localhost/secret", allowedPrivateAddresses: [])
        } throws: { error in
            guard let e = error as? OutboundURLValidationError,
                  case .reservedHost = e else { return false }
            return true
        }
    }

    @Test("Regular domain is allowed")
    func domainAllowed() throws {
        try validateOutboundURL("https://example.com/nodeinfo/2.1", allowedPrivateAddresses: [])
    }

    // MARK: - IPv4 Private Range Blocking

    @Test("127.0.0.1 (loopback) is rejected")
    func ipv4LoopbackRejected() throws {
        #expect {
            try validateOutboundURL("https://127.0.0.1/secret", allowedPrivateAddresses: [])
        } throws: { error in
            guard let e = error as? OutboundURLValidationError,
                  case .privateAddress(_, host: let host) = e else { return false }
            return host == "127.0.0.1"
        }
    }

    @Test("10.0.0.1 (RFC 1918) is rejected")
    func ipv4Class10Rejected() {
        #expect(throws: OutboundURLValidationError.self) {
            try validateOutboundURL("https://10.0.0.1/admin", allowedPrivateAddresses: [])
        }
    }

    @Test("172.16.0.1 (RFC 1918) is rejected")
    func ipv4Class172Rejected() {
        #expect(throws: OutboundURLValidationError.self) {
            try validateOutboundURL("https://172.16.0.1/admin", allowedPrivateAddresses: [])
        }
    }

    @Test("192.168.1.1 (RFC 1918) is rejected")
    func ipv4Class192Rejected() {
        #expect(throws: OutboundURLValidationError.self) {
            try validateOutboundURL("https://192.168.1.1/admin", allowedPrivateAddresses: [])
        }
    }

    @Test("169.254.169.254 (link-local) is rejected")
    func ipv4LinkLocalRejected() {
        #expect(throws: OutboundURLValidationError.self) {
            try validateOutboundURL("https://169.254.169.254/meta-data", allowedPrivateAddresses: [])
        }
    }

    @Test("0.0.0.1 (current network) is rejected")
    func ipv4CurrentNetworkRejected() {
        #expect(throws: OutboundURLValidationError.self) {
            try validateOutboundURL("https://0.0.0.1/path", allowedPrivateAddresses: [])
        }
    }

    @Test("8.8.8.8 (public) is allowed")
    func ipv4PublicAllowed() throws {
        try validateOutboundURL("https://8.8.8.8/path", allowedPrivateAddresses: [])
    }

    @Test("93.184.216.34 (public) is allowed")
    func ipv4PublicAllowed2() throws {
        try validateOutboundURL("https://93.184.216.34/nodeinfo/2.1", allowedPrivateAddresses: [])
    }

    // MARK: - IPv6 Private Range Blocking

    @Test("::1 (loopback) is rejected")
    func ipv6LoopbackRejected() throws {
        #expect {
            try validateOutboundURL("https://[::1]/secret", allowedPrivateAddresses: [])
        } throws: { error in
            guard let e = error as? OutboundURLValidationError,
                  case .privateAddress = e else { return false }
            return true
        }
    }

    @Test("fc00::1 (unique local) is rejected")
    func ipv6UniqueLocalRejected() {
        #expect(throws: OutboundURLValidationError.self) {
            try validateOutboundURL("https://[fc00::1]/admin", allowedPrivateAddresses: [])
        }
    }

    @Test("fe80::1 (link-local) is rejected")
    func ipv6LinkLocalRejected() {
        #expect(throws: OutboundURLValidationError.self) {
            try validateOutboundURL("https://[fe80::1]/admin", allowedPrivateAddresses: [])
        }
    }

    @Test("2606:4700::1 (public) is allowed")
    func ipv6PublicAllowed() throws {
        try validateOutboundURL("https://[2606:4700::1]/nodeinfo/2.1", allowedPrivateAddresses: [])
    }

    // MARK: - ALLOWED_PRIVATE_ADDRESSES Exceptions

    @Test("Private IPv4 allowed by CIDR exception")
    func ipv4AllowedByCIDR() throws {
        try validateOutboundURL("https://10.0.0.5/nodeinfo/2.1", allowedPrivateAddresses: ["10.0.0.0/8"])
    }

    @Test("Private IPv4 allowed by subnet exception")
    func ipv4AllowedBySubnet() throws {
        try validateOutboundURL("https://192.168.1.1/nodeinfo/2.1", allowedPrivateAddresses: ["192.168.1.0/24"])
    }

    @Test("Private IPv4 rejected when outside allowed subnet")
    func ipv4RejectedOutsideSubnet() throws {
        #expect {
            try validateOutboundURL("https://192.168.2.1/admin", allowedPrivateAddresses: ["192.168.1.0/24"])
        } throws: { error in
            guard let e = error as? OutboundURLValidationError,
                  case .privateAddress(_, host: let host) = e else { return false }
            return host == "192.168.2.1"
        }
    }

    @Test("Private IPv6 allowed by CIDR exception")
    func ipv6AllowedByCIDR() throws {
        try validateOutboundURL("https://[::1]/nodeinfo/2.1", allowedPrivateAddresses: ["::1/128"])
    }

    // MARK: - Malformed URLs

    @Test("Empty string is rejected")
    func emptyStringRejected() throws {
        #expect {
            try validateOutboundURL("", allowedPrivateAddresses: [])
        } throws: { error in
            guard let e = error as? OutboundURLValidationError,
                  case .invalidURL = e else { return false }
            return true
        }
    }

    @Test("Invalid URL is rejected")
    func invalidURLRejected() throws {
        #expect {
            try validateOutboundURL("not a url", allowedPrivateAddresses: [])
        } throws: { error in
            error is OutboundURLValidationError
        }
    }
}
