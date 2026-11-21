import Foundation

/// What Launcher and Explorer say to each other, as distributed notifications.
public enum LauncherMessage: String, CaseIterable, Sendable {
    /// To Launcher: show the grid.
    case open
    /// To Launcher: settings were changed in Explorer; read them again.
    case settingsDidChange

    public var name: Notification.Name { Notification.Name("local.explorer.Launcher." + rawValue) }

    public func post(_ userInfo: [String: Any]? = nil) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: userInfo,
                                                                     deliverImmediately: true)
    }

    @discardableResult
    public func observe(_ handler: @escaping (Notification) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main,
                                                            using: handler)
    }
}
