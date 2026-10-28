import AppKit
import TeletypeCore

/// Draws a `TerminalEmulator`'s grid cell by cell: each cell filled with its
/// background color, the glyph drawn in its foreground color (monospaced, via
/// AppKit/CoreText). A GPU (Metal) renderer can replace `draw(_:)` later without
/// touching the rest of the app.
final class TerminalView: NSView {
    private let emulator: TerminalEmulator
    private var font: NSFont
    private var boldFont: NSFont
    private var cellWidth: CGFloat
    private var cellHeight: CGFloat
    private let padding: CGFloat = 4
    private var backgroundColor: NSColor
    private var foregroundColor: NSColor

    /// Called with raw bytes to send to the shell when the user types.
    var onInput: ((Data) -> Void)?
    /// Called with the (columns, rows) that fit the view whenever that changes.
    var onResize: ((Int, Int) -> Void)?
    /// Called when this pane becomes the first responder (gains focus).
    var onFocus: (() -> Void)?
    private var lastGridSize: (cols: Int, rows: Int)?
    /// Selection anchors are buffer-absolute (visible row + `emulator.scrollOffset`),
    /// not visible rows — otherwise they'd stay put while the text scrolled under
    /// them, and a selection made while scrolling would drift off its text.
    private var selectionStart: GridPosition?
    private var selectionEnd: GridPosition?
    /// True between mouseDown and mouseUp, so scrolling mid-drag keeps extending
    /// the selection instead of just moving the viewport.
    private var isSelecting = false
    private var scrollAccumulator = ScrollAccumulator()
    /// Where the cursor was at the last repaint, so the cell it left is cleared.
    private var lastCursorRow = 0
    /// ⌘F state: the bar, the hits (buffer-absolute) and which one is current.
    private var findBar: FindBarView?
    private var searchHits: [SearchMatch] = []
    private var currentHit: SearchMatch?
    /// The fading overlay of a visual bell, while one is running.
    private var bellFlash: NSView?
    /// Blink state, and the timer driving it. The timer only exists while a
    /// program actually asked for a blinking cursor and this pane has focus —
    /// an idle pane costs nothing.
    private var cursorBlinkTimer: Timer?
    private var cursorIsOn = true

    init(emulator: TerminalEmulator, fontSize: CGFloat = 13, background: NSColor = .black, foreground: NSColor = .white) {
        self.emulator = emulator
        self.backgroundColor = background
        self.foregroundColor = foreground
        let font = TerminalFont.regular(ofSize: fontSize)
        self.font = font
        self.boldFont = TerminalFont.bold(ofSize: fontSize)
        self.cellWidth = TerminalView.advance(of: font)
        self.cellHeight = ceil(font.ascender - font.descender + font.leading)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = background.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Live-applies appearance settings: rebuilds the font at the new size,
    /// updates the background, and reflows the grid.
    func applyAppearance(fontSize: CGFloat, background: NSColor, foreground: NSColor) {
        backgroundColor = background
        foregroundColor = foreground
        layer?.backgroundColor = background.cgColor
        let font = TerminalFont.regular(ofSize: fontSize)
        self.font = font
        boldFont = TerminalFont.bold(ofSize: fontSize)
        cellWidth = TerminalView.advance(of: font)
        cellHeight = ceil(font.ascender - font.descender + font.leading)
        lastGridSize = nil          // force a reflow at the new cell size
        reportGridSizeIfChanged()
        needsDisplay = true
    }

    // Draw rows from the top down.
    override var isFlipped: Bool { true }

    // MARK: - Keyboard input

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        onFocus?()
        defer { updateCursorBlink() }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        defer { updateCursorBlink() }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        // Let ⌘-shortcuts (New Tab, Close, Quit, …) go to the menu instead of
        // being typed into the shell.
        guard !event.modifierFlags.contains(.command) else { return }
        if emulator.isScrolledBack {   // typing jumps back to the live view
            emulator.scrollToBottom()
            needsDisplay = true
        }
        if let special = event.specialKey,
           let sequence = escapeSequence(for: special, modifiers: event.modifierFlags) {
            onInput?(Data(sequence.utf8))
            return
        }
        guard let characters = event.characters, !characters.isEmpty else { return }
        onInput?(Data(characters.utf8))
    }

    /// Maps an AppKit key event onto the core's key encoder. Returns nil for
    /// keys that already send the right character themselves.
    private func escapeSequence(for key: NSEvent.SpecialKey,
                                modifiers: NSEvent.ModifierFlags) -> String? {
        guard let terminalKey = TerminalView.terminalKey(for: key) else { return nil }
        return TerminalKey.escapeSequence(for: terminalKey,
                                          modifiers: TerminalView.keyModifiers(for: modifiers),
                                          applicationCursor: emulator.applicationCursorKeys)
    }

    private static func terminalKey(for key: NSEvent.SpecialKey) -> TerminalKey? {
        switch key {
        case .upArrow:       return .up
        case .downArrow:     return .down
        case .rightArrow:    return .right
        case .leftArrow:     return .left
        case .home:          return .home
        case .end:           return .end
        case .pageUp:        return .pageUp
        case .pageDown:      return .pageDown
        case .deleteForward: return .deleteForward
        // AppKit calls the key above Return ".delete"; ".backspace" is the
        // control character. Both are the same physical key here.
        case .delete, .backspace: return .backspace
        default:             return nil
        }
    }

    private static func keyModifiers(for flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if flags.contains(.shift)   { modifiers.insert(.shift) }
        if flags.contains(.option)  { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    /// Cmd-V: send the clipboard's text to the shell.
    @objc func paste(_ sender: Any?) {
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        // When the program asked for bracketed paste, wrap the text so it arrives
        // as one literal block: a multi-line paste lands in the shell as an
        // editable buffer instead of every line executing the moment it arrives.
        let payload = emulator.bracketedPaste ? "\u{1b}[200~\(string)\u{1b}[201~" : string
        onInput?(Data(payload.utf8))
    }

    // MARK: - Mouse selection

    /// Hands the event to the running program when it tracks the mouse. Holding
    /// Shift overrides that and selects text instead — the convention in every
    /// terminal, and the only way to copy out of a mouse-tracking program.
    private func reportMouse(_ kind: MouseEventKind, _ event: NSEvent,
                             button: MouseButton = .left) -> Bool {
        guard emulator.mouseTracking != .off,
              !event.modifierFlags.contains(.shift) else { return false }
        let position = gridPosition(at: convert(event.locationInWindow, from: nil))
        emulator.sendMouse(kind, button: button,
                           modifiers: TerminalView.keyModifiers(for: event.modifierFlags),
                           column: position.column, row: position.row)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)   // clicking a pane focuses it
        if event.modifierFlags.contains(.command), openLink(at: event) { return }
        if reportMouse(.press, event) { return }
        isSelecting = true
        let position = gridPosition(at: convert(event.locationInWindow, from: nil))
        switch event.clickCount {
        case 2:   // double-click selects the word
            let (start, end) = emulator.wordRange(at: position)
            selectionStart = absolute(start)
            selectionEnd = absolute(end)
        case 3:   // triple-click selects the line
            let (start, end) = emulator.lineRange(atRow: position.row)
            selectionStart = absolute(start)
            selectionEnd = absolute(end)
        default:
            selectionStart = absolute(position)
            selectionEnd = absolute(position)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if reportMouse(.drag, event) { return }
        selectionEnd = absolute(gridPosition(at: convert(event.locationInWindow, from: nil)))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if reportMouse(.release, event) { return }
        isSelecting = false
        // A plain single click (no drag, no double/triple) clears the selection.
        if event.clickCount <= 1, selectionStart == selectionEnd {
            selectionStart = nil
            selectionEnd = nil
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if reportMouse(.press, event, button: .right) { return }
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        if reportMouse(.release, event, button: .right) { return }
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        if reportMouse(.press, event, button: .middle) { return }
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if reportMouse(.release, event, button: .middle) { return }
        super.otherMouseUp(with: event)
    }

    /// Drops any active selection. Called when the emulator says buffer-absolute
    /// rows changed meaning (a pager opened or quit, the scrollback was dropped)
    /// — the anchors would then highlight unrelated text. Plain output does *not*
    /// come through here: a selection has to survive a running build, which is
    /// exactly when you want to copy out of it.
    func clearSelection() {
        guard selectionStart != nil || selectionEnd != nil else { return }
        selectionStart = nil
        selectionEnd = nil
        needsDisplay = true
    }

    /// Repaints just what the last chunk of output changed. Redrawing the whole
    /// grid for every chunk pushed every cell through CoreText and made a large
    /// window sluggish under heavy output.
    func markDirtyForOutput() {
        let cursorRow = emulator.cursorPosition.row
        let rows = GridGeometry.rowsToRepaint(dirty: emulator.takeDirtyRows(),
                                              cursorRows: [lastCursorRow, cursorRow],
                                              totalRows: emulator.rows)
        lastCursorRow = cursorRow
        guard let rows else { return }
        let band = GridGeometry.band(forRows: rows,
                                     cellHeight: Double(cellHeight),
                                     padding: Double(padding))
        setNeedsDisplay(NSRect(x: 0, y: CGFloat(band.minY),
                               width: bounds.width, height: CGFloat(band.height)))
    }

    /// ⌘-click on a URL opens it in the default browser.
    private func openLink(at event: NSEvent) -> Bool {
        let position = gridPosition(at: convert(event.locationInWindow, from: nil))
        let line = emulator.line(position.row)
        guard let hit = LinkDetection.url(in: line, atColumn: position.column),
              let url = URL(string: hit.text) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    /// A program rang the bell. Silent unless the user turned it on in Settings.
    func ringBell() {
        switch AppSettings.store.bellStyle {
        case .none:
            break
        case .sound:
            NSSound.beep()
        case .visual:
            flashBell()
        }
    }

    /// A short, soft flash over the pane — visible without being a strobe.
    private func flashBell() {
        guard bellFlash == nil else { return }       // don't stack flashes
        let flash = NSView(frame: bounds)
        flash.autoresizingMask = [.width, .height]
        flash.wantsLayer = true
        flash.layer?.backgroundColor = foregroundColor.withAlphaComponent(0.18).cgColor
        addSubview(flash)
        bellFlash = flash
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            flash.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.bellFlash?.removeFromSuperview()
            self?.bellFlash = nil
        }
    }

    // MARK: - Find

    /// ⌘F: opens the bar (or refocuses it if already open).
    @objc func openFind(_ sender: Any?) {
        if let bar = findBar {
            bar.focusField()
            return
        }
        let bar = FindBarView()
        bar.onQueryChanged = { [weak self] query in self?.runSearch(query) }
        bar.onNext = { [weak self] in self?.step(forward: true) }
        bar.onPrevious = { [weak self] in self?.step(forward: false) }
        bar.onClose = { [weak self] in self?.closeFind() }
        addSubview(bar)
        findBar = bar
        layoutFindBar()
        bar.focusField()
    }

    @objc func findNext(_ sender: Any?) { step(forward: true) }
    @objc func findPrevious(_ sender: Any?) { step(forward: false) }

    private func closeFind() {
        findBar?.removeFromSuperview()
        findBar = nil
        searchHits = []
        currentHit = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func runSearch(_ query: String) {
        searchHits = TextSearch.matches(of: query, in: emulator.bufferLines(),
                                        caseSensitive: false)
        // Start at the hit nearest the bottom — the newest output is what you
        // are usually looking for.
        currentHit = searchHits.last
        reveal(currentHit)
        updateFindCount()
        needsDisplay = true
    }

    private func step(forward: Bool) {
        guard !searchHits.isEmpty else { return }
        currentHit = forward ? TextSearch.next(after: currentHit, in: searchHits)
                             : TextSearch.previous(before: currentHit, in: searchHits)
        reveal(currentHit)
        updateFindCount()
        needsDisplay = true
    }

    private func reveal(_ hit: SearchMatch?) {
        guard let hit else { return }
        emulator.scrollToReveal(absoluteRow: hit.row)
    }

    private func updateFindCount() {
        let index = currentHit.flatMap { hit in searchHits.firstIndex(of: hit) }
        findBar?.showCount(current: index, total: searchHits.count)
    }

    private func layoutFindBar() {
        guard let bar = findBar else { return }
        let size = bar.intrinsicContentSize
        bar.frame = NSRect(x: max(0, bounds.width - size.width - 12), y: 10,
                           width: size.width, height: size.height)
    }

    // MARK: - Select All

    /// ⌘A: selects everything written, scrollback included.
    @objc override func selectAll(_ sender: Any?) {
        guard let range = emulator.contentRange() else { return }
        selectionStart = range.start
        selectionEnd = range.end
        needsDisplay = true
    }

    // MARK: - Scrolling

    override func scrollWheel(with event: NSEvent) {
        let lines = scrollAccumulator.lines(
            delta: Double(event.scrollingDeltaY),
            precise: event.hasPreciseScrollingDeltas,
            speed: AppSettings.store.scrollSpeed,
            cellHeight: Double(cellHeight))
        guard lines != 0 else { return }

        // A program that tracks the mouse scrolls itself — that is what makes
        // the wheel work properly in less, htop or a mouse-aware vim, instead
        // of the arrow-key approximation below.
        if emulator.mouseTracking != .off, !event.modifierFlags.contains(.shift) {
            let position = gridPosition(at: convert(event.locationInWindow, from: nil))
            let kind: MouseEventKind = lines > 0 ? .scrollUp : .scrollDown
            let modifiers = TerminalView.keyModifiers(for: event.modifierFlags)
            for _ in 0..<abs(lines) {
                emulator.sendMouse(kind, button: .left, modifiers: modifiers,
                                   column: position.column, row: position.row)
            }
            return
        }

        // A full-screen program (less, man, vim, htop) owns the screen and has no
        // scrollback, so moving the viewport would do nothing at all. Send arrow
        // keys instead, so the wheel scrolls the program like in any terminal.
        if emulator.isAlternateScreen {
            let app = emulator.applicationCursorKeys
            let key = lines > 0 ? (app ? "\u{1b}OA" : "\u{1b}[A")
                                : (app ? "\u{1b}OB" : "\u{1b}[B")
            onInput?(Data(String(repeating: key, count: abs(lines)).utf8))
            return
        }

        emulator.scroll(lines: lines)   // positive = toward older output
        // Mid-drag the text under the pointer just changed, so extend the
        // selection to it — that's what "scroll up while selecting" should do.
        if isSelecting {
            selectionEnd = absolute(gridPosition(at: convert(event.locationInWindow, from: nil)))
        }
        needsDisplay = true
    }

    /// Cmd-C: copy the selected text to the clipboard.
    @objc func copy(_ sender: Any?) {
        guard let start = selectionStart, let end = selectionEnd, start != end else { return }
        let text = emulator.text(fromAbsolute: start, toAbsolute: end)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func gridPosition(at point: NSPoint) -> GridPosition {
        let column = Int((point.x - padding) / cellWidth)
        let row = Int((point.y - padding) / cellHeight)
        return GridPosition(row: max(0, min(emulator.rows - 1, row)),
                            column: max(0, min(emulator.columns - 1, column)))
    }

    /// A visible-row position translated to the buffer-absolute one the selection
    /// anchors use, so it survives scrolling.
    private func absolute(_ position: GridPosition) -> GridPosition {
        GridPosition(row: position.row + emulator.scrollOffset, column: position.column)
    }

    /// Amber for every hit, orange for the one you are on — nil when the cell
    /// isn't part of a match.
    private func searchHighlight(row: Int, column: Int) -> NSColor? {
        guard !searchHits.isEmpty else { return nil }
        let absoluteRow = row + emulator.scrollOffset
        guard let hit = searchHits.first(where: {
            $0.row == absoluteRow && column >= $0.column && column < $0.column + $0.length
        }) else { return nil }
        return hit == currentHit
            ? NSColor(srgbRed: 1.0, green: 0.55, blue: 0.10, alpha: 0.55)
            : NSColor(srgbRed: 1.0, green: 0.85, blue: 0.25, alpha: 0.32)
    }

    private func isSelected(row: Int, column: Int) -> Bool {
        guard let s = selectionStart, let e = selectionEnd, s != e else { return false }
        let (start, end) = s <= e ? (s, e) : (e, s)
        let position = GridPosition(row: row + emulator.scrollOffset, column: column)
        return position >= start && position <= end
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportGridSizeIfChanged()
        layoutFindBar()
    }

    // The pane is often sized before it's inserted into the window (session
    // restore builds the split tree first). Report again once it's in, in case
    // that final size never triggers another setFrameSize.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportGridSizeIfChanged()
    }

    private func reportGridSizeIfChanged() {
        let cols = max(1, Int((bounds.width - 2 * padding) / cellWidth))
        let rows = max(1, Int((bounds.height - 2 * padding) / cellHeight))
        // A pane briefly has a near-zero frame while splits are arranged; don't
        // resize the PTY to a sliver there (a program running at shell startup
        // would wrap its output to 1-2 columns and stay wrapped). A usable size
        // gates that. NB: don't also require `window != nil` — the real size is
        // often set before the view is in the window, and skipping it then left
        // the grid stuck at the 80x24 default (cursor frozen mid-pane), because no
        // later setFrameSize re-reported it.
        guard cols >= 10, rows >= 4 else { return }
        guard lastGridSize?.cols != cols || lastGridSize?.rows != rows else { return }
        lastGridSize = (cols, rows)
        onResize?(cols, rows)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()

        // Only the rows AppKit asked for. A chunk of output usually dirties a
        // line or two; redrawing the whole grid pushed every cell through
        // CoreText each time, which is what made a big window feel sluggish
        // under heavy output.
        let visibleRows = GridGeometry.rows(fromY: Double(dirtyRect.minY),
                                            toY: Double(dirtyRect.maxY),
                                            cellHeight: Double(cellHeight),
                                            padding: Double(padding),
                                            totalRows: emulator.rows)
        for row in visibleRows {
            // Round cell edges to whole pixels so adjacent backgrounds tile
            // seamlessly — a fractional cellWidth/Height otherwise leaves thin
            // gridlines between cells (very visible on a full-screen background).
            let y0 = (padding + CGFloat(row) * cellHeight).rounded()
            let y1 = (padding + CGFloat(row + 1) * cellHeight).rounded()

            // Backgrounds and the selection stay per cell: each one can differ.
            var cells: [TerminalCell?] = []
            cells.reserveCapacity(emulator.columns)
            for col in 0..<emulator.columns {
                let cell = emulator.cell(row: row, col: col)
                cells.append(cell)
                // The trailing half of a wide glyph is a width-0 placeholder —
                // the wide cell already painted both halves. Filling it here
                // would repaint background over the glyph's right half.
                guard let cell, cell.width != 0 else { continue }
                let span = cell.width == 2 ? 2 : 1
                let x0 = (padding + CGFloat(col) * cellWidth).rounded()
                let x1 = (padding + CGFloat(col + span) * cellWidth).rounded()
                let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)

                nsColor(cell.background).setFill()
                rect.fill()

                if isSelected(row: row, column: col) {
                    NSColor(srgbRed: 1.0, green: 0.35, blue: 0.65, alpha: 0.45).setFill()
                    rect.fill()
                }
                if let highlight = searchHighlight(row: row, column: col) {
                    highlight.setFill()
                    rect.fill()
                }
            }

            // Text goes out a run at a time instead of a character at a time:
            // one CoreText call for a whole stretch of same-looking cells.
            for run in CellRun.runs(in: cells) {
                draw(run, y: y0)
            }
        }

        drawCursor()
    }

    /// Starts or stops the blink timer to match the program's wish and focus.
    func updateCursorBlink() {
        let wanted = emulator.cursorStyle.blinks && window?.firstResponder === self
        guard wanted != (cursorBlinkTimer != nil) else { return }
        if wanted {
            cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.cursorIsOn.toggle()
                    self.setNeedsDisplay(self.cursorRect())
                }
            }
        } else {
            cursorBlinkTimer?.invalidate()
            cursorBlinkTimer = nil
            cursorIsOn = true
            needsDisplay = true
        }
    }

    /// The cell the cursor sits in.
    private func cursorRect() -> NSRect {
        let cursor = emulator.cursorPosition
        return NSRect(x: padding + CGFloat(cursor.column) * cellWidth,
                      y: padding + CGFloat(cursor.row) * cellHeight,
                      width: cellWidth, height: cellHeight)
    }

    /// Draws one run. `.kern` pins every glyph to the cell grid: the font's own
    /// advance is fractional, so without it a long run would drift away from
    /// the cell backgrounds painted underneath.
    private func draw(_ run: CellRun, y: CGFloat) {
        let font = run.bold ? boldFont : self.font
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor(legibleForeground(run.foreground, on: run.background))
        ]
        if run.italic { attributes[.obliqueness] = 0.2 }
        if run.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if !run.isWide, run.text.count > 1 {
            attributes[.kern] = cellWidth - TerminalView.exactAdvance(of: font)
        }
        let x = (padding + CGFloat(run.startColumn) * cellWidth).rounded()
        (run.text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    private func drawCursor() {
        guard emulator.cursorVisible, !emulator.isScrolledBack else { return }
        guard cursorIsOn || cursorBlinkTimer == nil else { return }
        let cursor = emulator.cursorPosition
        guard cursor.row >= 0, cursor.row < emulator.rows,
              cursor.column >= 0, cursor.column < emulator.columns else { return }
        let cell = CGRect(
            x: padding + CGFloat(cursor.column) * cellWidth,
            y: padding + CGFloat(cursor.row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        // An unfocused pane always shows the hollow block, so you can see at a
        // glance which pane takes your keystrokes.
        guard window?.firstResponder === self else {
            foregroundColor.withAlphaComponent(0.6).setStroke()
            let path = NSBezierPath(rect: cell.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
            return
        }
        // The shape the program asked for (DECSCUSR): vim uses a bar in insert
        // mode. We honor the shape but not the blink — a steady cursor is
        // calmer, and blinking would need a timer per pane.
        let thickness: CGFloat = 2
        let rect: CGRect
        switch emulator.cursorStyle.shape {
        case .block:
            rect = cell
        case .underline:
            rect = CGRect(x: cell.minX, y: cell.maxY - thickness,
                          width: cell.width, height: thickness)
        case .bar:
            rect = CGRect(x: cell.minX, y: cell.minY, width: thickness, height: cell.height)
        }
        let color = emulator.programCursorColor.map { NSColor($0) } ?? foregroundColor
        color.withAlphaComponent(0.6).setFill()
        rect.fill()
    }

    /// One monospace cell's advance, in whole pixels. Measured from a real glyph
    /// ("0") rather than `maximumAdvancement`, which a Nerd Font inflates with its
    /// wide icon glyphs (that made every cell too wide). Rounding to an integer
    /// keeps columns evenly spaced and lets cell backgrounds tile without seams.
    /// The font's real, unrounded advance. `advance(of:)` rounds it to keep the
    /// grid even; the difference is what `.kern` has to make up per glyph.
    private static func exactAdvance(of font: NSFont) -> CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font]).width
    }

    private static func advance(of font: NSFont) -> CGFloat {
        let width = ("0" as NSString).size(withAttributes: [.font: font]).width
        return max(1, width.rounded())
    }

    /// Keeps glyphs legible when a program draws the foreground in (nearly) the
    /// background color. asciiquarium's castle, for example, is BLACK on a black
    /// background and relies on terminals showing it as a faint gray. Only nudges
    /// when the two are almost identical, so normal colors stay untouched.
    private func legibleForeground(_ fg: TermColor, on bg: TermColor) -> TermColor {
        let dr = Int(fg.red) - Int(bg.red)
        let dg = Int(fg.green) - Int(bg.green)
        let db = Int(fg.blue) - Int(bg.blue)
        guard dr * dr + dg * dg + db * db < 30 * 30 else { return fg }
        let bgLuminance = 0.299 * Double(bg.red) + 0.587 * Double(bg.green) + 0.114 * Double(bg.blue)
        let shift = 78
        func nudge(_ value: UInt8) -> UInt8 {
            bgLuminance < 128 ? UInt8(min(255, Int(value) + shift))
                              : UInt8(max(0, Int(value) - shift))
        }
        return TermColor(red: nudge(bg.red), green: nudge(bg.green), blue: nudge(bg.blue))
    }

    private func nsColor(_ color: TermColor) -> NSColor {
        NSColor(srgbRed: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255,
                alpha: 1)
    }
}
