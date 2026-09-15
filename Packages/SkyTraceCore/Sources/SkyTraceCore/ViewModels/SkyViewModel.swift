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
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
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
            catalogState = .ready
            refreshSnapshot()
        } else {
            do {
                repository = try CatalogRepository()
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
        SkyTraceDiagnostics.event("SnapshotBuildStarted")
        defer { SkyTraceDiagnostics.event("SnapshotBuildCompleted") }
        let transform = astronomy.horizontalTransform(for: moment, observer: observer)

        var segments: [ConstellationSegment] = []
        var anchorWeightedSums: [String: Vector3D] = [:]
        var anchorWeights: [String: Double] = [:]

        for constellation in repository.constellations {
            for line in constellation.segments {
                guard line.count > 1 else { continue }
                for index in 1..<line.count {
                    let start = line[index - 1]
                    let end = line[index]
                    guard start.count >= 2, end.count >= 2 else { continue }

                    let startHorizontal = transform.horizontal(raDegrees: start[0], decDegrees: start[1])
                    let endHorizontal = transform.horizontal(raDegrees: end[0], decDegrees: end[1])
                    let startVector = vector(azimuth: startHorizontal.azimuth, altitude: startHorizontal.altitude)
                    let endVector = vector(azimuth: endHorizontal.azimuth, altitude: endHorizontal.altitude)
                    segments.append(
                        ConstellationSegment(
                            constellationID: constellation.id,
                            start: startVector,
                            end: endVector
                        )
                    )

                    let segmentLength = (endVector - startVector).length
                    guard segmentLength > 0 else { continue }
                    let midpoint = (startVector + endVector) * 0.5
                    anchorWeightedSums[constellation.id] = (anchorWeightedSums[constellation.id] ?? Vector3D(x: 0, y: 0, z: 0)) + midpoint * segmentLength
                    anchorWeights[constellation.id, default: 0] += segmentLength
                }
            }
        }

        var positions: [SkyPosition] = []
        positions.reserveCapacity(repository.allObjects.count)
        for object in repository.allObjects {
            let coordinate: (azimuth: Double, altitude: Double)

            if
                let constellationID = constellationID(for: object),
                let weightedSum = anchorWeightedSums[constellationID],
                let weight = anchorWeights[constellationID],
                weight > 0
            {
                let anchor = weightedSum.normalized
                coordinate = (
                    azimuth: normalizedDegrees(atan2(anchor.x, -anchor.z) * 180 / .pi),
                    altitude: asin(min(1, max(-1, anchor.y))) * 180 / .pi
                )
            } else {
                coordinate = astronomy.horizontal(
                    object: object,
                    moment: moment,
                    observer: observer,
                    transform: transform
                )
            }

            positions.append(
                SkyPosition(
                    object: object,
                    azimuth: coordinate.azimuth,
                    altitude: coordinate.altitude
                )
            )
        }

        let recommendations = Array(bestRecommendations(from: positions).prefix(6))
        snapshot = SkySnapshot(
            observer: observer,
            moment: moment,
            positions: positions,
            constellationSegments: segments,
            recommendations: recommendations
        )
        if updateObservationPlan {
            scheduleObservationPlanRefresh()
            scheduleAstronomyEventRefresh()
        }
    }

    public func setDate(_ date: Date, recenter: Bool = false) {
        moment = SkyMoment(date: min(max(date, dateRange.lowerBound), dateRange.upperBound))
        refreshSnapshot()
        if recenter, let id = selectedObjectID {
            center(on: id)
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
        refreshSnapshot()
    }

    public func setObserver(_ observer: ObserverContext) {
        self.observer = observer
        Self.saveObserver(observer)
        refreshSnapshot()
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
            center(on: objectID)
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
            guard let self, self.motionEnabled else { return }
            self.camera.azimuth = reading.azimuth
            self.camera.altitude = reading.altitude
            self.camera.roll = reading.roll
        }
        motionService.onErrorMessage = { [weak self] message in
            self?.showToast(message)
        }
    }

    private func constellationID(for object: CelestialObject) -> String? {
        guard object.kind == .constellation else { return nil }
        let prefix = "constellation-"
        guard object.id.hasPrefix(prefix) else { return nil }
        return String(object.id.dropFirst(prefix.count))
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
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
                self.refreshSnapshot(updateObservationPlan: false)
                if let id = self.selectedObjectID {
                    self.center(on: id)
                }
            }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        scheduleObservationPlanRefresh()
    }

    private func vector(azimuth: Double, altitude: Double) -> Vector3D {
        SkyPosition(
            object: Self.placeholderObject,
            azimuth: azimuth,
            altitude: altitude
        ).horizontalVector
    }

    private func bestRecommendations(from positions: [SkyPosition]) -> [SkyPosition] {
        positions
            .filter { position in
                guard position.object.kind != .constellation, position.object.kind != .sun else { return false }
                return position.altitude >= 12
            }
            .sorted { lhs, rhs in
                recommendationScore(lhs) > recommendationScore(rhs)
            }
    }

    private func recommendationScore(_ position: SkyPosition) -> Double {
        let priority: Double
        switch position.object.kind {
        case .moon: priority = 65
        case .planet: priority = 60
        case .deepSky: priority = 45
        case .star: priority = 35
        case .constellation: priority = 0
        case .sun: priority = -100
        }
        let magnitudeBonus = max(0, 7 - (position.object.magnitude ?? 7)) * 1.5
        let altitudeBonus = min(position.altitude, 70) * 0.25
        return priority + magnitudeBonus + altitudeBonus
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

    private static let placeholderObject = CelestialObject(
        id: "placeholder",
        name: "",
        englishName: "",
        designation: "",
        kind: .star,
        raDegrees: 0,
        decDegrees: 0,
        magnitude: nil,
        bvColorIndex: nil,
        detail: "",
        aliases: []
    )
}
