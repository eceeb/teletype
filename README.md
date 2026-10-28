# Teletype

A fast, native macOS terminal emulator, built in Swift + AppKit with
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for VT/escape parsing.

## Features

- **Tabs** (top bar or left sidebar) and **split panes** (nested, resizable)
- The sidebar lists every pane; panes of a tab are grouped and labelled by their
  shared folder, and a group header can be renamed by double-clicking it
- **Session restore** — reopens your tabs, splits, and each shell's working
  directory on launch (layout only, no scrollback)
- **Search the scrollback** with ⌘F: every hit is highlighted, ⌘G / ⇧⌘G walk
  them, and jumping to one scrolls it into view
- **⌘-click opens a link** in your browser
- **Mouse support in full-screen programs** — vim, htop and less get real
  mouse events (click, drag, wheel); hold Shift to select text instead
- True-color rendering, bold / italic / underline, wide glyphs and emoji,
  Nerd-Font icons (bundled JetBrainsMono)
- Mouse selection + copy (drag / double-click word / triple-click line), paste
  (bracketed where the program asks for it), ⌘A selects the whole buffer
- Scrollback (configurable size), live resize, window position persistence
- The cursor takes the shape a program asks for — vim's bar in insert mode —
  and blinks if it says so
- **Color themes** — 13 built-in profiles (Dracula, Nord, Gruvbox, Solarized
  Dark/Light, Tokyo Night, Catppuccin, Monokai, …) that recolor the
  background, text and all 16 ANSI colors. A program can override them for
  itself with OSC 10/11/12
- A program can also copy to the clipboard (OSC 52, how tmux and vim do it over
  SSH) and raise a notification (OSC 777). Reading the clipboard is refused
- **Bell**: silent (the default), a sound, or a short flash
- Live **settings**: font size, color theme, background & text color, sidebar
  color, scroll speed, scrollback size, bell, app icon, shell, new-tab folder,
  tab placement, and the `claude` command
- A **Claude** tab/pane that runs the `claude` CLI
- Configurable shell (defaults to `$SHELL`); a new split inherits the active
  pane's directory, new tabs open in a configurable folder

## Keyboard shortcuts

| Action | Keys |
| --- | --- |
| New Tab / New Claude Tab | ⌘T / ⌘E |
| Go to Tab 1–9 / Last Used | ⌘1…9 / ⌃⇥ |
| Split Right / Split Down | ⌘D / ⇧⌘D |
| New Claude Pane | ⇧⌘E |
| Close Pane / Close Tab | ⌘W / ⇧⌘W |
| Previous / Next Pane | ⌘[ / ⌘] |
| Focus Pane | ⌥⌘ ← ↑ ↓ → |
| Copy / Paste / Select All | ⌘C / ⌘V / ⌘A |
| Find / Next / Previous | ⌘F / ⌘G / ⇧⌘G |
| Zoom In / Out / Actual Size | ⌘+ / ⌘− / ⌘0 |
| Open link under pointer | ⌘-click |
| Select text in a mouse-aware program | ⇧-drag |
| Settings / Hide / Minimize | ⌘, / ⌘H / ⌘M |

(Also available in-app under Settings → Keyboard Shortcuts.)

## Build & install

Requires macOS 14+ and a Swift 6 toolchain.

```sh
swift test                   # run the test suite
bash packaging/install.sh    # build release + install Teletype.app into /Applications
swift run Teletype           # run without installing
```

Contributing? See [CLAUDE.md](CLAUDE.md) for the project layout, data flow, and conventions.

## Updating dependencies

The only dependency is SwiftTerm:

```sh
swift package update
```

## License

[The Unlicense](LICENSE) — public domain, do whatever you want.

The bundled font (JetBrainsMono Nerd Font, under `Sources/Teletype/Resources/Fonts`)
is covered separately by the SIL Open Font License.

The built-in color schemes are adapted from
[iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)
(MIT, © Mark Badolato); each scheme remains © its respective author under its own license.
