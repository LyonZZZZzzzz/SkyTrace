import AstronomyEngine
import Foundation

public protocol ObservationPlanning: Sendable {
    func makePlan(
        for moment: SkyMoment,
        observer: ObserverContext,
        candidates: [CelestialObject],
        favoriteIDs: Set<String>,
        minimumAltitude: Double
    ) async -> ObservationPlan
}

public actor ObservationPlanner: ObservationPlanning {
    private let astronomy: any AstronomyCalculating
    private let sampleInterval: TimeInterval
    private let minimumWindowDuration: TimeInterval

    public init(
        astronomy: any AstronomyCalculating = AstronomyService(),
        sampleInterval: TimeInterval = 10 * 60,
        minimumWindowDuration: TimeInterval = 20 * 60
    ) {
        self.astronomy = astronomy
        self.sampleInterval = sampleInterval
        self.minimumWindowDuration = minimumWindowDuration
    }

    public func makePlan(
        for moment: SkyMoment,
        observer: ObserverContext,
        candidates: [CelestialObject],
        favoriteIDs: Set<String>,
        minimumAltitude: Double = 10
    ) async -> ObservationPlan {
        SkyTraceDiagnostics.planning.info("Building observation plan")
        defer { SkyTraceDiagnostics.event("ObservationPlanCompleted") }
        let night = observationNight(for: moment, observer: observer)
        let moon = moonObservation(for: night, moment: moment, observer: observer)

        guard let darkStart = night.effectiveDarkStart, let darkEnd = night.effectiveDarkEnd, darkStart < darkEnd else {
            return ObservationPlan(
                moment: moment,
                observer: observer,
                night: night,
                moon: moon,
                recommendations: [],
                favoriteVisibilities: [],
                warningMessage: night.quality == .polarDay ? "当前纬度处于极昼，暂无有效暗夜观测窗口。" : "当前夜晚没有足够的黑暗观测时间。"
            )
        }

        let eligible = candidates.filter { object in
            if object.kind == .sun { return false }
            if object.kind == .constellation && !favoriteIDs.contains(object.id) { return false }
            if favoriteIDs.contains(object.id) { return true }
            if object.kind == .moon || object.kind == .planet { return true }
            return (object.magnitude ?? 99) <= 4.8
        }

        var visibilities: [ObservationVisibility] = []
        visibilities.reserveCapacity(eligible.count)

        for object in eligible {
            guard let visibility = visibility(
                for: object,
                darkStart: darkStart,
                darkEnd: darkEnd,
                moment: moment,
                observer: observer,
                minimumAltitude: minimumAltitude,
                moon: moon
            ) else { continue }
            visibilities.append(visibility)
        }

        let recommendations = visibilities
            .sorted { $0.score > $1.score }
            .prefix(8)
            .map { $0 }
        let favoriteVisibilities = visibilities
            .filter { favoriteIDs.contains($0.object.id) }
            .sorted { $0.score > $1.score }

        let warning: String?
        switch night.quality {
        case .astronomical:
            warning = nil
        case .nautical:
            warning = "今夜没有完整天文暗夜，推荐时间基于航海暮光。"
        case .civil:
            warning = "今夜没有更深黑暗阶段，推荐时间基于民用暮光。"
        case .polarDay:
            warning = "当前纬度处于极昼，暂无有效暗夜观测窗口。"
        }

        return ObservationPlan(
            moment: moment,
            observer: observer,
            night: night,
            moon: moon,
            recommendations: recommendations,
            favoriteVisibilities: favoriteVisibilities,
            warningMessage: warning
        )
    }

    private func observationNight(for moment: SkyMoment, observer: ObserverContext) -> ObservationNight {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = observer.timeZone
        let startOfToday = calendar.startOfDay(for: moment.date)
        let localHour = calendar.component(.hour, from: moment.date)
        let anchorDay = localHour < 12
            ? calendar.date(byAdding: .day, value: -1, to: startOfToday)!
            : startOfToday
        let noon = calendar.date(byAdding: .hour, value: 12, to: anchorDay)!
        let nextNoon = calendar.date(byAdding: .day, value: 1, to: noon)!
        let nextMidnight = calendar.date(byAdding: .hour, value: 12, to: noon)!

        let sunEvents = astronomy.riseSet(body: .sun, startDate: noon, observer: observer, searchDays: 1.5)
        let sunset = sunEvents.set
        let sunrise = sunEvents.rise

        let civilDusk = astronomy.altitudeCrossing(
            body: .sun, direction: .setting, altitude: -6,
            startDate: noon, observer: observer, searchDays: 1
        )
        let civilDawn = astronomy.altitudeCrossing(
            body: .sun, direction: .rising, altitude: -6,
            startDate: noon, observer: observer, searchDays: 1.5
        )
        let nauticalDusk = astronomy.altitudeCrossing(
            body: .sun, direction: .setting, altitude: -12,
            startDate: noon, observer: observer, searchDays: 1
        )
        let nauticalDawn = astronomy.altitudeCrossing(
            body: .sun, direction: .rising, altitude: -12,
            startDate: noon, observer: observer, searchDays: 1.5
        )
        let astronomicalDusk = astronomy.altitudeCrossing(
            body: .sun, direction: .setting, altitude: -18,
            startDate: noon, observer: observer, searchDays: 1
        )
        let astronomicalDawn = astronomy.altitudeCrossing(
            body: .sun, direction: .rising, altitude: -18,
            startDate: noon, observer: observer, searchDays: 1.5
        )

        let fallbackNightStart = calendar.date(byAdding: .hour, value: 18, to: anchorDay)!
        let fallbackNightEnd = calendar.date(byAdding: .hour, value: 6, to: nextMidnight)!
        let nightStart = sunset ?? fallbackNightStart
        let nightEnd = sunrise ?? fallbackNightEnd

        let polarDay = sunset == nil && sunrise == nil && isSunAboveHorizon(noon, observer: observer)
        let polarNight = sunset == nil && sunrise == nil && !polarDay
        let effective: (start: Date, end: Date, quality: ObservationNightQuality)
        if polarDay {
            effective = (nightStart, nightEnd, .polarDay)
        } else if polarNight {
            effective = (nightStart, nightEnd, .astronomical)
        } else if let start = astronomicalDusk, let end = astronomicalDawn, start < end {
            effective = (start, end, .astronomical)
        } else if let start = nauticalDusk, let end = nauticalDawn, start < end {
            effective = (start, end, .nautical)
        } else if let start = civilDusk, let end = civilDawn, start < end {
            effective = (start, end, .civil)
        } else {
            effective = (nightStart, nightEnd, .civil)
        }
        _ = nextNoon

        return ObservationNight(
            anchorDate: anchorDay,
            sunset: sunset,
            sunrise: sunrise,
            civilDusk: civilDusk,
            civilDawn: civilDawn,
            nauticalDusk: nauticalDusk,
            nauticalDawn: nauticalDawn,
            astronomicalDusk: astronomicalDusk,
            astronomicalDawn: astronomicalDawn,
            effectiveDarkStart: effective.start,
            effectiveDarkEnd: effective.end,
            quality: effective.quality
        )
    }

    private func isSunAboveHorizon(_ date: Date, observer: ObserverContext) -> Bool {
        astronomy.horizontal(body: .sun, date: date, latitude: observer.latitude, longitude: observer.longitude, height: observer.altitude).altitude > 0
    }

    private func moonObservation(
        for night: ObservationNight,
        moment: SkyMoment,
        observer: ObserverContext
    ) -> MoonObservation {
        let reference = night.effectiveDarkStart.map { $0.addingTimeInterval((night.effectiveDarkEnd ?? $0).timeIntervalSince($0) / 2) }
            ?? moment.date
        let info = astronomy.moonInfo(date: reference)
        let events = astronomy.riseSet(body: .moon, startDate: reference, observer: observer, searchDays: 1.5)
        let horizontal = astronomy.horizontal(
            body: .moon,
            date: reference,
            latitude: observer.latitude,
            longitude: observer.longitude,
            height: observer.altitude
        )
        return MoonObservation(
            phase: Self.phase(for: info.phaseAngle),
            phaseAngle: info.phaseAngle,
            illuminationFraction: info.illuminationFraction,
            magnitude: info.magnitude,
            rise: events.rise,
            set: events.set,
            altitudeAtBestTime: horizontal.altitude,
            azimuthAtBestTime: horizontal.azimuth
        )
    }

    private func visibility(
        for object: CelestialObject,
        darkStart: Date,
        darkEnd: Date,
        moment: SkyMoment,
        observer: ObserverContext,
        minimumAltitude: Double,
        moon: MoonObservation
    ) -> ObservationVisibility? {
        var samples: [(date: Date, altitude: Double)] = []
        var date = darkStart
        while date <= darkEnd {
            samples.append((date, altitude(of: object, at: date, observer: observer)))
            date = date.addingTimeInterval(sampleInterval)
        }
        if samples.last?.date != darkEnd {
            samples.append((darkEnd, altitude(of: object, at: darkEnd, observer: observer)))
        }

        var windows: [(start: Date, end: Date, maxAltitude: Double, bestTime: Date)] = []
        var index = 0
        while index < samples.count {
            guard samples[index].altitude >= minimumAltitude else {
                index += 1
                continue
            }

            let startIndex = index
            var maxAltitude = samples[index].altitude
            var bestTime = samples[index].date
            while index + 1 < samples.count, samples[index + 1].altitude >= minimumAltitude {
                index += 1
                if samples[index].altitude > maxAltitude {
                    maxAltitude = samples[index].altitude
                    bestTime = samples[index].date
                }
            }

            let rawStart = samples[startIndex].date
            let rawEnd = samples[index].date
            let refinedStart = startIndex > 0
                ? refineCrossing(object, lower: samples[startIndex - 1], upper: samples[startIndex], minimumAltitude: minimumAltitude, observer: observer)
                : rawStart
            let refinedEnd = index + 1 < samples.count
                ? refineCrossing(object, lower: samples[index], upper: samples[index + 1], minimumAltitude: minimumAltitude, observer: observer)
                : rawEnd
            let duration = refinedEnd.timeIntervalSince(refinedStart)
            if duration >= minimumWindowDuration {
                windows.append((refinedStart, refinedEnd, maxAltitude, bestTime))
            }
            index += 1
        }

        guard let bestWindow = windows.max(by: { $0.maxAltitude < $1.maxAltitude }) else { return nil }

        let targetAtBest = horizontal(of: object, at: bestWindow.bestTime, observer: observer)
        let moonAtBest = astronomy.horizontal(
            body: .moon,
            date: bestWindow.bestTime,
            latitude: observer.latitude,
            longitude: observer.longitude,
            height: observer.altitude
        )
        let separation = angularSeparation(targetAtBest, moonAtBest)
        let moonPenalty = moonlightPenalty(
            moon: moon,
            moonAltitude: moonAtBest.altitude,
            separation: separation
        )
        let duration = bestWindow.end.timeIntervalSince(bestWindow.start)
        let score = recommendationScore(
            object: object,
            maximumAltitude: bestWindow.maxAltitude,
            duration: duration,
            moonPenalty: moonPenalty
        )
        let reason = recommendationReason(
            window: bestWindow,
            darkStart: darkStart,
            darkEnd: darkEnd,
            moonRise: moon.rise,
            moonSet: moon.set
        )

        return ObservationVisibility(
            object: object,
            start: bestWindow.start,
            end: bestWindow.end,
            bestTime: bestWindow.bestTime,
            maximumAltitude: bestWindow.maxAltitude,
            duration: duration,
            score: score,
            reason: reason,
            moonSeparation: separation
        )
    }

    private func altitude(of object: CelestialObject, at date: Date, observer: ObserverContext) -> Double {
        if let body = AstronomyService.body(for: object) {
            return astronomy.horizontal(
                body: body,
                date: date,
                latitude: observer.latitude,
                longitude: observer.longitude,
                height: observer.altitude
            ).altitude
        }
        let moment = SkyMoment(date: date)
        let transform = astronomy.horizontalTransform(for: moment, observer: observer)
        return astronomy.horizontal(object: object, moment: moment, observer: observer, transform: transform).altitude
    }

    private func horizontal(of object: CelestialObject, at date: Date, observer: ObserverContext) -> AstronomyHorizontalCoordinate {
        if let body = AstronomyService.body(for: object) {
            return astronomy.horizontal(
                body: body,
                date: date,
                latitude: observer.latitude,
                longitude: observer.longitude,
                height: observer.altitude
            )
        }
        let moment = SkyMoment(date: date)
        let transform = astronomy.horizontalTransform(for: moment, observer: observer)
        let coordinate = astronomy.horizontal(object: object, moment: moment, observer: observer, transform: transform)
        return AstronomyHorizontalCoordinate(
            azimuth: coordinate.azimuth,
            altitude: coordinate.altitude,
            raHours: object.raDegrees / 15,
            decDegrees: object.decDegrees
        )
    }

    private func refineCrossing(
        _ object: CelestialObject,
        lower: (date: Date, altitude: Double),
        upper: (date: Date, altitude: Double),
        minimumAltitude: Double,
        observer: ObserverContext
    ) -> Date {
        var low = lower
        var high = upper
        for _ in 0..<10 {
            let midpoint = low.date.addingTimeInterval(high.date.timeIntervalSince(low.date) / 2)
            let midpointAltitude = altitude(of: object, at: midpoint, observer: observer)
            let lowAbove = low.altitude >= minimumAltitude
            if (lowAbove && midpointAltitude >= minimumAltitude) || (!lowAbove && midpointAltitude < minimumAltitude) {
                low = (midpoint, midpointAltitude)
            } else {
                high = (midpoint, midpointAltitude)
            }
        }
        return low.date.addingTimeInterval(high.date.timeIntervalSince(low.date) / 2)
    }

    private func angularSeparation(
        _ lhs: AstronomyHorizontalCoordinate,
        _ rhs: AstronomyHorizontalCoordinate
    ) -> Double {
        let left = Vector3D(
            x: cos(lhs.altitude * .pi / 180) * sin(lhs.azimuth * .pi / 180),
            y: sin(lhs.altitude * .pi / 180),
            z: -cos(lhs.altitude * .pi / 180) * cos(lhs.azimuth * .pi / 180)
        )
        let right = Vector3D(
            x: cos(rhs.altitude * .pi / 180) * sin(rhs.azimuth * .pi / 180),
            y: sin(rhs.altitude * .pi / 180),
            z: -cos(rhs.altitude * .pi / 180) * cos(rhs.azimuth * .pi / 180)
        )
        return acos(min(1, max(-1, Vector3D.dot(left, right)))) * 180 / .pi
    }

    private func moonlightPenalty(
        moon: MoonObservation,
        moonAltitude: Double,
        separation: Double
    ) -> Double {
        guard moonAltitude > 0, moon.illuminationFraction > 0.15 else { return 0 }
        let proximity = max(0, 1 - separation / 90)
        return moon.illuminationFraction * proximity * 35
    }

    private func recommendationScore(
        object: CelestialObject,
        maximumAltitude: Double,
        duration: TimeInterval,
        moonPenalty: Double
    ) -> Double {
        let priority: Double
        switch object.kind {
        case .moon: priority = 60
        case .planet: priority = 58
        case .deepSky: priority = 46
        case .star: priority = 40
        case .constellation: priority = 28
        case .sun: priority = -100
        }
        let magnitudeBonus = max(0, 6.5 - (object.magnitude ?? 6.5)) * 1.8
        let altitudeBonus = max(0, maximumAltitude) * 0.45
        let durationBonus = min(duration / 3600, 5) * 4
        return priority + magnitudeBonus + altitudeBonus + durationBonus - moonPenalty
    }

    private func recommendationReason(
        window: (start: Date, end: Date, maxAltitude: Double, bestTime: Date),
        darkStart: Date,
        darkEnd: Date,
        moonRise: Date?,
        moonSet: Date?
    ) -> ObservationReason {
        let startsAtDark = window.start.timeIntervalSince(darkStart) <= sampleInterval
        let endsAtDawn = darkEnd.timeIntervalSince(window.end) <= sampleInterval
        if startsAtDark && endsAtDawn { return .allNight }
        if let moonRise, window.start < moonRise, moonRise < window.bestTime { return .bestBeforeMoonrise }
        if let moonSet, window.start < moonSet, moonSet < window.bestTime { return .bestAfterMoonset }
        if window.bestTime.timeIntervalSince(window.start) < window.end.timeIntervalSince(window.bestTime) {
            return .bestAfterDark
        }
        if window.end.timeIntervalSince(window.start) < 60 * 60 { return .shortWindow }
        return .bestBeforeDawn
    }

    private static func phase(for angle: Double) -> LunarPhase {
        let normalized = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        switch normalized {
        case 0..<22.5, 337.5...360: return .newMoon
        case 22.5..<67.5: return .waxingCrescent
        case 67.5..<112.5: return .firstQuarter
        case 112.5..<157.5: return .waxingGibbous
        case 157.5..<202.5: return .fullMoon
        case 202.5..<247.5: return .waningGibbous
        case 247.5..<292.5: return .lastQuarter
        default: return .waningCrescent
        }
    }
}
