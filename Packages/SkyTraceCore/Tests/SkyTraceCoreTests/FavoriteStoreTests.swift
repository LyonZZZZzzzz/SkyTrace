import XCTest
@testable import SkyTraceCore

@MainActor
final class FavoriteStoreTests: XCTestCase {
    func testFavoritesAndRemindersPersist() throws {
        let suiteName = "SkyTraceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = FavoriteStore(defaults: defaults, namespace: "Favorites")
        XCTAssertTrue(store.toggleFavorite("star-1"))
        XCTAssertFalse(store.toggleFavorite("star-1"))
        XCTAssertTrue(store.toggleFavorite("star-2"))
        XCTAssertTrue(store.setReminder(true, for: "star-2"))
        XCTAssertFalse(store.setReminder(true, for: "star-1"))

        let restored = FavoriteStore(defaults: defaults, namespace: "Favorites")
        XCTAssertEqual(restored.favoriteIDs, ["star-2"])
        XCTAssertEqual(restored.reminderIDs, ["star-2"])

        restored.removeUnknownFavorites(validIDs: ["star-3"])
        XCTAssertTrue(restored.favoriteIDs.isEmpty)
        XCTAssertTrue(restored.reminderIDs.isEmpty)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDeniedReminderStillKeepsFavorite() async throws {
        let suiteName = "SkyTraceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = FavoriteStore(defaults: defaults, namespace: "Reminders")
        let scheduler = DeniedReminderScheduler()
        let catalog = try CatalogRepository()
        let viewModel = SkyViewModel(
            locationService: CoreLocationService(),
            motionService: NoopDeviceMotionProvider(),
            astronomy: AstronomyService(),
            catalog: catalog,
            planner: EmptyObservationPlanner(),
            favoriteStore: store,
            reminderScheduler: scheduler
        )
        let object = try XCTUnwrap(catalog.allObjects.first)

        await viewModel.toggleReminder(for: object)

        XCTAssertTrue(viewModel.isFavorite(object.id))
        XCTAssertFalse(viewModel.isReminderEnabled(object.id))
        XCTAssertNotNil(viewModel.toastMessage)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class DeniedReminderScheduler: ObservationReminderScheduling {
    var authorizationStatus: ObservationNotificationAuthorization = .notDetermined
    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> Bool {
        authorizationStatus = .denied
        return false
    }
    func scheduleReminder(object: CelestialObject, at date: Date, observer: ObserverContext) async throws {
        throw ObservationReminderError.authorizationDenied
    }
    func removeReminder(objectID: String) {}
    func removeAllReminders() {}
}

private struct EmptyObservationPlanner: ObservationPlanning {
    func makePlan(
        for moment: SkyMoment,
        observer: ObserverContext,
        candidates: [CelestialObject],
        favoriteIDs: Set<String>,
        minimumAltitude: Double
    ) async -> ObservationPlan {
        let night = ObservationNight(
            anchorDate: moment.date,
            sunset: nil,
            sunrise: nil,
            civilDusk: nil,
            civilDawn: nil,
            nauticalDusk: nil,
            nauticalDawn: nil,
            astronomicalDusk: nil,
            astronomicalDawn: nil,
            effectiveDarkStart: nil,
            effectiveDarkEnd: nil,
            quality: .polarDay
        )
        let moon = MoonObservation(
            phase: .newMoon,
            phaseAngle: 0,
            illuminationFraction: 0,
            magnitude: -12,
            rise: nil,
            set: nil,
            altitudeAtBestTime: nil,
            azimuthAtBestTime: nil
        )
        return ObservationPlan(
            moment: moment,
            observer: observer,
            night: night,
            moon: moon,
            recommendations: [],
            favoriteVisibilities: [],
            warningMessage: "测试"
        )
    }
}
