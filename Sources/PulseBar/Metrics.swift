import Foundation

struct MemoryReading: Codable, Sendable {
    var total, app, wired, compressed, cached, free, swapUsed, swapTotal: UInt64
    var pressure: Int
    var used: UInt64 { min(total, app + wired + compressed) }
    var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    var pressureName: String {
        switch pressure { case 1: "正常"; case 2: "偏高"; case 4: "紧张"; default: "未提供" }
    }
}

struct DiskReading: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var total, available: UInt64
    var internalDisk: Bool
    var used: UInt64 { total > available ? total - available : 0 }
    var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
}

struct NetworkReading: Codable, Identifiable, Sendable {
    var id: String
    var address: String
    var received, sent: UInt64
    var download, upload: Double?
    var isPrimary: Bool
    var label: String {
        if id.hasPrefix("utun") { return "VPN 隧道" }
        if id.hasPrefix("en") { return "网络接口" }
        if id.hasPrefix("bridge") { return "网桥" }
        return "网络接口"
    }
}

struct ProcessReading: Codable, Identifiable, Sendable {
    var id: Int32
    var name: String
    var cpu: Double?
    var memory: UInt64
    var threads: Int
}

struct PowerReading: Codable, Sendable {
    var source: String
    var batteryPercent: Double?
    var charging: Bool
    var minutesRemaining: Int?
}

struct Snapshot: Codable, Sendable {
    var date = Date()
    var cpu: Double?
    var cores: [Double] = []
    var gpu: Double?
    var memory: MemoryReading?
    var disks: [DiskReading] = []
    var networks: [NetworkReading] = []
    var processes: [ProcessReading] = []
    var diskRead: Double?
    var diskWrite: Double?
    var loads: [Double] = []
    var uptime: Double = 0
    var thermal = "读取中"
    var lowPower = false
    var power = PowerReading(source: "读取中", charging: false)
    var errors: [String] = []
    var primaryNetwork: NetworkReading? { networks.first(where: \.isPrimary) }
    var startupDisk: DiskReading? {
        disks.first { $0.id == "/System/Volumes/Data" } ?? disks.first { $0.id == "/" }
    }
}

struct TrendPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let cpu, gpu, memory, download, upload, diskRead, diskWrite: Double?
    init(_ snapshot: Snapshot) {
        date = snapshot.date; cpu = snapshot.cpu; gpu = snapshot.gpu
        memory = snapshot.memory?.percent
        download = snapshot.primaryNetwork?.download; upload = snapshot.primaryNetwork?.upload
        diskRead = snapshot.diskRead; diskWrite = snapshot.diskWrite
    }
}

enum Readout {
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
    static func bytes(_ value: UInt64, compact: Bool = false) -> String { bytes(Double(value), compact: compact) }
    static func bytes(_ value: Double, compact: Bool = false) -> String {
        guard value.isFinite && value >= 0 else { return "—" }
        let units = compact ? ["B", "K", "M", "G", "T"] : ["B", "KiB", "MiB", "GiB", "TiB"]
        var n = value; var index = 0
        while n >= 1024 && index < units.count - 1 { n /= 1024; index += 1 }
        return String(format: n >= 100 || index == 0 ? "%.0f" : "%.1f", n) + (compact ? "" : " ") + units[index]
    }
    static func rate(_ value: Double?) -> String { value.map { bytes($0) + "/s" } ?? "—" }
    static func uptime(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes >= 1440 { return "\(minutes / 1440) 天 \(minutes % 1440 / 60) 小时" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }
}

enum MetricMath {
    static func rate(current: UInt64, previous: UInt64, seconds: Double) -> Double? {
        guard seconds > 0, seconds.isFinite, current >= previous else { return nil }
        return Double(current - previous) / seconds
    }
    static func cpu(current: [UInt32], previous: [UInt32]) -> [Double] {
        guard current.count == previous.count, current.count % 4 == 0 else { return [] }
        return stride(from: 0, to: current.count, by: 4).map { offset in
            let delta = (0..<4).map { UInt64(current[offset + $0] &- previous[offset + $0]) }
            let total = delta.reduce(0, +)
            return total > 0 ? Double(total - delta[2]) / Double(total) * 100 : 0
        }
    }
}
