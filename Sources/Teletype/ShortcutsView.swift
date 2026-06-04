import SwiftUI

/// A read-only cheat sheet of the app's keyboard shortcuts.
struct ShortcutsView: View {
    private struct Item: Identifiable {
        let id = UUID()
        let action: String
        let keys: String
    }
    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let items: [Item]
    }

    private let groups: [Group] = [
        Group(title: "Tabs", items: [
            Item(action: "New Tab", keys: "⌘T"),
            Item(action: "New Claude Tab", keys: "⌘E"),
            Item(action: "Go to Tab 1–9", keys: "⌘1 … ⌘9"),
            Item(action: "Last Used Tab", keys: "⌃⇥")
        ]),
        Group(title: "Panes", items: [
            Item(action: "Split Right", keys: "⌘D"),
            Item(action: "Split Down", keys: "⇧⌘D"),
            Item(action: "New Claude Pane", keys: "⇧⌘E"),
            Item(action: "Close Pane", keys: "⌘W"),
            Item(action: "Previous / Next Pane", keys: "⌘[   ⌘]"),
            Item(action: "Focus Pane", keys: "⌥⌘ ← ↑ ↓ →")
        ]),
        Group(title: "Edit", items: [
            Item(action: "Copy", keys: "⌘C"),
            Item(action: "Paste", keys: "⌘V")
        ]),
        Group(title: "App", items: [
            Item(action: "Settings", keys: "⌘,"),
            Item(action: "Quit", keys: "⌘Q")
        ])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.headline)
                        ForEach(group.items) { item in
                            HStack {
                                Text(item.action)
                                Spacer()
                                Text(item.keys)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 420, height: 520)
    }
}
