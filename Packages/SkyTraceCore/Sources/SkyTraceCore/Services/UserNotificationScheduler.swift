@preconcurrency import UserNotifications
import Foundation

@MainActor
public final class UserNotificationScheduler: ObservationReminderScheduling {
    public private(set) var authorizationStatus: ObservationNotificationAuthorization = .notDetermined

    @ObservationIgnored private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = Self.map(settings.authorizationStatus)
    }

    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            authorizationStatus = .denied
            return false
        }
    }

    public func scheduleReminder(
        object: CelestialObject,
        at date: Date,
        observer: ObserverContext
    ) async throws {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            throw ObservationReminderError.authorizationDenied
        }
        guard date > Date() else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = observer.timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.timeZone = observer.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "\(object.name) 进入最佳观测时刻"
        content.body = "\(observer.name) · \(object.subtitle)，现在适合抬头观察。"
        content.sound = .default
        content.userInfo = ["objectID": object.id]

        let identifier = Self.identifier(for: object.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            SkyTraceDiagnostics.notifications.info("Scheduled observation reminder")
        } catch {
            throw ObservationReminderError.schedulingFailed(error.localizedDescription)
        }
    }

    public func removeReminder(objectID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: objectID)])
    }

    public func removeAllReminders() {
        center.removeAllPendingNotificationRequests()
    }

    private static func identifier(for objectID: String) -> String {
        "SkyTrace.Observation.\(objectID)"
    }

    private static func map(_ status: UNAuthorizationStatus) -> ObservationNotificationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .provisional, .ephemeral: .provisional
        @unknown default: .denied
        }
    }
}
