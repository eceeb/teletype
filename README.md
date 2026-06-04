# Teletype

A fast, native macOS terminal emulator, built in Swift + AppKit with
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for VT/escape parsing.

## Features

- **Tabs** (top bar or left sidebar) and **split panes** (nested, resizable)
- The sidebar lists every pane; panes of a tab are grouped and labelled by their
  shared folder (e.g. root `e`, rows `teletype` / `teletype/Tests`)
- **Session restore** — reopens your tabs, splits, and each shell's working
  directory on launch (layout only, no scrollback)
- True-color rendering, bold / italic / underline, wide glyphs, Nerd-Font icons
  (bundled JetBrainsMono)
- Mouse selection + copy (drag / double-click word / triple-click line), paste
- Scrollback, visible cursor, live resize, window position persistence
- Live **settings**: font size, background & text color, shell, tab placement
- A **Claude** tab/pane that runs the `claude` CLI
- Configurable shell (defaults to `$SHELL`); a new split inherits the active
  pane's directory

## Keyboard shortcuts

| Action | Keys |
| --- | --- |
| New Tab / New Claude Tab | ⌘T / ⌘E |
| Go to Tab 1–9 / Last Used | ⌘1…9 / ⌃⇥ |
| Split Right / Split Down | ⌘D / ⇧⌘D |
| New Claude Pane | ⇧⌘E |
| Close Pane | ⌘W |
| Previous / Next Pane | ⌘[ / ⌘] |
| Focus Pane | ⌥⌘ ← ↑ ↓ → |
| Copy / Paste | ⌘C / ⌘V |
| Settings | ⌘, |

(Also available in-app under Settings → Keyboard Shortcuts.)

## Build & install

Requires macOS 14+ and a Swift 6 toolchain.

```sh
swift test                   # run the test suite
bash packaging/install.sh    # build release + install Teletype.app into /Applications
swift run Teletype           # run without installing
```

## Updating dependencies

The only dependency is SwiftTerm:

```sh
swift package update
```

## License

[The Unlicense](LICENSE) — public domain, do whatever you want.

The bundled font (JetBrainsMono Nerd Font, under `Sources/Teletype/Resources/Fonts`)
is covered separately by the SIL Open Font License.
