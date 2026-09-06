import AppKit
import XCTest
@testable import PulseBar

final class StatusBarAlertTests: XCTestCase {
    func testUsageThresholdsAndMissingReadings() {
        for percent: Double? in [nil,.nan,.infinity,0,79.99] {
            XCTAssertEqual(StatusBarTitle.usageLevel(percent),.normal)
        }
        for percent in [80.0,89.99] { XCTAssertEqual(StatusBarTitle.usageLevel(percent),.warning) }
        for percent in [90.0,100] { XCTAssertEqual(StatusBarTitle.usageLevel(percent),.critical) }
    }

    func testMemoryPressureEscalatesButNeverDowngradesHighUsage() {
        var memory = MemoryReading(total:100,app:50,wired:0,compressed:0,cached:30,free:20,swapUsed:0,swapTotal:0,pressure:1)
        XCTAssertEqual(StatusBarTitle.memoryLevel(memory),.normal)
        memory.pressure = 2
        XCTAssertEqual(StatusBarTitle.memoryLevel(memory),.warning)
        memory.pressure = 4
        XCTAssertEqual(StatusBarTitle.memoryLevel(memory),.critical)
        memory.app = 95
        memory.pressure = 1
        XCTAssertEqual(StatusBarTitle.memoryLevel(memory),.critical)
        memory.pressure = 2
        XCTAssertEqual(StatusBarTitle.memoryLevel(memory),.critical)
        XCTAssertEqual(StatusBarTitle.memoryLevel(nil),.normal)
    }

    func testDiskWarnsForLowRemainingSpaceNotLargeAvailableValues() {
        var disk = DiskReading(id:"/",name:"System",total:100_000,available:15_001,internalDisk:true)
        XCTAssertEqual(StatusBarTitle.diskLevel(disk),.normal)
        disk.available = 15_000
        XCTAssertEqual(StatusBarTitle.diskLevel(disk),.warning)
        disk.available = 10_001
        XCTAssertEqual(StatusBarTitle.diskLevel(disk),.warning)
        disk.available = 10_000
        XCTAssertEqual(StatusBarTitle.diskLevel(disk),.critical)
        disk.available = 0
        XCTAssertEqual(StatusBarTitle.diskLevel(disk),.critical)
        disk.total = 0
        XCTAssertEqual(StatusBarTitle.diskLevel(disk),.normal)
        XCTAssertEqual(StatusBarTitle.diskLevel(nil),.normal)
    }

    func testOnlyAffectedNumbersChangeColorAndRecoverAfterLoadDrops() throws {
        var snapshot = Snapshot()
        snapshot.cpu = 95
        snapshot.gpu = 85
        snapshot.memory = MemoryReading(total:100,app:70,wired:0,compressed:0,cached:20,free:10,swapUsed:0,swapTotal:0,pressure:4)
        snapshot.disks = [DiskReading(id:"/",name:"System",total:1_000,available:80,internalDisk:true)]
        snapshot.networks = [NetworkReading(id:"en0",address:"",received:0,sent:0,download:123*1024*1024,upload:44*1024*1024,isPrimary:true)]
        func make() -> NSAttributedString {
            StatusBarTitle.make(snapshot:snapshot,showCPU:true,showMemory:true,showGPU:true,
                                showNetwork:true,showDisk:true,paused:false)
        }
        func color(_ substring: String,in title: NSAttributedString) throws -> NSColor {
            let range = (title.string as NSString).range(of:substring)
            XCTAssertNotEqual(range.location,NSNotFound)
            guard range.location != NSNotFound else { throw NSError(domain:"MissingReadout",code:1) }
            return try XCTUnwrap(title.attribute(.foregroundColor,at:range.location,effectiveRange:nil) as? NSColor)
        }
        let title = make()
        for (value,level) in [("95%",StatusBarTitle.Level.critical),("85%",.warning),("70%",.critical),("80B",.critical)] {
            let actual = try color(value,in:title)
            for name in [NSAppearance.Name.aqua,.darkAqua] {
                try XCTUnwrap(NSAppearance(named:name)).performAsCurrentDrawingAppearance {
                    XCTAssertEqual(actual.usingColorSpace(.sRGB),level.color.usingColorSpace(.sRGB))
                }
            }
        }
        for label in ["CPU","MEM","GPU","DISK","\u{53EF}\u{7528}","123M","44.0M"] {
            XCTAssertEqual(try color(label,in:title),.labelColor)
        }
        snapshot.cpu = 25
        XCTAssertEqual(try color("25%",in:make()),.labelColor)
    }

    func testAlertColorsRemainReadableOnLightAndDarkMenuBars() throws {
        func luminance(_ color: NSColor) throws -> Double {
            let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
            func linear(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value/12.92 : pow((value+0.055)/1.055,2.4)
            }
            return 0.2126*linear(rgb.redComponent)+0.7152*linear(rgb.greenComponent)+0.0722*linear(rgb.blueComponent)
        }
        for (name,background) in [(NSAppearance.Name.aqua,NSColor(white:0.95,alpha:1)),(.darkAqua,NSColor(white:0.12,alpha:1))] {
            try XCTUnwrap(NSAppearance(named:name)).performAsCurrentDrawingAppearance {
                for level in [StatusBarTitle.Level.warning,.critical] {
                    do {
                        let text = try luminance(level.color), bg = try luminance(background)
                        XCTAssertGreaterThanOrEqual((max(text,bg)+0.05)/(min(text,bg)+0.05),4.5)
                    } catch { XCTFail("Failed to resolve alert color: \(error)") }
                }
            }
        }
    }
}
