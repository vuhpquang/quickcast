import Foundation

/// Finished dictations, newest first, in one JSON file that never leaves this Mac.
@MainActor
@Observable
final class DictationHistoryStore {
    private let fileURL: URL

    private(set) var entries: [DictationHistoryEntry]
    private(set) var limit: Int

    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
    }

    @ObservationIgnored private var searchMemo = Memo<SearchKey, [DictationHistoryEntry]>()
    /// Bumped on every mutation, so the memo key names the entries it filtered.
    private var revision = 0

    init(fileURL: URL, limit: Int) {
        self.fileURL = fileURL
        let limit = max(limit, 0)
        self.limit = limit
        let stored =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([DictationHistoryEntry].self, from: $0) } ?? []
        entries = Array(stored.prefix(limit))
        if entries.count < stored.count { persist() }
    }

    /// Nil when nothing was kept: empty text, or history switched off.
    @discardableResult
    func record(
        _ text: String, model: String, modelTitle: String, appName: String?, bundleID: String?,
        at date: Date
    ) -> DictationHistoryEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !trimmed.isEmpty else { return nil }
        let entry = DictationHistoryEntry(
            text: trimmed, date: date, appName: appName, bundleID: bundleID, model: model,
            modelTitle: modelTitle)
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        persist()
        return entry
    }

    /// Lowering the limit drops the oldest entries at once; zero drops them all.
    func setLimit(_ newLimit: Int) {
        limit = max(newLimit, 0)
        guard entries.count > limit else { return }
        entries.removeLast(entries.count - limit)
        persist()
    }

    func entry(id: DictationHistoryEntry.ID) -> DictationHistoryEntry? {
        entries.first { $0.id == id }
    }

    func remove(id: DictationHistoryEntry.ID) {
        let before = entries.count
        entries.removeAll { $0.id == id }
        if entries.count != before { persist() }
    }

    func clearAll() {
        entries = []
        persist()
    }

    func search(_ query: String) -> [DictationHistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return searchMemo.value(for: SearchKey(query: trimmed, revision: revision)) {
            entries.filter {
                $0.text.localizedCaseInsensitiveContains(trimmed)
                    || $0.appName?.localizedCaseInsensitiveContains(trimmed) == true
            }
        }
    }

    /// An empty history leaves no file behind, so switching it off removes the text from disk.
    private func persist() {
        revision &+= 1
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
