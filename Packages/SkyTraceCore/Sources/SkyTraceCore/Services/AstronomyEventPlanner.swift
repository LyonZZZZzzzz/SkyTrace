import AstronomyEngine
import Foundation

public actor AstronomyEventPlanner: AstronomyEventPlanning {
    private let astronomy: any AstronomyCalculating
    private let conjunctionThreshold: Double
    private var cache: [EventCacheKey: [AstronomyEvent]] = [:]
    private var cacheOrder: [EventCacheKey] = []

    public init(
        astronomy: any AstronomyCalculating = AstronomyService(),
        conjunctionThreshold: Double = 5
    ) {
        self.astronomy = astronomy
        self.conjunctionThreshold = conjunctionThreshold
    }

    public func events(
        from startDate: Date,
        through endDate: Date,
        observer: ObserverContext,
        objects: [CelestialObject]
    ) async -> [AstronomyEvent] {
        guard startDate < endDate else { return [] }
        let key = EventCacheKey(startDate: startDate, endDate: endDate, observer: observer)
        if let cached = cache[key] { return cached }
        var events: [AstronomyEvent] = []
        events.append(contentsOf: moonQuarterEvents(from: startDate, through: endDate))
        events.append(contentsOf: seasonEvents(from: startDate, through: endDate, observer: observer))
        events.append(contentsOf: eclipseEvents(from: startDate, through: endDate, observer: observer))
        events.append(contentsOf: conjunctionEvents(from: startDate, through: endDate, observer: observer, objects: objects))
        let unique = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = unique.values.sorted { $0.date < $1.date }
        cache[key] = sorted
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > 8, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        return sorted
    }

    private func moonQuarterEvents(from startDate: Date, through endDate: Date) -> [AstronomyEvent] {
        var result: [AstronomyEvent] = []
        var cursor = startDate
        while let quarter = astronomy.nextMoonQuarter(after: cursor), quarter.date <= endDate {
            let kind: AstronomyEventKind
            switch quarter.kind {
            case .newMoon: kind = .newMoon
            case .firstQuarter: kind = .firstQuarter
            case .fullMoon: kind = .fullMoon
            case .lastQuarter: kind = .lastQuarter
            }
            result.append(AstronomyEvent(
                id: "moon-quarter-\(Int(quarter.date.timeIntervalSince1970))",
                kind: kind,
                date: quarter.date,
                title: kind.localizedName,
                summary: "月相变化事件",
                objectIDs: ["moon"]
            ))
            cursor = quarter.date.addingTimeInterval(60)
        }
        return result
    }

    private func seasonEvents(from startDate: Date, through endDate: Date, observer: ObserverContext) -> [AstronomyEvent] {
        var result: [AstronomyEvent] = []
        let startYear = Calendar(identifier: .gregorian).component(.year, from: startDate)
        let endYear = Calendar(identifier: .gregorian).component(.year, from: endDate)
        for year in startYear...endYear {
            guard let seasons = astronomy.seasons(year: year) else { continue }
            let values: [(String, Date)] = [
                ("春分", seasons.marchEquinox),
                ("夏至", seasons.juneSolstice),
                ("秋分", seasons.septemberEquinox),
                ("冬至", seasons.decemberSolstice)
            ]
            for (title, date) in values where date >= startDate && date <= endDate {
                result.append(AstronomyEvent(
                    id: "season-\(year)-\(title)",
                    kind: .season,
                    date: date,
                    title: title,
                    summary: "太阳到达黄经关键位置",
                    objectIDs: ["sun"]
                ))
            }
        }
        return result
    }

    private func eclipseEvents(from startDate: Date, through endDate: Date, observer: ObserverContext) -> [AstronomyEvent] {
        var result: [AstronomyEvent] = []
        var lunarCursor = startDate
        for _ in 0..<8 {
            guard let eclipse = astronomy.nextLunarEclipse(after: lunarCursor, observer: observer), eclipse.peak <= endDate else { break }
            if eclipse.altitude > 0 {
                result.append(AstronomyEvent(
                    id: "lunar-eclipse-\(Int(eclipse.peak.timeIntervalSince1970))",
                    kind: .lunarEclipse,
                    date: eclipse.peak,
                    title: eclipseTitle(prefix: "月食", kind: eclipse.kind),
                    summary: String(format: "食分遮挡 %.0f%%，当地月亮高度 %.0f°", eclipse.obscuration * 100, eclipse.altitude),
                    objectIDs: ["moon"],
                    altitude: eclipse.altitude
                ))
            }
            lunarCursor = eclipse.peak.addingTimeInterval(24 * 3600)
        }

        var solarCursor = startDate
        for _ in 0..<8 {
            guard let eclipse = astronomy.nextLocalSolarEclipse(after: solarCursor, observer: observer), eclipse.peak <= endDate else { break }
            if eclipse.altitude > 0 {
                result.append(AstronomyEvent(
                    id: "solar-eclipse-\(Int(eclipse.peak.timeIntervalSince1970))",
                    kind: .solarEclipse,
                    date: eclipse.peak,
                    title: eclipseTitle(prefix: "日食", kind: eclipse.kind),
                    summary: String(format: "遮挡 %.0f%%，当地太阳高度 %.0f°", eclipse.obscuration * 100, eclipse.altitude),
                    objectIDs: ["sun", "moon"],
                    altitude: eclipse.altitude
                ))
            }
            solarCursor = eclipse.peak.addingTimeInterval(24 * 3600)
        }
        return result
    }

    private func conjunctionEvents(
        from startDate: Date,
        through endDate: Date,
        observer: ObserverContext,
        objects: [CelestialObject]
    ) -> [AstronomyEvent] {
        let moon = objects.first { $0.id == "moon" }
        let planets = objects.filter { $0.kind == .planet }
        var pairs: [(CelestialObject, CelestialObject, AstronomyEventKind)] = []
        for (index, planet) in planets.enumerated() {
            if let moon { pairs.append((moon, planet, .moonPlanetConjunction)) }
            for other in planets.dropFirst(index + 1) {
                pairs.append((planet, other, .planetConjunction))
            }
        }

        var result: [AstronomyEvent] = []
        for (first, second, kind) in pairs {
            guard let firstBody = AstronomyService.body(for: first), let secondBody = AstronomyService.body(for: second) else { continue }
            let interval: TimeInterval = 6 * 3600
            var previous = startDate.addingTimeInterval(-interval)
            var previousSeparation = angularSeparation(firstBody, secondBody, at: previous, observer: observer)
            var current = startDate
            var currentSeparation = angularSeparation(firstBody, secondBody, at: current, observer: observer)
            while current < endDate {
                let next = min(current.addingTimeInterval(interval), endDate)
                let nextSeparation = angularSeparation(firstBody, secondBody, at: next, observer: observer)
                if currentSeparation <= previousSeparation,
                   currentSeparation <= nextSeparation,
                   currentSeparation <= conjunctionThreshold {
                    let refined = refineMinimum(
                        firstBody: firstBody,
                        secondBody: secondBody,
                        around: current,
                        radius: interval,
                        observer: observer
                    )
                    result.append(AstronomyEvent(
                        id: "conjunction-\(first.id)-\(second.id)-\(Int(refined.date.timeIntervalSince1970))",
                        kind: kind,
                        date: refined.date,
                        title: kind == .moonPlanetConjunction ? "\(first.name)合\(second.name)" : "\(first.name)合\(second.name)",
                        summary: String(format: "角距 %.1f°", refined.separation),
                        objectIDs: [first.id, second.id],
                        altitude: min(refined.firstAltitude, refined.secondAltitude)
                    ))
                }
                previous = current
                previousSeparation = currentSeparation
                current = next
                currentSeparation = nextSeparation
            }
        }
        return result
    }

    private func angularSeparation(
        _ first: AstronomyBody,
        _ second: AstronomyBody,
        at date: Date,
        observer: ObserverContext
    ) -> Double {
        let one = astronomy.horizontal(body: first, date: date, latitude: observer.latitude, longitude: observer.longitude, height: observer.altitude)
        let two = astronomy.horizontal(body: second, date: date, latitude: observer.latitude, longitude: observer.longitude, height: observer.altitude)
        let firstVector = Vector3D(
            x: cos(one.altitude * .pi / 180) * sin(one.azimuth * .pi / 180),
            y: sin(one.altitude * .pi / 180),
            z: -cos(one.altitude * .pi / 180) * cos(one.azimuth * .pi / 180)
        )
        let secondVector = Vector3D(
            x: cos(two.altitude * .pi / 180) * sin(two.azimuth * .pi / 180),
            y: sin(two.altitude * .pi / 180),
            z: -cos(two.altitude * .pi / 180) * cos(two.azimuth * .pi / 180)
        )
        return acos(min(1, max(-1, Vector3D.dot(firstVector, secondVector)))) * 180 / .pi
    }

    private func refineMinimum(
        firstBody: AstronomyBody,
        secondBody: AstronomyBody,
        around date: Date,
        radius: TimeInterval,
        observer: ObserverContext
    ) -> (date: Date, separation: Double, firstAltitude: Double, secondAltitude: Double) {
        var low = date.addingTimeInterval(-radius)
        var high = date.addingTimeInterval(radius)
        for _ in 0..<20 {
            let third = high.timeIntervalSince(low) / 3
            let left = low.addingTimeInterval(third)
            let right = high.addingTimeInterval(-third)
            let leftSeparation = angularSeparation(firstBody, secondBody, at: left, observer: observer)
            let rightSeparation = angularSeparation(firstBody, secondBody, at: right, observer: observer)
            if leftSeparation < rightSeparation {
                high = right
            } else {
                low = left
            }
        }
        let best = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
        let first = astronomy.horizontal(body: firstBody, date: best, latitude: observer.latitude, longitude: observer.longitude, height: observer.altitude)
        let second = astronomy.horizontal(body: secondBody, date: best, latitude: observer.latitude, longitude: observer.longitude, height: observer.altitude)
        return (best, angularSeparation(firstBody, secondBody, at: best, observer: observer), first.altitude, second.altitude)
    }

    private func eclipseTitle(prefix: String, kind: AstronomyEclipseKind) -> String {
        switch kind {
        case .total: "\(prefix)（全食）"
        case .annular: "\(prefix)（环食）"
        case .partial: "\(prefix)（偏食）"
        case .penumbral: "\(prefix)（半影）"
        case .none: prefix
        }
    }
}


private struct EventCacheKey: Hashable {
    let startTime: Date
    let endTime: Date
    let latitude: Int
    let longitude: Int

    init(startDate: Date, endDate: Date, observer: ObserverContext) {
        startTime = startDate
        endTime = endDate
        latitude = Int((observer.latitude * 100).rounded())
        longitude = Int((observer.longitude * 100).rounded())
    }
}
