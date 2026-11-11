import Foundation

extension CustomWindowSize {
    init?(linkFields fields: [String: String]) {
        guard let width = fields["width"].flatMap(Dimension.init(linkValue:)),
            let height = fields["height"].flatMap(Dimension.init(linkValue:)),
            let anchor = Self.anchor(fields["anchor"]),
            let x = Self.offset(fields["x"]), let y = Self.offset(fields["y"])
        else { return nil }
        self.init(
            name: "", width: width, height: height, anchor: anchor,
            offset: Offset(x: x.value, y: y.value, xUnit: x.unit, yUnit: y.unit))
    }

    private static func anchor(_ value: String?) -> WindowLayoutAnchor? {
        guard let value else { return .center }
        return WindowLayoutAnchor(rawValue: value.lowercased())
    }

    // Quickcast fork: `10%` is a share of the display, as a width can be.
    private static func offset(_ value: String?) -> (value: Int, unit: Offset.Unit)? {
        guard let value else { return (0, .points) }
        return Offset.Unit.coordinate(typed: value)
    }
}

extension CustomWindowSize.Dimension {
    /// `1200` is points and `60%` a share of the screen; out of range is refused, never clamped.
    init?(linkValue: String) {
        let trimmed = linkValue.trimmingCharacters(in: .whitespaces)
        // Quickcast fork: `current` keeps the window's own length on that axis.
        if trimmed.lowercased() == Unit.current.rawValue {
            self.init(1, .current)
            return
        }
        let unit: Unit = trimmed.hasSuffix("%") ? .percent : .points
        let digits = unit == .percent ? String(trimmed.dropLast()) : trimmed
        guard let value = Int(digits), unit.range.contains(value) else { return nil }
        self.init(value, unit)
    }
}
