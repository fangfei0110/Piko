import XCTest
@testable import PulseBar

final class MetricsTests: XCTestCase {
    func testCPUUsesAllTickStatesAndIdleIndex() {
        let result = MetricMath.cpu(current:[160,120,260,110,110,110,180,100],previous:[100,100,100,100,100,100,100,100])
        XCTAssertEqual(result[0],36,accuracy:0.001)
        XCTAssertEqual(result[1],20,accuracy:0.001)
    }
    func testCPUHandlesCounterWrapAndTopologyChanges() {
        XCTAssertEqual(MetricMath.cpu(current:[2,0,3,0],previous:[UInt32.max,0,0,0])[0],50,accuracy:0.001)
        XCTAssertTrue(MetricMath.cpu(current:[1,2,3,4],previous:[]).isEmpty)
    }
    func testRatesRejectCounterResetAndInvalidTime() {
        XCTAssertNil(MetricMath.rate(current:10,previous:100,seconds:1))
        XCTAssertNil(MetricMath.rate(current:100,previous:10,seconds:0))
        XCTAssertNil(MetricMath.rate(current:100,previous:10,seconds:.nan))
        XCTAssertEqual(MetricMath.rate(current:4096,previous:2048,seconds:2),1024)
    }
    func testRatesPreserveCountersLargerThanFourGiB() {
        XCTAssertEqual(MetricMath.rate(current:29_629_509_379,previous:29_629_505_283,seconds:2),2048)
        XCTAssertEqual(Readout.bytes(UInt64(29_629_509_379)),"27.6 GiB")
    }
    func testMemoryExcludesReclaimableCacheFromUsed() {
        let memory = MemoryReading(total:16000,app:6000,wired:2000,compressed:1000,cached:5000,free:2000,swapUsed:0,swapTotal:0,pressure:1)
        XCTAssertEqual(memory.used,9000)
        XCTAssertEqual(memory.percent,56.25)
        XCTAssertEqual(memory.pressureName,"正常")
    }
    func testUnitFormattingAndMissingReadings() {
        XCTAssertEqual(Readout.bytes(UInt64(1_073_741_824)),"1.0 GiB")
        XCTAssertEqual(Readout.rate(nil),"—")
        XCTAssertEqual(Readout.percent(nil),"—")
        XCTAssertEqual(Readout.bytes(Double.infinity),"—")
    }
}
