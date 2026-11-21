import AppKit
import Carbon.HIToolbox

/// The launcher's inline hotkey and alias rows: what each row offers, and that a change writes
/// the same keys Settings writes and meets the same conflict rule.
@main
@MainActor
struct InlineConfigureTest {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        offeredItems()
        aliasMatching()
        writes()
        print("\(checks) inline configure checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    static func offeredItems() {
        typealias Config = InlineConfiguration
        check(
            "a fresh row offers both setters",
            Config.items(isPersistent: true, takesHotkey: true, isBound: false, hasAlias: false)
                == [.setHotkey, .setAlias])
        check(
            "a configured row offers change and remove for both",
            Config.items(isPersistent: true, takesHotkey: true, isBound: true, hasAlias: true)
                == [.changeHotkey, .removeHotkey, .changeAlias, .removeAlias])
        check(
            "a row no hotkey can bind offers only the alias",
            Config.items(isPersistent: true, takesHotkey: false, isBound: false, hasAlias: true)
                == [.changeAlias, .removeAlias])
        check(
            "a query-driven or ephemeral row offers nothing",
            Config.items(isPersistent: false, takesHotkey: true, isBound: true, hasAlias: true).isEmpty)
        check(
            "each item names its field",
            Config.Item.removeHotkey.field == .hotkey && Config.Item.setAlias.field == .alias)
    }

    static func aliasMatching() {
        typealias Config = InlineConfiguration
        check("an alias matches case-insensitively", Config.holds("Em", typed: "em"))
        check("surrounding spaces don't count", Config.holds(" em ", typed: "em "))
        check("a different alias doesn't match", !Config.holds("emoji", typed: "em"))
        check("no alias matches nothing", !Config.holds(nil, typed: "em"))
        check("a blank draft matches nothing", !Config.holds("  ", typed: " "))
    }

    static func writes() {
        let domain = "quickcast.inline-configure-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let hotKeys = HotKeyManager(defaults: defaults)
        let aliases = AliasStore(defaults: defaults)
        let writer = EntryConfigurationWriter(hotKeys: hotKeys, aliases: aliases)

        let safari = HotKeyAction.app(bundleID: "com.apple.Safari")
        let notes = HotKeyAction.app(bundleID: "com.apple.Notes")
        let combo = HotKeyBinding.combo(
            KeyShortcut(carbonKeyCode: kVK_ANSI_S, carbonModifiers: optionKey | cmdKey))
        // What the recorder's commit runs once the capture accepts a binding.
        hotKeys.setBinding(combo, for: safari)
        check("a binding persists under the Settings key", defaults.string(forKey: "hotkey.app.com.apple.Safari") != nil)
        check(
            "a bound app joins the bound-ID index",
            defaults.stringArray(forKey: "boundAppBundleIDs")?.contains("com.apple.Safari") == true)
        check(
            "the same chord on another row is refused, naming its owner",
            hotKeys.conflictOwner(of: combo, excluding: notes) == "com.apple.Safari")
        check("re-recording the row's own chord is no conflict", hotKeys.conflictOwner(of: combo, excluding: safari) == nil)

        hotKeys.recordingAction = safari
        writer.removeHotkey(for: safari)
        check("removing ends a recording of that row", hotKeys.recordingAction == nil)
        check("removing clears the binding", hotKeys.binding(for: safari) == nil)
        check("removing deletes the Settings key", defaults.string(forKey: "hotkey.app.com.apple.Safari") == nil)
        check(
            "removing leaves the bound-ID index",
            defaults.stringArray(forKey: "boundAppBundleIDs")?.contains("com.apple.Safari") != true)
        check("a removed chord is free again", hotKeys.conflictOwner(of: combo, excluding: notes) == nil)

        let ext = HotKeyAction.extensionCommand(entryID: "extension:emoji/search")
        hotKeys.setBinding(combo, for: ext)
        writer.removeHotkey(for: ext)
        check(
            "an extension command's binding clears from its own index",
            defaults.string(forKey: "hotkey.extensionCommand.extension:emoji/search") == nil
                && defaults.stringArray(forKey: "boundExtensionCommandEntryIDs")?.isEmpty != false)

        let revision = aliases.revision
        writer.saveAlias("sf", for: "com.apple.Safari")
        let stored = defaults.dictionary(forKey: "launcherAliases") as? [String: String]
        check("an alias persists in launcherAliases by preference key", stored?["com.apple.Safari"] == "sf")
        check("saving bumps the revision the launcher keys on", aliases.revision != revision)
        writer.saveAlias("s f", for: "com.apple.Safari")
        check("an alias is stored as typed, as AliasField stores it", aliases.alias(for: "com.apple.Safari") == "s f")
        writer.saveAlias("   ", for: "com.apple.Safari")
        check("a blank alias removes it", aliases.alias(for: "com.apple.Safari") == nil)
        writer.saveAlias("sf", for: "com.apple.Safari")
        writer.removeAlias(for: "com.apple.Safari")
        let after = defaults.dictionary(forKey: "launcherAliases") as? [String: String]
        check("Remove Alias drops the key", after?["com.apple.Safari"] == nil)
    }
}
