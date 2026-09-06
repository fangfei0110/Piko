import AppKit
import XCTest
@testable import PulseBar

final class StatusBarTitleTests: XCTestCase {
    func testEveryModuleCombinationHasOnlyInteriorSeparators() {
        for mask in 0..<32 {
            let enabled = (0..<5).map { mask & (1 << $0) != 0 }
            let title = StatusBarTitle.make(snapshot:Snapshot(),showCPU:enabled[0],showMemory:enabled[1],
                showGPU:enabled[2],showNetwork:enabled[3],showDisk:enabled[4],paused:false).string
            let count = enabled.filter { $0 }.count
            XCTAssertEqual(title.filter { $0 == "\u{2502}" }.count,max(0,count-1))
            let trimmed = title.trimmingCharacters(in:.whitespaces)
            XCTAssertFalse(trimmed.hasPrefix("\u{2502}"))
            XCTAssertFalse(trimmed.hasSuffix("\u{2502}"))
            XCTAssertEqual(title.contains("CPU"),enabled[0])
            XCTAssertEqual(title.contains("MEM"),enabled[1])
            XCTAssertEqual(title.contains("GPU"),enabled[2])
            XCTAssertEqual(title.contains("\u{2193}"),enabled[3])
            XCTAssertEqual(title.contains("DISK"),enabled[4])
            XCTAssertFalse(title.contains("-"))
            XCTAssertFalse(title.contains("\u{25CF}"))
            if count == 0 { XCTAssertEqual(title,"") }
        }
    }

    func testLiveValuesUsePrimaryInterfaceAndKeepNeutralMonospacedNumbers() throws {
        var snapshot = Snapshot()
        snapshot.cpu = 27
        snapshot.networks = [
            NetworkReading(id:"utun0",address:"",received:0,sent:0,download:999,upload:999,isPrimary:false),
            NetworkReading(id:"en0",address:"",received:0,sent:0,download:54_579,upload:26_624,isPrimary:true)
        ]
        let title = StatusBarTitle.make(snapshot:snapshot,showCPU:true,showMemory:false,
                                       showGPU:false,showNetwork:true,showDisk:false,paused:false)
        XCTAssertTrue(title.string.contains("CPU\u{2002}27%"))
        XCTAssertTrue(title.string.contains("53.3K"))
        XCTAssertTrue(title.string.contains("26.0K"))
        let number = (title.string as NSString).range(of:"27%").location
        let font = try XCTUnwrap(title.attribute(.font,at:number,effectiveRange:nil) as? NSFont)
        XCTAssertEqual(font,NSFont.monospacedDigitSystemFont(ofSize:12,weight:.semibold))
        XCTAssertEqual(title.attribute(.foregroundColor,at:number,effectiveRange:nil) as? NSColor,.labelColor)
        let down = (title.string as NSString).range(of:"\u{2193}").location
        let up = (title.string as NSString).range(of:"\u{2191}").location
        let downColor = try XCTUnwrap(title.attribute(.foregroundColor,at:down,effectiveRange:nil) as? NSColor)
        let upColor = try XCTUnwrap(title.attribute(.foregroundColor,at:up,effectiveRange:nil) as? NSColor)
        XCTAssertEqual(downColor,.secondaryLabelColor)
        XCTAssertEqual(upColor,.secondaryLabelColor)
    }

    func testUnavailableReadingsAndPauseKeepIconOnlyMode() {
        let title = StatusBarTitle.make(snapshot:Snapshot(),showCPU:true,showMemory:true,
                                       showGPU:true,showNetwork:true,showDisk:true,paused:true).string
        XCTAssertEqual(title.filter { $0 == "\u{2014}" }.count,6)
        XCTAssertTrue(title.trimmingCharacters(in:.whitespaces).hasSuffix("\u{2161}"))
        XCTAssertEqual(StatusBarTitle.make(snapshot:Snapshot(),showCPU:false,showMemory:false,
            showGPU:false,showNetwork:false,showDisk:false,paused:true).string,"")
    }

    func testDiskShowsAvailableCapacityFromStartupVolumeNotExternalDrive() {
        var snapshot = Snapshot()
        let gib: UInt64 = 1024 * 1024 * 1024
        snapshot.disks = [
            DiskReading(id:"/Volumes/Backup",name:"Backup",total:2_000*gib,available:999*gib,internalDisk:false),
            DiskReading(id:"/",name:"System",total:256*gib,available:100*gib,internalDisk:true),
            DiskReading(id:"/System/Volumes/Data",name:"Macintosh HD",total:256*gib,available:35*gib,internalDisk:true)
        ]
        let title = StatusBarTitle.make(snapshot:snapshot,showCPU:false,showMemory:false,showGPU:false,
            showNetwork:false,showDisk:true,paused:false).string
        XCTAssertTrue(title.contains("DISK"))
        XCTAssertTrue(title.contains("35.0G"))
        XCTAssertTrue(title.contains("\u{53EF}\u{7528}"))
        XCTAssertFalse(title.contains("%"))
        XCTAssertFalse(title.contains("999"))
        snapshot.disks.removeLast()
        XCTAssertEqual(snapshot.startupDisk?.id,"/")
        snapshot.disks.removeLast()
        XCTAssertNil(snapshot.startupDisk)
    }
}
