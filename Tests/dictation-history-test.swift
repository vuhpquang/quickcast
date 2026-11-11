import Foundation

@main
struct DictationHistoryTest {
    @MainActor
    static func main() {
        var failures = 0
        func check(_ label: String, _ condition: Bool) {
            if !condition {
                failures += 1
                print("FAIL: \(label)")
            }
        }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "dictation-history-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "nested/dictation-history.json")
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        func record(_ store: DictationHistoryStore, _ text: String, offset: TimeInterval) -> Bool {
            store.record(
                text, model: "redux", modelTitle: "Parakeet · Redux", appName: "Notes",
                bundleID: "com.apple.Notes", at: start.addingTimeInterval(offset)) != nil
        }

        let store = DictationHistoryStore(fileURL: fileURL, limit: 3)
        check("a fresh store is empty", store.entries.isEmpty)
        check("empty text is skipped", !record(store, "  \n ", offset: 0))
        check("nothing is written for skipped text", !FileManager.default.fileExists(atPath: fileURL.path))
        check("text is kept", record(store, " Hello there, world. ", offset: 1))
        check("trimmed on save", store.entries.first?.text == "Hello there, world.")
        check("words are counted", store.entries.first?.wordCount == 3)
        check("metadata is kept",
            store.entries.first?.appName == "Notes" && store.entries.first?.bundleID == "com.apple.Notes"
                && store.entries.first?.model == "redux"
                && store.entries.first?.modelTitle == "Parakeet · Redux")
        check("the file is written, creating its folder", FileManager.default.fileExists(atPath: fileURL.path))

        _ = record(store, "second", offset: 2)
        _ = record(store, "third", offset: 3)
        _ = record(store, "fourth\nline", offset: 4)
        check("the cap keeps the newest", store.entries.map(\.text) == ["fourth\nline", "third", "second"])
        check("a preview folds newlines", store.entries.first?.preview == "fourth line")

        let reloaded = DictationHistoryStore(fileURL: fileURL, limit: 3)
        check("entries round-trip through the file", reloaded.entries == store.entries)
        check("dates round-trip", reloaded.entries.first?.date == start.addingTimeInterval(4))

        let tighter = DictationHistoryStore(fileURL: fileURL, limit: 2)
        check("a lower limit on load trims", tighter.entries.map(\.text) == ["fourth\nline", "third"])
        check(
            "and the trim is persisted",
            DictationHistoryStore(fileURL: fileURL, limit: 10).entries.count == 2)

        check("search matches text", tighter.search("THIRD").map(\.text) == ["third"])
        check("search matches the app", tighter.search("notes").count == 2)
        check("a blank query lists everything", tighter.search("  ").count == 2)

        if let first = tighter.entries.first { tighter.remove(id: first.id) }
        check("remove drops one entry", tighter.entries.map(\.text) == ["third"])
        check("search sees the removal", tighter.search("fourth").isEmpty)
        check("remove persists", DictationHistoryStore(fileURL: fileURL, limit: 10).entries.count == 1)

        tighter.clearAll()
        check("clear empties the store", tighter.entries.isEmpty)
        check("clear removes the file", !FileManager.default.fileExists(atPath: fileURL.path))

        let off = DictationHistoryStore(fileURL: fileURL, limit: 5)
        _ = record(off, "kept", offset: 5)
        off.setLimit(DictationHistoryLimit.off.rawValue)
        check("off clears what was kept", off.entries.isEmpty)
        check("off removes the file", !FileManager.default.fileExists(atPath: fileURL.path))
        check("off records nothing", !record(off, "dropped", offset: 6))
        check("a zero limit on load keeps nothing", DictationHistoryStore(fileURL: fileURL, limit: 0).entries.isEmpty)

        off.setLimit(DictationHistoryLimit.standard.rawValue)
        check("turning it back on records again", record(off, "back", offset: 7))

        check("the default keeps a hundred", DictationHistoryLimit.standard.rawValue == 100)
        check("off is zero", DictationHistoryLimit.off.rawValue == 0)
        check("off has a title", DictationHistoryLimit.off.title(locale: Locale(identifier: "en_US")) == "Off")
        check(
            "counts are formatted", DictationHistoryLimit.fiveHundred.title(locale: Locale(identifier: "en_US")) == "500")
        check("languages without spaces count words", DictationHistoryEntry.wordCount("今日は良い天気です") > 1)

        let corrupt = directory.appending(path: "corrupt.json")
        try? Data("not json".utf8).write(to: corrupt)
        check("a corrupt file loads empty", DictationHistoryStore(fileURL: corrupt, limit: 5).entries.isEmpty)

        guard failures == 0 else {
            print("\(failures) failed")
            exit(1)
        }
        print("dictation-history-test passed")
    }
}
