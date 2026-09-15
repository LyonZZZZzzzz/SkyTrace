import Foundation

public enum ObservationNotificationAuthorization: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case provisional
}

public enum ObservationReminderError: LocalizedError {
    case authorizationDenied
    case schedulingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied: "系统通知权限未开启。"
        case .schedulingFailed(let message): "无法安排观测提醒：\(message)"
        }
    }
}

@MainActor
public protocol ObservationReminderScheduling: AnyObject {
    var authorizationStatus: ObservationNotificationAuthorization { get }

    func refreshAuthorizationStatus() async
    func requestAuthorization() async -> Bool
    func scheduleReminder(
        object: CelestialObject,
        at date: Date,
        observer: ObserverContext
    ) async throws
    func removeReminder(objectID: String)
    func removeAllReminders()
}

@MainActor
public final class NoopObservationReminderScheduler: ObservationReminderScheduling {
    public private(set) var authorizationStatus: ObservationNotificationAuthorization = .denied

    public init() {}
    public func refreshAuthorizationStatus() async {}
    public func requestAuthorization() async -> Bool { false }
    public func scheduleReminder(object: CelestialObject, at date: Date, observer: ObserverContext) async throws {
        throw ObservationReminderError.authorizationDenied
    }
    public func removeReminder(objectID: String) {}
    public func removeAllReminders() {}
}
