import XCTest
@testable import SkyTraceCore

final class SkyPerformanceGovernorTests: XCTestCase {
    func testSustainedSlowFramesDegradeAndRecoverWithHysteresis() {
        var governor = SkyPerformanceGovernor()
        let slow = makeMetrics(interval: 0.070)

        XCTAssertEqual(governor.update(metrics: slow, at: 10), .normal)
        XCTAssertEqual(governor.update(metrics: slow, at: 12.1), .elevated)

        let fast = makeMetrics(interval: 1.0 / 30.0)
        XCTAssertEqual(governor.update(metrics: fast, at: 20), .elevated)
        XCTAssertEqual(governor.update(metrics: fast, at: 25.1), .normal)
    }

    func testIsolatedSpikeDoesNotDegradeQuality() {
        var governor = SkyPerformanceGovernor()
        let isolatedSpike = makeMetrics(interval: 1.0 / 60.0, spikeCount: 1)

        XCTAssertEqual(governor.update(metrics: isolatedSpike, at: 10), .normal)
        XCTAssertEqual(governor.update(metrics: isolatedSpike, at: 12.1), .normal)
    }

    private func makeMetrics(interval: Double, spikeCount: Int = 0) -> SkyFrameMetrics {
        var metrics = SkyFrameMetrics(sampleCapacity: 180)
        var time = 0.0
        metrics.recordFrame(at: time)
        for index in 0..<120 {
            time += index < spikeCount ? 0.120 : interval
            metrics.recordFrame(at: time)
        }
        return metrics
    }
}
