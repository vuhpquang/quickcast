import SwiftUI

struct DictationHistoryScreen: PaletteScreen {
    let coordinator: DictationHistoryCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [DictationHistoryEntry] { coordinator.store.search(vm.query) }

    var primaryActionTitle: String { vm.pasteTarget?.pasteTitle ?? String(localized: "Paste") }

    private func entry(at selection: Int) -> DictationHistoryEntry? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else { return nil }
        return DictationHistoryActionsMenu.content(
            entry: entry, coordinator: coordinator, target: vm.pasteTarget)
    }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        coordinator.paste(entry)
    }

    /// ⌘↵ copies instead of pasting.
    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        coordinator.copy(entry)
        return true
    }

    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        coordinator.pasteKeepingWindowOpen(entry)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete, .delete:
            if let entry = entry(at: selection) { coordinator.delete(entry) }
            return true
        case .deleteAll:
            Task { await coordinator.clearAll() }
            return true
        default: return false
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(
                text: coordinator.store.entries.isEmpty
                    ? String(localized: "No dictations yet")
                    : String(localized: "No matching dictations"))
        } else {
            let selected = entry(at: selection)
            DictationHistoryBrowser(
                results: rows, selected: selected, scroll: scroll,
                onSelect: { entry in vm.selection = rows.firstIndex(of: entry) ?? 0 },
                onActivate: { activate(at: vm.selection) },
                onActions: { entry in
                    if let index = rows.firstIndex(of: entry) { vm.selection = index }
                    openActions()
                })
        }
    }
}

@MainActor
enum DictationHistoryActionsMenu {
    static func content(
        entry: DictationHistoryEntry, coordinator: DictationHistoryCoordinator, target: PasteTarget?
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: String(entry.preview.prefix(40)),
            items: [
                PopoverMenuItem(
                    title: target?.pasteTitle ?? String(localized: "Paste"),
                    icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "↵"
                ) {
                    coordinator.paste(entry)
                },
                PopoverMenuItem(
                    title: String(localized: "Copy to Clipboard"), systemImage: "doc.on.doc",
                    shortcut: "⌘↵"
                ) {
                    coordinator.copy(entry)
                },
                PopoverMenuItem(
                    title: String(localized: "Paste and Keep Window Open"),
                    icon: .paste(target, fallback: "macwindow"), shortcut: "⌥↵"
                ) {
                    coordinator.pasteKeepingWindowOpen(entry)
                },
                PopoverMenuItem(
                    title: String(localized: "Delete Entry"), systemImage: "trash", startsSection: true,
                    shortcut: "⌃X", isDestructive: true
                ) {
                    coordinator.delete(entry)
                },
                PopoverMenuItem(
                    title: String(localized: "Delete All Entries"), systemImage: "trash",
                    shortcut: "⌃⇧X", isDestructive: true
                ) {
                    Task { await coordinator.clearAll() }
                }
            ])
    }
}
