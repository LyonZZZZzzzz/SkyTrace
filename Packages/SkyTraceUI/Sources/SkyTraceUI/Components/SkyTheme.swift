import SwiftUI

public extension Color {
    static let skyBackground = Color(red: 0.008, green: 0.024, blue: 0.055)
    static let skyCanvasLight = Color(red: 0.055, green: 0.10, blue: 0.20)
    static let skyCyan = Color(red: 0.25, green: 0.82, blue: 0.98)
    static let skyOrange = Color(red: 1.0, green: 0.60, blue: 0.22)
    static let skyMint = Color(red: 0.35, green: 0.92, blue: 0.76)
}

public struct SkyPanelModifier: ViewModifier {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 20) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.primary.opacity(0.09), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

public extension View {
    func skyPanel(cornerRadius: CGFloat = 20) -> some View {
        modifier(SkyPanelModifier(cornerRadius: cornerRadius))
    }
}

public struct SkyRoundIconButton: View {
    public let systemName: String
    public let accessibilityLabel: String
    public var isActive: Bool
    public let action: () -> Void

    public init(
        systemName: String,
        accessibilityLabel: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(isActive ? Color.skyBackground : .primary)
                .background(isActive ? Color.skyCyan : Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

public enum SkyLabelDensity: String, CaseIterable, Codable, Sendable {
    case compact
    case standard
    case detailed

    public var localizedName: String {
        switch self {
        case .compact: "精简"
        case .standard: "标准"
        case .detailed: "完整"
        }
    }

    public var magnitudeLimit: Double {
        switch self {
        case .compact: 1.5
        case .standard: 2.8
        case .detailed: 4.2
        }
    }
}
