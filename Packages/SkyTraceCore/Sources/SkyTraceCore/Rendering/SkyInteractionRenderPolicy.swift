import Foundation

struct SkyInteractionRenderProfile: Equatable, Sendable {
    let hidesFaintStars: Bool
    let labelCapacityLimit: Int?

    static let full = SkyInteractionRenderProfile(
        hidesFaintStars: false,
        labelCapacityLimit: nil
    )
}

/// Keeps interactive camera motion within the frame budget without changing
/// the settled star-map appearance.
struct SkyInteractionRenderPolicy: Sendable {
    static let faintStarMagnitudeCutoff = 5.5
    static let faintStarEntryFieldOfView = 95.0
    static let faintStarExitFieldOfView = 88.0
    static let labelCapacityLimit = 50

    private(set) var hidesFaintStars = false

    mutating func update(
        isInteractionActive: Bool,
        fieldOfView: Double
    ) -> SkyInteractionRenderProfile {
        guard isInteractionActive else {
            hidesFaintStars = false
            return .full
        }

        if hidesFaintStars {
            if fieldOfView <= Self.faintStarExitFieldOfView {
                hidesFaintStars = false
            }
        } else if fieldOfView >= Self.faintStarEntryFieldOfView {
            hidesFaintStars = true
        }

        return SkyInteractionRenderProfile(
            hidesFaintStars: hidesFaintStars,
            labelCapacityLimit: Self.labelCapacityLimit
        )
    }

    static func isFaintStar(_ object: CelestialObject) -> Bool {
        object.kind == .star &&
            Double(object.magnitude ?? .infinity) > faintStarMagnitudeCutoff
    }
}
