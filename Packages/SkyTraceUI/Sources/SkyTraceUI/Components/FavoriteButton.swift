import SkyTraceCore
import SwiftUI

public struct FavoriteButton: View {
    public let isFavorite: Bool
    public let accessibilityLabel: String
    public let action: () -> Void

    public init(isFavorite: Bool, accessibilityLabel: String = "收藏", action: @escaping () -> Void) {
        self.isFavorite = isFavorite
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.skyOrange : .secondary)
                .frame(width: 32, height: 32)
                .background(.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
