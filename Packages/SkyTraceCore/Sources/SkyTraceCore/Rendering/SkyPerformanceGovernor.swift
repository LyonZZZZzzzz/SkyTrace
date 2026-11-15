import Foundation

/// Converts sustained frame-time degradation into a bounded render-quality
/// level. Thresholds use hysteresis so a single transition or label warmup
/// cannot permanently reduce quality.
struct SkyPerformanceGovernor: Sendable {
    private(set) var level: SkyRenderQuality = .normal
    private var degradationStartedAt: TimeInterval?
    private var criticalStartedAt: TimeInterval?
    private var recoveryStartedAt: TimeInterval?

    mutating func update(metrics: SkyFrameMetrics, at time: TimeInterval) -> SkyRenderQuality {
        guard metrics.sampleWindowCount >= 90 else { return level }

        let p95 = metrics.p95FrameInterval
        let p99 = metrics.p99FrameInterval
        switch level {
        case .normal:
            guard p95 > 0.030, p99 > 0.055 else {
                degradationStartedAt = nil
                return level
            }
            if degradationStartedAt == nil {
                degradationStartedAt = time
            } else if time - (degradationStartedAt ?? time) >= 2 {
                level = .elevated
                resetTimers()
            }
        case .elevated:
            if p95 > 0.060, p99 > 0.090 {
                recoveryStartedAt = nil
                if criticalStartedAt == nil {
                    criticalStartedAt = time
                } else if time - (criticalStartedAt ?? time) >= 5 {
                    level = .critical
                    resetTimers()
                }
            } else if p95 < 0.045, p99 < 0.045 {
                criticalStartedAt = nil
                if recoveryStartedAt == nil {
                    recoveryStartedAt = time
                } else if time - (recoveryStartedAt ?? time) >= 5 {
                    level = .normal
                    resetTimers()
                }
            } else {
                resetTimers()
            }
        case .critical:
            guard p95 < 0.050, p99 < 0.050 else {
                recoveryStartedAt = nil
                return level
            }
            if recoveryStartedAt == nil {
                recoveryStartedAt = time
            } else if time - (recoveryStartedAt ?? time) >= 10 {
                level = .elevated
                resetTimers()
            }
        }
        return level
    }

    mutating func reset() {
        level = .normal
        resetTimers()
    }

    private mutating func resetTimers() {
        degradationStartedAt = nil
        criticalStartedAt = nil
        recoveryStartedAt = nil
    }
}
