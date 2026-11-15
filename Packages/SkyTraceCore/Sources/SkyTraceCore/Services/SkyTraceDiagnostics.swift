import Foundation
import os

public enum SkyTraceDiagnostics {
    public static let subsystem = "com.lyonzzzzzzzz.SkyTrace"

    public static let catalog = Logger(subsystem: subsystem, category: "Catalog")
    public static let snapshot = Logger(subsystem: subsystem, category: "Snapshot")
    public static let planning = Logger(subsystem: subsystem, category: "ObservationPlanning")
    public static let frames = Logger(subsystem: subsystem, category: "Frames")
    public static let notifications = Logger(subsystem: subsystem, category: "Notifications")

    private static let signposter = OSSignposter(subsystem: subsystem, category: "Performance")

    public static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

final class SkyRendererLifecycleTrace: Sendable {
    private static let enabled = ProcessInfo.processInfo.arguments.contains("--trace-renderer-lifecycle")
    private static let signposter = OSSignposter(
        subsystem: SkyTraceDiagnostics.subsystem,
        category: "PointsOfInterest"
    )

    private let id = signposter.makeSignpostID()
    private let awaitingFirstFrame = OSAllocatedUnfairLock(initialState: false)

    static func makeIfEnabled() -> SkyRendererLifecycleTrace? {
        enabled ? SkyRendererLifecycleTrace() : nil
    }

    func event(_ name: StaticString) {
        Self.signposter.emitEvent(name, id: id)
    }

    func awaitFirstFrame() {
        awaitingFirstFrame.withLock { awaiting in
            event("RendererResumeRequested")
            awaiting = true
        }
    }

    func cancelFirstFrame() {
        awaitingFirstFrame.withLock { $0 = false }
    }

    func recordFirstFrame() {
        awaitingFirstFrame.withLock { awaiting in
            guard awaiting else { return }
            awaiting = false
            event("RendererFirstFrameAfterResume")
        }
    }
}
