import XCTest
import SkyTraceCore

@MainActor
final class SkyViewModelTests: XCTestCase {
    func testSnapshotContainsFullCatalogAndRecommendations() throws {
        let viewModel = SkyViewModel()
        guard case .ready = viewModel.catalogState else {
            return XCTFail("Catalog failed to load")
        }

        XCTAssertEqual(viewModel.snapshot.positions.count, viewModel.repository?.allObjects.count)
        XCTAssertFalse(viewModel.snapshot.constellationSegments.isEmpty)
        XCTAssertLessThanOrEqual(viewModel.snapshot.recommendations.count, 6)
    }

    func testTimeTravelUpdatesSnapshotMoment() {
        let viewModel = SkyViewModel()
        let originalDate = viewModel.moment.date
        viewModel.shiftTime(by: 3_600)

        XCTAssertEqual(viewModel.moment.date.timeIntervalSince(originalDate), 3_600, accuracy: 0.1)
        XCTAssertEqual(viewModel.snapshot.moment.date, viewModel.moment.date)
    }
}
