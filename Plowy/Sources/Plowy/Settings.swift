import Foundation

extension Notification.Name {
    static let plowyPlowNow = Notification.Name("PlowyPlowNow")
    static let plowyClearCables = Notification.Name("PlowyClearCables")
}

/// User preferences, persisted in UserDefaults.
final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("PlowySettingsDidChange")
    /// Set PLOWY_DEMO=1 to pre-fill the scene (used for automated screenshots).
    static let demo = ProcessInfo.processInfo.environment["PLOWY_DEMO"] != nil

    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "intensity": 1,
            "wind": true,
            "accumulate": true,
            "snowman": true,
            "paused": false,
            "lights": true,
            "lightStyle": 0,
            "plow": true,
            "cableCar": true,
            "iconSnow": true,
            "wallpaperSnow": false,
        ])
    }

    private func bool(_ key: String) -> Bool { d.bool(forKey: key) }
    private func set(_ value: Any, _ key: String) {
        d.set(value, forKey: key)
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }

    /// 0 = light, 1 = medium, 2 = heavy
    var intensity: Int {
        get { min(2, max(0, d.integer(forKey: "intensity"))) }
        set { set(newValue, "intensity") }
    }
    /// 0...3, see `Art.bulbStyles`
    var lightStyle: Int {
        get { min(3, max(0, d.integer(forKey: "lightStyle"))) }
        set { set(newValue, "lightStyle") }
    }
    /// Language code, or "" to follow the system.
    var language: String {
        get { d.string(forKey: "language") ?? "" }
        set { set(newValue, "language") }
    }
    var wind: Bool { get { bool("wind") } set { set(newValue, "wind") } }
    var accumulate: Bool { get { bool("accumulate") } set { set(newValue, "accumulate") } }
    var snowman: Bool { get { bool("snowman") } set { set(newValue, "snowman") } }
    var paused: Bool { get { bool("paused") } set { set(newValue, "paused") } }
    var lights: Bool { get { bool("lights") } set { set(newValue, "lights") } }
    var plow: Bool { get { bool("plow") } set { set(newValue, "plow") } }
    var cableCar: Bool { get { bool("cableCar") } set { set(newValue, "cableCar") } }
    var iconSnow: Bool { get { bool("iconSnow") } set { set(newValue, "iconSnow") } }
    var wallpaperSnow: Bool {
        get { Settings.demo || bool("wallpaperSnow") }
        set { set(newValue, "wallpaperSnow") }
    }
}
