import SwiftUI

/// Quickcast fork: one launcher row's hotkey or alias, pushed from its ⌘K menu.
struct InlineConfigureScreen: PaletteScreen {
    let coordinator: InlineConfigureCoordinator
    let query: String

    private var target: InlineConfigureCoordinator.Target? { coordinator.target }
    private var editsAlias: Bool { target?.field == .alias }

    var rows: [AppEntry] { target.map { [$0.entry] } ?? [] }
    let primaryActionTitle = String(localized: "Save Alias")
    /// The recorder takes every key itself; only the alias is typed into the search field.
    var hidesSearchField: Bool { !editsAlias }
    let actsWithoutRows = true

    func hasPrimaryAction(at selection: Int) -> Bool { editsAlias }
    func hasActions(at selection: Int) -> Bool { editsAlias }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard editsAlias, let target else { return nil }
        var items = [
            PopoverMenuItem(
                title: String(localized: "Save Alias"), systemImage: "checkmark", shortcut: "↵"
            ) { coordinator.saveAlias() }
        ]
        if coordinator.hasAlias(target.entry) {
            items.append(
                PopoverMenuItem(title: String(localized: "Remove Alias"), systemImage: "minus.circle") {
                    coordinator.removeAlias()
                })
        }
        return PopoverMenuContent(header: target.entry.name, items: items)
    }

    func activate(at selection: Int) { coordinator.saveAlias() }
    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard let target else { return AnyView(Color.clear) }
        return AnyView(
            InlineConfigureView(
                target: target, sharingNames: editsAlias ? coordinator.sharingNames(of: query) : [],
                onRecordingEnded: coordinator.recordingEnded))
    }
}

private struct InlineConfigureView: View {
    let target: InlineConfigureCoordinator.Target
    let sharingNames: [String]
    let onRecordingEnded: () -> Void

    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.spacing.lg) {
            AppIconView(app: target.entry, pointSize: metrics.size.dialogIcon)
                .frame(width: metrics.size.dialogIcon, height: metrics.size.dialogIcon)
            Text(target.entry.name)
                .font(metrics.typography.panelTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            switch target.field {
            case .hotkey: hotkeyEditor
            case .alias: aliasHints
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, metrics.spacing.xxxl * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shortcutRecorderPopoverHost()
    }

    @ViewBuilder
    private var hotkeyEditor: some View {
        if let action = target.hotKeyAction {
            ShortcutRecorder(action: action)
                // After the ⌘K menu hands key focus back, whose resign would end the recording.
                .task {
                    await Task.yield()
                    hotKeys.recordingAction = action
                }
                .onChange(of: hotKeys.recordingAction) { old, new in
                    if old == action, new != action { onRecordingEnded() }
                }
            hint(String(localized: "Press the new shortcut. Delete removes it, Escape cancels."))
        }
    }

    @ViewBuilder
    private var aliasHints: some View {
        hint(String(localized: "Type the alias, then press Return. Leave it empty to remove it."))
        if !sharingNames.isEmpty {
            Text(
                String(
                    localized:
                        "Also the alias of \(sharingNames.formatted(.list(type: .and))). A shared alias doesn’t open with Space."
                )
            )
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(.orange)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
