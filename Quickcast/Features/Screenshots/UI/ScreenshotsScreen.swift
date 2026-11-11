import SwiftUI

/// The screenshot folder as a day-grouped grid whose ↑/↓ move by visual row, as the emoji grid's do.
struct ScreenshotsScreen: PaletteScreen {
    let coordinator: ScreenshotsCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [Screenshot] { coordinator.results(for: vm.query) }

    private var days: [ScreenshotDay] { ScreenshotGrid.days(rows, calendar: .current) }

    var primaryActionTitle: String { vm.pasteTarget?.pasteTitle ?? String(localized: "Paste") }

    private func item(at selection: Int) -> Screenshot? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasActions(at selection: Int) -> Bool { item(at: selection) != nil }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let item = item(at: selection) else { return nil }
        return ScreenshotActionsMenu.content(item: item, coordinator: coordinator, target: vm.pasteTarget)
    }

    func activate(at selection: Int) {
        guard let item = item(at: selection) else { return }
        coordinator.paste(item)
    }

    /// ⌘↵ opens in the default app; copying has its own ⇧⌘C.
    func secondary(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        coordinator.open(item)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        switch shortcut {
        case .copyFile: coordinator.copy(item)
        case .copyPath: coordinator.copyPath(item)
        case .openInApp: coordinator.open(item)
        case .showInFinder: coordinator.showInFinder(item)
        case .delete, .commandDelete: Task { await coordinator.trash(item) }
        default: return false
        }
        return true
    }

    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        let days = days
        let count = days.reduce(0) { $0 + $1.items.count }
        guard count > 0 else { return selection }
        switch axis {
        case .vertical:
            let geometry = EmojiGridGeometry(
                counts: days.map(\.items.count), columns: coordinator.columns.rawValue)
            return delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        case .horizontal:
            return min(max(selection + delta, 0), count - 1)
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ScreenshotsContent(
                coordinator: coordinator, vm: vm, days: days, selection: selection, scroll: scroll,
                openActions: openActions))
    }
}

/// Owns the screen's lifetime: the folder watch, recognition, zoom chords and a stable selection.
private struct ScreenshotsContent: View {
    let coordinator: ScreenshotsCoordinator
    let vm: PaletteState
    let days: [ScreenshotDay]
    let selection: Int
    let scroll: ScrollIntent
    let openActions: () -> Void

    @Environment(AppSettings.self) private var settings
    @State private var selectedID: String?

    private struct RecognitionKey: Equatable {
        let active: Bool
        let enabled: Bool
        let revision: Int
    }

    private var flat: [Screenshot] { days.flatMap(\.items) }

    var body: some View {
        content
            .onAppear {
                coordinator.setActive(vm.isVisible)
                selectedID = flat.indices.contains(selection) ? flat[selection].id : nil
            }
            .onDisappear { coordinator.setActive(false) }
            .onChange(of: vm.isVisible) { coordinator.setActive(vm.isVisible) }
            .onChange(of: selection) {
                selectedID = flat.indices.contains(selection) ? flat[selection].id : nil
            }
            // A new capture lands at the top; the highlight stays on the capture it was on.
            .onChange(of: coordinator.library.revision) {
                guard let selectedID, let index = flat.firstIndex(where: { $0.id == selectedID }),
                    index != vm.selection
                else { return }
                vm.selection = index
            }
            .onChange(of: vm.emojiGridZoomToken) {
                if let zoom = vm.emojiGridZoom { coordinator.zoom(zoom) }
            }
            .task(
                id: RecognitionKey(
                    active: vm.isVisible, enabled: settings.screenshotTextSearchEnabled,
                    revision: coordinator.library.revision)
            ) {
                guard vm.isVisible, settings.screenshotTextSearchEnabled else { return }
                // Lets a burst of scans settle before a helper is started.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await coordinator.recognizeText()
            }
    }

    @ViewBuilder
    private var content: some View {
        let library = coordinator.library
        switch library.state {
        case .loading where library.items.isEmpty:
            EmptyResults(text: String(localized: "Loading screenshots…"), systemImage: "photo.on.rectangle")
        case .unreadable:
            EmptyResults(
                text: String(localized: "Can’t read \(library.folder.lastPathComponent)"),
                detail: String(
                    localized: """
                        Allow Quickcast to access it in System Settings › Privacy & Security › Files and Folders.
                        """),
                systemImage: "lock")
        default:
            if days.isEmpty {
                EmptyResults(
                    text: library.items.isEmpty
                        ? String(localized: "No screenshots in \(library.folder.lastPathComponent)")
                        : String(localized: "No matching screenshots"),
                    systemImage: "photo.on.rectangle")
            } else {
                ScreenshotGridView(
                    days: days, selection: selection, columns: coordinator.columns, scroll: scroll,
                    onSelect: { vm.selection = $0 },
                    onActivate: {
                        if flat.indices.contains(vm.selection) { coordinator.paste(flat[vm.selection]) }
                    },
                    onActions: { index in
                        vm.selection = index
                        openActions()
                    })
            }
        }
    }
}

@MainActor
enum ScreenshotActionsMenu {
    static func content(
        item: Screenshot, coordinator: ScreenshotsCoordinator, target: PasteTarget?
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: item.title,
            items: [
                PopoverMenuItem(
                    title: target?.pasteTitle ?? String(localized: "Paste"),
                    icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "↵"
                ) { coordinator.paste(item) },
                PopoverMenuItem(
                    title: String(localized: "Open"), systemImage: "arrow.up.forward.app", shortcut: "⌘↵"
                ) { coordinator.open(item) },
                PopoverMenuItem(
                    title: item.kind == .image
                        ? String(localized: "Copy Image") : String(localized: "Copy File"),
                    systemImage: "doc.on.doc", startsSection: true, shortcut: "⇧⌘C"
                ) { coordinator.copy(item) },
                PopoverMenuItem(
                    title: String(localized: "Copy Path"), systemImage: "doc.on.clipboard", shortcut: "⌃⌘C"
                ) { coordinator.copyPath(item) },
                PopoverMenuItem(
                    title: String(localized: "Show in Finder"), systemImage: "folder", shortcut: "⌘F"
                ) { coordinator.showInFinder(item) },
                PopoverMenuItem(
                    title: String(localized: "Actual Size"), systemImage: "magnifyingglass",
                    isEnabled: coordinator.canZoom(.actualSize), startsSection: true, shortcut: "⌘0"
                ) { coordinator.zoom(.actualSize) },
                PopoverMenuItem(
                    title: String(localized: "Zoom In"), systemImage: "plus.magnifyingglass",
                    isEnabled: coordinator.canZoom(.zoomIn), shortcut: "⌘+"
                ) { coordinator.zoom(.zoomIn) },
                PopoverMenuItem(
                    title: String(localized: "Zoom Out"), systemImage: "minus.magnifyingglass",
                    isEnabled: coordinator.canZoom(.zoomOut), shortcut: "⌘-"
                ) { coordinator.zoom(.zoomOut) },
                PopoverMenuItem(
                    title: String(localized: "Move to Trash"), systemImage: "trash", startsSection: true,
                    shortcut: "⌃X", isDestructive: true
                ) { Task { await coordinator.trash(item) } }
            ])
    }
}
