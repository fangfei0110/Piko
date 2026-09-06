import XCTest
@testable import PulseBar

final class PaletteTests: XCTestCase {
    private func luminance(_ tone: ColorTone) -> Double {
        let (r,g,b) = tone.rgb
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055,2.4) }
        return 0.2126*linear(r) + 0.7152*linear(g) + 0.0722*linear(b)
    }
    private func contrast(_ a: ColorTone,_ b: ColorTone) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x,y)+0.05)/(min(x,y)+0.05)
    }
    private func checkContrast(_ palette: Palette,file: StaticString = #filePath,line: UInt = #line) {
        for color in [palette.inkTone,palette.secondaryInkTone,palette.brandTone,palette.supportingTone,palette.transferTone,palette.warningTone,palette.positiveTone] {
            XCTAssertGreaterThanOrEqual(contrast(color,palette.cardTone),4.5,file:file,line:line)
        }
        for color in [palette.brandTone,palette.supportingTone,palette.transferTone,palette.warningTone] {
            XCTAssertGreaterThanOrEqual(contrast(palette.onTintTone,color),4.5,file:file,line:line)
        }
        XCTAssertGreaterThanOrEqual(contrast(palette.secondaryInkTone,palette.shellTone),4.5,file:file,line:line)
        // The compact header displays status and brand directly on the shell.
        for color in [palette.inkTone,palette.brandTone,palette.warningTone] {
            XCTAssertGreaterThanOrEqual(contrast(color,palette.shellTone),4.5,file:file,line:line)
        }
    }
    func testColdPaletteTextAndControlsHaveSufficientContrast() {
        checkContrast(MonitorAppearance.cold.palette)
    }
    func testWarmPaletteTextAndControlsHaveSufficientContrast() {
        checkContrast(MonitorAppearance.warm.palette)
    }
    func testDarkPaletteTextAndControlsHaveSufficientContrast() {
        checkContrast(MonitorAppearance.dark.palette)
    }
    func testLegacyAndInvalidAppearanceMigrationPreservesOtherPreferences() throws {
        let suite = "PulseBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(5.0,forKey:"interval")
        defaults.set(false,forKey:"showCPU")
        let cases: [(String?,MonitorAppearance)] = [(nil,.cold),("system",.cold),("light",.cold),("dark",.dark),("invalid",.cold)]
        for (stored,expected) in cases {
            defaults.set(stored,forKey:"appearance")
            XCTAssertEqual(MonitorAppearance.load(from:defaults),expected)
            XCTAssertEqual(defaults.string(forKey:"appearance"),expected.rawValue)
        }
        XCTAssertEqual(defaults.double(forKey:"interval"),5)
        XCTAssertFalse(defaults.bool(forKey:"showCPU"))
    }
    func testEveryThemeSurvivesPreferenceReload() throws {
        let suite = "PulseBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        for appearance in MonitorAppearance.allCases {
            defaults.set(appearance.rawValue,forKey:"appearance")
            let reloaded = try XCTUnwrap(UserDefaults(suiteName:suite))
            XCTAssertEqual(MonitorAppearance.load(from:reloaded),appearance)
            XCTAssertEqual(MonitorAppearance.load(from:reloaded),appearance)
        }
    }
    func testNeutralColorConversionPreservesEndpoints() {
        let white = ColorTone(1,0,0).rgb, black = ColorTone(0,0,0).rgb
        for value in [white.0,white.1,white.2] { XCTAssertEqual(value,1,accuracy:0.00001) }
        for value in [black.0,black.1,black.2] { XCTAssertEqual(value,0,accuracy:0.00001) }
    }
}
