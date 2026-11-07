# Quickcast

**A tiny, fully native macOS launcher. One hotkey, everything you reach for all day, under 100 MB of
RAM.**

<p align="center">
  <a href="https://github.com/vuhpquang/quickcast/releases/latest">
    <img alt="Latest release"
         src="https://img.shields.io/github/v/release/vuhpquang/quickcast?sort=semver&style=flat&label=release&color=1F6FEB"></a>
  <img alt="Swift 6.0"
       src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white">
  <img alt="macOS 26 or later"
       src="https://img.shields.io/badge/macOS-26%2B-000000?style=flat&logo=apple&logoColor=white">
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
</p>

SwiftUI and AppKit, **zero third-party dependencies**, no Electron and no telemetry. It also **runs
real Raycast extensions**, rendered as native SwiftUI. Free, open source, and staying that way.

> **Quickcast is a fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar**, renamed and
> maintained by [vuhpquang](https://github.com/vuhpquang). Licensed under AGPL-3.0, like the original.

<p align="center">
  <img src="docs/screenshot.png" alt="Quickcast command palette" width="720">
</p>

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).
- **Deeplinks** — run any command, window action, quicklink, snippet, note or chat from a
  `quickcast://` URL, for Karabiner-Elements, Shortcuts or scripts. A link can carry text and
  arguments, and a link from outside asks before it acts. Copy Deeplink (⇧⌘C) gives you the link.
- **Search Files** — find files and folders instantly from a private index of the folders you choose,
  kept on your Mac. Needs Full Disk Access; off by default.
- **Dictionary** — look a word up with the Define Word command, or define whatever you typed from the
  launcher's fallbacks, read from the Mac's own dictionaries.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Calculator** — do math, unit, live currency and crypto conversions inline, right in the palette.
- **Quicklinks** — turn a URL, search, file or deeplink into a command, with placeholders for typed
  input, the clipboard or the date.
- **Apple Shortcuts** — search and run the shortcuts you built in the Shortcuts app, with aliases and
  global hotkeys.
- **Snippets** — reusable Markdown templates with dynamic placeholders, arguments, nested references
  and optional keyword expansion.
- **Custom commands** — run named shell commands through fuzzy search or their own global hotkeys.
- **Window management** — 39 Rectangle-style actions: halves, quarters, thirds, sizing, nudging,
  edge moves, display moves, fullscreen and Spaces.
- **System actions** — lock, sleep, restart, empty trash, toggle appearance, Bluetooth, mute, hidden
  files, and more.
- **Calendar and meetings** — your next meeting on the empty palette and in the menu bar, one key to
  join it, or let it join itself.
- **Notes** — an unlimited collection of plain Markdown files in one floating editor, searchable from
  the palette and rendered as you write.
- **Emoji picker** — a searchable emoji grid, one keystroke away.
- **AI chat** — use your own key or an installed AI account: ask Quick AI from the palette, or keep
  longer conversations in the AI Chat window, with a searchable, pinnable history. Off out of the box,
  like every AI feature.
- **Quick Actions** — fix grammar, rewrite, translate or summarize the selected text in any app.
- **Dictation** — press a shortcut and speak, and the text lands in the app you're
  using. Speech is turned into text on your Mac. Off by default.
- **Raycast extensions** — run the ones you already have natively, rendered as SwiftUI.
- **Backup and import** — export your settings to a file, or import your setup from Raycast.

## Install

On an Apple silicon Mac with macOS 26 or newer:

Download `Quickcast.app` from [Releases](https://github.com/vuhpquang/quickcast/releases) and drag it to
`/Applications`, or build it from source.

## Building from source

See **[docs/development.md](docs/development.md)** for the toolchain, build, packaging, release and
website workflows. **[docs/](docs/README.md)** indexes everything else — architecture, engineering
standards, the design system and one document per feature.

## Upstream

All credit for the original app goes to [Tinycast](https://github.com/abue-ammar/tinycast). To
support its author, see the Tinycast repository.

## License

[AGPL-3.0](LICENSE)
