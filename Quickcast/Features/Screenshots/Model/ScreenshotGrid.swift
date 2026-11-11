import Foundation

/// One day's captures; `start` is the flat selection index of its first cell.
struct ScreenshotDay: Identifiable, Sendable {
    let day: Date
    let items: [Screenshot]
    let start: Int

    var id: Date { day }
}

/// Grid density. Zoom changes it for the open screen only, as the emoji picker's does.
enum ScreenshotGridColumns: Int, CaseIterable, Identifiable, Sendable {
    case three = 3
    case four = 4
    case five = 5
    case six = 6

    static let `default`: Self = .four

    var id: Int { rawValue }

    /// Nil when the zoom would change nothing: already at the default, or at three or six columns.
    func applying(_ zoom: EmojiGridZoom, default defaultColumns: Self) -> Self? {
        let next: Self? =
            switch zoom {
            case .actualSize: defaultColumns
            case .zoomIn: Self(rawValue: rawValue - 1)
            case .zoomOut: Self(rawValue: rawValue + 1)
            }
        return next == self ? nil : next
    }
}

/// Order, day grouping and search over the folder's captures.
enum ScreenshotGrid {
    /// Newest first; equal dates fall back to the name, so the order never flickers between scans.
    static func sorted(_ items: [Screenshot]) -> [Screenshot] {
        items.sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.name > rhs.name
        }
    }

    /// Consecutive runs of the same calendar day; `items` must already be newest first.
    static func days(_ items: [Screenshot], calendar: Calendar) -> [ScreenshotDay] {
        var days: [ScreenshotDay] = []
        var current: (day: Date, items: [Screenshot])?
        var start = 0
        func flush() {
            guard let current else { return }
            days.append(ScreenshotDay(day: current.day, items: current.items, start: start))
            start += current.items.count
        }
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            if current?.day == day {
                current?.items.append(item)
            } else {
                flush()
                current = (day, [item])
            }
        }
        flush()
        return days
    }

    /// The name and the date written the ways people type it: "march", "mon", "2026-03-02".
    static func searchText(for item: Screenshot, locale: Locale, calendar: Calendar) -> String {
        var parts = [item.title]
        for locale in [locale, Locale(identifier: "en_US_POSIX")] {
            let full = Date.FormatStyle(
                date: .complete, time: .shortened, locale: locale, calendar: calendar,
                timeZone: calendar.timeZone)
            let short = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .month(.abbreviated).weekday(.abbreviated)
            parts.append(item.date.formatted(full))
            parts.append(item.date.formatted(short))
        }
        let day = calendar.dateComponents([.year, .month, .day], from: item.date)
        if let year = day.year, let month = day.month, let date = day.day {
            parts.append(String(format: "%04d-%02d-%02d", year, month, date))
        }
        return ScreenshotDetection.fold(parts.joined(separator: " "))
    }

    /// Every word must appear in the name, the date or the recognized text; all three come folded.
    static func matches(searchText: String, recognizedText: String?, terms: [String]) -> Bool {
        terms.allSatisfy { term in
            searchText.contains(term) || (recognizedText?.contains(term) ?? false)
        }
    }

    static func terms(_ query: String) -> [String] {
        ScreenshotDetection.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
