import Foundation

/// User preferences, persisted in UserDefaults.
final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("BarfakSettingsDidChange")

    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "intensity": 1,
            "wind": true,
            "accumulate": true,
            "snowman": true,
            "paused": false,
        ])
    }

    /// 0 = light, 1 = medium, 2 = heavy
    var intensity: Int {
        get { min(2, max(0, d.integer(forKey: "intensity"))) }
        set { d.set(newValue, forKey: "intensity"); notify() }
    }
    var wind: Bool {
        get { d.bool(forKey: "wind") }
        set { d.set(newValue, forKey: "wind"); notify() }
    }
    var accumulate: Bool {
        get { d.bool(forKey: "accumulate") }
        set { d.set(newValue, forKey: "accumulate"); notify() }
    }
    var snowman: Bool {
        get { d.bool(forKey: "snowman") }
        set { d.set(newValue, forKey: "snowman"); notify() }
    }
    var paused: Bool {
        get { d.bool(forKey: "paused") }
        set { d.set(newValue, forKey: "paused"); notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }
}
