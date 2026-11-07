import AppKit

/// Opening a running LaunchApp sends a reopen event, which toggles its grid like its Dock icon does.
enum LaunchAppBridge {
    static let bundleID = "com.vuhpquang.launchapp"
    static let sfSymbol = "square.grid.3x3"
    static let releasesURL = URL(string: "https://github.com/vuhpquang/launch-app/releases")!

    @MainActor
    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// False when LaunchApp is not installed, so the caller can point at its download instead.
    @MainActor
    @discardableResult
    static func open() -> Bool {
        guard let appURL else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        return true
    }
}
