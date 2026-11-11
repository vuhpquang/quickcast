import CoreGraphics
import Foundation

/// Quickcast fork: the Stage Manager strip window commands keep clear. See window-management.md.
struct StageManagerStrip: Equatable, Sendable {
    enum Edge: String, Sendable { case left, right }

    /// Rectangle's default reservation, used when the strip's thumbnails can't be measured.
    static let defaultWidth: CGFloat = 190
    /// A measurement outside this is something else the WindowManager drew, not the strip.
    static let measurableWidths: ClosedRange<CGFloat> = 80...360
    /// A display narrower than this many strips keeps its full width rather than a sliver.
    private static let minimumDisplayStrips: CGFloat = 3

    var edge: Edge
    var width: CGFloat

    init(edge: Edge, width: CGFloat = defaultWidth) {
        self.edge = edge
        self.width = width.isFinite ? max(0, width) : 0
    }

    /// The strip's side: it moves to the right only when the Dock sits on the left.
    static func edge(dockOrientation: String?) -> Edge {
        dockOrientation == "left" ? .right : .left
    }

    /// From the thumbnails' frames on `visible`'s strip side, or the default when none measure.
    static func width(thumbnails: [CGRect], in visible: CGRect, edge: Edge) -> CGFloat {
        let reach = thumbnails.compactMap { thumbnail -> CGFloat? in
            guard visible.intersects(thumbnail), thumbnail.width < visible.width / 2 else {
                return nil
            }
            return edge == .left ? thumbnail.maxX - visible.minX : visible.maxX - thumbnail.minX
        }
        guard let widest = reach.max(), measurableWidths.contains(widest) else {
            return defaultWidth
        }
        return widest.rounded(.up)
    }

    /// `visible` with the strip taken off its side.
    func inset(_ visible: CGRect) -> CGRect {
        guard width > 0, visible.width >= width * Self.minimumDisplayStrips else { return visible }
        var inset = visible
        inset.size.width -= width
        if edge == .left { inset.origin.x += width }
        return inset
    }

    /// Every display's visible frame inset, so every command sees the strip as screen edge.
    func inset(_ screens: [WindowPlacementEngine.Screen]) -> [WindowPlacementEngine.Screen] {
        screens.map {
            WindowPlacementEngine.Screen(id: $0.id, frame: $0.frame, visibleFrame: inset($0.visibleFrame))
        }
    }

    // MARK: - Center

    /// True centre when the window clears the strip there, else centred beside it, shrunk to fit.
    func centered(_ window: CGSize, in visible: CGRect, gap: CGFloat) -> CGRect? {
        let full = WindowPlacementEngine.canvas(
            visible, gap: WindowPlacementEngine.sanitizedGap(gap, in: visible))
        let clearVisible = inset(visible)
        let clear = WindowPlacementEngine.canvas(
            clearVisible, gap: WindowPlacementEngine.sanitizedGap(gap, in: clearVisible))
        guard full.width > 0, full.height > 0, clear.width > 0, clear.height > 0 else {
            return nil
        }
        let size = CGSize(width: min(window.width, full.width), height: min(window.height, full.height))
        let centred = WindowPlacementEngine.rounded(
            WindowPlacementEngine.Anchor.centered.place(size, in: full))
        if centred.minX >= clear.minX, centred.maxX <= clear.maxX { return centred }
        let fitted = CGSize(width: min(size.width, clear.width), height: min(size.height, clear.height))
        return WindowPlacementEngine.rounded(
            WindowPlacementEngine.Anchor.centered.place(fitted, in: clear))
    }

    /// Center's placement on the window's own display, measured against full visible frames.
    func centerPlacement(
        for windowFrame: CGRect, screens: [WindowPlacementEngine.Screen], gap: CGFloat
    ) -> WindowPlacementEngine.Placement? {
        guard let host = WindowPlacementEngine.screen(containing: windowFrame, in: screens),
            let frame = centered(windowFrame.size, in: host.visibleFrame, gap: gap)
        else { return nil }
        return WindowPlacementEngine.Placement(
            frame: frame, screenID: host.id, anchor: .centered, resizes: true)
    }
}
