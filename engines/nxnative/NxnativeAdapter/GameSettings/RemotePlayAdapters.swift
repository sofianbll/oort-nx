import Darwin
import NXLibraryCore
import SystemConfiguration

public struct RemotePlayAdapters: Equatable, Sendable {
    public enum Connection: Equatable {
        case connected(name: String, ipv4: String), disconnected, ignored, ambiguous
    }

    private var addresses: [String: UInt32] = [:]
    var reportedProviders: [String: MultiplayerVPN] = [:]
    private var zeroTier: Set<String> { names { $0.hasPrefix("feth") || $0.hasPrefix("zt") } }
    public var interfaceNames: [String] { addresses.keys.sorted() }
    var localInterface: String? {
        let candidates = names { $0.hasPrefix("en") }
        return candidates.count == 1 ? candidates.first : nil
    }

    public init() {}

    mutating func consider(_ name: String, flags: UInt32, ipv4: UInt32) {
        guard flags & UInt32(IFF_UP | IFF_LOOPBACK) == UInt32(IFF_UP),
              ipv4 != 0, ipv4 >> 16 != 0xa9fe else { return }
        addresses[name] = min(addresses[name] ?? ipv4, ipv4)
    }

    private func names(_ filter: (String) -> Bool) -> Set<String> {
        Set(addresses.keys.filter(filter))
    }

    public func connection(for vpn: MultiplayerVPN, manual: String?) -> Connection {
        if let manual { return connected(manual) ?? .disconnected }
        // 100.64.0.0/10 is shared by Tailscale and NetBird on Darwin.
        let shared = names { $0.hasPrefix("utun") && addresses[$0, default: 0] & 0xffc00000 == 0x64400000 }
        let privateTunnels = names { name in
            let a = addresses[name, default: 0]
            return (name.hasPrefix("wt") || name.hasPrefix("utun")) && (a & 0xffc00000 == 0x64400000
                || a >> 24 == 10 || a >> 20 == 0xac1 || a >> 16 == 0xc0a8)
        }
        let wireTrustee = privateTunnels.filter { $0.hasPrefix("wt") }
        let otherTunnels = names { $0.hasPrefix("utun") || $0.hasPrefix("wg") || $0.hasPrefix("tun") }
        let candidates: Set<String>
        switch vpn {
        case .none: return .disconnected
        case .zeroTier: candidates = zeroTier
        case .tailscale:
            candidates = shared.filter { reportedProviders[$0] == .tailscale }
            if candidates.isEmpty && shared.contains(where: { reportedProviders[$0] == nil }) { return .ambiguous }
        case .netBird:
            candidates = wireTrustee.union(privateTunnels.filter { reportedProviders[$0] == .netBird })
            if candidates.isEmpty && privateTunnels.contains(where: { reportedProviders[$0] == nil }) { return .ambiguous }
        }
        if candidates.count > 1 { return .ambiguous }
        if let name = candidates.first { return connected(name) ?? .disconnected }
        return zeroTier.union(wireTrustee).union(otherTunnels).isEmpty ? .disconnected : .ignored
    }

    private func connected(_ name: String) -> Connection? {
        addresses[name].map { address in
            .connected(name: name, ipv4: [24, 16, 8, 0].map { String((address >> $0) & 255) }.joined(separator: "."))
        }
    }

    public static func current() -> Self {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return Self() }
        defer { freeifaddrs(list) }
        var adapters = Self()
        var cursor = list
        while let entry = cursor?.pointee {
            cursor = entry.ifa_next
            guard let address = entry.ifa_addr, address.pointee.sa_family == AF_INET else { continue }
            let ipv4 = UInt32(bigEndian: UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr)
            adapters.consider(String(cString: entry.ifa_name), flags: entry.ifa_flags, ipv4: ipv4)
        }
        if adapters.addresses.keys.contains(where: { $0.hasPrefix("utun") }) { adapters.readReportedProviders() }
        return adapters
    }

    private mutating func readReportedProviders() {
        guard let store = SCDynamicStoreCreate(nil, "Arcane VPN status" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "Setup:/Network/Service/[^/]+/VPN" as CFString) as? [String]
        else { return }
        var claims: [String: Set<MultiplayerVPN>] = [:]
        for key in keys {
            guard let setup = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let provider = setup["NEProviderBundleIdentifier"] as? String ?? setup["ProviderBundleIdentifier"] as? String
            else { continue }
            let service = "State:" + key.dropFirst("Setup:".count).dropLast("/VPN".count)
            let vpn: MultiplayerVPN = provider.hasPrefix("io.tailscale.") ? .tailscale
                : provider.hasPrefix("io.netbird.") ? .netBird : .none
            for kind in ["IPv4", "DNS"] {
                guard let state = SCDynamicStoreCopyValue(store, "\(service)/\(kind)" as CFString) as? [String: Any],
                      let name = state["InterfaceName"] as? String, name.hasPrefix("utun"), addresses[name] != nil
                else { continue }
                claims[name, default: []].insert(vpn)
            }
        }
        reportedProviders = claims.compactMapValues { $0.count == 1 ? $0.first : nil }
    }
}
