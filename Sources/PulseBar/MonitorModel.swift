import AppKit
import SwiftUI
import ServiceManagement
import IOKit.pwr_mgt

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case status, cleanup, apps, analysis, tools, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .status: "状态"; case .cleanup: "清理"; case .apps: "软件"
        case .analysis: "分析"; case .tools: "工具"; case .settings: "设置"
        }
    }
}

enum MonitorTab: String, CaseIterable, Identifiable {
    case overview, cpu, memory, disks, network, processes, system, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "总览"; case .cpu: "处理器"; case .memory: "内存"; case .disks: "磁盘"
        case .network: "网络"; case .processes: "进程"; case .system: "系统"; case .settings: "设置"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "waveform.path.ecg"; case .cpu: "cpu"; case .memory: "memorychip"; case .disks: "internaldrive"
        case .network: "network"; case .processes: "list.bullet.rectangle"; case .system: "desktopcomputer"; case .settings: "slider.horizontal.3"
        }
    }
}

@MainActor
final class MonitorModel: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var history: [TrendPoint] = []
    @Published var tab: MonitorTab = .overview
    @Published var section: WorkspaceSection = .status
    @Published var pinnedProcesses: Set<Int32> = []
    @Published private(set) var awakeUntil: Date?
    @Published var paused = false
    @Published var loading = true
    @Published var search = ""
    @Published var processSort = "cpu"
    @Published var range: Double = 120
    @Published var message: String?
    @Published var interval: Double { didSet { UserDefaults.standard.set(interval, forKey:"interval") } }
    @Published var appearance: MonitorAppearance { didSet { UserDefaults.standard.set(appearance.rawValue, forKey:"appearance"); onStatusChange?() } }
    @Published var showCPU: Bool { didSet { persistBar() } }
    @Published var showMemory: Bool { didSet { persistBar() } }
    @Published var showNetwork: Bool { didSet { persistBar() } }
    @Published var showGPU: Bool { didSet { persistBar() } }
    @Published var showDisk: Bool { didSet { persistBar() } }
    @Published var statusBarTypography: StatusBarTypography {
        didSet { statusBarTypography.save(to:.standard); onStatusChange?() }
    }
    @Published var loginStatus = SMAppService.mainApp.status
    let hardware = Hardware()
    let maintenance = MaintenanceModel()
    private var awakeAssertion: IOPMAssertionID = 0
    private var awakeTimer: Task<Void,Never>?
    private let sampler = SystemSampler()
    private var loop: Task<Void,Never>?
    var onStatusChange: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults:["interval":2.0,"appearance":"cold","showCPU":true,"showMemory":true,"showNetwork":false,"showGPU":false,"showDisk":true])
        let storedInterval = defaults.double(forKey:"interval")
        interval = [1.0,2.0,5.0,10.0].contains(storedInterval) ? storedInterval : 2
        appearance = MonitorAppearance.load(from:defaults)
        showCPU = defaults.bool(forKey:"showCPU"); showMemory = defaults.bool(forKey:"showMemory")
        showNetwork = defaults.bool(forKey:"showNetwork"); showGPU = defaults.bool(forKey:"showGPU")
        showDisk = defaults.bool(forKey:"showDisk")
        statusBarTypography = StatusBarTypography.load(from:defaults)
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.paused {
                    let sample = await self.sampler.sample()
                    self.snapshot = sample
                    self.history.append(TrendPoint(sample))
                    if self.history.count > 3600 { self.history.removeFirst(self.history.count - 3600) }
                    let earliest = sample.date.addingTimeInterval(-3600)
                    self.history.removeAll { $0.date < earliest }
                    self.loading = false
                    self.onStatusChange?()
                }
                do { try await Task.sleep(for:.seconds(self.interval)) } catch { return }
            }
        }
    }

    var visibleHistory: [TrendPoint] { history.filter { $0.date >= snapshot.date.addingTimeInterval(-range) } }
    var filteredProcesses: [ProcessReading] {
        let filtered = snapshot.processes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.id).contains(search) }
        return filtered.sorted { a,b in
            if processSort == "memory" { return a.memory == b.memory ? a.id < b.id : a.memory > b.memory }
            return (a.cpu ?? -1) == (b.cpu ?? -1) ? a.id < b.id : (a.cpu ?? -1) > (b.cpu ?? -1)
        }
    }
    var topProcesses: [ProcessReading] {
        snapshot.processes.sorted { a,b in
            let aPinned = pinnedProcesses.contains(a.id), bPinned = pinnedProcesses.contains(b.id)
            if aPinned != bPinned { return aPinned }
            if processSort == "memory" { return a.memory == b.memory ? a.id < b.id : a.memory > b.memory }
            return (a.cpu ?? -1) == (b.cpu ?? -1) ? a.id < b.id : (a.cpu ?? -1) > (b.cpu ?? -1)
        }
    }

    func togglePin(_ pid: Int32) {
        if pinnedProcesses.contains(pid) { pinnedProcesses.remove(pid) }
        else { pinnedProcesses.insert(pid) }
    }
    func toggleAwake() {
        if awakeUntil != nil { stopAwake(); return }
        var assertion: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),"Piko keep awake for one hour" as CFString,&assertion)
        guard result == kIOReturnSuccess else { message = "未能保持屏幕唤醒（\(result)）"; return }
        awakeAssertion = assertion
        awakeUntil = Date().addingTimeInterval(3600)
        awakeTimer = Task { [weak self] in
            do { try await Task.sleep(for:.seconds(3600)) } catch { return }
            self?.stopAwake()
        }
    }
    func stopAwake() {
        awakeTimer?.cancel(); awakeTimer = nil
        if awakeUntil != nil { IOPMAssertionRelease(awakeAssertion) }
        awakeAssertion = 0; awakeUntil = nil
    }
    var concerns: [String] {
        var result: [String] = []
        if let disk = snapshot.disks.first, disk.percent >= 90 { result.append("启动磁盘空间偏低") }
        if let m = snapshot.memory, m.pressure == 4 { result.append("内存压力紧张") }
        else if snapshot.memory?.pressure == 2 { result.append("内存压力偏高") }
        if let cpu = snapshot.cpu, cpu >= 90 { result.append("CPU 高负载") }
        if ["偏热","过热"].contains(snapshot.thermal) { result.append("系统散热压力偏高") }
        return result + snapshot.errors
    }
    var stateTitle: String {
        if paused { return "监控已暂停" }
        if loading { return "正在读取系统" }
        return concerns.first ?? "系统运行正常"
    }
    var stateSymbol: String { paused ? "pause.circle.fill" : concerns.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill" }

    func togglePause() { paused.toggle(); onStatusChange?() }
    private func persistBar() {
        let d = UserDefaults.standard
        d.set(showCPU, forKey:"showCPU"); d.set(showMemory, forKey:"showMemory")
        d.set(showNetwork, forKey:"showNetwork"); d.set(showGPU, forKey:"showGPU")
        d.set(showDisk, forKey:"showDisk")
        onStatusChange?()
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginStatus = SMAppService.mainApp.status
            message = loginStatus == .requiresApproval ? "请在系统设置的登录项中允许 Piko。" : nil
        } catch { message = "登录项未能更新：\(error.localizedDescription)"; loginStatus = SMAppService.mainApp.status }
    }
    func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }
    func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Utilities/Activity Monitor.app"))
    }
    func openStorageSettings() {
        if let url = URL(string:"x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(url) }
    }
    func exportSnapshot() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Piko-\(Date().formatted(.iso8601.year().month().day()))-snapshot.json"
        panel.title = "导出当前系统快照"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to:url, options:.atomic)
            message = "快照已导出到 \(url.lastPathComponent)"
        } catch { message = "导出失败：\(error.localizedDescription)" }
    }
}
