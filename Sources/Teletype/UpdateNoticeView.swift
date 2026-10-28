import AppKit
import TeletypeCore

/// The update hint at the bottom of the sidebar: a small badge, a title and a
/// line of detail. Clicking it opens the full report.
@MainActor
final class UpdateNoticeView: NSView {
    var onClick: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "↑")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        badge.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.lineBreakMode = .byTruncatingTail

        for label in [badge, titleLabel, detailLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Fills the notice, or hides it when there is nothing to report.
    func show(_ notice: UpdateNotice.Text?, foreground: NSColor?) {
        guard let notice else {
            isHidden = true
            return
        }
        isHidden = false
        titleLabel.stringValue = notice.title
        detailLabel.stringValue = notice.detail
        let color = foreground ?? .labelColor
        titleLabel.textColor = color
        detailLabel.textColor = color.withAlphaComponent(0.65)
        badge.textColor = color.withAlphaComponent(0.8)
        toolTip = "\(notice.title) — \(notice.detail). Click for details."
    }

    /// Drawn rather than set as a layer background: `layer` is still nil while
    /// init runs, so assigning a colour there silently does nothing.
    override func draw(_ dirtyRect: NSRect) {
        // Muted amber — visible against the sidebar without shouting, and not a
        // colour the pane groups already use.
        NSColor(srgbRed: 0.52, green: 0.38, blue: 0.18, alpha: 0.30).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
