import Foundation
import Darwin
import SystemConfiguration
import IOKit.ps
import SystemProbe

struct Hardware: Sendable {
    let model = Self.string("hw.model")
    let chip = Self.string("machdep.cpu.brand_string")
    let cores = ProcessInfo.processInfo.processorCount
    let performanceCores = Self.integer("hw.perflevel0.physicalcpu")
    let efficiencyCores = Self.integer("hw.perflevel1.physicalcpu")
    let memory = ProcessInfo.processInfo.physicalMemory
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let host = Host.current().localizedName ?? "Mac"
    static func integer(_ key: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(key,&value,&size,nil,0) == 0 ? max(0,Int(value)) : 0
    }
    static func string(_ key: String) -> String {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var data = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &data, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding:data.prefix(while:{ $0 != 0 }).map { UInt8(bitPattern:$0) },as:UTF8.self)
    }
}

actor SystemSampler {
    private var previousTicks: [UInt32]?
    private var previousTime: Double?
    private var previousNetworks: [String: (UInt64, UInt64)] = [:]
    private var previousProcesses: [Int32: (cpu: UInt64, start: UInt64)] = [:]
    private var previousIO: (UInt64, UInt64)?
    private var diskCache: [DiskReading] = []
    private var diskRefreshTime: Double = -100

    func sample() -> Snapshot {
        var result = Snapshot()
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { now - $0 }
        let interval = elapsed.flatMap { $0 > 0 && $0 < 30 ? $0 : nil }
        var cpu = PBCPU()
        if pb_cpu(&cpu) == 1 {
            let ticks = withUnsafeBytes(of: cpu.ticks) { Array($0.bindMemory(to: UInt32.self).prefix(Int(cpu.count) * 4)) }
            if let previousTicks, interval != nil {
                result.cores = MetricMath.cpu(current: ticks, previous: previousTicks)
                if !result.cores.isEmpty { result.cpu = result.cores.reduce(0, +) / Double(result.cores.count) }
            }
            previousTicks = ticks
        } else { result.errors.append("CPU 暂时无法读取") }

        var memory = PBMemory()
        if pb_memory(&memory) == 1 {
            result.memory = MemoryReading(total: memory.total, app: memory.app, wired: memory.wired,
                compressed: memory.compressed, cached: memory.cached, free: memory.free_bytes,
                swapUsed: memory.swap_used, swapTotal: memory.swap_total, pressure: Int(memory.pressure))
        } else { result.errors.append("内存暂时无法读取") }
        let gpu = pb_gpu()
        result.gpu = gpu >= 0 ? gpu : nil
        if now - diskRefreshTime >= 10 {
            diskCache = disks()
            diskRefreshTime = now
        }
        result.disks = diskCache
        if diskCache.isEmpty { result.errors.append("磁盘容量暂时无法读取") }

        let addresses = ipv4Addresses()
        let primary = primaryInterface()
        var interfaces = [PBInterface](repeating: PBInterface(), count: Int(PB_MAX_INTERFACES))
        let count = pb_interfaces(&interfaces, Int32(interfaces.count))
        var nextNetwork: [String: (UInt64, UInt64)] = [:]
        if count >= 0 {
            for index in 0..<Int(count) {
                var item = interfaces[index]
                let name = cString(&item.name)
                let old = previousNetworks[name]
                let down = interval.flatMap { dt in old.flatMap { MetricMath.rate(current:item.received, previous:$0.0, seconds:dt) } }
                let up = interval.flatMap { dt in old.flatMap { MetricMath.rate(current:item.sent, previous:$0.1, seconds:dt) } }
                nextNetwork[name] = (item.received, item.sent)
                result.networks.append(NetworkReading(id:name, address:addresses[name] ?? "", received:item.received,
                    sent:item.sent, download:down, upload:up, isPrimary:name == primary))
            }
            result.networks.sort { ($0.isPrimary ? 0 : 1, $0.id) < ($1.isPrimary ? 0 : 1, $1.id) }
        } else { result.errors.append("网络计数器暂时无法读取") }
        previousNetworks = nextNetwork

        var read: UInt64 = 0; var write: UInt64 = 0
        if pb_disk_io(&read, &write) == 1 {
            if let old = previousIO, let interval {
                result.diskRead = MetricMath.rate(current:read, previous:old.0, seconds:interval)
                result.diskWrite = MetricMath.rate(current:write, previous:old.1, seconds:interval)
            }
            previousIO = (read, write)
        } else { previousIO = nil }

        var processes = [PBProcess](repeating: PBProcess(), count: 4096)
        let processCount = pb_processes(&processes, Int32(processes.count))
        var nextProcesses: [Int32: (cpu: UInt64, start: UInt64)] = [:]
        for index in 0..<Int(processCount) {
            var item = processes[index]
            var percent: Double?
            if let old = previousProcesses[item.pid], old.start == item.start_time, let interval {
                percent = MetricMath.rate(current:item.cpu_ns, previous:old.cpu, seconds:interval).map { $0 / 1e9 * 100 }
            }
            nextProcesses[item.pid] = (item.cpu_ns, item.start_time)
            result.processes.append(ProcessReading(id:item.pid, name:cString(&item.name), cpu:percent,
                memory:item.memory, threads:Int(item.threads)))
        }
        previousProcesses = nextProcesses
        result.processes.sort { ($0.cpu ?? 0) > ($1.cpu ?? 0) }
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { result.loads = loads }
        result.uptime = pb_uptime()
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: result.thermal = "正常"
        case .fair: result.thermal = "温热"
        case .serious: result.thermal = "偏热"
        case .critical: result.thermal = "过热"
        @unknown default: result.thermal = "未提供"
        }
        result.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        result.power = power()
        previousTime = now
        return result
    }

    private func cString<T>(_ value: inout T) -> String {
        withUnsafePointer(to: &value) { p in
            p.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
        }
    }

    private func primaryInterface() -> String? {
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let dict = SCDynamicStoreCopyValue(nil, key as CFString) as? [String:Any],
               let name = dict["PrimaryInterface"] as? String { return name }
        }
        return nil
    }

    private func ipv4Addresses() -> [String:String] {
        var result: [String:String] = [:]
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return result }
        defer { freeifaddrs(first) }
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating:0, count:Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result[String(cString:entry.pointee.ifa_name)] = String(decoding:host.prefix(while:{ $0 != 0 }).map { UInt8(bitPattern:$0) },as:UTF8.self)
            }
        }
        return result
    }

    private func disks() -> [DiskReading] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsInternalKey, .volumeIsLocalKey]
        let dataPath = "/System/Volumes/Data"
        var urls = [URL(fileURLWithPath:dataPath)]
        urls += (manager.mountedVolumeURLs(includingResourceValuesForKeys:Array(keys), options:[.skipHiddenVolumes]) ?? [])
            .filter { $0.path.hasPrefix("/Volumes/") }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys:keys), values.volumeIsLocal != false,
                  let attrs = try? manager.attributesOfFileSystem(forPath:url.path),
                  let total = (attrs[.systemSize] as? NSNumber)?.uint64Value,
                  let free = (attrs[.systemFreeSize] as? NSNumber)?.uint64Value else { return nil }
            return DiskReading(id:url.path, name:url.path == dataPath ? "Macintosh HD" : (values.volumeName ?? url.lastPathComponent),
                total:total, available:free, internalDisk:values.volumeIsInternal ?? true)
        }
    }

    private func power() -> PowerReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerReading(source:"未提供", charging:false)
        }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String:Any],
                  let current = details[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = details[kIOPSIsChargingKey] as? Bool ?? false
            let state = details[kIOPSPowerSourceStateKey] as? String
            let minutes = details[kIOPSTimeToEmptyKey] as? Int
            return PowerReading(source:state == kIOPSACPowerValue ? "外接电源" : "电池供电",
                batteryPercent:Double(current)/Double(maximum)*100, charging:charging,
                minutesRemaining:minutes.flatMap { $0 > 0 ? $0 : nil })
        }
        return PowerReading(source:"外接电源", charging:false)
    }
}
