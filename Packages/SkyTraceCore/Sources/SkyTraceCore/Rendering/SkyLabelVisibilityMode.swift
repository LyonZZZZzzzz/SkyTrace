import Foundation

/// Controls whether the renderer may automatically suppress labels.
public enum SkyLabelVisibilityMode: Sendable, Equatable {
    /// Preserves the current mobile behavior: field-of-view, interaction and
    /// system-pressure profiles may reduce or collision-hide labels.
    case adaptive

    /// Keeps every label allowed by the user's density setting visible inside
    /// the viewport. Labels may still be culled when they are off-screen.
    case alwaysVisible
}
