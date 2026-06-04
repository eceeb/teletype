import Testing
@testable import TeletypeCore

@Test func sharedRootBecomesHeaderWithPathsBelow() {
    let result = PaneGrouping.summarize([
        "/Users/elce/e/teletype",
        "/Users/elce/e/teletype/Tests"
    ])
    #expect(result.header == "e")
    #expect(result.labels == ["teletype", "teletype/Tests"])
}

@Test func siblingFoldersShareTheirParent() {
    let result = PaneGrouping.summarize([
        "/Users/elce/c/mailing-editor/frontend",
        "/Users/elce/c/mailing-editor/backend"
    ])
    #expect(result.header == "mailing-editor")
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
        "/Users/elce/e/teletype",
        "/tmp/foo"
    ])
    #expect(result.header == nil)
    #expect(result.labels == ["e/teletype", "tmp/foo"])
}

@Test func singlePaneHasNoHeader() {
    let result = PaneGrouping.summarize(["/Users/elce/e/teletype"])
    #expect(result.header == nil)
    #expect(result.labels == ["e/teletype"])
}
