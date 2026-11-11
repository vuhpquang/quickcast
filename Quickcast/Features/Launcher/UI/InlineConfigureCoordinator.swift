import Foundation

/// Quickcast fork: sets a launcher row's hotkey or alias from its ⌘K menu, as Settings would.
@MainActor
@Observable
final class InlineConfigureCoordinator {
    struct Target {
        let entry: AppEntry
        let field: InlineConfiguration.Field
        let hotKeyAction: HotKeyAction?
        /// The row's place in the launcher's ordering when the editor opened, to find it again.
        let entryIndex: Int?
    }

    private(set) var target: Target?

    @ObservationIgnored private let palette: PaletteState
    @ObservationIgnored private let appIndex: AppIndex
    @ObservationIgnored private let visibility: VisibilityStore
    @ObservationIgnored private let favorites: FavoritesStore
    @ObservationIgnored private let hotKeys: HotKeyManager
    @ObservationIgnored private let aliases: AliasStore

    init(
        palette: PaletteState, appIndex: AppIndex, visibility: VisibilityStore,
        favorites: FavoritesStore, hotKeys: HotKeyManager, aliases: AliasStore
    ) {
        self.palette = palette
        self.appIndex = appIndex
        self.visibility = visibility
        self.favorites = favorites
        self.hotKeys = hotKeys
        self.aliases = aliases
    }

    private var writer: EntryConfigurationWriter {
        EntryConfigurationWriter(hotKeys: hotKeys, aliases: aliases)
    }

    // MARK: - ⌘K rows

    func menuItems(for entry: AppEntry) -> [PopoverMenuItem] {
        let action = entry.configurableHotKeyAction
        let alias = aliases.alias(for: entry.preferenceKey)
        let items = InlineConfiguration.items(
            isPersistent: entry.kind != .meeting && !CommandCatalog.isQueryDriven(entry),
            takesHotkey: action != nil, isBound: action.flatMap(hotKeys.binding(for:)) != nil,
            hasAlias: alias != nil)
        return items.enumerated().map { index, item in
            PopoverMenuItem(
                title: item.title, systemImage: item.systemImage, startsSection: index == 0
            ) { [weak self] in
                self?.perform(item, on: entry)
            }
        }
    }

    private func perform(_ item: InlineConfiguration.Item, on entry: AppEntry) {
        switch item {
        case .setHotkey, .changeHotkey, .setAlias, .changeAlias:
            open(item.field, for: entry)
        case .removeHotkey:
            guard let action = entry.configurableHotKeyAction else { return }
            writer.removeHotkey(for: action)
        case .removeAlias:
            writer.removeAlias(for: entry.preferenceKey)
        }
    }

    // MARK: - The editor screen

    private func open(_ field: InlineConfiguration.Field, for entry: AppEntry) {
        guard palette.mode == .launcher else { return }
        target = Target(
            entry: entry, field: field, hotKeyAction: entry.configurableHotKeyAction,
            entryIndex: launcherIndex(of: entry))
        palette.push(mode: .inlineConfigure)
        if field == .alias { palette.rewriteQuery(aliases.alias(for: entry.preferenceKey) ?? "") }
    }

    func saveAlias() {
        guard palette.mode == .inlineConfigure, let target, target.field == .alias else { return }
        writer.saveAlias(palette.query, for: target.entry.preferenceKey)
        finish()
    }

    func removeAlias() {
        guard palette.mode == .inlineConfigure, let target, target.field == .alias else { return }
        writer.removeAlias(for: target.entry.preferenceKey)
        finish()
    }

    /// The recorder ended — a binding landed, ⌫ cleared it, or Esc or a click cancelled.
    func recordingEnded() {
        guard palette.mode == .inlineConfigure, target?.field == .hotkey else { return }
        finish()
    }

    /// The panel's Escape, ahead of the field: Escape leaves the editor rather than clearing text.
    func handleEscape() -> Bool {
        guard palette.mode == .inlineConfigure, !palette.isComposing else { return false }
        finish()
        return true
    }

    func hasAlias(_ entry: AppEntry) -> Bool { aliases.alias(for: entry.preferenceKey) != nil }

    /// Other listed entries that already answer to `typed`; Alias + Space skips a shared alias.
    func sharingNames(of typed: String) -> [String] {
        guard let target, !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return appIndex.matches(typed.trimmingCharacters(in: .whitespaces), limit: 20)
            .filter {
                $0.preferenceKey != target.entry.preferenceKey
                    && InlineConfiguration.holds(aliases.alias(for: $0.preferenceKey), typed: typed)
            }
            .map(\.name)
    }

    /// Back onto the launcher with the highlight on the same row, which the change may have moved.
    private func finish() {
        let finished = target
        target = nil
        if let action = finished?.hotKeyAction, hotKeys.recordingAction == action {
            hotKeys.recordingAction = nil
        }
        guard palette.pop(preservingSelection: true) else {
            palette.prepare(mode: .launcher)
            return
        }
        guard let finished, let before = finished.entryIndex,
            let after = launcherIndex(of: finished.entry), after != before
        else { return }
        palette.selection = max(palette.selection + after - before, 0)
        palette.preserveSelection()
    }

    private func launcherIndex(of entry: AppEntry) -> Int? {
        appIndex.orderedResults(
            query: palette.query, visibility: visibility, favorites: favorites, hotKeys: hotKeys
        ).entries.firstIndex { $0.id == entry.id }
    }
}

extension AppEntry {
    /// `hotKeyAction` is nil for an extension command, whose shortcut is keyed by entry ID.
    var configurableHotKeyAction: HotKeyAction? {
        kind == .extensionCommand ? .extensionCommand(entryID: id) : hotKeyAction
    }
}

extension InlineConfiguration.Item {
    var title: String {
        switch self {
        case .setHotkey: String(localized: "Set Hotkey…")
        case .changeHotkey: String(localized: "Change Hotkey…")
        case .removeHotkey: String(localized: "Remove Hotkey")
        case .setAlias: String(localized: "Set Alias…")
        case .changeAlias: String(localized: "Change Alias…")
        case .removeAlias: String(localized: "Remove Alias")
        }
    }

    var systemImage: String {
        switch self {
        case .setHotkey, .changeHotkey: "keyboard"
        case .setAlias, .changeAlias: "character.cursor.ibeam"
        case .removeHotkey, .removeAlias: "minus.circle"
        }
    }
}
