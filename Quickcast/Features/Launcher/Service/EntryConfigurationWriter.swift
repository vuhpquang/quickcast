import Foundation

/// Quickcast fork: the launcher's inline writes, through the same calls Settings' fields make.
@MainActor
struct EntryConfigurationWriter {
    let hotKeys: HotKeyManager
    let aliases: AliasStore

    /// Recording goes through `HotKeyManager.recordingAction`, so only the removal is written here.
    func removeHotkey(for action: HotKeyAction) {
        if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
        hotKeys.setBinding(nil, for: action)
    }

    /// `AliasField`'s commit: stored as typed, and a blank draft removes the alias.
    func saveAlias(_ draft: String, for key: String) {
        aliases.setAlias(draft, for: key)
    }

    func removeAlias(for key: String) {
        aliases.setAlias("", for: key)
    }
}
