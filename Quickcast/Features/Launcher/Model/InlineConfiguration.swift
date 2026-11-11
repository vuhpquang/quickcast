import Foundation

/// Quickcast fork: the hotkey and alias rows a launcher entry's ⌘K menu offers.
enum InlineConfiguration {
    enum Field: Sendable, Equatable {
        case hotkey
        case alias
    }

    enum Item: Sendable, Equatable {
        case setHotkey
        case changeHotkey
        case removeHotkey
        case setAlias
        case changeAlias
        case removeAlias

        var field: Field {
            switch self {
            case .setHotkey, .changeHotkey, .removeHotkey: .hotkey
            case .setAlias, .changeAlias, .removeAlias: .alias
            }
        }
    }

    /// A query-driven or ephemeral row has no stable key, so nothing could be stored against it.
    static func items(isPersistent: Bool, takesHotkey: Bool, isBound: Bool, hasAlias: Bool) -> [Item] {
        guard isPersistent else { return [] }
        var items: [Item] = []
        if takesHotkey { items += isBound ? [.changeHotkey, .removeHotkey] : [.setHotkey] }
        items += hasAlias ? [.changeAlias, .removeAlias] : [.setAlias]
        return items
    }

    /// The comparison Alias + Space makes, so a warning names exactly the holders it would skip.
    static func holds(_ stored: String?, typed: String) -> Bool {
        let typed = folded(typed)
        guard let stored, !typed.isEmpty else { return false }
        return folded(stored) == typed
    }

    private static func folded(_ alias: String) -> String {
        alias.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
