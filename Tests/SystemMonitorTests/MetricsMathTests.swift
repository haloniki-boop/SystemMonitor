import XCTest
@testable import SystemMonitor

final class MetricsMathTests: XCTestCase {
    func testCPUUsageUsesTickDelta() {
        let previous = CPUTicks(user: 10, system: 10, idle: 80, nice: 0)
        let current = CPUTicks(user: 30, system: 20, idle: 150, nice: 0)
        XCTAssertEqual(MetricsMath.cpuUsage(previous: previous, current: current), 30, accuracy: 0.001)
    }

    func testMetricFractionIsClamped() {
        XCTAssertEqual(MetricValue(used: 120, remaining: 0, total: 100).fraction, 1)
        XCTAssertEqual(MetricValue(used: -10, remaining: 110, total: 100).fraction, 0)
        XCTAssertEqual(MetricValue(used: 10, remaining: 0, total: 0).fraction, 0)
    }

    func testLowRemainingThreshold() {
        XCTAssertTrue(MetricValue(used: 80, remaining: 20, total: 100).isLowRemaining)
        XCTAssertTrue(MetricValue(used: 95, remaining: 5, total: 100).isLowRemaining)
        XCTAssertFalse(MetricValue(used: 79, remaining: 21, total: 100).isLowRemaining)
    }

    func testByteLabelHasUnit() {
        XCTAssertTrue(MetricsMath.bytesLabel(8 * 1_073_741_824).contains("GB"))
    }
}
