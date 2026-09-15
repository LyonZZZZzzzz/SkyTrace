import Foundation
import Observation

public enum CatalogState: Equatable, Sendable {
    case loading
    case ready
    case failed(String)
}

@MainActor
@Observable
public final class SkyViewModel {
    public private(set) var catalogState: CatalogState = .loading
    public private(set) var repository: (any SkyCatalogProviding)?

    public var observer: ObserverContext
    public var moment: SkyMoment
    public var snapshot: SkySnapshot = .empty
    public private(set) var sceneCatalog: SkySceneCatalog?

    public var selectedObjectID: String?
    public var searchQuery = ""
    public var searchResults: [CelestialObject] = []
    public var toastMessage: String?

    public var camera = SkyCameraState()
    public var isPlaying = false
    public var playbackDaysPerSecond = 1.0

    public private(set) var motionReading: SkyMotionReading?
    public private(set) var locationAuthorization: SkyLocationAuthorizationStatus = .notDetermined
    public private(set) var locationErrorMessage: String?

    public private(set) var observationPlan: ObservationPlan?
    public private(set) var observationPlanState: ObservationPlanState = .idle
    public private(set) var observationLogs: [ObservationLogEntry] = []
    public private(set) var observationLogError: String?
    public private(set) var astronomyEvents: [AstronomyEvent] = []
    public private(set) var astronomyEventState: ObservationPlanState = .idle
    public private(set) var reminderAuthorization: ObservationNotificationAuthorization = .notDetermined
    public var minimumObservationAltitude = 10.0

    public var motionEnabled = false {
        didSet {
            motionEnabled ? motionService.start() : motionService.stop()
        }
    }

    @ObservationIgnored public let locationService: any LocationProviding
    @ObservationIgnored public let motionService: any DeviceMotionProviding
    @ObservationIgnored public let favoriteStore: FavoriteStore
    @ObservationIgnored public let reminderScheduler: any ObservationReminderScheduling
    @ObservationIgnored public let logRepository: ObservationLogRepository
    @ObservationIgnored private let eventPlanner: any AstronomyEventPlanning
    @ObservationIgnored private let astronomy: any AstronomyCalculating
    @ObservationIgnored private let planner: any ObservationPlanning
    @ObservationIgnored private let snapshotWorker = SkySnapshotWorker()
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotBuildInFlight = false
    @ObservationIgnored private var snapshotGeneration: UInt64 = 0
    @ObservationIgnored private var pendingSnapshotRefresh: Bool?
    @ObservationIgnored private var snapshotWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var planTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    public convenience init() {
        self.init(
            locationService: CoreLocationService(),
            motionService: NoopDeviceMotionProvider(),
            astronomy: AstronomyService()
        )
    }

    public convenience init(catalog: any SkyCatalogProviding) {
        self.init(
            locationService: CoreLocationService(),
            motionService: NoopDeviceMotionProvider(),
            astronomy: AstronomyService(),
            catalog: catalog
        )
    }

    public init(
        locationService: any LocationProviding,
        motionService: any DeviceMotionProviding,
        astronomy: any AstronomyCalculating,
        catalog: (any SkyCatalogProviding)? = nil,
        planner: (any ObservationPlanning)? = nil,
        favoriteStore: FavoriteStore? = nil,
        reminderScheduler: (any ObservationReminderScheduling)? = nil,
        logRepository: ObservationLogRepository? = nil,
        eventPlanner: (any AstronomyEventPlanning)? = nil
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.astronomy = astronomy
        self.planner = planner ?? ObservationPlanner(astronomy: astronomy)
        self.favoriteStore = favoriteStore ?? FavoriteStore()
        self.reminderScheduler = reminderScheduler ?? NoopObservationReminderScheduler()
        self.logRepository = logRepository ?? ObservationLogRepository()
        self.eventPlanner = eventPlanner ?? AstronomyEventPlanner(astronomy: astronomy)
        observer = Self.loadObserver() ?? .shanghai
        moment = .now

        if let catalog {
            repository = catalog
            sceneCatalog = SkySceneCatalog(objects: catalog.allObjects, constellations: catalog.constellations)
            catalogState = .ready
            refreshSnapshot()
        } else {
            do {
                let loadedCatalog = try CatalogRepository()
                repository = loadedCatalog
                sceneCatalog = SkySceneCatalog(
                    objects: loadedCatalog.allObjects,
                    constellations: loadedCatalog.constellations
                )
                catalogState = .ready
                refreshSnapshot()
            } catch {
                catalogState = .failed(error.localizedDescription)
            }
        }

        bindServices()
        self.favoriteStore.removeUnknownFavorites(
            validIDs: Set(repository?.allObjects.map(\.id) ?? [])
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.reminderScheduler.refreshAuthorizationStatus()
            self.reminderAuthorization = self.reminderScheduler.authorizationStatus
            await self.loadObservationLogs()
            self.scheduleObservationPlanRefresh()
        }
    }

    deinit {
        playbackTask?.cancel()
        snapshotTask?.cancel()
        toastTask?.cancel()
        planTask?.cancel()
        eventTask?.cancel()
    }

    public var cameraAzimuth: Double {
        get { camera.azimuth }
        set { camera.azimuth = Self.normalizedDegrees(newValue) }
    }

    public var cameraAltitude: Double {
        get { camera.altitude }
        set { camera.altitude = min(89, max(-89, newValue)) }
    }

    public var cameraRoll: Double {
        get { camera.roll }
        set { camera.roll = Self.normalizedDegrees(newValue) }
    }

    public var fieldOfView: Double {
        get { camera.fieldOfView }
        set { camera.fieldOfView = min(110, max(20, newValue)) }
    }

    public var selectedObject: CelestialObject? {
        guard let selectedObjectID else { return nil }
        return repository?.allObjects.first { $0.id == selectedObjectID }
    }

    public var favoriteObjects: [CelestialObject] {
        let IDs = favoriteStore.favoriteIDs
        return repository?.allObjects
            .filter { IDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
    }

    public var favoriteIDs: Set<String> {
        favoriteStore.favoriteIDs
    }

    public var visibilityByObjectID: [String: ObservationVisibility] {
        let visibilities = (observationPlan?.recommendations ?? []) + (observationPlan?.favoriteVisibilities ?? [])
        return Dictionary(visibilities.map { ($0.object.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func visibility(for objectID: String) -> ObservationVisibility? {
        visibilityByObjectID[objectID]
    }

    public func observationLogs(for objectID: String) -> [ObservationLogEntry] {
        observationLogs.filter { $0.objectID == objectID }
    }

    public func loadObservationLogs(filter: ObservationLogFilter = ObservationLogFilter()) async {
        do {
            observationLogs = try await logRepository.entries(matching: filter)
            observationLogError = nil
            if filter == ObservationLogFilter(), let validIDs = repository.map({ Set($0.allObjects.map(\.id)) }) {
                try? await logRepository.removeUnknownObjects(validIDs: validIDs)
            }
        } catch {
            observationLogError = error.localizedDescription
            observationLogs = []
        }
    }

    @discardableResult
    public func saveObservationLog(_ entry: ObservationLogEntry) async -> Bool {
        do {
            _ = try await logRepository.save(entry)
            await loadObservationLogs()
            showToast("观测记录已保存")
            return true
        } catch {
            observationLogError = error.localizedDescription
            showToast(error.localizedDescription)
            return false
        }
    }

    public func deleteObservationLog(id: UUID) async {
        do {
            try await logRepository.delete(id: id)
            await loadObservationLogs()
        } catch {
            observationLogError = error.localizedDescription
            showToast(error.localizedDescription)
        }
    }

    public func isFavorite(_ objectID: String) -> Bool {
        favoriteStore.isFavorite(objectID)
    }

    public func isReminderEnabled(_ objectID: String) -> Bool {
        favoriteStore.isReminderEnabled(objectID)
    }

    public func toggleFavorite(_ object: CelestialObject) {
        let enabled = favoriteStore.toggleFavorite(object.id)
        if !enabled {
            reminderScheduler.removeReminder(objectID: object.id)
        }
        scheduleObservationPlanRefresh()
    }

    public func toggleReminder(for object: CelestialObject) async {
        if favoriteStore.isReminderEnabled(object.id) {
            favoriteStore.setReminder(false, for: object.id)
            reminderScheduler.removeReminder(objectID: object.id)
            return
        }

        if !favoriteStore.isFavorite(object.id) {
            favoriteStore.toggleFavorite(object.id)
        }

        if reminderScheduler.authorizationStatus == .notDetermined {
            let granted = await reminderScheduler.requestAuthorization()
            reminderAuthorization = reminderScheduler.authorizationStatus
            if !granted {
                showToast("通知权限未开启，收藏已保存，但不会发送提醒。")
                return
            }
        }
        guard reminderScheduler.authorizationStatus == .authorized || reminderScheduler.authorizationStatus == .provisional else {
            reminderAuthorization = reminderScheduler.authorizationStatus
            showToast("通知权限未开启，可在系统设置中允许。")
            return
        }

        favoriteStore.remindersEnabled = true
        favoriteStore.setReminder(true, for: object.id)
        scheduleObservationPlanRefresh()
    }

    public func setRemindersEnabled(_ enabled: Bool) async {
        guard enabled else {
            favoriteStore.remindersEnabled = false
            reminderScheduler.removeAllReminders()
            return
        }
        if reminderScheduler.authorizationStatus == .notDetermined {
            let granted = await reminderScheduler.requestAuthorization()
            reminderAuthorization = reminderScheduler.authorizationStatus
            guard granted else {
                showToast("通知权限未开启，可在系统设置中允许。")
                return
            }
        }
        guard reminderScheduler.authorizationStatus == .authorized || reminderScheduler.authorizationStatus == .provisional else {
            reminderAuthorization = reminderScheduler.authorizationStatus
            showToast("通知权限未开启，可在系统设置中允许。")
            return
        }
        favoriteStore.remindersEnabled = true
        scheduleObservationPlanRefresh()
    }

    public var selectedPosition: SkyPosition? {
        guard let selectedObjectID else { return nil }
        return snapshot.positions.first { $0.id == selectedObjectID }
    }

    public var formattedMoment: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = observer.timeZone
        formatter.dateFormat = "M月d日 EEEE HH:mm"
        return formatter.string(from: moment.date)
    }

    public var observerSubtitle: String {
        String(format: "%@ · %.2f°, %.2f°", observer.name, observer.latitude, observer.longitude)
    }

    public var cameraDirection: Vector3D {
        camera.direction
    }

    public var dateRange: ClosedRange<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let lower = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))!
        let upper = calendar.date(from: DateComponents(year: 2100, month: 12, day: 31, hour: 23, minute: 59))!
        return lower...upper
    }

    public func refreshSnapshot(updateObservationPlan: Bool = true) {
        guard let repository else { return }
        snapshotGeneration &+= 1
        snapshotTask?.cancel()
        let nextSnapshot = SkySnapshotBuilder.makeSnapshot(
            objects: repository.allObjects,
            constellations: repository.constellations,
            moment: moment,
            observer: observer,
            astronomy: astronomy
        )
        applySnapshot(nextSnapshot, updateObservationPlan: updateObservationPlan)
    }

    private func scheduleSnapshotRefresh(updateObservationPlan: Bool) {
        guard repository != nil else { return }
        snapshotGeneration &+= 1
        pendingSnapshotRefresh = (pendingSnapshotRefresh ?? false) || updateObservationPlan
        guard !snapshotBuildInFlight else { return }
        startNextSnapshotBuild()
    }

    private func startNextSnapshotBuild() {
        guard
            let repository,
            let updateObservationPlan = pendingSnapshotRefresh
        else {
            resumeSnapshotWaitersIfIdle()
            return
        }

        pendingSnapshotRefresh = nil
        snapshotBuildInFlight = true
        let generation = snapshotGeneration
        let objects = repository.allObjects
        let constellations = repository.constellations
        let moment = moment
        let observer = observer
        let astronomy = astronomy
        let worker = snapshotWorker

        snapshotTask = Task { [weak self] in
            let nextSnapshot = await worker.makeSnapshot(
                objects: objects,
                constellations: constellations,
                moment: moment,
                observer: observer,
                astronomy: astronomy
            )
            guard let self else { return }
            self.snapshotBuildInFlight = false
            if !Task.isCancelled,
               generation == self.snapshotGeneration,
               self.moment == moment,
               self.observer == observer {
                self.applySnapshot(nextSnapshot, updateObservationPlan: updateObservationPlan)
            }
            self.startNextSnapshotBuild()
        }
    }

    private func resumeSnapshotWaitersIfIdle() {
        guard !snapshotBuildInFlight, pendingSnapshotRefresh == nil else { return }
        let waiters = snapshotWaiters
        snapshotWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    public func waitForSnapshotUpdate() async {
        guard snapshotBuildInFlight || pendingSnapshotRefresh != nil else { return }
        await withCheckedContinuation { continuation in
            snapshotWaiters.append(continuation)
        }
    }

    private func applySnapshot(_ nextSnapshot: SkySnapshot, updateObservationPlan: Bool) {
        snapshot = nextSnapshot
        if updateObservationPlan {
            scheduleObservationPlanRefresh()
            scheduleAstronomyEventRefresh()
        }
    }

    public func setDate(_ date: Date, recenter: Bool = false) {
        moment = SkyMoment(date: min(max(date, dateRange.lowerBound), dateRange.upperBound))
        scheduleSnapshotRefresh(updateObservationPlan: true)
        if recenter, let id = selectedObjectID {
            Task { [weak self] in
                await self?.waitForSnapshotUpdate()
                self?.center(on: id)
            }
        }
    }

    public func shiftTime(by interval: TimeInterval) {
        setDate(moment.date.addingTimeInterval(interval))
    }

    public func resetToNow() {
        setDate(Date())
    }

    public func togglePlayback() {
        isPlaying ? stopPlayback() : startPlayback()
    }

    public func search() {
        searchResults = repository?.search(searchQuery, limit: 30) ?? []
    }

    public func select(_ object: CelestialObject, focus: Bool = true) {
        selectedObjectID = object.id
        if focus, let position = snapshot.positions.first(where: { $0.object.id == object.id }) {
            cameraAzimuth = position.azimuth
            cameraAltitude = max(-20, min(80, position.altitude))
        }
    }

    public func clearSelection() {
        selectedObjectID = nil
    }

    public func center(on objectID: String) {
        guard let position = snapshot.positions.first(where: { $0.id == objectID }) else { return }
        cameraAzimuth = position.azimuth
        cameraAltitude = max(-20, min(80, position.altitude))
        selectedObjectID = objectID
    }

    public func resetCamera() {
        camera = SkyCameraState()
    }

    public func orbit(horizontalDelta: Double, verticalDelta: Double, viewportSize: CGSize) {
        let horizontalScale = camera.fieldOfView / max(Double(viewportSize.width), 1)
        let verticalScale = camera.fieldOfView / max(Double(viewportSize.height), 1)
        cameraAzimuth -= horizontalDelta * horizontalScale
        cameraAltitude += verticalDelta * verticalScale
    }

    public func zoom(by scale: Double) {
        fieldOfView /= max(scale, 0.05)
    }

    public func rotate(by degrees: Double) {
        cameraRoll += degrees
    }

    public func nudge(horizontal: Double = 0, vertical: Double = 0, zoom: Double = 0) {
        cameraAzimuth += horizontal
        cameraAltitude += vertical
        if zoom != 0 {
            fieldOfView += zoom
        }
    }

    public func useCurrentLocation() {
        locationService.requestLocation()
    }

    public func applyCurrentLocation(_ location: LocationSample) {
        let name = observer.name == "当前位置" || observer.name == "上海" ? "当前位置" : observer.name
        observer = ObserverContext(
            name: name,
            latitude: location.latitude,
            longitude: location.longitude,
            altitude: location.altitude,
            timeZoneIdentifier: TimeZone.current.identifier
        )
        Self.saveObserver(observer)
        scheduleSnapshotRefresh(updateObservationPlan: true)
    }

    public func setObserver(_ observer: ObserverContext) {
        self.observer = observer
        Self.saveObserver(observer)
        scheduleSnapshotRefresh(updateObservationPlan: true)
    }

    public func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    private func scheduleObservationPlanRefresh() {
        guard let repository else { return }
        planTask?.cancel()
        observationPlanState = .loading
        let moment = moment
        let observer = observer
        let candidates = repository.allObjects
        let favoriteIDs = favoriteStore.favoriteIDs
        let minimumAltitude = minimumObservationAltitude
        let planner = planner

        planTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                let plan = await planner.makePlan(
                    for: moment,
                    observer: observer,
                    candidates: candidates,
                    favoriteIDs: favoriteIDs,
                    minimumAltitude: minimumAltitude
                )
                try Task.checkCancellation()
                guard let self else { return }
                self.observationPlan = plan
                self.observationPlanState = .ready
                await self.refreshScheduledReminders(for: plan)
            } catch is CancellationError {
                return
            } catch {
                self?.observationPlanState = .failed(error.localizedDescription)
            }
        }
    }

    public func refreshAstronomyEvents() {
        guard let repository else { return }
        eventTask?.cancel()
        astronomyEventState = .loading
        let startDate = moment.date
        let endDate = startDate.addingTimeInterval(120 * 24 * 3600)
        let observer = observer
        let objects = repository.allObjects
        let eventPlanner = eventPlanner

        eventTask = Task { @MainActor [weak self] in
            let events = await eventPlanner.events(
                from: startDate,
                through: endDate,
                observer: observer,
                objects: objects
            )
            guard !Task.isCancelled, let self else { return }
            self.astronomyEvents = events
            self.astronomyEventState = .ready
            SkyTraceDiagnostics.event("AstronomyEventsCompleted")
        }
    }

    private func scheduleAstronomyEventRefresh() {
        eventTask?.cancel()
        astronomyEventState = .loading
        eventTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.refreshAstronomyEvents()
        }
    }

    public func focus(on event: AstronomyEvent) {
        setDate(event.date, recenter: false)
        if let objectID = event.objectIDs.first {
            Task { [weak self] in
                await self?.waitForSnapshotUpdate()
                self?.center(on: objectID)
            }
        }
    }

    private func refreshScheduledReminders(for plan: ObservationPlan) async {
        reminderScheduler.removeAllReminders()
        guard favoriteStore.remindersEnabled else { return }
        let enabledIDs = favoriteStore.reminderIDs
        for visibility in plan.favoriteVisibilities where enabledIDs.contains(visibility.object.id) {
            do {
                try await reminderScheduler.scheduleReminder(
                    object: visibility.object,
                    at: visibility.bestTime,
                    observer: plan.observer
                )
            } catch {
                showToast(error.localizedDescription)
            }
        }
    }

    private func bindServices() {
        locationAuthorization = locationService.authorizationStatus
        locationErrorMessage = locationService.errorMessage
        locationService.onLocationUpdate = { [weak self] location in
            self?.applyCurrentLocation(location)
        }
        locationService.onErrorMessage = { [weak self] message in
            self?.locationErrorMessage = message
            self?.showToast(message)
        }

        motionService.onReading = { [weak self] reading in
            self?.motionReading = reading
        }
        motionService.onErrorMessage = { [weak self] message in
            self?.showToast(message)
        }
    }

    private func startPlayback() {
        playbackTask?.cancel()
        isPlaying = true
        playbackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.isPlaying else { return }
                self.moment = SkyMoment(date: self.moment.date.addingTimeInterval(self.playbackDaysPerSecond * 0.25))
                if self.moment.date > self.dateRange.upperBound {
                    self.moment = SkyMoment(date: self.dateRange.lowerBound)
                }
                self.scheduleSnapshotRefresh(updateObservationPlan: false)
            }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        scheduleObservationPlanRefresh()
    }

    private static func loadObserver() -> ObserverContext? {
        guard let data = UserDefaults.standard.data(forKey: "SkyTrace.Observer") else { return nil }
        return try? JSONDecoder().decode(ObserverContext.self, from: data)
    }

    private static func saveObserver(_ observer: ObserverContext) {
        guard let data = try? JSONEncoder().encode(observer) else { return }
        UserDefaults.standard.set(data, forKey: "SkyTrace.Observer")
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }

}
