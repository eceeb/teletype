import AppKit

/// The ⌘F bar: a search field, a hit counter and prev/next/close buttons,
/// floating over the top-right of a pane. Reports what the user types; the
/// pane's view owns the actual searching and highlighting.
@MainActor
final class FindBarView: NSView, NSTextFieldDelegate {
    var onQueryChanged: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    private let field = NSTextField(string: "")
    private let counter = NSTextField(labelWithString: "")

    var query: String { field.stringValue }

    /// Shows "3 of 17", or "not found" for a query with no hits.
    func showCount(current: Int?, total: Int) {
        if field.stringValue.isEmpty {
            counter.stringValue = ""
        } else if total == 0 {
            counter.stringValue = "not found"
        } else {
            counter.stringValue = "\(current.map { $0 + 1 } ?? 0) of \(total)"
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        field.placeholderString = "Find"
        field.font = .systemFont(ofSize: 12)
        field.delegate = self
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none

        counter.font = .systemFont(ofSize: 11)
        counter.textColor = .secondaryLabelColor
        counter.alignment = .right

        let previous = button("chevron.up", #selector(previousClicked))
        let next = button("chevron.down", #selector(nextClicked))
        let close = button("xmark", #selector(closeClicked))

        for view in [field, counter, previous, next, close] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 170),

            counter.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
            counter.centerYAnchor.constraint(equalTo: centerYAnchor),
            counter.widthAnchor.constraint(equalToConstant: 70),

            previous.leadingAnchor.constraint(equalTo: counter.trailingAnchor, constant: 4),
            previous.centerYAnchor.constraint(equalTo: centerYAnchor),
            next.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 2),
            next.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.leadingAnchor.constraint(equalTo: next.trailingAnchor, constant: 6),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 380, height: 34) }

    /// Puts the caret in the field and selects whatever is there, so typing
    /// replaces the previous query.
    func focusField() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func button(_ symbol: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                              ?? NSImage(), target: self, action: action)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        return button
    }

    @objc private func nextClicked() { onNext?() }
    @objc private func previousClicked() { onPrevious?() }
    @objc private func closeClicked() { onClose?() }

    func controlTextDidChange(_ notification: Notification) {
        onQueryChanged?(field.stringValue)
    }

    /// Return jumps to the next hit (Shift-Return to the previous), Escape closes.
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { onPrevious?() }
            else { onNext?() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}
