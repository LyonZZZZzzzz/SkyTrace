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

    public var motionEnabled = false {
        didSet {
            motionEnabled ? motionService.start() : motionService.stop()
        }
    }

    @ObservationIgnored public let locationService: any LocationProviding
    @ObservationIgnored public let motionService: any DeviceMotionProviding
    @ObservationIgnored private let astronomy: any AstronomyCalculating
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

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
        catalog: (any SkyCatalogProviding)? = nil
    ) {
        self.locationService = locationService
        self.motionService = motionService
        self.astronomy = astronomy
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
    }

    deinit {
        playbackTask?.cancel()
        toastTask?.cancel()
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

    public func refreshSnapshot() {
        guard let repository else { return }
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
                self.refreshSnapshot()
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
