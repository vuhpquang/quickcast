import AppKit
import UniformTypeIdentifiers

/// Search Screenshots' action surface: the folder, the search over it and what a cell does.
@MainActor
@Observable
final class ScreenshotsCoordinator {
    let library = ScreenshotLibrary()
    let textStore: ScreenshotTextStore
    /// Nil means the configured default; zoom only overrides it while the screen is open.
    var columnsOverride: ScreenshotGridColumns?

    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    @ObservationIgnored private unowned let core: AppCore

    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
        let textRevision: Int?
    }

    @ObservationIgnored private var searchMemo = Memo<SearchKey, [Screenshot]>()
    @ObservationIgnored private var searchTexts: [String: String] = [:]
    @ObservationIgnored private var searchTextsRevision = -1
    /// Captures recognition failed on this session; retried on the next launch, never in a loop.
    @ObservationIgnored private var unreadable: Set<String> = []

    /// Matches `Paster`'s wait between activating the target and its ⌘V.
    private static let activationDelay: TimeInterval = 0.08

    init(
        textStore: ScreenshotTextStore, settings: AppSettings, windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.textStore = textStore
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    var columns: ScreenshotGridColumns { columnsOverride ?? settings.screenshotGridColumns }

    func show(query: String = "") {
        columnsOverride = nil
        paletteCoordinator.togglePalette(mode: .screenshots, seeding: query.isEmpty ? nil : query)
    }

    func zoom(_ zoom: EmojiGridZoom) {
        let defaultColumns = settings.screenshotGridColumns
        guard let next = columns.applying(zoom, default: defaultColumns) else { return }
        columnsOverride = next == defaultColumns ? nil : next
    }

    func canZoom(_ zoom: EmojiGridZoom) -> Bool {
        columns.applying(zoom, default: settings.screenshotGridColumns) != nil
    }

    /// The watcher and tiles live only while the screen is on screen.
    func setActive(_ active: Bool) {
        if active {
            library.activate()
        } else {
            library.deactivate()
            columnsOverride = nil
            ScreenshotThumbnails.purge()
            textStore.save()
        }
    }

    // MARK: - Search

    func results(for query: String) -> [Screenshot] {
        let terms = ScreenshotGrid.terms(query)
        let readsText = settings.screenshotTextSearchEnabled && !terms.isEmpty
        let key = SearchKey(
            query: terms.joined(separator: " "), revision: library.revision,
            textRevision: readsText ? textStore.revision : nil)
        return searchMemo.value(for: key) {
            guard !terms.isEmpty else { return library.items }
            let texts = searchTexts(for: library.items)
            return library.items.filter { item in
                ScreenshotGrid.matches(
                    searchText: texts[item.id] ?? "",
                    recognizedText: readsText ? textStore.text(for: item) : nil, terms: terms)
            }
        }
    }

    /// Formatted once per scan rather than per keystroke.
    private func searchTexts(for items: [Screenshot]) -> [String: String] {
        guard searchTextsRevision != library.revision else { return searchTexts }
        var texts: [String: String] = [:]
        for item in items {
            texts[item.id] =
                searchTexts[item.id]
                ?? ScreenshotGrid.searchText(for: item, locale: .current, calendar: .current)
        }
        searchTexts = texts
        searchTextsRevision = library.revision
        return texts
    }

    /// Reads one capture at a time in `ClipboardTextHelper`, newest first, until none is left.
    func recognizeText() async {
        defer {
            textStore.retain(only: library.items)
            textStore.save()
        }
        var sinceSave = 0
        while settings.screenshotTextSearchEnabled, !Task.isCancelled {
            guard
                let next = library.items.first(where: {
                    textStore.needsText($0) && !unreadable.contains($0.id)
                })
            else { return }
            do {
                let text = try await ClipboardTextWorker.extract(
                    at: next.url, isPDF: false, executable: ClipboardTextWorker.executable)
                guard !Task.isCancelled else { return }
                textStore.setText(text, for: next)
            } catch {
                guard !Task.isCancelled else { return }
                unreadable.insert(next.id)
            }
            sinceSave += 1
            if sinceSave >= 10 {
                textStore.save()
                sinceSave = 0
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - Actions

    func paste(_ item: Screenshot) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        guard Self.write(item) else { return reportMissing(item) }
        previous?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationDelay) {
            Paster.postCommandV()
        }
    }

    func copy(_ item: Screenshot) {
        guard Self.write(item) else { return reportMissing(item) }
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.showMessage(
            item.kind == .image ? String(localized: "Copied image") : String(localized: "Copied file"))
    }

    func open(_ item: Screenshot) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            do {
                _ = try await NSWorkspace.shared.open(item.url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                await core.showNotice(
                    title: String(localized: "Couldn’t Open \(item.name)"),
                    message: error.localizedDescription, symbol: "photo", tone: .danger)
            }
        }
    }

    func showInFinder(_ item: Screenshot) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(item.url)
    }

    func copyPath(_ item: Screenshot) {
        Paster.copyPlainText(item.url.path)
        core.showMessage(String(localized: "Copied path"))
    }

    func trash(_ item: Screenshot) async {
        guard
            await core.confirm(
                title: String(localized: "Move \(item.name) to Trash?"),
                message: String(localized: "You can put it back from the Trash in Finder."),
                symbol: "trash", confirmTitle: String(localized: "Move to Trash"))
        else { return }
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            }.value
            library.remove(item)
            core.showMessage(String(localized: "Moved to Trash"))
        } catch {
            await core.showNotice(
                title: String(localized: "Couldn’t Move \(item.name) to Trash"),
                message: error.localizedDescription, symbol: "trash", tone: .danger)
        }
    }

    private func reportMissing(_ item: Screenshot) {
        library.rescan()
        core.showMessage(String(localized: "That screenshot is no longer available."), tone: .danger)
    }

    /// The image itself plus its file URL, unmarked, so the copy enters Clipboard History as any would.
    private static func write(_ item: Screenshot, to pasteboard: NSPasteboard = .general) -> Bool {
        guard FileManager.default.fileExists(atPath: item.url.path) else { return false }
        guard item.kind == .image,
            let type = UTType(filenameExtension: item.url.pathExtension),
            let data = try? Data(contentsOf: item.url, options: .mappedIfSafe)
        else {
            PasteboardFiles.write(item.url, to: pasteboard)
            return true
        }
        let imageType = NSPasteboard.PasteboardType(type.identifier)
        pasteboard.clearContents()
        pasteboard.declareTypes([imageType, .fileURL], owner: nil)
        pasteboard.setData(data, forType: imageType)
        pasteboard.setData(item.url.dataRepresentation, forType: .fileURL)
        return true
    }
}
