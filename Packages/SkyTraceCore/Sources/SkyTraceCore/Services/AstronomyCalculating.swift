import AstronomyEngine
import Foundation

public protocol AstronomyCalculating: Sendable {
    func horizontalTransform(for moment: SkyMoment, observer: ObserverContext) -> HorizontalTransform
    func horizontal(
        object: CelestialObject,
        moment: SkyMoment,
        observer: ObserverContext,
        transform: HorizontalTransform
    ) -> (azimuth: Double, altitude: Double)
}

public struct AstronomyService: AstronomyCalculating {
    public init() {}

    public func horizontalTransform(for moment: SkyMoment, observer: ObserverContext) -> HorizontalTransform {
        AstronomyEngine.horizontalTransform(
            date: moment.date,
            latitude: observer.latitude,
            longitude: observer.longitude,
            height: observer.altitude
        )
    }

    public func horizontal(
        object: CelestialObject,
        moment: SkyMoment,
        observer: ObserverContext,
        transform: HorizontalTransform
    ) -> (azimuth: Double, altitude: Double) {
        if let body = Self.body(for: object) {
            let coordinate = AstronomyEngine.horizontal(
                body: body,
                date: moment.date,
                latitude: observer.latitude,
                longitude: observer.longitude,
                height: observer.altitude
            )
            return (coordinate.azimuth, coordinate.altitude)
        }

        let coordinate = transform.horizontal(
            raDegrees: object.raDegrees,
            decDegrees: object.decDegrees
        )
        return (coordinate.azimuth, coordinate.altitude)
    }

    public static func body(for object: CelestialObject) -> AstronomyBody? {
        switch object.id {
        case "sun": .sun
        case "moon": .moon
        case "planet-mercury": .mercury
        case "planet-venus": .venus
        case "planet-mars": .mars
        case "planet-jupiter": .jupiter
        case "planet-saturn": .saturn
        case "planet-uranus": .uranus
        case "planet-neptune": .neptune
        default: nil
        }
    }
}
