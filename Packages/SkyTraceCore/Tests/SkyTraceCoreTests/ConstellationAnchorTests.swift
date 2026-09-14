import XCTest
@testable import SkyTraceCore

@MainActor
final class ConstellationAnchorTests: XCTestCase {
    func testConstellationPositionUsesWeightedLineCenter() throws {
        let repository = try CatalogRepository()
        let constellation = try XCTUnwrap(repository.constellations.first { $0.id == "Psc" })
        let viewModel = SkyViewModel(catalog: repository)
        let position = try XCTUnwrap(
            viewModel.snapshot.positions.first { $0.object.id == "constellation-\(constellation.id)" }
        )

        let transform = AstronomyService().horizontalTransform(
            for: viewModel.moment,
            observer: viewModel.observer
        )
        var weightedSum = Vector3D(x: 0, y: 0, z: 0)
        var totalLength = 0.0

        for line in constellation.segments {
            guard line.count > 1 else { continue }
            for index in 1..<line.count {
                let start = line[index - 1]
                let end = line[index]
                guard start.count >= 2, end.count >= 2 else { continue }
                let startCoordinate = transform.horizontal(raDegrees: start[0], decDegrees: start[1])
                let endCoordinate = transform.horizontal(raDegrees: end[0], decDegrees: end[1])
                let startVector = vector(azimuth: startCoordinate.azimuth, altitude: startCoordinate.altitude)
                let endVector = vector(azimuth: endCoordinate.azimuth, altitude: endCoordinate.altitude)
                let length = (endVector - startVector).length
                guard length > 0 else { continue }
                weightedSum = weightedSum + (startVector + endVector) * (0.5 * length)
                totalLength += length
            }
        }

        let expectedAnchor = (weightedSum * (1 / totalLength)).normalized
        let expectedAzimuth = normalizedDegrees(atan2(expectedAnchor.x, -expectedAnchor.z) * 180 / .pi)
        let expectedAltitude = asin(min(1, max(-1, expectedAnchor.y))) * 180 / .pi

        XCTAssertEqual(position.azimuth, expectedAzimuth, accuracy: 0.000_001)
        XCTAssertEqual(position.altitude, expectedAltitude, accuracy: 0.000_001)
    }

    private func vector(azimuth: Double, altitude: Double) -> Vector3D {
        SkyPosition(
            object: CelestialObject(
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
            ),
            azimuth: azimuth,
            altitude: altitude
        ).horizontalVector
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
