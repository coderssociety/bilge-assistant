import Foundation

/// Whether an IP address is on the public internet. Fetching tools refuse everything else, so a web
/// page cannot make the assistant probe the router, the LM Studio server or other local services.
public enum NetworkAddress {
    public static func isPublic(_ address: String) -> Bool {
        if let octets = ipv4(address) { return isPublicIPv4(octets) }
        guard let groups = ipv6(address) else { return false }
        let embeddedIPv4 = [groups[6] >> 8, groups[6] & 0xFF, groups[7] >> 8, groups[7] & 0xFF].map { Int($0) }
        if groups[0..<5].allSatisfy({ $0 == 0 }) && groups[5] == 0xFFFF { return isPublicIPv4(embeddedIPv4) }
        // NAT64 (64:ff9b::/96) reaches IPv4 hosts from IPv6-only networks, private ones included.
        if groups[0] == 0x64, groups[1] == 0xFF9B, groups[2..<6].allSatisfy({ $0 == 0 }) { return isPublicIPv4(embeddedIPv4) }
        if groups.allSatisfy({ $0 == 0 }) || groups[0..<7].allSatisfy({ $0 == 0 }) { return false }
        let first = groups[0]
        if first & 0xFE00 == 0xFC00 { return false }  // unique local fc00::/7
        if first & 0xFFC0 == 0xFE80 { return false }  // link-local fe80::/10
        if first & 0xFFC0 == 0xFEC0 { return false }  // deprecated site-local fec0::/10
        if first & 0xFF00 == 0xFF00 { return false }  // multicast
        return true
    }

    /// A URL's host that may be reached: an IP literal on the public internet, or a name that is not a local one.
    /// The address a name resolves to still has to be checked when connecting.
    public static func isPublicHost(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !bare.isEmpty else { return false }
        let isIPLiteral = bare.contains(":") || Int(bare.split(separator: ".").last ?? "") != nil
        return isIPLiteral ? isPublic(bare) : !isLocalName(bare)
    }

    /// Host names that never leave the machine or the local network.
    public static func isLocalName(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == "localhost" || ["local", "localhost", "internal", "lan", "home", "arpa"].contains { host.hasSuffix(".\($0)") }
            || !host.contains(".")
    }

    private static func isPublicIPv4(_ o: [Int]) -> Bool {
        switch (o[0], o[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168), (224...255, _): return false
        case (172, 16...31), (100, 64...127), (192, 0), (198, 18...19): return false
        default: return true
        }
    }

    private static func ipv4(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }.filter { (0...255).contains($0) }
        return octets.count == 4 ? octets : nil
    }

    private static func ipv6(_ text: String) -> [UInt16]? {
        var address = text.split(separator: "%").first.map(String.init) ?? text
        guard address.contains(":") else { return nil }
        // An embedded IPv4 tail ("::ffff:8.8.8.8") becomes two hex groups.
        if let colon = address.lastIndex(of: ":"), let octets = ipv4(String(address[address.index(after: colon)...])) {
            address = address[...colon] + String(octets[0] << 8 | octets[1], radix: 16) + ":" + String(octets[2] << 8 | octets[3], radix: 16)
        }
        let halves = address.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        func groups(_ part: String) -> [UInt16]? {
            guard !part.isEmpty else { return [] }
            let values = part.split(separator: ":", omittingEmptySubsequences: false).map { UInt16($0, radix: 16) }
            return values.contains(nil) ? nil : values.compactMap { $0 }
        }
        guard let head = groups(halves[0]), head.count <= 8 else { return nil }
        guard let tail = halves.count == 2 ? groups(halves[1]) : [] else { return nil }
        let missing = 8 - head.count - tail.count
        guard halves.count == 2 ? missing >= 1 : missing == 0 else { return nil }
        return head + Array(repeating: 0, count: missing) + tail
    }
}
