import Foundation

/// Quickcast fork: "em " opens the entry aliased `em`; "em heart" opens it with "heart" typed.
extension LauncherCoordinator {
    /// A shared or stale alias stays ordinary search text, so only a single listed holder fires.
    func openAliasBeforeSpace(in query: String) -> Bool {
        guard let space = query.firstIndex(of: " "), space > query.startIndex else { return false }
        let typedAlias = String(query[..<space])
        let rest = String(query[query.index(after: space)...])
        guard let entry = entry(forExactAlias: typedAlias) else { return false }
        // The back step restores this query; with its space it would re-open the entry forever.
        core.palette.query = typedAlias

        if entry.kind == .command, let id = CommandCatalog.command(for: entry),
            !rest.trimmingCharacters(in: .whitespaces).isEmpty, open(id, seeding: rest)
        {
            return true
        }
        launch(entry)
        return true
    }

    private func entry(forExactAlias typed: String) -> AppEntry? {
        let folded = typed.lowercased()
        let aliases = core.aliases
        let hits = core.appIndex.matches(typed, limit: 20).filter {
            aliases.alias(for: $0.preferenceKey)?
                .trimmingCharacters(in: .whitespaces).lowercased() == folded
        }
        return hits.count == 1 ? hits[0] : nil
    }

    /// The screens that take text open on it already typed, as their deeplinks do.
    private func open(_ id: CommandID, seeding text: String) -> Bool {
        let palette = core.paletteCoordinator
        switch id {
        case .clipboardHistory: palette.togglePalette(mode: .clipboard, seeding: text)
        case .searchEmoji: palette.togglePalette(mode: .emoji, seeding: text)
        case .calculatorHistory: palette.togglePalette(mode: .calculatorHistory, seeding: text)
        case .dictationHistory: core.dictationHistoryCoordinator.show(query: text)
        case .searchQuicklinks: palette.togglePalette(mode: .quicklinks, seeding: text)
        case .searchFiles: core.fileSearchCoordinator.show(query: text)
        case .define: core.dictionaryCoordinator.show(term: text)
        case .quickAI: core.quickAICoordinator.show(draft: text)
        case .searchSnippets: core.snippetCoordinator.showSnippets(query: text)
        case .searchCustomCommands: core.customCommandCoordinator.showCustomCommands(query: text)
        case .searchMenuItems: core.menuSearchCoordinator.show(query: text)
        case .switchWindows: core.windowSwitchCoordinator.show(query: text)
        default: return false
        }
        return true
    }
}
