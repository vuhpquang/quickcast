import Foundation

/// One finished dictation, as it was delivered; kept on this Mac only.
struct DictationHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let text: String
    let date: Date
    let wordCount: Int
    /// The app the text went to; nil when no app could be named.
    let appName: String?
    let bundleID: String?
    /// The model's raw identifier, so a renamed title still reads back.
    let model: String
    let modelTitle: String

    init(
        id: UUID = UUID(), text: String, date: Date, appName: String?, bundleID: String?,
        model: String, modelTitle: String
    ) {
        self.id = id
        self.text = text
        self.date = date
        wordCount = Self.wordCount(text)
        self.appName = appName
        self.bundleID = bundleID
        self.model = model
        self.modelTitle = modelTitle
    }

    /// Word boundaries from Foundation, so languages written without spaces still count.
    static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in count += 1 }
        return count
    }

    /// The list row's one line: newlines folded so a paragraph break doesn't cut the preview.
    var preview: String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
