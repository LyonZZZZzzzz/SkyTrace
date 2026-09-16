import Foundation

enum SkyRenderPolicy: Equatable, Sendable {
    case interactive
    case animating
    case idleWarm
    case suspended

    var usesContinuousRendering: Bool {
        self == .interactive || self == .animating
    }
}
