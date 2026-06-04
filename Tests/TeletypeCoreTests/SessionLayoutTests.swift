import Foundation
import Testing
@testable import TeletypeCore

@Test func sessionLayoutSurvivesEncodeDecode() throws {
    let layout = SessionLayout(tabs: [
        .leaf(cwd: "/Users/elce"),
        .split(vertical: true, children: [
            .leaf(cwd: "/Users/elce/c/mailing-editor/frontend"),
            .split(vertical: false, children: [
                .leaf(cwd: "/Users/elce/c/mailing-editor/backend"),
                .leaf(cwd: nil)
            ])
        ])
    ])

    let data = try #require(layout.encoded())
    let restored = SessionLayout.decoded(from: data)

    #expect(restored == layout)
}
