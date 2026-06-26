import Foundation
import Testing
@testable import TeletypeCore

@Test func sessionLayoutSurvivesEncodeDecode() throws {
    let layout = SessionLayout(tabs: [
        SavedTab(name: nil, root: .leaf(cwd: "/Users/elce")),
        SavedTab(name: "Work", root: .split(vertical: true, children: [
            .leaf(cwd: "/Users/elce/c/mailing-editor/frontend"),
            .split(vertical: false, children: [
                .leaf(cwd: "/Users/elce/c/mailing-editor/backend"),
                .leaf(cwd: nil)
            ])
        ]))
    ])

    let data = try #require(layout.encoded())
    let restored = SessionLayout.decoded(from: data)

    #expect(restored == layout)
}

@Test func editedTabNameSurvivesEncodeDecode() throws {
    let layout = SessionLayout(tabs: [SavedTab(name: "Deploys", root: .leaf(cwd: "/tmp"))])
    let restored = SessionLayout.decoded(from: try #require(layout.encoded()))
    #expect(restored?.tabs.first?.name == "Deploys")
}

/// Sessions saved before tab names existed stored each tab as a bare PaneNode.
@Test func legacyLayoutWithoutNamesStillDecodes() throws {
    let legacyJSON = #"{"tabs":[{"leaf":{"cwd":"/Users/elce"}}]}"#
    let restored = SessionLayout.decoded(from: Data(legacyJSON.utf8))
    #expect(restored?.tabs.first?.name == nil)
    #expect(restored?.tabs.first?.root == .leaf(cwd: "/Users/elce"))
}
