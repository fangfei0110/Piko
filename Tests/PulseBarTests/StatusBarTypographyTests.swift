import AppKit
import XCTest
@testable import PulseBar

final class StatusBarTypographyTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults,String) throws -> Void) throws {
        let suite = "PikoTypographyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        try body(defaults,suite)
    }

    func testExistingInstallationKeepsCurrentTypographyAndOtherPreferences() throws {
        try withDefaults { defaults,_ in
            defaults.set("dark",forKey:"appearance")
            defaults.set(false,forKey:"showDisk")
            defaults.set(5,forKey:"interval")
            let typography = StatusBarTypography.load(from:defaults)
            XCTAssertEqual(typography,StatusBarTypography())
            XCTAssertEqual(typography.label.font(),NSFont.systemFont(ofSize:11,weight:.medium))
            XCTAssertEqual(typography.value.font(numeric:true),NSFont.monospacedDigitSystemFont(ofSize:12,weight:.semibold))
            typography.save(to:defaults)
            XCTAssertEqual(defaults.string(forKey:"appearance"),"dark")
            XCTAssertFalse(defaults.bool(forKey:"showDisk"))
            XCTAssertEqual(defaults.integer(forKey:"interval"),5)
        }
    }

    func testIndependentChoicesSurviveReloadIncludingUncheckedBold() throws {
        try withDefaults { defaults,suite in
            let expected = StatusBarTypography(label:StatusBarFontStyle(family:.rounded,size:15,bold:true),
                                               value:StatusBarFontStyle(family:.monospaced,size:10,bold:false))
            expected.save(to:defaults)
            let reloaded = try XCTUnwrap(UserDefaults(suiteName:suite))
            XCTAssertEqual(StatusBarTypography.load(from:reloaded),expected)
        }
    }

    func testInvalidStoredFontsAndSizesFallBackWithoutAffectingValidChoices() throws {
        try withDefaults { defaults,_ in
            defaults.set("removed-font",forKey:"statusBarLabelFontFamily")
            defaults.set("rounded",forKey:"statusBarValueFontFamily")
            defaults.set(false,forKey:"statusBarValueBold")
            for invalid in [-100.0,0,8,11.5,17,1e30] {
                defaults.set(invalid,forKey:"statusBarLabelFontSize")
                defaults.set(invalid,forKey:"statusBarValueFontSize")
                let loaded = StatusBarTypography.load(from:defaults)
                XCTAssertEqual(loaded.label,StatusBarTypography().label)
                XCTAssertEqual(loaded.value,StatusBarFontStyle(family:.rounded,size:12,bold:false))
            }
        }
    }

    func testEveryFontChoiceKeepsDigitsTabularAtSupportedSizes() {
        for family in StatusBarFontFamily.allCases {
            for size in [9,12,16] {
                for bold in [false,true] {
                    let font = StatusBarFontStyle(family:family,size:size,bold:bold).font(numeric:true)
                    XCTAssertEqual(font.pointSize,CGFloat(size))
                    let widths = (0...9).map { (String($0) as NSString).size(withAttributes:[.font:font]).width }
                    XCTAssertEqual(widths.min()!,widths.max()!,accuracy:0.01,"\(family) \(size) \(bold)")
                }
            }
        }
    }

    func testTitleUsesSeparateFontsForLabelsAndAllNumericReadouts() throws {
        var snapshot = Snapshot()
        snapshot.cpu = 27
        snapshot.disks = [DiskReading(id:"/System/Volumes/Data",name:"Macintosh HD",total:1_000_000,available:35_840,internalDisk:true)]
        snapshot.networks = [NetworkReading(id:"en0",address:"",received:0,sent:0,download:12_288,upload:3_072,isPrimary:true)]
        let typography = StatusBarTypography(label:StatusBarFontStyle(family:.monospaced,size:16,bold:true),
                                             value:StatusBarFontStyle(family:.rounded,size:9,bold:false))
        let title = StatusBarTitle.make(snapshot:snapshot,showCPU:true,showMemory:false,showGPU:false,
            showNetwork:true,showDisk:true,paused:false,typography:typography)
        for label in ["CPU","DISK","\u{53EF}\u{7528}"] {
            let index = (title.string as NSString).range(of:label).location
            XCTAssertNotEqual(index,NSNotFound)
            guard index != NSNotFound else { continue }
            XCTAssertEqual(title.attribute(.font,at:index,effectiveRange:nil) as? NSFont,typography.label.font())
        }
        for value in ["27%","35.0K","12.0K","3.0K"] {
            let index = (title.string as NSString).range(of:value).location
            XCTAssertNotEqual(index,NSNotFound)
            guard index != NSNotFound else { continue }
            XCTAssertEqual(title.attribute(.font,at:index,effectiveRange:nil) as? NSFont,typography.value.font(numeric:true))
        }
        XCTAssertLessThanOrEqual(title.size().height,24)
    }
}
