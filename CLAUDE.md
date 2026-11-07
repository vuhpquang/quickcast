@AGENTS.md

# Quickcast fork rules

Quickcast is vuhpquang's fork of [Tinycast](https://github.com/abue-ammar/tinycast) (remote `upstream`).
Everything in AGENTS.md applies; these rules come first.

## New feature requests

Use the `quickcast-feature` skill (in the parent repo's `.claude/skills/`). In short:

1. **Check it doesn't already exist** (`docs/features/`, Settings). Many features ship switched off.
2. **Extension** when it is a list/form/detail/menu-bar command that `@raycast/api` covers, or a
   Raycast Store extension already does it — install that, don't rewrite it.
3. **Native Swift** when it touches the palette itself (header, Compact Shortcuts, aliases, ranking),
   needs system permissions / window control / background work, or must be a built-in `CommandID`.
4. Prefer extension when unsure: a smaller diff against upstream keeps merges easy.

## Keeping upstream merges cheap

- Fork-only code goes in its own files (`Features/LaunchApp/`, `LauncherCoordinator+AliasSpace.swift`).
- One-line hooks in upstream files carry a `// Quickcast fork:` comment.
- After merging `upstream/main`, re-apply the rename (Tinycast→Quickcast, `com.tinycast.app`→
  `com.vuhpquang.quickcast`) to incoming files, then `xcodegen generate`.
- Keep the `BundleSignature` fallback to the running copy's designated requirement: releases are
  self-signed ("Quickcast Self-Signed"), not Developer ID.

## Build, test, release

- `xcodegen generate` after adding/removing files (the .xcodeproj is generated and committed).
- Debug build: `xcodebuild -project Quickcast.xcodeproj -scheme Quickcast -derivedDataPath build/dd build`.
- Tests: `Scripts/run-tests.sh [harness]` (~5 min for all). `custom-command-test` fails on this Mac on
  upstream too. Harnesses compile file subsets, so shared model files (`CommandID`, `SettingsTab`)
  must not reference fork-only types.
- Release: `INSTALL=1 Scripts/release.sh X.Y.Z notes.md` (tests off unless `RUN_TESTS=1`).
  Signing material lives in `~/.config/quickcast-signing/` — never commit it.
