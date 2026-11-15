import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// A bounded, UI-friendly snapshot of long-running renderer health.
public struct SkyRenderDiagnostics: Sendable, Equatable {
    public let renderQuality: SkyRenderQuality
    public let renderActivity: SkyRenderActivity
    public let p95FrameInterval: Double
    public let p99FrameInterval: Double
    public let cumulativeP95FrameInterval: Double
    public let cumulativeP99FrameInterval: Double
    public let cumulativeFrameCount: UInt64
    public let longestFrameInterval: Double
    public let mainThreadStallCount: Int
    public let labelNodeCount: Int
    public let pendingLabelTextUpdates: Int
    public let geometryRebuildCount: Int
    public let labelSourceCount: Int
    public let displayedLabelCount: Int
    public let residentMemoryBytes: UInt64

    public init(
        renderQuality: SkyRenderQuality = .normal,
        renderActivity: SkyRenderActivity = .idle,
        p95FrameInterval: Double = 0,
        p99FrameInterval: Double = 0,
        cumulativeP95FrameInterval: Double = 0,
        cumulativeP99FrameInterval: Double = 0,
        cumulativeFrameCount: UInt64 = 0,
        longestFrameInterval: Double = 0,
        mainThreadStallCount: Int = 0,
        labelNodeCount: Int = 0,
        pendingLabelTextUpdates: Int = 0,
        geometryRebuildCount: Int = 0,
        labelSourceCount: Int = 0,
        displayedLabelCount: Int = 0,
        residentMemoryBytes: UInt64 = 0
    ) {
        self.renderQuality = renderQuality
        self.renderActivity = renderActivity
        self.p95FrameInterval = p95FrameInterval
        self.p99FrameInterval = p99FrameInterval
        self.cumulativeP95FrameInterval = cumulativeP95FrameInterval
        self.cumulativeP99FrameInterval = cumulativeP99FrameInterval
        self.cumulativeFrameCount = cumulativeFrameCount
        self.longestFrameInterval = longestFrameInterval
        self.mainThreadStallCount = mainThreadStallCount
        self.labelNodeCount = labelNodeCount
        self.pendingLabelTextUpdates = pendingLabelTextUpdates
        self.geometryRebuildCount = geometryRebuildCount
        self.labelSourceCount = labelSourceCount
        self.displayedLabelCount = displayedLabelCount
        self.residentMemoryBytes = residentMemoryBytes
    }

    public static let empty = SkyRenderDiagnostics()
}

public enum SkyRenderActivity: String, Sendable, Equatable {
    case suspended
    case idle
    case warmup
    case interactive
    case animating
}

enum SkyProcessMemory {
    static func residentBytes() -> UInt64 {
#if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
#else
        return 0
#endif
    }
}
