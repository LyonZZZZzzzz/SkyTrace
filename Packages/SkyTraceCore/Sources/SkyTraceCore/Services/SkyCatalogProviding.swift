import Foundation

@MainActor
public protocol SkyCatalogProviding: Sendable {
    var stars: [StarRecord] { get }
    var constellations: [ConstellationRecord] { get }
    var deepSkyObjects: [DeepSkyRecord] { get }
    var cities: [City] { get }
    var allObjects: [CelestialObject] { get }
    var constellationObjects: [CelestialObject] { get }

    func search(_ query: String, limit: Int) -> [CelestialObject]
}

extension CatalogRepository: SkyCatalogProviding {}
