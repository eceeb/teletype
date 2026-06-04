import SwiftUI
import TeletypeCore

/// The settings window contents. Edits write straight to the shared store and
/// post a change notification so open panes update live.
struct SettingsView: View {
    @State private var fontSize = AppSettings.store.fontSize
    @State private var background = Color(nsColor: NSColor(AppSettings.store.backgroundColor))
    @State private var foreground = Color(nsColor: NSColor(AppSettings.store.foregroundColor))
    @State private var shell = AppSettings.store.shell ?? ""
    @State private var tabsOnLeft = (AppSettings.store.tabPlacement == "left")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Font size")
                Slider(value: $fontSize, in: 8...28, step: 1)
                Text("\(Int(fontSize)) pt")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            ColorPicker("Background", selection: $background, supportsOpacity: false)
            ColorPicker("Text", selection: $foreground, supportsOpacity: false)
            HStack {
                Text("Shell")
                TextField("$SHELL (default)", text: $shell)
            }
            HStack {
                Text("Tabs")
                Picker("", selection: $tabsOnLeft) {
                    Text("Top").tag(false)
                    Text("Left").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Divider()
            Button("Keyboard Shortcuts…") {
                NSApp.sendAction(#selector(AppDelegate.openShortcuts(_:)), to: nil, from: nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onChange(of: fontSize) { _, value in
            AppSettings.store.fontSize = value
            AppSettings.notifyChanged()
        }
        .onChange(of: background) { _, value in
            AppSettings.store.backgroundColor = TermColor(NSColor(value))
            AppSettings.notifyChanged()
        }
        .onChange(of: foreground) { _, value in
            AppSettings.store.foregroundColor = TermColor(NSColor(value))
            AppSettings.notifyChanged()
        }
        .onChange(of: shell) { _, value in
            AppSettings.store.shell = value.isEmpty ? nil : value
            AppSettings.notifyChanged()
        }
        .onChange(of: tabsOnLeft) { _, value in
            AppSettings.store.tabPlacement = value ? "left" : "top"
            AppSettings.notifyChanged()
        }
    }
}
