import Foundation
import Darwin

struct PathStamp: Equatable, Sendable {
    let device, inode: UInt64
    let modified: Date
    let isDirectory: Bool

    static func read(_ url: URL) throws -> Self {
        let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
        guard let type = attributes[.type] as? FileAttributeType, type != .typeSymbolicLink,
              type == .typeDirectory || type == .typeRegular else {
            throw ScanError.unsafe("不是普通文件或目录：\(url.path)")
        }
        guard url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path else {
            throw ScanError.unsafe("路径包含符号链接：\(url.path)")
        }
        return PathStamp(device:(attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
                         inode:(attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                         modified:attributes[.modificationDate] as? Date ?? .distantPast,isDirectory:type == .typeDirectory)
    }
}

struct FileFootprint: Equatable, Sendable {
    var bytes: UInt64 = 0
    var files = 0
    var latest: Date = .distantPast
    var skipped = 0
    var limited = false
    var fingerprint: UInt64 = 0
}

struct ScannedPath: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let category: String
    let stamp: PathStamp
    let footprint: FileFootprint
    var blockedReason: String?
    var bytes: UInt64 { footprint.bytes }
}

struct FolderReport: Sendable {
    let root: URL
    let items: [ScannedPath]
    let skipped: Int
    var bytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }
}

struct AppRecord: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let name, version, bundleID: String
    let footprint: FileFootprint
    let related: [ScannedPath]
    var bytes: UInt64 { footprint.bytes }
    var relatedBytes: UInt64 { related.reduce(0) { $0 + $1.bytes } }
}

enum ScanError: LocalizedError {
    case unsafe(String)
    var errorDescription: String? { switch self { case .unsafe(let reason): reason } }
}

struct CleanupPolicy: Sendable {
    let home: URL
    var roots: [(URL,String)] {
        [("Library/Caches","应用缓存"),("Library/Logs","日志"),("Downloads","旧安装包")]
            .map { (home.appendingPathComponent($0.0,isDirectory:true),$0.1) }
    }

    func validate(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        guard let root = roots.first(where:{ url.deletingLastPathComponent().standardizedFileURL.path == $0.0.path }) else {
            throw ScanError.unsafe("不在允许清理的直接子目录中：\(path)")
        }
        let name = url.lastPathComponent.lowercased()
        guard !name.hasPrefix("."), !name.hasPrefix("com.apple."), !name.contains("cloud"),
              !name.contains("steam"), !name.contains("dota"), !name.contains("keychain") else {
            throw ScanError.unsafe("受保护或共享目录，仅供查看")
        }
        if root.1 == "旧安装包" {
            guard ["dmg","pkg","xip"].contains(url.pathExtension.lowercased()),
                  try !PathStamp.read(url).isDirectory else {
                throw ScanError.unsafe("下载目录仅允许检查 dmg、pkg、xip 安装包")
            }
        }
        _ = try PathStamp.read(url)
    }

    func validateUnchanged(_ item: ScannedPath,current: FileFootprint) throws {
        try validate(item.url)
        guard try PathStamp.read(item.url) == item.stamp, current == item.footprint else {
            throw ScanError.unsafe("文件在扫描后发生变化，请重新扫描：\(item.url.lastPathComponent)")
        }
        guard !current.limited, current.skipped == 0 else {
            throw ScanError.unsafe("有未能检查的内容，跳过此项")
        }
    }

    func runningReason(_ item: ScannedPath,bundleIDs: Set<String>) -> String? {
        let name = item.url.lastPathComponent.lowercased()
        return bundleIDs.contains(where:{ name == $0.lowercased() || name.hasPrefix($0.lowercased()+".") })
            ? "关联应用正在运行" : nil
    }
}

actor FileScanner {
    private let limit: Int
    init(limit: Int = 150_000) { self.limit = limit }

    func footprint(_ url: URL) throws -> FileFootprint {
        // A scan may run for minutes without returning to an autorelease boundary.
        try autoreleasepool { try measureFootprint(url) }
    }

    private nonisolated func measureFootprint(_ url: URL) throws -> FileFootprint {
        let manager = FileManager.default
        let stamp = try PathStamp.read(url)
        var result = FileFootprint(latest:stamp.modified)
        let keys: Set<URLResourceKey> = [.isRegularFileKey,.isSymbolicLinkKey,.fileAllocatedSizeKey,.totalFileAllocatedSizeKey,.fileSizeKey,.contentModificationDateKey]
        var seen: Set<String> = []
        func count(_ entry: URL) {
            do {
                let values = try entry.resourceValues(forKeys:keys)
                if values.isSymbolicLink == true { return }
                if let modified = values.contentModificationDate { result.latest = max(result.latest,modified) }
                guard values.isRegularFile == true else { return }
                let attributes = try manager.attributesOfItem(atPath:entry.path)
                let inode = "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
                guard seen.insert(inode).inserted else { return }
                let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
                result.bytes += UInt64(max(0,size)); result.files += 1
                let identity = "\(entry.path):\(inode):\(size):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                let hash = identity.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
                result.fingerprint ^= hash
            } catch { result.skipped += 1 }
        }
        if !stamp.isDirectory { count(url); return result }
        guard let iterator = manager.enumerator(at:url,includingPropertiesForKeys:Array(keys),options:[],
            errorHandler:{ _,_ in result.skipped += 1; return true }) else {
            throw ScanError.unsafe("无法读取：\(url.path)")
        }
        var visited = 0
        // Drain Foundation/FileProvider temporaries per entry, not after the whole tree.
        while try autoreleasepool(invoking: { () throws -> Bool in
            try Task.checkCancellation()
            guard let entry = iterator.nextObject() as? URL else { return false }
            visited += 1
            if visited > limit { result.limited = true; return false }
            if entry.lastPathComponent == ".Trash" || entry.lastPathComponent == "CloudStorage" || entry.lastPathComponent == "Mobile Documents" {
                iterator.skipDescendants(); result.skipped += 1; return true
            }
            count(entry)
            return true
        }) {}
        return result
    }

    func cleanup(home: URL,now: Date = Date()) throws -> [ScannedPath] {
        let policy = CleanupPolicy(home:home)
        var items: [ScannedPath] = []
        for (root,category) in policy.roots {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath:root.path) else { continue }
            let children = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])
            for child in children {
                try Task.checkCancellation()
                if category == "旧安装包" && !["dmg","pkg","xip"].contains(child.pathExtension.lowercased()) { continue }
                do {
                    try policy.validate(child)
                    let stamp = try PathStamp.read(child)
                    let size = try footprint(child)
                    guard size.bytes > 0 else { continue }
                    let cutoff = now.addingTimeInterval(category == "旧安装包" ? -30*86400 : -7*86400)
                    let reason: String? = size.skipped > 0 || size.limited ? "未能完整检查，暂不可清理"
                        : size.latest > cutoff ? "近期仍有变化，暂不可清理" : nil
                    items.append(ScannedPath(url:child,category:category,stamp:stamp,footprint:size,blockedReason:reason))
                } catch is CancellationError { throw CancellationError() }
                catch { continue }
            }
        }
        return items.sorted { $0.bytes > $1.bytes }
    }

    func analyze(_ root: URL) throws -> FolderReport {
        guard try PathStamp.read(root).isDirectory else { throw ScanError.unsafe("请选择目录") }
        let children = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil,options:[])
        var items: [ScannedPath] = []
        var skipped = 0
        for child in children {
            try Task.checkCancellation()
            if [".Trash","CloudStorage","Mobile Documents"].contains(child.lastPathComponent) { skipped += 1; continue }
            do {
                let stamp = try PathStamp.read(child)
                let size = try footprint(child)
                items.append(ScannedPath(url:child,category:stamp.isDirectory ? "文件夹" : "文件",stamp:stamp,footprint:size))
                skipped += size.skipped + (size.limited ? 1 : 0)
            } catch is CancellationError { throw CancellationError() }
            catch { skipped += 1 }
        }
        return FolderReport(root:root,items:items.sorted { $0.bytes > $1.bytes },skipped:skipped)
    }

    func apps(home: URL) throws -> [AppRecord] {
        let manager = FileManager.default
        var appURLs: [URL] = []
        for root in [URL(fileURLWithPath:"/Applications",isDirectory:true),home.appendingPathComponent("Applications",isDirectory:true)] {
            guard let iterator = manager.enumerator(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey],options:[.skipsPackageDescendants,.skipsHiddenFiles]) else { continue }
            for case let url as URL in iterator {
                try Task.checkCancellation()
                if iterator.level > 3 { iterator.skipDescendants(); continue }
                if url.pathExtension.lowercased() == "app" { appURLs.append(url); iterator.skipDescendants() }
            }
        }
        var records: [AppRecord] = []
        for url in appURLs {
            try Task.checkCancellation()
            guard let bundle = Bundle(url:url), let stamp = try? PathStamp.read(url), stamp.isDirectory else { continue }
            let name = bundle.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey:"CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
            let bundleID = bundle.bundleIdentifier ?? ""
            let version = bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—"
            do {
                let size = try footprint(url)
                var related: [ScannedPath] = []
                if !bundleID.isEmpty, !bundleID.contains("/"), bundleID != ".", bundleID != ".." {
                    for suffix in ["Library/Caches/\(bundleID)","Library/Logs/\(bundleID)","Library/Application Support/\(bundleID)","Library/Preferences/\(bundleID).plist"] {
                        let path = home.appendingPathComponent(suffix)
                        guard manager.fileExists(atPath:path.path) else { continue }
                        if let relatedStamp = try? PathStamp.read(path), let footprint = try? footprint(path) {
                            related.append(ScannedPath(url:path,category:"关联数据",stamp:relatedStamp,footprint:footprint))
                        }
                    }
                }
                records.append(AppRecord(url:url,name:name,version:version,bundleID:bundleID,footprint:size,related:related))
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        return records.sorted { $0.bytes > $1.bytes }
    }

    func moveToTrash(_ item: ScannedPath,home: URL,runningBundleIDs: Set<String>) throws -> URL? {
        let policy = CleanupPolicy(home:home)
        guard item.blockedReason == nil else { throw ScanError.unsafe(item.blockedReason!) }
        if let reason = policy.runningReason(item,bundleIDs:runningBundleIDs) { throw ScanError.unsafe(reason) }
        try policy.validateUnchanged(item,current:footprint(item.url))
        try checkOpenFiles(item.url,isDirectory:item.stamp.isDirectory)
        try Task.checkCancellation()
        try policy.validateUnchanged(item,current:footprint(item.url))
        var destination: NSURL?
        try FileManager.default.trashItem(at:item.url,resultingItemURL:&destination)
        return destination as URL?
    }

    func checkOpenFiles(_ url: URL,isDirectory: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath:"/usr/sbin/lsof")
        process.arguments = ["-n","-P","-t"] + (isDirectory ? ["+D",url.path] : ["--",url.path])
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                kill(process.processIdentifier,SIGKILL)
                process.waitUntilExit()
                throw ScanError.unsafe("文件占用检查未完成，已跳过；请稍后重试")
            }
            Thread.sleep(forTimeInterval:0.04)
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        guard stderr.isEmpty, process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw ScanError.unsafe("无法确认文件是否被占用，已跳过")
        }
        guard data.isEmpty else { throw ScanError.unsafe("有进程正在使用此项，请关闭关联应用后重新扫描") }
    }
}
