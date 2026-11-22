import Foundation
import SuiteCore

/// Launcher's settings, kept in its user defaults. Launcher reads them as its own; Explorer Settings
/// will read and write them through `forManager`.
public final class LauncherSettings {
    public static let bundleID = LauncherApp.bundleID

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static func forManager() -> LauncherSettings {
        LauncherSettings(defaults: UserDefaults(suiteName: bundleID) ?? .standard)
    }

    public func reload() { defaults.synchronize() }

    /// Pressing Esc closes the Launcher.
    public var dismissOnEsc: Bool {
        get { defaults.object(forKey: "dismissOnEsc") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "dismissOnEsc") }
    }

    /// Clicking outside the icons closes the Launcher.
    public var dismissOnClickOutside: Bool {
        get { defaults.object(forKey: "dismissOnClickOutside") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "dismissOnClickOutside") }
    }
}
