import Foundation

/// Settings shared between the app and its home-screen widget through an
/// App Group, so the widget can show the user's favourite teams.
enum SharedStore {
    static let appGroup = "group.app.rankpulse"
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: appGroup) ?? .standard  // UserDefaults is thread-safe

    static var favourites: [String] {
        get { defaults.stringArray(forKey: "favourites") ?? [] }
        set { defaults.set(newValue, forKey: "favourites") }
    }
}
