import XCTest
@testable import SkyTraceCore

final class SkyFrameMetricsTests: XCTestCase {
    func testPercentilesAndSlowFrameRuns() {
        var metrics = SkyFrameMetrics(sampleCapacity: 10)
        let intervals: [Double] = [1.0 / 60, 1.0 / 60, 1.0 / 60, 0.017, 0.018, 0.030, 0.031, 0.032, 0.016, 0.016]
        var timestamp = 0.0
        metrics.recordFrame(at: timestamp)

        for interval in intervals {
            timestamp += interval
            metrics.recordFrame(at: timestamp)
        }

        let expectedFPS = 1 / (intervals.reduce(0, +) / Double(intervals.count))
        XCTAssertEqual(metrics.averageFPS, expectedFPS, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(metrics.p95FrameInterval, 0.030)
        XCTAssertGreaterThanOrEqual(metrics.p99FrameInterval, 0.031)
        XCTAssertEqual(metrics.longestSlowFrameRun, 3)
        XCTAssertEqual(metrics.consecutiveSlowFrames, 0)
        XCTAssertEqual(metrics.measuredFrameCount, intervals.count)
    }

    func testSampleCapacityKeepsMemoryBounded() {
        var metrics = SkyFrameMetrics(sampleCapacity: 3)
        var timestamp = 0.0
        metrics.recordFrame(at: timestamp)
        for _ in 0..<10 {
            timestamp += 0.02
            metrics.recordFrame(at: timestamp)
        }

        XCTAssertEqual(metrics.frameIntervals.count, 3)
        XCTAssertEqual(metrics.measuredFrameCount, 10)
    }
}
