#!/bin/bash
# The test suite: each harness compiles the shipped sources it guards. See docs/testing.md.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/quickcast-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    TIMEFORMAT=%1R
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS ships no `timeout`, so the worker polls; a wedged harness must fail, not stall.
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((QUICKCAST_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$QUICKCAST_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${QUICKCAST_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

failed=()
ran=0
only="${1:-}"

# `--index` feeds harness compile commands to .compile, as xcodebuild never compiles Tests/.
emit_db=0
DB="${TMPDIR:-/tmp}/quickcast-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

QUEUE="$BIN/queue"
# `--index` queues nothing, so it must never reset the state of a suite already running.
if [ "$emit_db" -eq 0 ]; then
    # Queue, logs and verdicts are shared by path, so a second suite in this $TMPDIR waits its turn.
    if [ -z "${QUICKCAST_SUITE_LOCKED:-}" ]; then
        export QUICKCAST_SUITE_LOCKED=1
        lockf -k -t 0 "$BIN/suite.lock" true 2>/dev/null || echo "Waiting for the suite already running…" >&2
        exec lockf -k "$BIN/suite.lock" "$SELF" "$@"
    fi
    : > "$QUEUE"
    rm -f "$BIN"/*.failed "$BIN"/*.running
fi

# `slow` dispatches in the first wave; `index` only claims editor flags for a hand-run harness.
run() {
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths: sourcekit-lsp ignores `directory` for relative arguments and indexes nothing.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Only `Tests/` files: `.compile` is last-wins, so a shipped source keeps the app's command.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Quickcast/Features/Launcher/Model
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift
FS=Quickcast/Features/FileSearch
FILE_INDEX="$FS/Service/FileIndex.swift $FS/Service/FileIndexSnapshot.swift $FS/Service/FileIndexCrawler.swift"
run file-search-test       $FS/Model/*.swift
run file-index-test        $FS/Model/*.swift $FILE_INDEX
run file-search-session-test $FS/Model/*.swift $FS/Service/FileSearchSession.swift $FILE_INDEX
run menu-search-test       $L/SearchRelevance.swift \
                           Quickcast/Features/MenuSearch/Model/*.swift \
                           Quickcast/Features/MenuSearch/Service/*.swift
run window-switch-test     $L/SearchRelevance.swift \
                           Quickcast/Features/WindowSwitcher/Model/*.swift
run index file-search-performance $FS/Model/*.swift $FILE_INDEX
run ranking-test           $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run app-name-test          Quickcast/Platform/AppDisplayName.swift \
                           Quickcast/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run favorites-test         $L/FavoriteSlots.swift
run app-installation-test  $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift $L/SearchScopes.swift \
                           Quickcast/Features/Launcher/Service/AppIndex.swift \
                           Quickcast/Features/Launcher/Service/AppLauncher.swift \
                           Quickcast/Features/Launcher/Service/RunningAppsMonitor.swift \
                           Quickcast/Features/Launcher/Service/FavoritesStore.swift \
                           $FS/Model/FileSearchResult.swift \
                           Quickcast/Features/Launcher/Service/AliasStore.swift \
                           Quickcast/Features/Launcher/Service/VisibilityStore.swift \
                           Quickcast/Features/Launcher/Service/BundleNameCache.swift \
                           Quickcast/Platform/AppDisplayName.swift Quickcast/Platform/BundleLocalization.swift \
                           Quickcast/Platform/SystemLanguages.swift \
                           Quickcast/Platform/Images/FileIconStamp.swift Quickcast/Platform/Memo.swift \
                           Quickcast/Platform/Signposts.swift Quickcast/Platform/NotificationToken.swift \
                           Quickcast/Platform/LocalizedResource.swift
run launcher-file-test     $L/LauncherFileFormat.swift \
                           Quickcast/Features/Settings/Model/SettingsFileJSON.swift
run launcher-settings-file-test \
                           $L/LauncherFileFormat.swift $L/CommandID.swift $L/CommandCatalog.swift \
                           Quickcast/Features/Launcher/Service/LauncherSettingsFile.swift \
                           Quickcast/Features/Launcher/Service/AliasStore.swift \
                           Quickcast/Features/Launcher/Service/VisibilityStore.swift \
                           Quickcast/Features/Settings/SettingsTab.swift \
                           Quickcast/Features/Settings/Model/*.swift \
                           Quickcast/Features/HotKeys/Service/HotKeySettingsFile.swift \
                           Quickcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Quickcast/Features/HotKeys/Model/HotKeySpelling.swift \
                           Quickcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Quickcast/Features/HotKeys/Model/ModifierKey.swift \
                           Quickcast/Features/HotKeys/Model/HyperKey.swift \
                           Quickcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Quickcast/Platform/ASCIIKeyboardLayout.swift \
                           Quickcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/SystemActions/Model/SystemAction.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/Snippets/Model/Snippet.swift \
                           Quickcast/Platform/LocalizedResource.swift
run apple-shortcut-test    Quickcast/Features/AppleShortcuts/Model/*.swift
run calc-test              Quickcast/Features/Calculator/Model/*.swift
run index calc-performance Quickcast/Features/Calculator/Model/*.swift
run calendar-test          Quickcast/Features/Calendar/Model/*.swift \
                           Quickcast/Features/Calendar/UI/EventEditorSession.swift
run clipboard-test         Quickcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Quickcast/Platform/Images/ImageDerivative.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Quickcast/Features/Clipboard/Model/ColorValue.swift \
                           Quickcast/Features/Clipboard/Model/ColorFormat.swift \
                           Quickcast/Features/Clipboard/Model/ColorSpaces.swift
run clipboard-coordinator-test Quickcast/Features/Clipboard/UI/ClipboardCoordinator.swift \
                           Quickcast/Features/Clipboard/Model/*.swift \
                           Quickcast/Platform/Images/ImageDerivative.swift \
                           Quickcast/Palette/PaletteState.swift Quickcast/Palette/PaletteMode.swift \
                           Quickcast/Palette/HoverArming.swift \
                           Quickcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Quickcast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/CustomCommands/Model/CustomCommand.swift
run clipboard-thumbnail-test Quickcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Quickcast/Platform/Images/ImageDerivative.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Quickcast/Features/Clipboard/Model/ColorValue.swift \
                           Quickcast/Features/Clipboard/Model/ColorFormat.swift \
                           Quickcast/Features/Clipboard/Model/ColorSpaces.swift \
                           Quickcast/Platform/ProcessExit.swift \
                           Quickcast/Platform/Images/ImageThumbnail.swift \
                           Quickcast/Platform/Images/ThumbnailCache.swift
# `Q` is the URL detector a drag payload builds its link with, rather than a second one.
Q=Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift
run clipboard-search-test  Quickcast/Features/Clipboard/Model/*.swift Quickcast/Platform/Images/ImageDerivative.swift $Q
run paste-sequence-test    Quickcast/Features/Clipboard/Model/*.swift Quickcast/Platform/Images/ImageDerivative.swift $Q
run clipboard-text-test    Quickcast/Features/Clipboard/Model/*.swift Quickcast/Platform/Images/ImageDerivative.swift $Q \
                           Quickcast/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           Quickcast/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           Quickcast/Features/Clipboard/Service/ClipboardTextWorker.swift \
                           Quickcast/Platform/ProcessExit.swift
run pasteboard-test        Quickcast/Platform/PasteboardFiles.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Quickcast/Platform/Images/ImageDerivative.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Quickcast/Features/Clipboard/Model/ColorValue.swift \
                           Quickcast/Features/Clipboard/Model/ColorFormat.swift \
                           Quickcast/Features/Clipboard/Model/ColorSpaces.swift \
                           Quickcast/Features/Clipboard/Service/ClipboardManager.swift \
                           Quickcast/Features/Clipboard/Service/Paster.swift
run index clipboard-file-performance \
                           Quickcast/Platform/PasteboardFiles.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Quickcast/Platform/Images/ImageDerivative.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Quickcast/Features/Clipboard/Model/ColorValue.swift \
                           Quickcast/Features/Clipboard/Model/ColorFormat.swift \
                           Quickcast/Features/Clipboard/Model/ColorSpaces.swift \
                           Quickcast/Features/Clipboard/Service/ClipboardManager.swift
run index clipboard-thumbnail-performance \
                           Quickcast/Platform/ProcessExit.swift \
                           Quickcast/Platform/Images/ImageThumbnail.swift \
                           Quickcast/Platform/Images/ImageDerivative.swift \
                           Quickcast/Platform/Images/ThumbnailCache.swift
run emoji-test             Quickcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Quickcast/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Quickcast/Features/Emoji/Model/EmojiData.generated.swift
run emoji-search-test      Quickcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Quickcast/Features/Emoji/Model/EmojiData.generated.swift \
                           Quickcast/Features/Emoji/Service/EmojiIndex.swift \
                           Quickcast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Quickcast/Features/Emoji/Service/PinnedEmojiStore.swift \
                           Quickcast/Features/Launcher/Model/SearchRelevance.swift \
                           Quickcast/Platform/AppPaths.swift Quickcast/Platform/Memo.swift
run index emoji-search-performance \
                           Quickcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Quickcast/Features/Emoji/Model/EmojiData.generated.swift \
                           Quickcast/Features/Emoji/Service/EmojiIndex.swift \
                           Quickcast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Quickcast/Features/Launcher/Model/SearchRelevance.swift \
                           Quickcast/Platform/AppPaths.swift Quickcast/Platform/Memo.swift
run palette-selection-test Quickcast/Features/PaletteRowIndex.swift \
                           Quickcast/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        Quickcast/Platform/Appearance.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           Quickcast/Features/Settings/AppAppearance.swift
run language-test          Quickcast/Features/Settings/AppLanguage.swift
run localized-resource-test Quickcast/Platform/LocalizedResource.swift
run relaunch-test          Quickcast/App/AppDelegate.swift Quickcast/Platform/RelaunchRunner.swift
run interface-size-test    Quickcast/Platform/Appearance.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           Quickcast/Features/Settings/InterfaceSize.swift \
                           Quickcast/Features/Extensions/Model/ExtensionFormMetrics.swift
run palette-placement-test Quickcast/Platform/Appearance.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           Quickcast/Features/Settings/InterfaceSize.swift \
                           Quickcast/Palette/PalettePlacement.swift
run palette-menu-click-test Quickcast/Platform/Appearance.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/Platform/WindowLevel.swift \
                           Quickcast/Platform/NotificationToken.swift \
                           Quickcast/DesignSystem/Interaction/KeyboardFocus.swift \
                           Quickcast/DesignSystem/Interaction/Motion.swift \
                           Quickcast/DesignSystem/Interaction/AnimatedPanel.swift \
                           Quickcast/Palette/PalettePanel.swift
run form-input-test        Quickcast/Platform/Appearance.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           Quickcast/DesignSystem/FormTextInput.swift \
                           Quickcast/DesignSystem/FormTextArea.swift
run scroll-reveal-test     Quickcast/DesignSystem/Scrolling/SelectionReveal.swift
run redaction-test         Quickcast/DesignSystem/RedactedPlaceholder.swift
run keyboard-focus-test    Quickcast/DesignSystem/Interaction/KeyboardFocus.swift
run command-escape-tap-test Quickcast/Palette/CommandEscapeTap.swift
run palette-escape-test    Quickcast/Palette/PaletteMode.swift \
                           Quickcast/Palette/PaletteEscapeAction.swift \
                           Quickcast/Palette/CommandEscapeTap.swift \
                           Quickcast/Features/Settings/EscapeKeyBehavior.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/CustomCommands/Model/CustomCommand.swift
run palette-navigation-test Quickcast/Palette/PaletteState.swift \
                           Quickcast/Palette/PaletteMode.swift \
                           Quickcast/Palette/HoverArming.swift \
                           Quickcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Quickcast/Platform/Images/ImageDerivative.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Quickcast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Quickcast/Features/Clipboard/Model/ColorValue.swift \
                           Quickcast/Features/Clipboard/Model/ColorFormat.swift \
                           Quickcast/Features/Clipboard/Model/ColorSpaces.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/CustomCommands/Model/CustomCommand.swift
run palette-filter-test    Quickcast/Palette/PaletteMode.swift \
                           Quickcast/Palette/PaletteFilterAction.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/CustomCommands/Model/CustomCommand.swift
run action-menu-search-test Quickcast/Palette/ActionMenuSearchQuery.swift \
                            Quickcast/Features/Launcher/Model/SearchRelevance.swift
run palette-shortcut-test  Quickcast/Palette/PaletteShortcut.swift
run ascii-layout-test      Quickcast/Platform/ASCIIKeyboardLayout.swift
run palette-tab-test       Quickcast/Palette/PaletteMode.swift \
                           Quickcast/Palette/PaletteTabAction.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/CustomCommands/Model/CustomCommand.swift
run compact-bar-test       Quickcast/Features/Launcher/Model/CompactBarSelection.swift \
                           Quickcast/Features/Settings/AppSettingsKey.swift \
                           Quickcast/Features/Settings/Model/*.swift \
                           Quickcast/Features/Launcher/Model/CommandID.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Quickcast/Features/QuickActions/Model/QuickAction.swift \
                           Quickcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Quickcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/SystemActions/Model/SystemAction.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/Snippets/Model/Snippet.swift \
                           Quickcast/Platform/LocalizedResource.swift
run fallback-test          Quickcast/Features/Launcher/Model/Fallback.swift \
                           Quickcast/Features/Launcher/Model/CommandID.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Quickcast/Features/QuickActions/Model/QuickAction.swift \
                           Quickcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Quickcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/SystemActions/Model/SystemAction.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/Snippets/Model/Snippet.swift \
                           Quickcast/Platform/LocalizedResource.swift
run dictionary-test        Quickcast/Features/Dictionary/Model/DictionaryEntry.swift \
                           Quickcast/Features/Dictionary/Model/DictionaryMarkup.swift
run dictation-test         Quickcast/Features/Dictation/Model/DictationModel.swift Quickcast/Features/Dictation/Model/DictationIdleRelease.swift Quickcast/Features/Dictation/Model/DictationLanguage.swift Quickcast/Features/Dictation/Model/DictationTextFormatter.swift
run dictation-cue-test     Quickcast/Features/Dictation/Service/DictationCueRunner.swift
run dictation-history-test Quickcast/Features/Dictation/Model/DictationHistoryEntry.swift \
                           Quickcast/Features/Dictation/Model/DictationHistoryLimit.swift \
                           Quickcast/Features/Dictation/Model/DictationHistoryStore.swift \
                           Quickcast/Platform/Memo.swift
run dictation-field-test   Quickcast/Features/Dictation/Model/DictationModel.swift \
                           Quickcast/Features/Dictation/Model/DictationAudioChunks.swift \
                           Quickcast/Features/Dictation/Model/DictationMode.swift \
                           Quickcast/Features/Dictation/Model/DictationDestination.swift \
                           Quickcast/Features/Dictation/Model/DictationTextFormatter.swift \
                           Quickcast/Features/Dictation/Service/DictationCoordinator.swift \
                           Quickcast/Features/Dictation/Service/DictationInsertionContext.swift \
                           Quickcast/Features/AI/UI/ChatComposerTextView.swift \
                           Quickcast/Features/TextInjection/Service/*.swift \
                           Quickcast/Features/Snippets/Model/*.swift \
                           Quickcast/Platform/AccessibilityText.swift \
                           Quickcast/Platform/PasteboardFiles.swift \
                           Quickcast/Platform/Appearance.swift Quickcast/DesignSystem/Theme.swift
run dictation-volume-test  Quickcast/Features/Dictation/Model/DictationVolumeSnapshot.swift \
                           Quickcast/Features/Dictation/Service/DictationAudioDucker.swift \
                           Quickcast/Platform/AppPaths.swift
run index -O dictation-performance Quickcast/Platform/ProcessExit.swift \
                           Quickcast/Features/Dictation/Model/DictationModel.swift \
                           Quickcast/Features/Dictation/Service/DictationWire.swift
run dictation-inference-test Quickcast/Features/Dictation/Model/DictationAudioChunks.swift \
    Quickcast/Features/Dictation/Service/DictationSpectrum.swift \
    Quickcast/Features/Dictation/Helper/DictationTensor.swift Quickcast/Features/Dictation/Helper/DictationTokenizer.swift \
    Quickcast/Features/Dictation/Helper/DictationMel.swift
run dictation-worker-test  Quickcast/Features/Dictation/Model/DictationModel.swift \
                           Quickcast/Features/Dictation/Model/DictationIdleRelease.swift \
                           Quickcast/Features/Dictation/Service/DictationWire.swift \
                           Quickcast/Features/Dictation/Service/DictationWorker.swift \
                           Quickcast/Features/Dictation/Service/DictationModelStore.swift \
                           Quickcast/Features/Dictation/Service/DictationModelDownloader.swift \
                           Quickcast/Platform/ProcessExit.swift Quickcast/Platform/AppPaths.swift
run hotkey-test            Quickcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Quickcast/Features/HotKeys/Model/ModifierKey.swift \
                           Quickcast/Features/HotKeys/Model/ModifierKeyDetector.swift \
                           Quickcast/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Quickcast/Features/HotKeys/Model/HotKeySpelling.swift \
                           Quickcast/Features/HotKeys/Model/HyperKey.swift \
                           Quickcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Quickcast/Platform/ASCIIKeyboardLayout.swift \
                           Quickcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Quickcast/Features/QuickActions/Model/QuickAction.swift \
                           Quickcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Quickcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Quickcast/Features/Launcher/Model/CommandID.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/SystemActions/Model/SystemAction.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/Snippets/Model/Snippet.swift \
                           Quickcast/Platform/LocalizedResource.swift
run callout-test          Quickcast/Platform/Appearance.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           Quickcast/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Quickcast/Platform/Appearance.swift \
                           Quickcast/Platform/Images/IconCache.swift
run entry-icon-test        Quickcast/Platform/Appearance.swift \
                           Quickcast/Platform/Images/IconCache.swift \
                           Quickcast/Platform/Images/FileIconStamp.swift
run ext-icon-test          Quickcast/Platform/Appearance.swift \
                           Quickcast/Platform/AppDisplayName.swift \
                           Quickcast/Platform/Images/IconCache.swift \
                           Quickcast/Platform/Compression/Zlib.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           Quickcast/Features/Extensions/Model/ExtensionBootConfig.swift \
                           Quickcast/Features/Extensions/Model/ExtensionLaunchType.swift \
                           Quickcast/Features/Extensions/Model/ExtensionManifest.swift \
                           Quickcast/Features/Extensions/Model/ExtensionRefreshPolicy.swift \
                           Quickcast/Features/Extensions/Model/ExtensionRefreshState.swift \
                           Quickcast/Features/Extensions/Model/RenderNode.swift \
                           Quickcast/Features/Extensions/Service/ExtensionCatalog.swift \
                           Quickcast/Features/Extensions/Service/ExtensionFetcher.swift \
                           Quickcast/Platform/ProcessExit.swift \
                           Quickcast/Features/Extensions/Service/ExtensionNodeShims.swift \
                           Quickcast/Features/Extensions/Service/ExtensionRuntime.swift \
                           Quickcast/Features/Extensions/Service/ExtensionIconCache.swift \
                           Quickcast/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           Quickcast/Features/Extensions/UI/ExtensionImage.swift \
                           Quickcast/Features/Clipboard/Model/ColorValue.swift \
                           Quickcast/Features/Clipboard/Model/ColorSpaces.swift
run system-action-test     Quickcast/Features/SystemActions/Model/SystemAction.swift \
                           Quickcast/Platform/LocalizedResource.swift
run microphone-mute-test   Quickcast/Features/SystemActions/Service/SystemActionFailure.swift \
                           Quickcast/Features/SystemActions/Service/SystemActionRunner+Microphone.swift
run volume-test            Quickcast/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Quickcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Quickcast/Features/WindowManagement/Model/WindowActionMemory.swift \
                           Quickcast/Platform/LocalizedResource.swift
run window-preset-test     Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/WindowManagement/Model/WindowShortcutPreset.swift \
                           Quickcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Quickcast/Features/HotKeys/Model/ModifierKey.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Quickcast/Features/HotKeys/Model/HyperKey.swift \
                           Quickcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Quickcast/Platform/ASCIIKeyboardLayout.swift \
                           Quickcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Quickcast/Platform/LocalizedResource.swift
run space-gesture-test     Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/WindowManagement/Model/SpaceGesture.swift \
                           Quickcast/Platform/LocalizedResource.swift
run window-layout-test     Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Quickcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayout.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutStore.swift \
                           Quickcast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Quickcast/Features/WindowManagement/Model/CustomWindowSizeStore.swift \
                           Quickcast/Platform/LocalizedResource.swift
run deeplink-test          Quickcast/Features/DeepLinks/Model/DeepLink.swift \
                           Quickcast/Features/DeepLinks/Model/DeepLinkInput.swift \
                           Quickcast/Features/DeepLinks/Model/DeepLinkConsentPolicy.swift \
                           Quickcast/Features/DeepLinks/Model/DeepLinkSource.swift \
                           Quickcast/Features/DeepLinks/Model/CustomWindowSize+DeepLink.swift \
                           Quickcast/Features/Settings/SettingsTab.swift \
                           Quickcast/Features/Launcher/Model/CommandID.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyAction+EntryID.swift \
                           Quickcast/Features/QuickActions/Model/QuickAction.swift \
                           Quickcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Quickcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/SystemActions/Model/SystemAction.swift \
                           Quickcast/Features/CustomCommands/Model/CustomCommand.swift \
                           Quickcast/Features/AppleShortcuts/Model/AppleShortcut.swift \
                           Quickcast/Features/Snippets/Model/Snippet.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Quickcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayout.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Quickcast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Quickcast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Quickcast/Features/WindowManagement/Model/RoomGrid.swift \
                           Quickcast/Features/WindowManagement/Model/RoomWindow.swift \
                           Quickcast/Features/WindowManagement/Model/Room.swift \
                           Quickcast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Quickcast/Platform/LocalizedResource.swift
run window-room-test       Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Quickcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayout.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Quickcast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Quickcast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Quickcast/Features/WindowManagement/Model/RoomGrid.swift \
                           Quickcast/Features/WindowManagement/Model/RoomWindow.swift \
                           Quickcast/Features/WindowManagement/Model/Room.swift \
                           Quickcast/Features/WindowManagement/Model/RoomWindowMatcher.swift \
                           Quickcast/Features/WindowManagement/Model/RoomParking.swift \
                           Quickcast/Features/WindowManagement/Model/RoomPlan.swift \
                           Quickcast/Features/WindowManagement/Model/RoomArrangement.swift \
                           Quickcast/Features/WindowManagement/Model/RoomStore.swift \
                           Quickcast/Features/WindowManagement/Model/RoomMinimumSizeStore.swift \
                           Quickcast/Features/WindowManagement/Model/RoomParkingLedger.swift \
                           Quickcast/Platform/LocalizedResource.swift
run window-file-test       Quickcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Quickcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Quickcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayout.swift \
                           Quickcast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Quickcast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Quickcast/Features/WindowManagement/Model/Room.swift \
                           Quickcast/Features/WindowManagement/Model/RoomWindow.swift \
                           Quickcast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Quickcast/Features/WindowManagement/Model/RoomGrid.swift \
                           Quickcast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Quickcast/Features/WindowManagement/Model/WindowManagementFileFormat.swift \
                           Quickcast/Features/Settings/Model/SettingsFileJSON.swift \
                           Quickcast/Features/Settings/Model/SettingsFileIdentity.swift \
                           Quickcast/Platform/LocalizedResource.swift
run custom-command-test    Quickcast/Platform/PseudoTerminal.swift \
                           Quickcast/Platform/ProcessExit.swift \
                           Quickcast/Features/CustomCommands/Model/CustomCommand.swift \
                           Quickcast/Features/CustomCommands/Model/RaycastScriptImport.swift \
                           Quickcast/Features/CustomCommands/UI/CustomCommandEditorSession.swift \
                           Quickcast/Features/CustomCommands/Service/ShellCommandRunner.swift
run custom-command-list-test Quickcast/Features/CustomCommands/Model/CustomCommand.swift \
                             Quickcast/Features/CustomCommands/UI/CustomCommandListScreen.swift
run uninstall-coordinator-test Quickcast/Features/Uninstall/Model/*.swift \
                           Quickcast/Features/Uninstall/UI/UninstallCoordinator.swift
run uninstall-test         Quickcast/Features/Uninstall/Model/UninstallTarget.swift \
                           Quickcast/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Quickcast/Features/Uninstall/Model/UninstallRules.swift \
                           Quickcast/Features/Uninstall/Model/UninstallProtection.swift \
                           Quickcast/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Quickcast/Features/Quicklinks/Model/RaycastQuicklinkImport.swift \
                           Quickcast/Features/Quicklinks/UI/QuicklinkEditorSession.swift
run quicklink-coordinator-test Quickcast/Features/Quicklinks/Model/Quicklink.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Quickcast/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Quickcast/Features/Quicklinks/UI/QuicklinkCoordinator.swift \
                           Quickcast/Features/Quicklinks/UI/QuicklinkEditorSession.swift \
                           Quickcast/Features/Quicklinks/UI/QuicklinkArgumentsAccessory.swift \
                           Quickcast/Features/Snippets/Model/Snippet.swift \
                           Quickcast/Features/Snippets/Model/SnippetTemplateEngine.swift
run slow snippets-test     Quickcast/Platform/NotificationToken.swift \
                           Quickcast/Platform/HealthTicker.swift \
                           Quickcast/Platform/AccessibilityText.swift \
                           Quickcast/Features/Snippets/Model/*.swift \
                           Quickcast/Features/Snippets/Service/*.swift \
                           Quickcast/Features/Snippets/UI/SnippetEditorSession.swift \
                           Quickcast/Features/TextInjection/Service/*.swift
run notes-test             Quickcast/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Quickcast/Features/Notes/Model/*.swift \
                           Quickcast/Features/Notes/Service/*.swift
run notes-editor-test      Quickcast/Platform/Signposts.swift \
                           Quickcast/Platform/Appearance.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           Quickcast/Platform/NotificationToken.swift \
                           Quickcast/Features/TextInjection/Service/InjectableTextView.swift \
                           Quickcast/Features/Notes/Model/NoteDocument.swift \
                           Quickcast/Features/Notes/Model/NoteTitle.swift \
                           Quickcast/Features/Notes/Model/NoteMarkdown.swift \
                           Quickcast/Features/Notes/Model/NoteMarkdownParser.swift \
                           Quickcast/Features/Notes/Model/NoteInlineScanner.swift \
                           Quickcast/Features/Notes/Model/NoteEditPlan.swift \
                           Quickcast/Features/Notes/Model/NoteEditAction.swift \
                           Quickcast/Features/Notes/Model/NoteFormatting.swift \
                           Quickcast/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Quickcast/Features/Notes/Model/NoteRevealPolicy.swift \
                           Quickcast/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Quickcast/Features/Notes/UI/NoteBlockDecoration.swift \
                           Quickcast/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Quickcast/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Quickcast/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Quickcast/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Quickcast/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Quickcast/Features/Notes/UI/NoteTextViewEditing.swift \
                           Quickcast/Features/Notes/UI/NoteTextView.swift \
                           Quickcast/Features/Notes/UI/NoteEditorView.swift
run -O index notes-editor-performance \
                           Quickcast/Platform/Signposts.swift \
                           Quickcast/Platform/Appearance.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           Quickcast/Platform/NotificationToken.swift \
                           Quickcast/Features/TextInjection/Service/InjectableTextView.swift \
                           Quickcast/Features/Notes/Model/NoteDocument.swift \
                           Quickcast/Features/Notes/Model/NoteTitle.swift \
                           Quickcast/Features/Notes/Model/NoteMarkdown.swift \
                           Quickcast/Features/Notes/Model/NoteMarkdownParser.swift \
                           Quickcast/Features/Notes/Model/NoteInlineScanner.swift \
                           Quickcast/Features/Notes/Model/NoteEditPlan.swift \
                           Quickcast/Features/Notes/Model/NoteEditAction.swift \
                           Quickcast/Features/Notes/Model/NoteFormatting.swift \
                           Quickcast/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Quickcast/Features/Notes/Model/NoteRevealPolicy.swift \
                           Quickcast/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Quickcast/Features/Notes/UI/NoteBlockDecoration.swift \
                           Quickcast/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Quickcast/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Quickcast/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Quickcast/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Quickcast/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Quickcast/Features/Notes/UI/NoteTextViewEditing.swift \
                           Quickcast/Features/Notes/UI/NoteTextView.swift \
                           Quickcast/Features/Notes/UI/NoteEditorView.swift
run slow -O raycast-test   Quickcast/Features/Backup/Model/RaycastImportError.swift \
                           Quickcast/Features/Backup/Service/RaycastDecoder.swift \
                           Quickcast/Features/Backup/Service/Scrypt.swift \
                           Quickcast/Platform/Compression/Zlib.swift \
                           Quickcast/Features/Clipboard/Model/RaycastClipboardImport.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Quickcast/Platform/Images/ImageDerivative.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Quickcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Quickcast/Features/Clipboard/Model/ColorValue.swift \
                           Quickcast/Features/Clipboard/Model/ColorFormat.swift \
                           Quickcast/Features/Clipboard/Model/ColorSpaces.swift
run settings-backup-test   Quickcast/Features/Settings/AppSettingsKey.swift \
                           Quickcast/Features/Backup/Model/SettingsBackupCoverage.swift
run hyper-key-engine-test  Quickcast/Features/HotKeys/Model/HyperKeyEngine.swift \
                           Quickcast/Features/HotKeys/Model/HyperKey.swift \
                           Quickcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Quickcast/Features/HotKeys/Model/ModifierKey.swift \
                           Quickcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Quickcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Quickcast/Platform/ASCIIKeyboardLayout.swift
run hyper-key-test         Quickcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Quickcast/Features/HotKeys/Model/HyperKeyConflictPolicy.swift \
                           Quickcast/Features/HotKeys/Service/KeyboardRemapper.swift \
                           Quickcast/Features/HotKeys/Service/RemapInstanceLock.swift \
                           Tests/hyper-key-fixtures.swift
run dictation-key-test     Quickcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Quickcast/Features/HotKeys/Model/HyperKeyConflictPolicy.swift \
                           Quickcast/Features/HotKeys/Service/KeyboardRemapper.swift \
                           Quickcast/Features/HotKeys/Service/RemapInstanceLock.swift \
                           Quickcast/Features/HotKeys/Service/DictationKeyManager.swift \
                           Quickcast/Platform/HealthTicker.swift \
                           Quickcast/Platform/NotificationToken.swift \
                           Tests/hyper-key-fixtures.swift \
                           Tests/dictation-key-fixtures.swift
run hotkey-dispatch-test   Quickcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Quickcast/Features/HotKeys/Model/ModifierKey.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Quickcast/Features/HotKeys/Model/HyperKey.swift \
                           Quickcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Quickcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Quickcast/Features/HotKeys/Service/HotKeyManager.swift \
                           Quickcast/Platform/ASCIIKeyboardLayout.swift \
                           Tests/hotkey-dispatch-fixtures.swift
run inline-configure-test  Quickcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Quickcast/Features/HotKeys/Model/ModifierKey.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Quickcast/Features/HotKeys/Model/HyperKey.swift \
                           Quickcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Quickcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Quickcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Quickcast/Features/HotKeys/Service/HotKeyManager.swift \
                           Quickcast/Features/Launcher/Model/InlineConfiguration.swift \
                           Quickcast/Features/Launcher/Service/AliasStore.swift \
                           Quickcast/Features/Launcher/Service/EntryConfigurationWriter.swift \
                           Quickcast/Platform/ASCIIKeyboardLayout.swift \
                           Tests/hotkey-dispatch-fixtures.swift
run settings-file-test     Quickcast/Features/Settings/Model/*.swift \
                           Quickcast/Features/Settings/Service/SettingsFileMonitor.swift \
                           Quickcast/Features/Settings/Service/SettingsFileRepository.swift \
                           Quickcast/Platform/AppPaths.swift
run backup-archive-test   Quickcast/Platform/AppPaths.swift \
                           Quickcast/Features/Backup/Model/BackupArchive.swift \
                           Quickcast/Features/Backup/Model/BackupBundle.swift \
                           Quickcast/Features/Backup/Model/BackupCategory.swift \
                           Quickcast/Features/Backup/Model/BackupClipboardItem.swift \
                           Quickcast/Features/Backup/Model/BackupManifest.swift \
                           Quickcast/Features/Backup/Service/BackupStaging.swift
E=Quickcast/Features/Extensions
run symbols-test           $E/Service/SymbolCatalog.swift
run ext-cleanup-test       $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           Quickcast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-refresh-test       $E/Model/ExtensionManifest.swift \
                           Quickcast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-metadata-test      $E/Model/ExtensionCommandMetadata.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift
run ext-version-test       $E/Model/ExtensionListing.swift \
                           $E/Service/ExtensionVersionStore.swift
run ext-store-test         $E/Model/ExtensionGitHubSource.swift \
                           $E/Model/ExtensionListing.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ext-form-test          $E/Model/ExtensionFormMetrics.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/UI/ExtensionFormKey.swift \
                           $E/Model/ExtensionDateExpression.swift \
                           $E/UI/ExtensionListKey.swift \
                           Tests/ext-list-key-test.swift
run ext-image-size-test   $E/Model/ExtensionImageSize.swift
run ext-sign-in-test       $E/Service/ExtensionSignInSession.swift
run ext-accessory-test     $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionStorage.swift
run slow ext-test          -parse-as-library \
                           Tests/ext-menu-bar-test.swift \
                           Tests/ext-fetch-test.swift \
                           $E/Model/ExtensionLaunchError.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionStorage.swift \
                           $E/Service/ExtensionMenuBarManager.swift \
                           $E/Model/ExtensionCommandMetadata.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift \
                           $E/UI/ExtensionMenuBarController.swift \
                           $E/UI/ExtensionMenuBarImage.swift \
                           Quickcast/Platform/Appearance.swift \
                           Quickcast/Platform/AppDisplayName.swift \
                           Quickcast/Platform/Images/IconCache.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionDeepLink.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionSearchState.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift \
                           $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           Quickcast/Platform/ProcessExit.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/Service/ExtensionNameResolver.swift \
                           $E/Service/ExtensionWebSocketBridge.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Quickcast/Platform/Compression/Zlib.swift \
                           Quickcast/Features/Clipboard/Model/ColorValue.swift \
                           Quickcast/Features/Clipboard/Model/ColorSpaces.swift
run settings-history-test  Quickcast/Features/Settings/SettingsTab.swift \
                           Quickcast/Features/Settings/SettingsHistory.swift \
                           Quickcast/Features/Settings/SettingsAnchor.swift \
                           Quickcast/Features/Settings/SettingsNavigationState.swift \
                           Quickcast/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift \
                           Quickcast/Platform/LocalizedResource.swift
run updates-test           Quickcast/Features/Updates/Model/*.swift \
                           Quickcast/Features/Updates/Service/BundleSignature.swift \
                           Quickcast/Features/Updates/Service/UpdateSignature.swift
run update-check-test      Quickcast/Features/Updates/Model/*.swift \
                           Quickcast/Features/Updates/Service/UpdateCheckStore.swift \
                           Quickcast/Platform/AppPaths.swift
run support-test           Quickcast/Features/Support/Model/*.swift
run ai-provider-test       Quickcast/Features/Settings/AppSettingsKey.swift \
                           Quickcast/Features/AI/Model/*.swift \
                           Quickcast/Features/AI/Settings/AISettingsStore.swift \
                           Quickcast/Features/AI/Service/CodexAppServerClient.swift \
                           Quickcast/Features/AI/Service/InstalledAIProbe.swift \
                           Quickcast/Platform/ExecutableLocator.swift Quickcast/Platform/ProcessExit.swift
run opencode-mcp-test      Quickcast/Features/AI/Model/*.swift \
                           Quickcast/Platform/ExecutableLocator.swift Quickcast/Platform/ProcessExit.swift \
                           Quickcast/Features/AI/Service/AIProvider.swift \
                           Quickcast/Features/AI/Service/AIToolLoopProvider.swift \
                           Quickcast/Features/AI/Service/InstalledCLIProvider.swift \
                           Quickcast/Features/AI/Service/OpenCodeMCPBridge.swift
run ai-chat-test           Quickcast/Features/AI/Model/AIRequest.swift \
                           Quickcast/Features/AI/Model/AIConnection.swift \
                           Quickcast/Features/AI/Model/AIConversationOpenPolicy.swift \
                           Quickcast/Features/AI/Model/AppleIntelligence.swift \
                           Quickcast/Features/AI/Model/AIAttachmentPolicy.swift \
                           Quickcast/Features/AI/Model/AIRetention.swift \
                           Quickcast/Features/AI/Model/AITool.swift \
                           Quickcast/Features/AI/Model/JSONValue.swift \
                           Quickcast/Features/AI/Model/ChatMessage.swift \
                           Quickcast/Features/AI/Model/ChatSession.swift \
                           Quickcast/Features/AI/Model/ChatPreset.swift \
                           Quickcast/Features/AI/Model/ChatChoices.swift \
                           Quickcast/Features/AI/Model/ChatReferences.swift \
                           Quickcast/Features/AI/Model/ChatTitle.swift \
                           Quickcast/Features/AI/Model/ChatFind.swift \
                           Quickcast/Features/AI/Model/ChatCitations.swift \
                           Quickcast/Features/AI/Model/ChatToolScope.swift \
                           Quickcast/Features/AI/Model/MarkdownBlock.swift \
                           Quickcast/Features/AI/Model/MarkdownMath.swift \
                           Quickcast/Features/AI/Model/MathFormula.swift \
                           Quickcast/Features/AI/Model/MathNode.swift \
                           Quickcast/Features/AI/Model/MathSymbolCatalog.swift \
                           Quickcast/Features/AI/Service/AIProvider.swift \
                           Quickcast/Features/AI/Service/ChatHistoryStore.swift \
                           Quickcast/Features/AI/Service/AIToolLoopProvider.swift \
                           Quickcast/Features/AI/UI/AIChatState.swift \
                           Quickcast/Features/AI/UI/AIChatSurfacesState.swift \
                           Quickcast/Features/AI/UI/ChatFindState.swift
run ai-responses-test      Quickcast/Features/AI/Model/AIConnection.swift \
                           Quickcast/Features/AI/Model/AppleIntelligence.swift \
                           Quickcast/Features/AI/Model/AIModelDiscovery.swift \
                           Quickcast/Features/AI/Model/AIRequest.swift \
                           Quickcast/Features/AI/Model/AIRequestBody.swift \
                           Quickcast/Features/AI/Model/AIStreamDecoder.swift \
                           Quickcast/Features/AI/Model/AIResponsesDecoder.swift \
                           Quickcast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Quickcast/Features/AI/Model/AIProviderFailure.swift \
                           Quickcast/Features/AI/Model/AITool.swift \
                           Quickcast/Features/AI/Model/JSONValue.swift \
                           Quickcast/Features/AI/Service/AIProvider.swift \
                           Quickcast/Features/AI/Service/AIToolLoopProvider.swift
run chat-markdown-test     Quickcast/Platform/Appearance.swift \
                           Quickcast/DesignSystem/Theme.swift \
                           Quickcast/DesignSystem/InterfaceMetrics.swift \
                           Quickcast/Features/Settings/InterfaceSize.swift \
                           Quickcast/Features/AI/Model/AIRequest.swift \
                           Quickcast/Features/AI/Model/AITool.swift \
                           Quickcast/Features/AI/Model/JSONValue.swift \
                           Quickcast/Features/AI/Model/ChatMessage.swift \
                           Quickcast/Features/AI/Model/ChatChoices.swift \
                           Quickcast/Features/AI/Model/ChatReferences.swift \
                           Quickcast/Features/AI/Model/ChatCitations.swift \
                           Quickcast/Features/AI/Model/ChatFind.swift \
                           Quickcast/Features/AI/Model/MarkdownBlock.swift \
                           Quickcast/Features/AI/Model/MarkdownMath.swift \
                           Quickcast/Features/AI/Model/MathFormula.swift \
                           Quickcast/Features/AI/Model/MathNode.swift \
                           Quickcast/Features/AI/Model/MathSymbolCatalog.swift \
                           Quickcast/Features/AI/Model/SyntaxGrammar.swift \
                           Quickcast/Features/AI/Model/SyntaxHighlighter.swift \
                           Quickcast/Features/AI/Model/SyntaxStructuredLexers.swift \
                           Quickcast/Features/AI/UI/ChatTextHighlight.swift \
                           Quickcast/Features/AI/UI/ChatMarkdownRenderer.swift \
                           Quickcast/Features/AI/UI/MathAttachmentCell.swift \
                           Quickcast/Features/AI/UI/MathBox.swift \
                           Quickcast/Features/AI/UI/MathFont.swift \
                           Quickcast/Features/AI/UI/MathLayoutEngine.swift
run syntax-highlight-test  Quickcast/Features/AI/Model/SyntaxGrammar.swift \
                           Quickcast/Features/AI/Model/SyntaxHighlighter.swift \
                           Quickcast/Features/AI/Model/SyntaxStructuredLexers.swift
run mcp-test               Quickcast/Features/Settings/AppSettingsKey.swift \
                           Quickcast/Features/AI/Model/AIConnection.swift \
                           Quickcast/Features/AI/Model/AppleIntelligence.swift \
                           Quickcast/Features/AI/Model/AITool.swift \
                           Quickcast/Features/AI/Model/AIToolServer.swift \
                           Quickcast/Features/AI/Model/JSONValue.swift \
                           Quickcast/Features/MCP/Model/*.swift \
                           Quickcast/Features/MCP/Settings/MCPSettingsStore.swift
run -O text-diff-test      Quickcast/Features/QuickActions/Model/TextDiffEngine.swift
run index text-diff-performance Quickcast/Features/QuickActions/Model/TextDiffEngine.swift
run quick-action-test      Quickcast/Features/Settings/AppSettingsKey.swift \
                           Quickcast/Features/AI/Model/AIConnection.swift \
                           Quickcast/Features/AI/Model/AppleIntelligence.swift \
                           Quickcast/Features/AI/Model/ChatGPTSubscription.swift \
                           Quickcast/Features/AI/Model/InstalledAI.swift \
                           Quickcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Quickcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Quickcast/Features/QuickActions/Model/CustomQuickActionStore.swift \
                           Quickcast/Features/QuickActions/Model/QuickAction.swift \
                           Quickcast/Features/QuickActions/Model/QuickActionFailure.swift \
                           Quickcast/Features/QuickActions/Model/QuickActionPrompt.swift \
                           Quickcast/Features/QuickActions/Model/QuickActionSettings.swift \
                           Quickcast/Features/QuickActions/Settings/QuickActionSettingsStore.swift \
                           Quickcast/Platform/LocalizedResource.swift
run apple-intelligence-test Quickcast/Features/Settings/AppSettingsKey.swift \
                           Quickcast/Features/AI/Model/*.swift \
                           Quickcast/Features/AI/Service/AIProvider.swift \
                           Quickcast/Features/AI/Service/AppleIntelligenceProvider.swift
run mcp-oauth-test         Quickcast/Platform/ExecutableLocator.swift \
                           Quickcast/Platform/ProcessExit.swift \
                           Quickcast/Platform/KeychainSecretStore.swift \
                           Quickcast/Features/Settings/AppSettingsKey.swift \
                           Quickcast/Features/AI/Model/AIConnection.swift \
                           Quickcast/Features/AI/Model/AppleIntelligence.swift \
                           Quickcast/Features/AI/Model/AITool.swift \
                           Quickcast/Features/AI/Model/AIToolServer.swift \
                           Quickcast/Features/AI/Model/AIStreamDecoder.swift \
                           Quickcast/Features/AI/Model/AIResponsesDecoder.swift \
                           Quickcast/Features/AI/Model/AIProviderFailure.swift \
                           Quickcast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Quickcast/Features/AI/Model/AIRequest.swift \
                           Quickcast/Features/AI/Model/JSONValue.swift \
                           Quickcast/Features/MCP/Model/*.swift \
                           Quickcast/Features/MCP/Service/*.swift
run slow mcp-stdio-test    Quickcast/Platform/ExecutableLocator.swift \
                           Quickcast/Platform/ProcessExit.swift \
                           Quickcast/Platform/KeychainSecretStore.swift \
                           Quickcast/Features/Settings/AppSettingsKey.swift \
                           Quickcast/Features/AI/Model/AIConnection.swift \
                           Quickcast/Features/AI/Model/AppleIntelligence.swift \
                           Quickcast/Features/AI/Model/AITool.swift \
                           Quickcast/Features/AI/Model/AIToolServer.swift \
                           Quickcast/Features/AI/Model/AIStreamDecoder.swift \
                           Quickcast/Features/AI/Model/AIResponsesDecoder.swift \
                           Quickcast/Features/AI/Model/AIProviderFailure.swift \
                           Quickcast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Quickcast/Features/AI/Model/AIRequest.swift \
                           Quickcast/Features/AI/Model/JSONValue.swift \
                           Quickcast/Features/MCP/Model/*.swift \
                           Quickcast/Features/MCP/Service/*.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${QUICKCAST_TEST_JOBS:-4}"
export QUICKCAST_TEST_TIMEOUT="${QUICKCAST_TEST_TIMEOUT:-300}"
started=$SECONDS

# Numbers each result, and names what is still running whenever the output goes quiet.
report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in
                "dispatch "*)
                    [ "$finished" -eq "$ran" ] || return 1
                    return "${line#dispatch }";;
            esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # Bash 3.2 returns the same status for a timeout and EOF; only EOF comes back at once.
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

dispatch() {
    [ -s "$1" ] || return 0
    sort -s -k1,1n "$1" | cut -d' ' -f2- | xargs -P "$2" -L1 "$SELF" --exec
}

# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! {
    dispatch "$QUEUE" "$JOBS"
    echo "dispatch $?"
} | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
