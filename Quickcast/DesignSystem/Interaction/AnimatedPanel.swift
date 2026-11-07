import AppKit

/// A panel that opens and closes with AppKit's document-window animation while Quickcast animates.
@MainActor
protocol AnimatedPanel: NSPanel {}

extension AnimatedPanel {
    func followMotion() {
        animationBehavior = Motion.isEnabled ? .documentWindow : .none
    }
}
