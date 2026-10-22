import Testing
@testable import TeletypeCore

@Test func sharedRootBecomesHeaderWithPathsBelow() {
    let result = PaneGrouping.summarize([
        "/Users/dev/code/teletype",
        "/Users/dev/code/teletype/Tests"
    ])
    #expect(result.header == "code")
    #expect(result.labels == ["teletype", "teletype/Tests"])
}

@Test func siblingFoldersShareTheirParent() {
    let result = PaneGrouping.summarize([
        "/Users/dev/code/acme-shop/frontend",
        "/Users/dev/code/acme-shop/backend"
    ])
    #expect(result.header == "acme-shop")
    #expect(result.labels == ["frontend", "backend"])
}

@Test func threePanesUseDeepestCommonRoot() {
    let result = PaneGrouping.summarize([
        "/p/proj/a", "/p/proj/b", "/p/proj/c"
    ])
    #expect(result.header == "proj")
    #expect(result.labels == ["a", "b", "c"])
}

@Test func noSharedRootFallsBackToParentCurrent() {
    let result = PaneGrouping.summarize([
        "/Users/dev/code/teletype",
        "/tmp/foo"
    ])
    #expect(result.header == nil)
    #expect(result.labels == ["code/teletype", "tmp/foo"])
}

@Test func singlePaneHasNoHeader() {
    let result = PaneGrouping.summarize(["/Users/dev/code/teletype"])
    #expect(result.header == nil)
    #expect(result.labels == ["code/teletype"])
}
