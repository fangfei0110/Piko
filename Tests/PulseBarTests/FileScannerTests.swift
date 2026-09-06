import XCTest
import Darwin
@testable import PulseBar

@MainActor
final class FileScannerTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PulseBarTests-\(UUID().uuidString)",isDirectory:true).resolvingSymlinksInPath()
        for suffix in ["Library/Caches","Library/Logs","Downloads"] {
            try FileManager.default.createDirectory(at:root.appendingPathComponent(suffix),withIntermediateDirectories:true)
        }
        return root
    }
    private func file(_ url: URL,daysOld: Double = 40) throws {
        try Data(repeating:0x41,count:8192).write(to:url)
        try FileManager.default.setAttributes([.modificationDate:Date().addingTimeInterval(-daysOld*86400)],ofItemAtPath:url.path)
    }
    func testCleanupIsConservativeAndInstallersOnly() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at:home) }
        let old = home.appendingPathComponent("Library/Caches/com.example.old")
        let recent = home.appendingPathComponent("Library/Logs/recent.log")
        try file(old); try file(recent,daysOld:0)
        try file(home.appendingPathComponent("Downloads/old.dmg"))
        try file(home.appendingPathComponent("Downloads/important.zip"))
        try file(home.appendingPathComponent("Library/Caches/com.apple.protected"))
        try file(home.appendingPathComponent("Library/Caches/steam"))
        let items = try await FileScanner().cleanup(home:home)
        XCTAssertEqual(Set(items.map { $0.url.lastPathComponent }),["com.example.old","recent.log","old.dmg"])
        let oldItem = try XCTUnwrap(items.first { $0.url.standardizedFileURL.path == old.standardizedFileURL.path })
        let recentItem = try XCTUnwrap(items.first { $0.url.standardizedFileURL.path == recent.standardizedFileURL.path })
        XCTAssertNil(oldItem.blockedReason)
        XCTAssertNotNil(recentItem.blockedReason,"Latest: \(recentItem.footprint.latest)")
    }
    func testPolicyRejectsLinksAncestorTraversalAndOutsideRoots() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at:home) }
        let policy = CleanupPolicy(home:home)
        try file(home.appendingPathComponent("private.txt"))
        let link = home.appendingPathComponent("Library/Caches/link")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:home.appendingPathComponent("private.txt"))
        XCTAssertThrowsError(try policy.validate(link))
        XCTAssertThrowsError(try policy.validate(home))
        XCTAssertThrowsError(try policy.validate(home.appendingPathComponent("Library/Caches/../Logs")))
        XCTAssertThrowsError(try policy.validate(home.appendingPathComponent("private.txt")))
        XCTAssertThrowsError(try policy.validate(home.appendingPathComponent("Downloads/important.zip")))
    }
    func testFootprintDoesNotFollowSymlinksOrCountHardlinksTwice() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at:home) }
        let folder = home.appendingPathComponent("Library/Caches/data")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let payload = folder.appendingPathComponent("payload")
        try file(payload)
        try FileManager.default.linkItem(at:payload,to:folder.appendingPathComponent("hardlink"))
        try file(home.appendingPathComponent("outside"))
        try FileManager.default.createSymbolicLink(at:folder.appendingPathComponent("link"),withDestinationURL:home.appendingPathComponent("outside"))
        let result = try await FileScanner().footprint(folder)
        XCTAssertEqual(result.files,1)
        XCTAssertGreaterThan(result.bytes,0)
        XCTAssertFalse(result.limited)
    }
    func testChangedOrReplacedFileFailsRevalidation() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at:home) }
        let url = home.appendingPathComponent("Library/Caches/data")
        try file(url)
        let scanner = FileScanner()
        let original = try await scanner.footprint(url)
        let item = ScannedPath(url:url,category:"应用缓存",stamp:try PathStamp.read(url),footprint:original)
        let policy = CleanupPolicy(home:home)
        XCTAssertNoThrow(try policy.validateUnchanged(item,current:original))
        try Data(repeating:0x42,count:16384).write(to:url,options:.atomic)
        let changed = try await scanner.footprint(url)
        XCTAssertThrowsError(try policy.validateUnchanged(item,current:changed))
    }
    func testRecursiveScanLimitIsVisibleAndBlocksRemoval() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at:home) }
        let folder = home.appendingPathComponent("Library/Caches/data")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for index in 0..<4 { try file(folder.appendingPathComponent("\(index)")) }
        let scanner = FileScanner(limit:2)
        let size = try await scanner.footprint(folder)
        XCTAssertTrue(size.limited)
        XCTAssertEqual(size.files,2)
        let item = ScannedPath(url:folder,category:"应用缓存",stamp:try PathStamp.read(folder),footprint:size)
        XCTAssertThrowsError(try CleanupPolicy(home:home).validateUnchanged(item,current:size))
    }
    func testRunningAppAndHelperCacheAreProtected() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at:home) }
        let url = home.appendingPathComponent("Library/Caches/com.example.app.helper")
        try file(url)
        let item = ScannedPath(url:url,category:"应用缓存",stamp:try PathStamp.read(url),footprint:FileFootprint())
        XCTAssertNotNil(CleanupPolicy(home:home).runningReason(item,bundleIDs:["com.example.app"]))
        XCTAssertNil(CleanupPolicy(home:home).runningReason(item,bundleIDs:["com.example.other"]))
    }
    func testFileUseCheckAcceptsClosedFileAndRejectsOpenFile() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at:home) }
        let url = home.appendingPathComponent("Library/Caches/open")
        try file(url)
        let scanner = FileScanner()
        try await scanner.checkOpenFiles(url,isDirectory:false)
        let handle = try FileHandle(forReadingFrom:url)
        defer { try? handle.close() }
        do {
            try await scanner.checkOpenFiles(url,isDirectory:false)
            XCTFail("An open file must not pass removal checks")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("正在使用") || error.localizedDescription.contains("无法确认"))
        }
    }
    func testScanCancellationReturnsWithoutPartialSuccess() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at:home) }
        let scanner = FileScanner()
        let work = Task { try await scanner.cleanup(home:home) }
        work.cancel()
        do { _ = try await work.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testRepeatedLargeScansReleaseTemporaryMetadata() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at:home) }
        let folder = home.appendingPathComponent("Library/Caches/many-files")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for index in 0..<6000 {
            try autoreleasepool { try Data().write(to:folder.appendingPathComponent(String(index))) }
        }
        let scanner = FileScanner()
        _ = try await scanner.footprint(folder)
        let before = try physicalFootprint()
        for _ in 0..<3 {
            let result = try await scanner.footprint(folder)
            XCTAssertEqual(result.files,6000)
            XCTAssertFalse(result.limited)
        }
        let after = try physicalFootprint()
        let growth = after > before ? after-before : 0
        XCTAssertLessThan(growth,96*1024*1024,"Repeated metadata scans retained \(growth) bytes")
    }

    private func physicalFootprint() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
                task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)
            }
        }
        guard result == KERN_SUCCESS else { throw NSError(domain:NSMachErrorDomain,code:Int(result)) }
        return info.phys_footprint
    }
}

final class TreemapTests: XCTestCase {
    func testAreaMatchesWeightsWithoutOverlap() {
        let weights = [50.0,25,15,10]
        let bounds = CGRect(x:0,y:0,width:800,height:300)
        let result = TreemapLayout.rectangles(weights:weights,in:bounds)
        XCTAssertEqual(result.count,weights.count)
        for (index,rect) in result.enumerated() {
            XCTAssertEqual(rect.width*rect.height,bounds.width*bounds.height*weights[index]/100,accuracy:0.001)
            XCTAssertTrue(bounds.contains(rect))
            for other in result.dropFirst(index+1) {
                let intersection = rect.intersection(other)
                XCTAssertTrue(intersection.isNull || intersection.width*intersection.height == 0)
            }
        }
    }
    func testEmptyAndZeroSizesAreSafe() {
        XCTAssertTrue(TreemapLayout.rectangles(weights:[],in:.zero).isEmpty)
        for rect in TreemapLayout.rectangles(weights:[0,.nan,-1],in:CGRect(x:0,y:0,width:100,height:100)) {
            XCTAssertTrue(rect.width.isFinite && rect.height.isFinite)
            XCTAssertGreaterThanOrEqual(rect.width,0)
            XCTAssertGreaterThanOrEqual(rect.height,0)
        }
    }
}
