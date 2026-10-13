import Darwin
import Foundation
import FoundationModels

struct SystemInfoTool: AssistantTool {
    let name = "systemInfo"
    let description = "Mac'in durumunu söyler: boş disk alanı, bellek kullanımı, ne zamandır açık olduğu, macOS sürümü, Wi-Fi ve IP adresi."

    @Generable
    enum Topic {
        case disk, memory, uptime, osVersion, network
    }

    @Generable
    struct Arguments {
        @Guide(description: "İstenen bilgi")
        var topic: Topic
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.topic {
        case .disk: Self.disk()
        case .memory: Self.memory()
        case .uptime: Self.uptime()
        case .osVersion: "Bu Mac'te \(Self.osVersion()) çalışıyor."
        case .network: await Self.network()
        }
    }

    private static func disk() -> String {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(filePath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity
        else { return ToolReply.failure("Disk bilgisini okuyamadım.") }
        return "Diskte \(gigabytes(free)) GB boş yer var, toplam \(gigabytes(Int64(total))) GB."
    }

    private static func memory() -> String {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return "Bu Mac'te \(gibibytes(total)) GB bellek var." }
        let page = Int64(getpagesize())
        let used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return "\(gibibytes(total)) GB belleğin yaklaşık \(gibibytes(used)) GB'ı kullanımda."
    }

    private static func uptime() -> String {
        let minutes = Int(ProcessInfo.processInfo.systemUptime / 60)
        let (days, hours, rest) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
        let parts = [days > 0 ? "\(days) gün" : nil, hours > 0 ? "\(hours) saat" : nil, days == 0 && rest > 0 ? "\(rest) dakika" : nil]
        return "Mac \(parts.compactMap { $0 }.joined(separator: " ")) önce açıldı."
    }

    static func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func network() async -> String {
        let wifi = await WiFiControl.isPoweredOn()
        let wifiText = wifi.map { $0 ? "Wi-Fi açık" : "Wi-Fi kapalı" } ?? "Wi-Fi durumu okunamadı"
        guard let address = localIPv4Address() else { return "\(wifiText); ağ bağlantısı görünmüyor." }
        return "\(wifiText). Yerel IP adresin \(address)."
    }

    private static func localIPv4Address() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            return String(decoding: host.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
        }
        return nil
    }

    /// Memory is reported in binary units, as macOS does ("48 GB" for 48 GiB); disks in decimal ones.
    private static func gibibytes(_ bytes: Int64) -> Int {
        Int((Double(bytes) / Double(1 << 30)).rounded())
    }

    private static func gigabytes(_ bytes: Int64) -> Int {
        Int((Double(bytes) / 1_000_000_000).rounded())
    }
}
