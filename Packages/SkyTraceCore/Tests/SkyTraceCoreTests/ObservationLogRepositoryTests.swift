import XCTest
@testable import SkyTraceCore

final class ObservationLogRepositoryTests: XCTestCase {
    func testCRUDFilterAndPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("logs.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ObservationLogRepository(fileURL: fileURL)
        let observer = ObserverContext.shanghai
        let first = ObservationLogEntry(
            objectID: "planet-jupiter",
            objectName: "木星",
            observedAt: Date(timeIntervalSince1970: 1_789_000_000),
            observer: observer,
            rating: 5,
            weather: .clear,
            equipment: .binoculars,
            notes: "条纹清晰"
        )
        let second = ObservationLogEntry(
            objectID: "moon",
            objectName: "月球",
            observedAt: Date(timeIntervalSince1970: 1_789_100_000),
            observer: observer,
            rating: 3,
            weather: .partlyCloudy,
            equipment: .nakedEye,
            notes: ""
        )

        _ = try await repository.save(first)
        _ = try await repository.save(second)
        let allEntries = try await repository.allEntries()
        let moonEntries = try await repository.entries(matching: ObservationLogFilter(objectID: "moon"))
        let highlyRatedEntries = try await repository.entries(matching: ObservationLogFilter(minimumRating: 4))
        XCTAssertEqual(allEntries.count, 2)
        XCTAssertEqual(moonEntries.count, 1)
        XCTAssertEqual(highlyRatedEntries.count, 1)

        var edited = first
        edited.rating = 2
        edited.notes = "后半夜有云"
        _ = try await repository.save(edited)
        let reloaded = ObservationLogRepository(fileURL: fileURL)
        let entries = try await reloaded.allEntries()
        XCTAssertEqual(entries.first { $0.id == first.id }?.rating, 2)

        try await reloaded.delete(id: second.id)
        let remaining = try await reloaded.allEntries()
        XCTAssertEqual(remaining.count, 1)
    }

    func testCorruptFileIsBackedUp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("logs.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ObservationLogRepository(fileURL: fileURL)

        do {
            _ = try await repository.allEntries()
            XCTFail("Expected decoding failure")
        } catch {
            XCTAssertTrue(error is ObservationLogError)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(backups.contains { $0.hasPrefix("observation-log-corrupt-") })
        let remaining = try await repository.allEntries()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRemovingUnknownObjectsCleansLogs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("logs.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ObservationLogRepository(fileURL: fileURL)
        let entry = ObservationLogEntry(
            objectID: "removed-object",
            objectName: "旧目标",
            observedAt: Date(),
            observer: .shanghai,
            rating: 4,
            weather: .clear,
            equipment: .nakedEye,
            notes: ""
        )
        _ = try await repository.save(entry)
        try await repository.removeUnknownObjects(validIDs: ["moon"])
        let remaining = try await repository.allEntries()
        XCTAssertTrue(remaining.isEmpty)
    }
}
