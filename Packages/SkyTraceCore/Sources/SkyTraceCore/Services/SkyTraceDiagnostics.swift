import Foundation
import os

public enum SkyTraceDiagnostics {
    public static let subsystem = "com.lyonzzzzzzzz.SkyTrace"

    public static let catalog = Logger(subsystem: subsystem, category: "Catalog")
    public static let snapshot = Logger(subsystem: subsystem, category: "Snapshot")
    public static let planning = Logger(subsystem: subsystem, category: "ObservationPlanning")
    public static let notifications = Logger(subsystem: subsystem, category: "Notifications")

    private static let signposter = OSSignposter(subsystem: subsystem, category: "Performance")

    public static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
