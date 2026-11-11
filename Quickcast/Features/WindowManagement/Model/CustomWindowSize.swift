import CoreGraphics
import Foundation

struct CustomWindowSize: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "window-size:"
    static let sfSymbol = "macwindow.and.cursorarrow"

    struct Dimension: Codable, Hashable, Sendable {
        enum Unit: String, Codable, CaseIterable, Sendable {
            case points
            case percent
            /// Quickcast fork: keeps the window's own length on this axis, so a size can only move.
            case current

            /// Wider than any display for points; `current` keeps its number for switching back.
            var range: ClosedRange<Int> {
                switch self {
                case .points, .current: return 1...16_000
                case .percent: return 1...100
                }
            }

            var suffix: String {
                switch self {
                case .points: return "pt"
                case .percent: return "%"
                case .current: return ""
                }
            }

            /// What the editor's unit picker shows.
            var title: String {
                switch self {
                case .points: return "pt"
                case .percent: return "%"
                case .current: return String(localized: "window-size-unit-current", defaultValue: "Current")
                }
            }
        }

        var value: Int
        var unit: Unit

        init(_ value: Int, _ unit: Unit) {
            self.value = value.clamped(to: unit.range)
            self.unit = unit
        }

        var label: String {
            switch unit {
            case .points: return "\(value) pt"
            case .percent: return "\(value)%"
            case .current: return unit.title
            }
        }

        /// The length this asks for inside `available`, never zero and never past it.
        func length(in available: CGFloat, current: CGFloat? = nil) -> CGFloat {
            let requested: CGFloat
            switch unit {
            case .points: requested = CGFloat(value)
            case .percent: requested = available * CGFloat(value) / 100
            // No window to measure (an editor preview) reads as the whole box.
            case .current: requested = current ?? available
            }
            return min(available, max(WindowLayoutGeometry.minimumLength, requested))
        }

        func converted(to unit: Unit, in available: CGFloat) -> Dimension {
            // `current` carries no length of its own, so the number rides through unchanged.
            guard unit != self.unit, available > 0, unit != .current, self.unit != .current else {
                return Dimension(value, unit)
            }
            let points = unit == .percent ? CGFloat(value) : CGFloat(value) * available / 100
            let converted = unit == .percent ? points / available * 100 : points
            return Dimension(Int(converted.rounded()), unit)
        }
    }

    /// Applied on top of the anchor; +Y is down, as everywhere in AX space.
    struct Offset: Codable, Hashable, Sendable {
        /// Quickcast fork: an axis can be a share of the box, so one position suits every display.
        enum Unit: String, Codable, CaseIterable, Sendable {
            case points
            case percent

            var range: ClosedRange<Int> {
                switch self {
                case .points: return -4000...4000
                case .percent: return -100...100
                }
            }

            var suffix: String { self == .points ? "pt" : "%" }
        }

        static let range: ClosedRange<Int> = Unit.points.range
        static let zero = Offset(x: 0, y: 0)

        var x: Int
        var y: Int
        var xUnit: Unit
        var yUnit: Unit

        init(x: Int, y: Int, xUnit: Unit = .points, yUnit: Unit = .points) {
            self.x = x.clamped(to: xUnit.range)
            self.y = y.clamped(to: yUnit.range)
            self.xUnit = xUnit
            self.yUnit = yUnit
        }

        private enum CodingKeys: String, CodingKey { case x, y, xUnit, yUnit }

        // Units default to points, so an offset stored before they existed reads unchanged.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                x: try container.decode(Int.self, forKey: .x),
                y: try container.decode(Int.self, forKey: .y),
                xUnit: try container.decodeIfPresent(Unit.self, forKey: .xUnit) ?? .points,
                yUnit: try container.decodeIfPresent(Unit.self, forKey: .yUnit) ?? .points)
        }

        var isPoints: Bool { xUnit == .points && yUnit == .points }

        /// The shift in points inside a box of `size`.
        func distance(in size: CGSize) -> CGVector {
            func resolve(_ value: Int, _ unit: Unit, _ length: CGFloat) -> CGFloat {
                unit == .points ? CGFloat(value) : length * CGFloat(value) / 100
            }
            return CGVector(
                dx: resolve(x, xUnit, size.width), dy: resolve(y, yUnit, size.height))
        }

        static func label(_ value: Int, _ unit: Unit) -> String {
            unit == .points ? "\(value) pt" : "\(value)%"
        }
    }

    let id: UUID
    var name: String
    var width: Dimension
    var height: Dimension
    var anchor: WindowLayoutAnchor
    var offset: Offset

    init(
        id: UUID = UUID(), name: String, width: Dimension = Dimension(60, .percent),
        height: Dimension = Dimension(60, .percent), anchor: WindowLayoutAnchor = .center,
        offset: Offset = .zero
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.anchor = anchor
        self.offset = offset
    }

    // Hand-written, so an added field keeps stored sizes and older backups readable.
    private enum CodingKeys: String, CodingKey {
        case id, name, width, height, anchor, offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        width = try container.decode(Dimension.self, forKey: .width)
        height = try container.decode(Dimension.self, forKey: .height)
        anchor = try container.decode(WindowLayoutAnchor.self, forKey: .anchor)
        offset = try container.decodeIfPresent(Offset.self, forKey: .offset) ?? .zero
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    var summary: String {
        let base = "\(width.label) × \(height.label) · \(anchor.title)"
        guard offset.x != 0 || offset.y != 0 else { return base }
        guard offset.isPoints else {
            let x = Offset.label(offset.x, offset.xUnit)
            let y = Offset.label(offset.y, offset.yUnit)
            return String(localized: "\(base) · Offset \(x), \(y)")
        }
        return String(localized: "\(base) · Offset \(offset.x), \(offset.y) pt")
    }

    /// Quickcast fork: both axes keep the window's own length, so this only moves it.
    var movesOnly: Bool { width.unit == .current && height.unit == .current }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Trimmed and clamped rather than rejected, so a bad import keeps the record.
    var sanitized: CustomWindowSize {
        var cleaned = self
        cleaned.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.width = Dimension(width.value, width.unit)
        cleaned.height = Dimension(height.value, height.unit)
        cleaned.offset = Offset(x: offset.x, y: offset.y, xUnit: offset.xUnit, yUnit: offset.yUnit)
        return cleaned
    }

    // MARK: - Geometry

    /// The frame this size asks for on a display, in AX space; nil when the display has no room.
    func frame(in visibleFrame: CGRect, gap: CGFloat, current: CGSize? = nil) -> CGRect? {
        let canvas = WindowPlacementEngine.canvas(
            visibleFrame, gap: WindowPlacementEngine.sanitizedGap(gap, in: visibleFrame))
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        var size = CGSize(
            width: width.length(in: canvas.width, current: current?.width),
            height: height.length(in: canvas.height, current: current?.height))
        // A pure move never resizes, not even to fit; the clamp pins an oversized leading edge.
        if movesOnly, let current, current.width >= 1, current.height >= 1 { size = current }
        // Offset before the clamp: the nudge is the user's intent, the clamp only a safety net.
        let shift = offset.distance(in: canvas.size)
        let placed = anchor.placement.place(size, in: canvas).offsetBy(dx: shift.dx, dy: shift.dy)
        return WindowPlacementEngine.rounded(WindowPlacementEngine.clamped(placed, into: canvas))
    }

    /// Where this size puts a window, on the display the window is already on.
    func placement(
        for windowFrame: CGRect, screens: [WindowPlacementEngine.Screen], gap: CGFloat
    ) -> WindowPlacementEngine.Placement? {
        guard let host = WindowPlacementEngine.screen(containing: windowFrame, in: screens),
            let frame = frame(in: host.visibleFrame, gap: gap, current: windowFrame.size)
        else { return nil }
        return WindowPlacementEngine.Placement(
            frame: frame, screenID: host.id, anchor: anchor.placement, resizes: !movesOnly)
    }
}

enum CustomWindowSizeValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Enter a name for the size.")
        case .duplicateName: return String(localized: "A custom size with this name already exists.")
        case .invalidCharacter: return String(localized: "Names cannot contain null characters.")
        }
    }
}

extension Int {
    /// Saturating, so a typed or imported number is corrected rather than rejected.
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
