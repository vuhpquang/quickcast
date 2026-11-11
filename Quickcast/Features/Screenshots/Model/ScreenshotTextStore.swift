import Foundation

/// Text recognized in screenshots, folded for search and keyed by path and modification date.
@MainActor
@Observable
final class ScreenshotTextStore {
    private struct Entry: Codable {
        let modified: Date
        let text: String
    }

    private let fileURL: URL
    private var entries: [String: Entry]
    /// Bumped on every change, so a search memo can name the text it matched against.
    private(set) var revision = 0
    @ObservationIgnored private var isDirty = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        entries =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// Nil until the capture as it is now has been read; an edit since then counts as unread.
    func text(for item: Screenshot) -> String? {
        guard let entry = entries[item.id], entry.modified == item.modified else { return nil }
        return entry.text
    }

    func needsText(_ item: Screenshot) -> Bool {
        item.kind == .image && text(for: item) == nil
    }

    /// An empty result is kept too, so a capture with no text is not read again.
    func setText(_ text: String, for item: Screenshot) {
        entries[item.id] = Entry(modified: item.modified, text: ScreenshotDetection.fold(text))
        revision += 1
        isDirty = true
    }

    /// Drops captures that left the folder, so the file never outgrows it.
    func retain(only items: [Screenshot]) {
        let kept = Set(items.map(\.id))
        let before = entries.count
        entries = entries.filter { kept.contains($0.key) }
        guard entries.count != before else { return }
        revision += 1
        isDirty = true
    }

    func removeAll() {
        guard !entries.isEmpty else { return }
        entries = [:]
        revision += 1
        isDirty = true
        save()
    }

    var count: Int { entries.count }

    /// Written in batches by the caller rather than per capture; an empty store leaves no file.
    func save() {
        guard isDirty else { return }
        isDirty = false
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
