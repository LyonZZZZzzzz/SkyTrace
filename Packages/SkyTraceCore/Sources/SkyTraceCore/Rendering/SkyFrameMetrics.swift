import Foundation

/// Lightweight frame telemetry used by Debug and Instruments builds.
///
/// The release build keeps the counters but does not emit a signpost for every
/// frame. Samples are capped so time travel and camera interaction cannot grow
/// memory indefinitely.
public struct SkyFrameMetrics: Sendable {
    public private(set) var frameIntervals: [Double] = []
    public private(set) var geometryRebuildCount = 0
    public private(set) var dynamicNodeUpdateCount = 0
    public private(set) var labelProjectionDuration: Double = 0
    public private(set) var lastFrameInterval: Double = 0
    public private(set) var consecutiveSlowFrames = 0
    public private(set) var longestSlowFrameRun = 0
    public private(set) var measuredFrameCount = 0

    private var lastFrameTimestamp: TimeInterval?
    private let sampleCapacity: Int

    public init(sampleCapacity: Int = 240) {
        self.sampleCapacity = max(sampleCapacity, 1)
    }

    public var averageFPS: Double {
        guard !frameIntervals.isEmpty else { return 0 }
        let average = frameIntervals.reduce(0, +) / Double(frameIntervals.count)
        return average > 0 ? 1 / average : 0
    }

    public var p95FrameInterval: Double {
        percentile(0.95)
    }

    public var p99FrameInterval: Double {
        percentile(0.99)
    }

    public mutating func recordFrame(at timestamp: TimeInterval) {
        defer { lastFrameTimestamp = timestamp }
        guard let lastFrameTimestamp else { return }
        let interval = max(timestamp - lastFrameTimestamp, 0)
        lastFrameInterval = interval
        measuredFrameCount += 1
        frameIntervals.append(interval)
        if frameIntervals.count > sampleCapacity {
            frameIntervals.removeFirst(frameIntervals.count - sampleCapacity)
        }
        if interval > 0.025 {
            consecutiveSlowFrames += 1
            longestSlowFrameRun = max(longestSlowFrameRun, consecutiveSlowFrames)
        } else {
            consecutiveSlowFrames = 0
        }
    }

    public mutating func recordGeometryRebuild() {
        geometryRebuildCount += 1
    }

    public mutating func recordDynamicNodeUpdate(count: Int = 1) {
        dynamicNodeUpdateCount += count
    }

    public mutating func recordLabelProjection(duration: Double) {
        labelProjectionDuration = duration
    }

    public mutating func resetSampling() {
        frameIntervals.removeAll(keepingCapacity: true)
        lastFrameInterval = 0
        consecutiveSlowFrames = 0
        lastFrameTimestamp = nil
    }

    public mutating func reset() {
        resetSampling()
        geometryRebuildCount = 0
        dynamicNodeUpdateCount = 0
        labelProjectionDuration = 0
        longestSlowFrameRun = 0
        measuredFrameCount = 0
    }

    private func percentile(_ value: Double) -> Double {
        guard !frameIntervals.isEmpty else { return 0 }
        let sorted = frameIntervals.sorted()
        let index = min(sorted.count - 1, max(0, Int(ceil(value * Double(sorted.count))) - 1))
        return sorted[index]
    }
}
