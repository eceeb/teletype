import Foundation
import Testing
@testable import TeletypeCore

@Test func sessionLayoutSurvivesEncodeDecode() throws {
    let layout = SessionLayout(tabs: [
        .leaf(cwd: "/Users/dev"),
        .split(vertical: true, children: [
            .leaf(cwd: "/Users/dev/code/acme-shop/frontend"),
            .split(vertical: false, children: [
                .leaf(cwd: "/Users/dev/code/acme-shop/backend"),
                .leaf(cwd: nil)
            ])
        ])
    ])

    let data = try #require(layout.encoded())
    let restored = SessionLayout.decoded(from: data)

    #expect(restored == layout)
}
