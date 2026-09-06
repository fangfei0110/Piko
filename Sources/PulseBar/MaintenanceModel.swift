import AppKit
import SwiftUI

enum ScanKind: String { case cleanup = "清理扫描", analysis = "磁盘分析", apps = "应用统计", removal = "移除复核" }
enum ScanPayload: Sendable {
    case cleanup([ScannedPath])
    case analysis(FolderReport)
    case apps([AppRecord])
}
struct TrashRequest: Identifiable {
    let id = UUID()
    let items: [ScannedPath]
    var bytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }
}

@MainActor
final class MaintenanceModel: ObservableObject {
    @Published private(set) var candidates: [ScannedPath] = []
    @Published private(set) var folder: FolderReport?
    @Published private(set) var apps: [AppRecord] = []
    @Published private(set) var busy: ScanKind?
    @Published private(set) var scannedCleanup = false
    @Published private(set) var scannedApps = false
    @Published var selected: Set<String> = []
    @Published var appSearch = ""
    @Published var expandedApp: String?
    @Published var pendingTrash: TrashRequest?
    @Published var notice: String?
    @Published var failure: String?
    let home = FileManager.default.homeDirectoryForCurrentUser
    private let scanner = FileScanner()
    private var work: Task<Void,Never>?
    private var request = UUID()
    weak var presentationWindow: NSWindow?

    var runningBundleIDs: Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
    var selectedItems: [ScannedPath] { candidates.filter { selected.contains($0.id) && $0.blockedReason == nil } }
    var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var filteredApps: [AppRecord] { apps.filter { appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(appSearch) || $0.bundleID.localizedCaseInsensitiveContains(appSearch) } }

    func scanCleanup() {
        let scanner = scanner, home = home
        selected = []; pendingTrash = nil
        run(.cleanup) { .cleanup(try await scanner.cleanup(home:home)) }
    }
    func scanApps() {
        let scanner = scanner, home = home
        run(.apps) { .apps(try await scanner.apps(home:home)) }
    }
    func analyze(_ url: URL) {
        let scanner = scanner
        run(.analysis) { .analysis(try await scanner.analyze(url)) }
    }
    func chooseFolder() {
        guard let window = presentationWindow, window.isVisible, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要分析的目录"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = folder?.root ?? home
        panel.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.analyze(url.resolvingSymlinksInPath())
        }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func cancel() {
        work?.cancel(); work = nil; busy = nil; request = UUID()
        notice = "已停止扫描，已有结果保留。"
    }
    func prepareTrash() {
        guard !selectedItems.isEmpty, busy == nil else { return }
        pendingTrash = TrashRequest(items:selectedItems)
    }

    func confirmTrash(_ confirmation: TrashRequest) {
        guard busy == nil else { return }
        pendingTrash = nil; failure = nil; notice = nil; busy = .removal
        let token = UUID(); request = token
        work = Task {
            var moved: [String] = [], errors: [String] = []
            for item in confirmation.items {
                if Task.isCancelled { break }
                do {
                    _ = try await scanner.moveToTrash(item,home:home,runningBundleIDs:runningBundleIDs)
                    moved.append(item.id)
                } catch { errors.append("\(item.url.lastPathComponent)：\(error.localizedDescription)") }
            }
            guard request == token else { return }
            candidates.removeAll { moved.contains($0.id) }
            selected.subtract(moved)
            busy = nil; work = nil
            notice = "已移入废纸篓 \(moved.count) 项。清空废纸篓前不会释放磁盘空间。"
            if !errors.isEmpty { failure = "已跳过 \(errors.count) 项：\n" + errors.joined(separator:"\n") }
        }
    }

    private func run(_ kind: ScanKind,operation: @escaping @Sendable () async throws -> ScanPayload) {
        guard busy != .removal else { return }
        work?.cancel()
        let token = UUID(); request = token
        busy = kind; failure = nil; notice = nil
        work = Task {
            do {
                let payload = try await operation()
                try Task.checkCancellation()
                guard request == token else { return }
                switch payload {
                case .cleanup(let items):
                    let policy = CleanupPolicy(home:home), running = runningBundleIDs
                    candidates = items.map { item in
                        var item = item
                        if item.blockedReason == nil { item.blockedReason = policy.runningReason(item,bundleIDs:running) }
                        return item
                    }
                    scannedCleanup = true
                case .analysis(let report): folder = report
                case .apps(let records): apps = records; scannedApps = true
                }
                busy = nil; work = nil
            } catch {
                guard request == token else { return }
                busy = nil; work = nil
                if !(error is CancellationError) { failure = error.localizedDescription }
            }
        }
    }
}
