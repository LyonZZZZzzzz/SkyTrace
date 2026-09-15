import Foundation
import Observation

@MainActor
@Observable
public final class FavoriteStore {
    public private(set) var favoriteIDs: Set<String>
    public private(set) var reminderIDs: Set<String>
    public var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: keys.remindersEnabledKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keys: Keys

    public init(defaults: UserDefaults = .standard, namespace: String = "SkyTrace") {
        self.defaults = defaults
        keys = Keys(namespace: namespace)
        favoriteIDs = Set(defaults.stringArray(forKey: keys.favorites) ?? [])
        reminderIDs = Set(defaults.stringArray(forKey: keys.reminders) ?? [])
        remindersEnabled = defaults.object(forKey: keys.remindersEnabledKey) as? Bool ?? false
    }

    public func isFavorite(_ objectID: String) -> Bool {
        favoriteIDs.contains(objectID)
    }

    public func isReminderEnabled(_ objectID: String) -> Bool {
        reminderIDs.contains(objectID)
    }

    @discardableResult
    public func toggleFavorite(_ objectID: String) -> Bool {
        if favoriteIDs.contains(objectID) {
            favoriteIDs.remove(objectID)
            reminderIDs.remove(objectID)
            persist()
            return false
        }
        favoriteIDs.insert(objectID)
        persist()
        return true
    }

    @discardableResult
    public func setReminder(_ enabled: Bool, for objectID: String) -> Bool {
        guard favoriteIDs.contains(objectID) else { return false }
        if enabled {
            reminderIDs.insert(objectID)
        } else {
            reminderIDs.remove(objectID)
        }
        persist()
        return enabled
    }

    public func removeUnknownFavorites(validIDs: Set<String>) {
        let filteredFavorites = favoriteIDs.intersection(validIDs)
        let filteredReminders = reminderIDs.intersection(filteredFavorites)
        guard filteredFavorites != favoriteIDs || filteredReminders != reminderIDs else { return }
        favoriteIDs = filteredFavorites
        reminderIDs = filteredReminders
        persist()
    }

    private func persist() {
        defaults.set(Array(favoriteIDs).sorted(), forKey: keys.favorites)
        defaults.set(Array(reminderIDs).sorted(), forKey: keys.reminders)
    }

    private struct Keys {
        let favorites: String
        let reminders: String
        let remindersEnabledKey: String

        init(namespace: String) {
            favorites = "\(namespace).Favorites"
            reminders = "\(namespace).ObservationReminders"
            remindersEnabledKey = "\(namespace).RemindersEnabled"
        }
    }
}
