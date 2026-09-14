import Foundation

public struct StarRecord: Sendable {
    public let hr: UInt32
    public let hip: UInt32
    public let raDegrees: Float
    public let decDegrees: Float
    public let magnitude: Float
    public let bvColorIndex: Float

    public init(hr: UInt32, hip: UInt32, raDegrees: Float, decDegrees: Float, magnitude: Float, bvColorIndex: Float) {
        self.hr = hr
        self.hip = hip
        self.raDegrees = raDegrees
        self.decDegrees = decDegrees
        self.magnitude = magnitude
        self.bvColorIndex = bvColorIndex
    }
}

public struct StarLabel: Codable, Hashable, Sendable {
    public let hr: UInt32
    public let hip: UInt32
    public let name: String
    public let englishName: String
    public let designation: String
    public let magnitude: Float

    public init(hr: UInt32, hip: UInt32, name: String, englishName: String, designation: String, magnitude: Float) {
        self.hr = hr
        self.hip = hip
        self.name = name
        self.englishName = englishName
        self.designation = designation
        self.magnitude = magnitude
    }

    public var displayName: String {
        if !name.isEmpty { return name }
        if !englishName.isEmpty { return englishName }
        if !designation.isEmpty { return designation }
        return "HR \(hr)"
    }
}

public struct ConstellationRecord: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let englishName: String
    public let segments: [[[Double]]]

    public init(id: String, name: String, englishName: String, segments: [[[Double]]]) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.segments = segments
    }

    public var center: (ra: Double, dec: Double)? {
        let points = segments.flatMap { $0 }
        guard !points.isEmpty else { return nil }
        var sinSum = 0.0
        var cosSum = 0.0
        var decSum = 0.0
        for point in points {
            guard point.count >= 2 else { continue }
            let radians = point[0] * .pi / 180
            sinSum += sin(radians)
            cosSum += cos(radians)
            decSum += point[1]
        }
        let ra = atan2(sinSum, cosSum) * 180 / .pi
        return (ra < 0 ? ra + 360 : ra, decSum / Double(points.count))
    }
}

public struct DeepSkyRecord: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let englishName: String
    public let designation: String
    public let type: String
    public let category: String
    public let magnitude: Double?
    public let ra: Double
    public let dec: Double

    public init(
        id: String,
        name: String,
        englishName: String,
        designation: String,
        type: String,
        category: String,
        magnitude: Double?,
        ra: Double,
        dec: Double
    ) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.designation = designation
        self.type = type
        self.category = category
        self.magnitude = magnitude
        self.ra = ra
        self.dec = dec
    }
}
