import Foundation

/// How many finished dictations are kept; `off` keeps none and clears what was kept.
enum DictationHistoryLimit: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case twentyFive = 25
    case fifty = 50
    case hundred = 100
    case twoHundredFifty = 250
    case fiveHundred = 500

    static let standard = Self.hundred

    var id: Self { self }

    func title(locale: Locale) -> String {
        switch self {
        case .off: String(localized: "Off", locale: locale)
        default: rawValue.formatted(.number.locale(locale))
        }
    }
}
