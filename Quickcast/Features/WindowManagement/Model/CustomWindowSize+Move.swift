import Foundation

/// Quickcast fork: Move Window's typed position, a one-off custom size that keeps the size.
extension CustomWindowSize {
    /// The field names Move Window's launcher fields and its link's `arguments` share.
    enum MoveField {
        static let x = "x"
        static let y = "y"
        static let anchor = "anchor"
    }

    /// Nil when a coordinate is missing or out of range; the position defaults to the top left.
    static func move(x: String?, y: String?, anchor: String? = nil) -> CustomWindowSize? {
        guard let x = x.flatMap(Offset.Unit.coordinate(typed:)),
            let y = y.flatMap(Offset.Unit.coordinate(typed:))
        else { return nil }
        let corner: WindowLayoutAnchor
        if let anchor, !anchor.isEmpty {
            guard let named = WindowLayoutAnchor(rawValue: anchor.lowercased()) else { return nil }
            corner = named
        } else {
            corner = .topLeft
        }
        return CustomWindowSize(
            name: "", width: Dimension(1, .current), height: Dimension(1, .current),
            anchor: corner, offset: Offset(x: x.value, y: y.value, xUnit: x.unit, yUnit: y.unit))
    }
}

extension CustomWindowSize.Offset.Unit {
    /// `120` or `120pt` is points and `10%` a share of the box; out of range is refused.
    static func coordinate(typed: String) -> (value: Int, unit: Self)? {
        let trimmed = typed.trimmingCharacters(in: .whitespaces).lowercased()
        for unit in [Self.percent, .points] where trimmed.hasSuffix(unit.suffix) {
            return number(String(trimmed.dropLast(unit.suffix.count)), unit)
        }
        return number(trimmed, .points)
    }

    private static func number(_ digits: String, _ unit: Self) -> (value: Int, unit: Self)? {
        guard let value = Int(digits.trimmingCharacters(in: .whitespaces)),
            unit.range.contains(value)
        else { return nil }
        return (value, unit)
    }
}
