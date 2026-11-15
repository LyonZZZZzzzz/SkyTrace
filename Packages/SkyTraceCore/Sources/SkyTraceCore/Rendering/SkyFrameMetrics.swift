import Foundation

/// Lightweight frame telemetry used by Debug and Instruments builds.
///
/// The release build keeps the counters but does not emit a signpost for every
/// frame. Samples are capped so time travel and camera interaction cannot grow
/// memory indefinitely.
public struct SkyFrameMetrics: Sendable {
    public var frameIntervals: [Double] { orderedSamples() }
    public private(set) var geometryRebuildCount = 0
    public private(set) var dynamicNodeUpdateCount = 0
    public private(set) var labelProjectionDuration: Double = 0
    public private(set) var lastFrameInterval: Double = 0
    public private(set) var consecutiveSlowFrames = 0
    public private(set) var longestSlowFrameRun = 0
    public private(set) var longestFrameInterval: Double = 0
    public private(set) var mainThreadStallCount = 0
    public private(set) var measuredFrameCount = 0
    public var sampleWindowCount: Int { sampleCount }

    private var lastFrameTimestamp: TimeInterval?
    private let sampleCapacity: Int
    private var samples: [Double]
    private var writeIndex = 0
    private var sampleCount = 0
    private var intervalHistogram = Array(repeating: UInt64(0), count: 4_096)
    private var cumulativeFrameCount: UInt64 = 0

    public init(sampleCapacity: Int = 240) {
        self.sampleCapacity = max(sampleCapacity, 1)
        self.samples = Array(repeating: 0, count: max(sampleCapacity, 1))
    }

    public var averageFPS: Double {
        guard sampleCount > 0 else { return 0 }
        let total = orderedSamples().reduce(0, +)
        let average = total / Double(sampleCount)
        return average > 0 ? 1 / average : 0
    }

    public var p95FrameInterval: Double {
        percentile(0.95)
    }

    public var p99FrameInterval: Double {
        percentile(0.99)
    }

    public var cumulativeP95FrameInterval: Double {
        histogramPercentile(0.95)
    }

    public var cumulativeP99FrameInterval: Double {
        histogramPercentile(0.99)
    }

    public var cumulativeMeasuredFrameCount: UInt64 { cumulativeFrameCount }

    public mutating func recordFrame(at timestamp: TimeInterval) {
        guard timestamp.isFinite else { return }
        guard let lastFrameTimestamp else {
            self.lastFrameTimestamp = timestamp
            return
        }
        let interval = timestamp - lastFrameTimestamp
        guard interval.isFinite, interval > 0 else { return }
        self.lastFrameTimestamp = timestamp
        lastFrameInterval = interval
        longestFrameInterval = max(longestFrameInterval, interval)
        if interval >= 2 {
            mainThreadStallCount += 1
        }
        measuredFrameCount += 1
        cumulativeFrameCount &+= 1
        intervalHistogram[histogramIndex(for: interval)] &+= 1
        samples[writeIndex] = interval
        writeIndex = (writeIndex + 1) % sampleCapacity
        sampleCount = min(sampleCount + 1, sampleCapacity)
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
        writeIndex = 0
        sampleCount = 0
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
        longestFrameInterval = 0
        mainThreadStallCount = 0
        measuredFrameCount = 0
        intervalHistogram = Array(repeating: 0, count: intervalHistogram.count)
        cumulativeFrameCount = 0
    }

    private func percentile(_ value: Double) -> Double {
        let values = orderedSamples()
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int(ceil(value * Double(sorted.count))) - 1))
        return sorted[index]
    }

    private func histogramIndex(for interval: TimeInterval) -> Int {
        let bucket = (interval / 0.000_5).rounded(.down)
        return Int(min(bucket, Double(intervalHistogram.count - 1)))
    }

    private func histogramPercentile(_ percentile: Double) -> Double {
        guard cumulativeFrameCount > 0 else { return 0 }
        let target = UInt64(ceil(percentile * Double(cumulativeFrameCount)))
        var running: UInt64 = 0
        for (index, count) in intervalHistogram.enumerated() {
            running &+= count
            if running >= target {
                return Double(index) * 0.000_5 + 0.000_25
            }
        }
        return Double(intervalHistogram.count) * 0.000_5
    }

    private func orderedSamples() -> [Double] {
        guard sampleCount > 0 else { return [] }
        let oldest = (writeIndex - sampleCount + sampleCapacity) % sampleCapacity
        return (0..<sampleCount).map { samples[(oldest + $0) % sampleCapacity] }
    }
}
