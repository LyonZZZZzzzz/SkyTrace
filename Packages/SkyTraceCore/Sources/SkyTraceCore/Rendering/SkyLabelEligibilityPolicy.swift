import CoreGraphics
import Foundation

/// Screen-space eligibility rules for labels that are new versus already shown.
struct SkyLabelEligibilityPolicy {
    static let enteringDepth: Double = 0.02
    static let retainedDepth: Double = -0.03
    static let enteringHorizontalMargin: CGFloat = 24
    static let enteringVerticalMargin: CGFloat = 20
    static let retainedHorizontalMargin: CGFloat = 60
    static let retainedVerticalMargin: CGFloat = 48

    static func isDepthEligible(_ depth: Double, wasIncluded: Bool) -> Bool {
        depth > (wasIncluded ? retainedDepth : enteringDepth)
    }

    static func isPointEligible(_ point: CGPoint, size: CGSize, wasIncluded: Bool) -> Bool {
        let horizontalMargin = wasIncluded ? retainedHorizontalMargin : enteringHorizontalMargin
        let verticalMargin = wasIncluded ? retainedVerticalMargin : enteringVerticalMargin
        return point.x >= -horizontalMargin &&
            point.x <= size.width + horizontalMargin &&
            point.y >= -verticalMargin &&
            point.y <= size.height + verticalMargin
    }
}
