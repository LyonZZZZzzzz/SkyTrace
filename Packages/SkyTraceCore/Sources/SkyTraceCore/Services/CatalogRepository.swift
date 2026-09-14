import Foundation

public enum CatalogLoadError: LocalizedError {
    case missingResource(String)
    case malformedResource(String)
    case unsupportedCatalog

    public var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "缺少内置资源：\(name)"
        case .malformedResource(let name):
            "内置资源格式无效：\(name)"
        case .unsupportedCatalog:
            "星表版本不受支持"
        }
    }
}

public struct CatalogRepository: Sendable {
    public let stars: [StarRecord]
    public let starLabels: [UInt32: StarLabel]
    public let constellations: [ConstellationRecord]
    public let deepSkyObjects: [DeepSkyRecord]
    public let cities: [City]
    public let allObjects: [CelestialObject]
    public let constellationObjects: [CelestialObject]

    public init() throws {
        try self.init(bundle: .module)
    }

    public init(bundle: Bundle) throws {
        let starsData = try Self.resource(named: "Stars", extension: "bin", bundle: bundle)
        let labelsData = try Self.resource(named: "StarLabels", extension: "json", bundle: bundle)
        let constellationsData = try Self.resource(named: "Constellations", extension: "json", bundle: bundle)
        let deepSkyData = try Self.resource(named: "DeepSky", extension: "json", bundle: bundle)
        let citiesData = try Self.resource(named: "Cities", extension: "json", bundle: bundle)

        do {
            let decoder = JSONDecoder()
            stars = try Self.decodeStars(starsData)
            let labels = try decoder.decode([StarLabel].self, from: labelsData)
            starLabels = Dictionary(uniqueKeysWithValues: labels.map { ($0.hr, $0) })
            constellations = try decoder.decode([ConstellationRecord].self, from: constellationsData)
            deepSkyObjects = try decoder.decode([DeepSkyRecord].self, from: deepSkyData)
            cities = try decoder.decode([City].self, from: citiesData)
        } catch {
            throw CatalogLoadError.malformedResource("离线星表")
        }

        guard !stars.isEmpty, constellations.count == 88, deepSkyObjects.count == 110 else {
            throw CatalogLoadError.unsupportedCatalog
        }

        let labelsByHR = starLabels
        let starObjects = stars.map { star -> CelestialObject in
            let label = labelsByHR[star.hr]
            let fallback = star.hip > 0 ? "HIP \(star.hip)" : "HR \(star.hr)"
            let name = label?.displayName ?? fallback
            let aliases = [
                label?.name ?? "",
                label?.englishName ?? "",
                label?.designation ?? "",
                "HR \(star.hr)",
                star.hip > 0 ? "HIP \(star.hip)" : ""
            ].filter { !$0.isEmpty }
            let detail = String(
                format: "视星等 %.2f 的恒星。颜色指数 B-V %.2f，位置已按当前观测时间完成岁差与地平坐标计算。",
                star.magnitude,
                star.bvColorIndex
            )
            return CelestialObject(
                id: "star-\(star.hr)",
                name: name,
                englishName: label?.englishName ?? "",
                designation: label?.designation ?? "HR \(star.hr)",
                kind: .star,
                raDegrees: Double(star.raDegrees),
                decDegrees: Double(star.decDegrees),
                magnitude: Double(star.magnitude),
                bvColorIndex: Double(star.bvColorIndex),
                detail: detail,
                aliases: aliases
            )
        }

        let constellationObjects = constellations.compactMap { constellation -> CelestialObject? in
            guard let center = constellation.center else { return nil }
            return CelestialObject(
                id: "constellation-\(constellation.id)",
                name: constellation.name,
                englishName: constellation.englishName,
                designation: constellation.id.uppercased(),
                kind: .constellation,
                raDegrees: center.ra,
                decDegrees: center.dec,
                magnitude: nil,
                bvColorIndex: nil,
                detail: "\(constellation.name)是国际天文学联合会划定的 88 星座之一。连线仅用于辅助识别，并不构成星座边界。",
                aliases: [constellation.id, constellation.englishName, constellation.name]
            )
        }

        let deepSkyObjects = deepSkyObjects.map { object -> CelestialObject in
            let magnitudeText = object.magnitude.map { String(format: "视星等 %.1f，", $0) } ?? ""
            return CelestialObject(
                id: "deepsky-\(object.id.lowercased())",
                name: object.name,
                englishName: object.englishName,
                designation: object.designation.isEmpty ? object.id : object.designation,
                kind: .deepSky,
                raDegrees: object.ra,
                decDegrees: object.dec,
                magnitude: object.magnitude,
                bvColorIndex: nil,
                detail: "\(object.designation.isEmpty ? object.id : object.designation) 属于\(object.type)。\(magnitudeText)适合在光污染较低且目标高度足够时使用双筒望远镜或小型望远镜观测。",
                aliases: [object.id, object.name, object.englishName, object.designation]
            )
        }

        let solarSystem = Self.standardSolarSystemObjects
        allObjects = starObjects + constellationObjects + deepSkyObjects + solarSystem
        self.constellationObjects = constellationObjects
    }

    public func search(_ query: String, limit: Int = 30) -> [CelestialObject] {
        let term = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !term.isEmpty else { return [] }

        return allObjects.compactMap { object -> (CelestialObject, Int)? in
            let values = [object.name, object.englishName, object.designation] + object.aliases
            let normalized = values
                .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
                .filter { !$0.isEmpty }
            guard let rank = normalized.map({ value -> Int in
                if value == term { return 0 }
                if value.hasPrefix(term) { return 1 }
                if value.contains(term) { return 2 }
                return 100
            }).min(), rank < 100 else { return nil }
            return (object, rank)
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            if ($0.0.magnitude ?? 99) != ($1.0.magnitude ?? 99) {
                return ($0.0.magnitude ?? 99) < ($1.0.magnitude ?? 99)
            }
            return $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending
        }
        .prefix(limit)
        .map(\.0)
    }

    public static let standardSolarSystemObjects: [CelestialObject] = [
        CelestialObject(id: "sun", name: "太阳", englishName: "Sun", designation: "Sol", kind: .sun, raDegrees: 0, decDegrees: 0, magnitude: -26.74, bvColorIndex: nil, detail: "太阳是太阳系的中心天体，视星等约为 −26.7。观测时切勿直视太阳。", aliases: ["Sun", "Sol", "太阳"]),
        CelestialObject(id: "moon", name: "月球", englishName: "Moon", designation: "Luna", kind: .moon, raDegrees: 0, decDegrees: 0, magnitude: -12.7, bvColorIndex: nil, detail: "月球是地球唯一的天然卫星，月相和高度会显著影响深空天体观测。", aliases: ["Moon", "Luna", "月亮", "月球"]),
        CelestialObject(id: "planet-mercury", name: "水星", englishName: "Mercury", designation: "Mercury", kind: .planet, raDegrees: 0, decDegrees: 0, magnitude: -0.4, bvColorIndex: nil, detail: "水星是距离太阳最近的行星，只在晨昏低空短暂可见。", aliases: ["Mercury", "水星"]),
        CelestialObject(id: "planet-venus", name: "金星", englishName: "Venus", designation: "Venus", kind: .planet, raDegrees: 0, decDegrees: 0, magnitude: -4.4, bvColorIndex: nil, detail: "金星是夜空中最明亮的行星，常被称为启明星或长庚星。", aliases: ["Venus", "金星", "启明星", "长庚星"]),
        CelestialObject(id: "planet-mars", name: "火星", englishName: "Mars", designation: "Mars", kind: .planet, raDegrees: 0, decDegrees: 0, magnitude: 0.7, bvColorIndex: nil, detail: "火星呈橙红色，亮度和颜色在冲日前后最醒目。", aliases: ["Mars", "火星"]),
        CelestialObject(id: "planet-jupiter", name: "木星", englishName: "Jupiter", designation: "Jupiter", kind: .planet, raDegrees: 0, decDegrees: 0, magnitude: -2.2, bvColorIndex: nil, detail: "木星是太阳系最大的行星，双筒望远镜可看到伽利略卫星。", aliases: ["Jupiter", "木星"]),
        CelestialObject(id: "planet-saturn", name: "土星", englishName: "Saturn", designation: "Saturn", kind: .planet, raDegrees: 0, decDegrees: 0, magnitude: 0.5, bvColorIndex: nil, detail: "土星以显著的行星环闻名，小型望远镜即可辨认环系。", aliases: ["Saturn", "土星"]),
        CelestialObject(id: "planet-uranus", name: "天王星", englishName: "Uranus", designation: "Uranus", kind: .planet, raDegrees: 0, decDegrees: 0, magnitude: 5.7, bvColorIndex: nil, detail: "天王星在极佳暗空下可勉强凭肉眼看到，通常需要双筒望远镜确认。", aliases: ["Uranus", "天王星"]),
        CelestialObject(id: "planet-neptune", name: "海王星", englishName: "Neptune", designation: "Neptune", kind: .planet, raDegrees: 0, decDegrees: 0, magnitude: 7.8, bvColorIndex: nil, detail: "海王星是距太阳最远的行星，需要望远镜才能观测。", aliases: ["Neptune", "海王星"])
    ]

    private static func resource(
        named name: String,
        extension fileExtension: String,
        bundle: Bundle
    ) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            throw CatalogLoadError.missingResource("\(name).\(fileExtension)")
        }
        return try Data(contentsOf: url)
    }

    private static func decodeStars(_ data: Data) throws -> [StarRecord] {
        let recordSize = 24
        guard data.count.isMultiple(of: recordSize) else {
            throw CatalogLoadError.malformedResource("Stars.bin")
        }

        return data.withUnsafeBytes { rawBuffer in
            stride(from: 0, to: data.count, by: recordSize).map { offset in
                let hr = rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
                let hip = rawBuffer.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).littleEndian
                let ra = Float(bitPattern: rawBuffer.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self).littleEndian)
                let dec = Float(bitPattern: rawBuffer.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self).littleEndian)
                let magnitude = Float(bitPattern: rawBuffer.loadUnaligned(fromByteOffset: offset + 16, as: UInt32.self).littleEndian)
                let bv = Float(bitPattern: rawBuffer.loadUnaligned(fromByteOffset: offset + 20, as: UInt32.self).littleEndian)
                return StarRecord(
                    hr: hr,
                    hip: hip,
                    raDegrees: ra,
                    decDegrees: dec,
                    magnitude: magnitude,
                    bvColorIndex: bv
                )
            }
        }
    }
}
