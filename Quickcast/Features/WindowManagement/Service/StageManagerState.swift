import AppKit

/// Quickcast fork: whether Stage Manager shows its strip, read fresh for each command.
@MainActor
enum StageManagerState {
    private static let windowManager = "com.apple.WindowManager"

    /// Nil while Stage Manager is off or hides its recent apps, so nothing is reserved.
    static func strip(geometry: AXGeometry) -> StageManagerStrip? {
        let domain = windowManager as CFString
        // Another process writes these keys; without the sync a toggle reads stale until relaunch.
        CFPreferencesAppSynchronize(domain)
        guard preference("GloballyEnabled", in: domain) as? Bool == true,
            preference("AutoHide", in: domain) as? Bool != true
        else { return nil }
        let dock = preference("orientation", in: "com.apple.dock" as CFString) as? String
        let edge = StageManagerStrip.edge(dockOrientation: dock)
        guard let screen = NSScreen.main else { return StageManagerStrip(edge: edge) }
        let width = StageManagerStrip.width(
            thumbnails: thumbnailFrames(), in: geometry.flip(screen.visibleFrame), edge: edge)
        return StageManagerStrip(edge: edge, width: width)
    }

    private static func preference(_ key: String, in domain: CFString) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }

    /// The WindowManager's on-screen windows, in the global top-left space AX uses too.
    private static func thumbnailFrames() -> [CGRect] {
        guard
            let pid = NSRunningApplication.runningApplications(
                withBundleIdentifier: windowManager
            ).first?.processIdentifier,
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }
}
