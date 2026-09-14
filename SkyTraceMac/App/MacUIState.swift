import Observation
import SkyTraceUI
import SwiftUI

@MainActor
@Observable
final class MacUIState {
    var columnVisibility: NavigationSplitViewVisibility = .all
    var showSearch = false
    var showLocation = false
    var showTonight = false

    var showConstellations: Bool {
        didSet { UserDefaults.standard.set(showConstellations, forKey: Keys.showConstellations) }
    }

    var showCardinals: Bool {
        didSet { UserDefaults.standard.set(showCardinals, forKey: Keys.showCardinals) }
    }

    var starScale: Double {
        didSet { UserDefaults.standard.set(starScale, forKey: Keys.starScale) }
    }

    var labelDensity: SkyLabelDensity {
        didSet { UserDefaults.standard.set(labelDensity.rawValue, forKey: Keys.labelDensity) }
    }

    init() {
        let defaults = UserDefaults.standard
        showConstellations = defaults.object(forKey: Keys.showConstellations) as? Bool ?? true
        showCardinals = defaults.object(forKey: Keys.showCardinals) as? Bool ?? true
        starScale = defaults.object(forKey: Keys.starScale) as? Double ?? 1
        labelDensity = SkyLabelDensity(
            rawValue: defaults.string(forKey: Keys.labelDensity) ?? ""
        ) ?? .standard
    }

    func toggleInspector() {
        columnVisibility = columnVisibility == .all ? .doubleColumn : .all
    }

    func resetDisplaySettings() {
        showConstellations = true
        showCardinals = true
        starScale = 1
        labelDensity = .standard
    }

    private enum Keys {
        static let showConstellations = "SkyTrace.ShowConstellations"
        static let showCardinals = "SkyTrace.ShowCardinals"
        static let starScale = "SkyTrace.StarScale"
        static let labelDensity = "SkyTrace.LabelDensity"
    }
}
