import XCTest
@testable import SkyTraceCore

@MainActor
final class ReminderSchedulingTests: XCTestCase {
    func testSchedulingFailureDoesNotRemovePreviouslyScheduledReminder() async throws {
        let namespace = "ReminderSchedulingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: namespace))
        defer { defaults.removePersistentDomain(forName: namespace) }

        let catalog = try CatalogRepository()
        let moon = try XCTUnwrap(catalog.allObjects.first { $0.id == "moon" })
        let store = FavoriteStore(defaults: defaults, namespace: namespace)
        XCTAssertTrue(store.toggleFavorite(moon.id))
        XCTAssertTrue(store.setReminder(true, for: moon.id))
        store.remindersEnabled = true

        let scheduler = RecordingReminderScheduler()
        let planner = ReminderPlanPlanner()
        let viewModel = SkyViewModel(
            locationService: CoreLocationService(),
            motionService: NoopDeviceMotionProvider(),
            astronomy: AstronomyService(),
            catalog: catalog,
            planner: planner,
            favoriteStore: store,
            reminderScheduler: scheduler
        )

        viewModel.ensureTonightDataLoaded()
        let planReady = await waitUntil { viewModel.observationPlanState == .ready }
        let reminderScheduled = await waitUntil { scheduler.scheduledIDs.contains(moon.id) }
        XCTAssertTrue(planReady)
        XCTAssertTrue(reminderScheduled)

        scheduler.failScheduling = true
        viewModel.setDate(viewModel.moment.date.addingTimeInterval(3_600))
        let secondAttempt = await waitUntil { scheduler.scheduleAttempts >= 2 }
        XCTAssertTrue(secondAttempt)

        XCTAssertFalse(scheduler.removedIDs.contains(moon.id))
        XCTAssertFalse(scheduler.didRemoveAll)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

@MainActor
private final class RecordingReminderScheduler: ObservationReminderScheduling {
    private(set) var authorizationStatus: ObservationNotificationAuthorization = .authorized
    private(set) var scheduleAttempts = 0
    private(set) var scheduledIDs: Set<String> = []
    private(set) var removedIDs: Set<String> = []
    private(set) var didRemoveAll = false
    var failScheduling = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> Bool { true }

    func scheduleReminder(
        object: CelestialObject,
        at date: Date,
        observer: ObserverContext
    ) async throws {
        scheduleAttempts += 1
        guard !failScheduling else {
            throw ObservationReminderError.schedulingFailed("test")
        }
        scheduledIDs.insert(object.id)
    }

    func removeReminder(objectID: String) {
        removedIDs.insert(objectID)
        scheduledIDs.remove(objectID)
    }

    func removeAllReminders() {
        didRemoveAll = true
        scheduledIDs.removeAll()
    }
}

private actor ReminderPlanPlanner: ObservationPlanning {
    private let planner = ObservationPlanner()

    func makePlan(
        for moment: SkyMoment,
        observer: ObserverContext,
        candidates: [CelestialObject],
        favoriteIDs: Set<String>,
        minimumAltitude: Double
    ) async -> ObservationPlan {
        let base = await planner.makePlan(
            for: moment,
            observer: observer,
            candidates: candidates,
            favoriteIDs: favoriteIDs,
            minimumAltitude: minimumAltitude
        )
        guard let moon = candidates.first(where: { $0.id == "moon" }) else { return base }
        let visibility = base.favoriteVisibilities.first(where: { $0.object.id == moon.id }) ??
            ObservationVisibility(
                object: moon,
                start: moment.date,
                end: moment.date.addingTimeInterval(3_600),
                bestTime: moment.date.addingTimeInterval(1_800),
                maximumAltitude: 45,
                duration: 3_600,
                score: 1,
                reason: .bestAfterDark,
                moonSeparation: nil
            )
        return ObservationPlan(
            moment: base.moment,
            observer: base.observer,
            night: base.night,
            moon: base.moon,
            recommendations: base.recommendations,
            favoriteVisibilities: [visibility],
            warningMessage: base.warningMessage
        )
    }
}
