# Teletype — agent guide

Native macOS terminal emulator: Swift + AppKit, [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
for VT/escape parsing, CoreText for rendering. User-facing features, keyboard
shortcuts, and install instructions live in [README.md](README.md) — don't
duplicate them here.

## Layout / seams

- `Sources/TeletypeCore/` — **UI-free, testable logic. Never import AppKit here.**
  PTY, terminal emulator, color themes, pane grouping, session layout, settings.
- `Sources/Teletype/` — the AppKit app: window, tabs, split panes, the terminal
  renderer, menus. (The Settings and Shortcuts windows are SwiftUI, embedded via
  `NSHostingController`.)
- `Sources/CPTY/` — a tiny C shim: `fork` + `setsid` + `ioctl(TIOCSCTTY)` before
  `execve`, because `fork()` can't be called from Swift.
- `Tests/TeletypeCoreTests/` — tests for everything in Core.

The Core/UI split is the load-bearing rule: if logic can live in Core (no
AppKit), put it there so it stays testable. That's why the suite runs headless.

## Data flow

PTY bytes → `PTYProcess` (Core) → `TerminalSession` (Core) → `TerminalEmulator`
(Core, wraps SwiftTerm) → `TerminalView` (AppKit, draws the grid cell-by-cell
with CoreText). The UI shell: a `TerminalPane` (session + view) sits in a
`TerminalTab` (split-pane tree), owned by `MainWindowController` (window, tabs,
and the sidebar `TabBarView`).

Rendering is CPU/CoreText by design; a Metal renderer could replace
`TerminalView.draw(_:)` later (see the comment there). Not built yet.

## Build / test

```sh
swift build
swift test                 # Core tests, headless
bash packaging/install.sh  # release build → Teletype.app in /Applications
```

## Running a dev build (read before launching)

The installed app and a dev build are **both named "Teletype"** — never
`pkill -x Teletype`, you would kill the user's running copy. Start a dev instance
and identify it by its path/args instead:

```sh
env -u GIT_EDITOR ./.build/debug/Teletype                     # dev build
env -u GIT_EDITOR ./.build/debug/Teletype -tabPlacement left  # force the sidebar
```

The dev binary has no bundle id, so it uses its own `UserDefaults` domain (starts
with default settings, won't touch the user's). `-tabPlacement left` uses the
NSUserDefaults argument domain to flip to the sidebar without persisting anything.

## Conventions

- Test-driven, smallest sensible steps; keep the PTY → emulator → renderer → UI
  seams clean.
- Comment the **why** at non-obvious spots (AppKit quirks, couplings, ordering),
  not the **what**.
