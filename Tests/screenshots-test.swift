import Foundation

@main
struct ScreenshotsTest {
    @MainActor
    static func main() {
        var failures = 0
        func check(_ label: String, _ condition: Bool) {
            if !condition {
                failures += 1
                print("FAIL: \(label)")
            }
        }

        // Detection: the capture flag wins, a name is the fallback, the type always decides.
        typealias Detect = ScreenshotDetection
        check("a flagged png is an image", Detect.kind(of: "anything.png", flaggedAsCapture: true) == .image)
        check("a flagged mov is a recording", Detect.kind(of: "clip.MOV", flaggedAsCapture: true) == .recording)
        check("a flagged text file is not a capture", Detect.kind(of: "notes.txt", flaggedAsCapture: true) == nil)
        check(
            "the English name is enough",
            Detect.kind(of: "Screenshot 2026-11-11 at 10.32.08.png", flaggedAsCapture: false) == .image)
        check(
            "pre-Mojave names count",
            Detect.kind(of: "Screen Shot 2018-01-02 at 9.00.00 AM.png", flaggedAsCapture: false) == .image)
        check(
            "recordings by name",
            Detect.kind(of: "Screen Recording 2026-11-11 at 10.00.00.mov", flaggedAsCapture: false) == .recording)
        check("case is ignored", Detect.kind(of: "screenshot_1788939033.PNG", flaggedAsCapture: false) == .image)
        check(
            "localized names count, diacritics folded",
            Detect.kind(of: "Anh man hinh 2026-11-11.png", flaggedAsCapture: false) == .image
                && Detect.kind(of: "Ảnh màn hình 2026-11-11.png", flaggedAsCapture: false) == .image
                && Detect.kind(of: "Bildschirmfoto 2026-11-11.png", flaggedAsCapture: false) == .image
                && Detect.kind(of: "スクリーンショット 2026-11-11.png", flaggedAsCapture: false) == .image)
        check(
            "French curly and straight apostrophes both match",
            Detect.kind(of: "Capture d’écran 2026.png", flaggedAsCapture: false) == .image
                && Detect.kind(of: "Capture d'écran 2026.png", flaggedAsCapture: false) == .image)
        check("an unrelated image is skipped", Detect.kind(of: "holiday.jpg", flaggedAsCapture: false) == nil)
        check(
            "the custom prefix from screencapture's name counts",
            Detect.kind(of: "Shot 1.png", flaggedAsCapture: false, customPrefix: "Shot") == .image)
        check(
            "a blank custom prefix matches nothing extra",
            Detect.kind(of: "holiday.png", flaggedAsCapture: false, customPrefix: "  ") == nil)

        // Location: unset or blank is the Desktop, `~` expands, a relative path sits under home.
        let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)
        check("unset is the Desktop", Detect.folder(configured: nil, home: home).path == "/Users/test/Desktop")
        check("blank is the Desktop", Detect.folder(configured: "  ", home: home).path == "/Users/test/Desktop")
        check(
            "tilde expands",
            Detect.folder(configured: "~/Pictures/Screenshots", home: home).path
                == "/Users/test/Pictures/Screenshots")
        check("absolute stays", Detect.folder(configured: "/Volumes/Shots/", home: home).path == "/Volumes/Shots")
        check("relative is under home", Detect.folder(configured: "Shots", home: home).path == "/Users/test/Shots")

        // Order and days.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let base = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 10))!
        func shot(_ name: String, hours: Double, kind: Screenshot.Kind = .image) -> Screenshot {
            let date = base.addingTimeInterval(hours * 3600)
            return Screenshot(
                url: URL(filePath: "/tmp/shots/\(name)"), date: date, modified: date, kind: kind)
        }
        let a = shot("Screenshot a.png", hours: 0)
        let b = shot("Screenshot b.png", hours: 1)
        let c = shot("Screenshot c.png", hours: 30)
        let d = shot("Screen Recording d.mov", hours: -20, kind: .recording)
        let tie = shot("Screenshot z.png", hours: 1)
        let sorted = ScreenshotGrid.sorted([a, d, c, b, tie])
        check("newest first", sorted.map(\.name).first == c.name && sorted.last == d)
        check("equal dates order by name", sorted[1] == tie && sorted[2] == b)
        let days = ScreenshotGrid.days(sorted, calendar: calendar)
        check("three days", days.count == 3)
        check("day sizes", days.map(\.items.count) == [1, 3, 1])
        check("day starts are flat indexes", days.map(\.start) == [0, 1, 4])
        check("a day starts at midnight", days[1].day == calendar.startOfDay(for: a.date))
        check("no items, no days", ScreenshotGrid.days([], calendar: calendar).isEmpty)

        // Search: every word, in any order, against name, date and recognized text.
        let locale = Locale(identifier: "en_US")
        let text = ScreenshotGrid.searchText(for: a, locale: locale, calendar: calendar)
        func matches(_ query: String, _ recognized: String? = nil) -> Bool {
            ScreenshotGrid.matches(
                searchText: text, recognizedText: recognized.map(Detect.fold),
                terms: ScreenshotGrid.terms(query))
        }
        check("name matches", matches("screenshot"))
        check("month name matches", matches("march"))
        check("abbreviated month and weekday match", matches("mar mon"))
        check("ISO date matches", matches("2026-03-02"))
        check("words in any order", matches("march screenshot"))
        check("case and diacritics fold", matches("MÄRCH") && matches("SCREENSHOT"))
        check("a missing word fails", !matches("screenshot invoice"))
        check("recognized text matches", matches("invoice", "Invoice #42 — Total"))
        check("recognized text adds to the name", matches("screenshot total", "Invoice #42 — Total"))
        check("whitespace-only query has no terms", ScreenshotGrid.terms("   ").isEmpty)
        let vietnamese = ScreenshotGrid.searchText(
            for: a, locale: Locale(identifier: "vi_VN"), calendar: calendar)
        check("the English month is always searchable", vietnamese.contains("march"))

        // Columns and zoom.
        check("four is the default", ScreenshotGridColumns.default == .four)
        check("zoom in removes a column", ScreenshotGridColumns.four.applying(.zoomIn, default: .four) == .three)
        check("zoom out adds a column", ScreenshotGridColumns.four.applying(.zoomOut, default: .four) == .five)
        check("three is the floor", ScreenshotGridColumns.three.applying(.zoomIn, default: .four) == nil)
        check("six is the ceiling", ScreenshotGridColumns.six.applying(.zoomOut, default: .four) == nil)
        check("actual size returns", ScreenshotGridColumns.six.applying(.actualSize, default: .four) == .four)
        check("actual size at default is a no-op", ScreenshotGridColumns.four.applying(.actualSize, default: .four) == nil)

        // Keyboard moves reuse the emoji grid's geometry over day sections.
        let geometry = EmojiGridGeometry(counts: days.map(\.items.count), columns: 2)
        check("down from a lone day lands in the next day's column", geometry.down(from: 0) == 1)
        check("down inside a day keeps the column", geometry.down(from: 1) == 3)
        check("down onto a partial row clamps", geometry.down(from: 2) == 3)
        check("down from the last row of a day spills over", geometry.down(from: 3) == 4)
        check("up keeps the column across days", geometry.up(from: 4) == 3)

        // Recognized text: folded, keyed by modification date, pruned, saved only when dirty.
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "screenshots-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "nested/screenshot-text.json")
        let store = ScreenshotTextStore(fileURL: fileURL)
        check("a fresh store is empty", store.count == 0 && store.text(for: a) == nil)
        check("an image needs text", store.needsText(a))
        check("a recording never needs text", !store.needsText(d))
        store.setText("Ảnh Invoice", for: a)
        check("text is stored folded", store.text(for: a) == "anh invoice")
        check("a read image needs nothing", !store.needsText(a))
        store.setText("", for: b)
        check("empty text still counts as read", store.text(for: b) == "" && !store.needsText(b))
        let edited = Screenshot(url: a.url, date: a.date, modified: a.modified.addingTimeInterval(5), kind: .image)
        check("an edited capture is unread", store.text(for: edited) == nil && store.needsText(edited))
        store.save()
        check("the file is written, creating its folder", FileManager.default.fileExists(atPath: fileURL.path))
        let reloaded = ScreenshotTextStore(fileURL: fileURL)
        check("the file round-trips", reloaded.text(for: a) == "anh invoice" && reloaded.text(for: b) == "")
        let revision = reloaded.revision
        reloaded.retain(only: [a])
        check("retain drops captures that left", reloaded.text(for: b) == nil && reloaded.count == 1)
        check("retain bumps the revision", reloaded.revision > revision)
        reloaded.removeAll()
        check("removing everything deletes the file", !FileManager.default.fileExists(atPath: fileURL.path))

        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("screenshots-test: all checks passed")
    }
}
