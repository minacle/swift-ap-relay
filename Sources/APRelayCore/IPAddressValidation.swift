import Foundation

// MARK: - Private IPv4 Detection

/// Returns `true` if the given IPv4 address belongs to a private or reserved range.
///
/// Blocked ranges:
/// - `0.0.0.0/8` (current network)
/// - `10.0.0.0/8` (RFC 1918)
/// - `127.0.0.0/8` (loopback)
/// - `169.254.0.0/16` (link-local)
/// - `172.16.0.0/12` (RFC 1918)
/// - `192.168.0.0/16` (RFC 1918)
package func isPrivateIPv4(_ addr: in_addr) -> Bool {
    let ip = UInt32(bigEndian: addr.s_addr)
    let byte1 = UInt8((ip >> 24) & 0xFF)
    let byte2 = UInt8((ip >> 16) & 0xFF)

    if byte1 == 0 { return true }
    if byte1 == 10 { return true }
    if byte1 == 127 { return true }
    if byte1 == 169 && byte2 == 254 { return true }
    if byte1 == 172 && (byte2 >= 16 && byte2 <= 31) { return true }
    if byte1 == 192 && byte2 == 168 { return true }

    return false
}

// MARK: - Private IPv6 Detection

/// Returns `true` if the given IPv6 address belongs to a private or reserved range.
///
/// Blocked ranges:
/// - `::` (unspecified)
/// - `::1` (loopback)
/// - `fc00::/7` (unique local)
/// - `fe80::/10` (link-local)
package func isPrivateIPv6(_ addr: in6_addr) -> Bool {
    let bytes = unsafe withUnsafeBytes(of: addr) { buf in unsafe Array(buf) }

    // :: (unspecified)
    if bytes.allSatisfy({ $0 == 0 }) { return true }

    // ::1 (loopback)
    if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }

    // fc00::/7 (unique local)
    if bytes[0] & 0xFE == 0xFC { return true }

    // fe80::/10 (link-local)
    if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 { return true }

    return false
}

// MARK: - CIDR Allowlist Matching

/// Returns `true` if the given IP address string matches any CIDR in the allowlist.
///
/// Supports both IPv4 and IPv6 CIDR notation (e.g. `"10.0.0.0/8"`, `"fc00::/7"`).
/// A bare address without prefix length is treated as a host route (`/32` or `/128`).
package func isAddressAllowed(_ host: String, in allowedCIDRs: [String]) -> Bool {
    for cidr in allowedCIDRs {
        let parts = cidr.split(separator: "/", maxSplits: 1)
        let networkStr = String(parts[0])

        // Try IPv4
        var network4 = in_addr()
        var addr4 = in_addr()
        let net4OK = unsafe inet_pton(AF_INET, networkStr, &network4) == 1
        let addr4OK = unsafe inet_pton(AF_INET, host, &addr4) == 1
        if net4OK && addr4OK {
            let prefixLen = parts.count > 1 ? (Int(parts[1]) ?? 32) : 32
            let mask: UInt32 = prefixLen == 0 ? 0 : ~UInt32(0) << (32 - prefixLen)
            let networkIP = UInt32(bigEndian: network4.s_addr)
            let addrIP = UInt32(bigEndian: addr4.s_addr)
            if (networkIP & mask) == (addrIP & mask) {
                return true
            }
            continue
        }

        // Try IPv6
        var network6 = in6_addr()
        var addr6 = in6_addr()
        let net6OK = unsafe inet_pton(AF_INET6, networkStr, &network6) == 1
        let addr6OK = unsafe inet_pton(AF_INET6, host, &addr6) == 1
        if net6OK && addr6OK {
            let prefixLen = parts.count > 1 ? (Int(parts[1]) ?? 128) : 128
            let networkBytes = unsafe withUnsafeBytes(of: network6) { buf in unsafe Array(buf) }
            let addrBytes = unsafe withUnsafeBytes(of: addr6) { buf in unsafe Array(buf) }
            var match = true
            for i in 0..<16 {
                let bits = min(max(prefixLen - i * 8, 0), 8)
                if bits == 0 { break }
                let byteMask: UInt8 = bits == 8 ? 0xFF : UInt8(truncatingIfNeeded: 0xFF << (8 - bits))
                if (networkBytes[i] & byteMask) != (addrBytes[i] & byteMask) {
                    match = false
                    break
                }
            }
            if match { return true }
        }
    }
    return false
}
