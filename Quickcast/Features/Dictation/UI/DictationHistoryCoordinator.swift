import AppKit

/// Dictation History's action surface: what finished dictation records, and what its screen does.
@MainActor
final class DictationHistoryCoordinator {
    let store: DictationHistoryStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let palette: PaletteState
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(
        store: DictationHistoryStore, settings: AppSettings, appIndex: AppIndex, palette: PaletteState,
        windowController: PaletteWindowController, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.palette = palette
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// The command follows the Dictation switch; the kept history stays until it is cleared.
    func applyEnabled() {
        appIndex.setCommandsVisible([.dictationHistory], settings.dictationEnabled)
        guard !settings.dictationEnabled else { return }
        if palette.mode == .dictationHistory { palette.prepare(mode: .launcher) }
    }

    func applyLimit() {
        store.setLimit(settings.dictationHistoryLimit.rawValue)
    }

    func show(query: String = "") {
        guard settings.dictationEnabled else { return }
        paletteCoordinator.togglePalette(mode: .dictationHistory, seeding: query.isEmpty ? nil : query)
    }

    func record(_ text: String, model: DictationModel, target: InjectionTarget?) {
        let app: NSRunningApplication? =
            switch target {
            case .external(let app): app
            case .ownEditor: .current
            case nil: nil
            }
        store.record(
            text, model: model.rawValue, modelTitle: model.title, appName: app?.localizedName,
            bundleID: app?.bundleIdentifier, at: Date())
    }

    /// The clipboard's string paste: marked, so the text doesn't land in clipboard history again.
    func paste(_ entry: DictationHistoryEntry) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteString(entry.text, previousApp: previous)
    }

    func pasteKeepingWindowOpen(_ entry: DictationHistoryEntry) {
        windowController.pasteStringKeepingWindowOpen(entry.text)
    }

    func copy(_ entry: DictationHistoryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.text)
    }

    func delete(_ entry: DictationHistoryEntry) {
        store.remove(id: entry.id)
    }

    func clearAll() async {
        guard !store.entries.isEmpty else { return }
        guard
            await core.confirm(
                title: String(localized: "Clear dictation history?"),
                message: String(
                    localized: "Every saved dictation is deleted from this Mac. This can't be undone."),
                symbol: PaletteMode.dictationHistory.systemImage,
                confirmTitle: String(localized: "Clear History"))
        else { return }
        store.clearAll()
    }
}
