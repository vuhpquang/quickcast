import AppKit

/// Quickcast fork: Respect Stage Manager. See docs/features/window-management.md.
extension WindowCommandCoordinator {
    /// Nil with the setting off or the strip hidden, which leaves every command as upstream has it.
    func stageStrip() -> StageManagerStrip? {
        guard settings.windowRespectsStageManager else { return nil }
        return StageManagerState.strip(geometry: AXGeometry(screens: NSScreen.screens))
    }
}
