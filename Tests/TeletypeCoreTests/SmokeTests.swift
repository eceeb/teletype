import Testing

struct SmokeTests {
    @Test func harnessRuns() {
        #expect(1 + 1 == 2)
    }
}
