import XCTest

/// Discovery of Claude config roots — the multi-account story.
final class ClaudeConfigRootsTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appending(path: "roster-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeDir(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: home.appending(path: path), withIntermediateDirectories: true
        )
    }

    func testFindsEveryClaudeStyleRootAndNothingElse() throws {
        // The default account and two alias accounts.
        try makeDir(".claude/projects")
        try makeDir(".claude-pro")
        try Data("{}".utf8).write(to: home.appending(path: ".claude-pro/settings.json"))
        try makeDir(".claude-perso-danger/projects")

        // Distractors: a plain file, an unrelated tool's folder without
        // projects/ or settings.json, and a normal directory.
        try Data("{}".utf8).write(to: home.appending(path: ".claude.json"))
        try makeDir(".claude-unrelated-tool")
        try makeDir("Documents")

        let roots = ClaudeConfigRoots.discover(home: home, extraPaths: [])
        let names = roots.map(\.lastPathComponent).sorted()

        XCTAssertEqual(names, [".claude", ".claude-perso-danger", ".claude-pro"])
    }

    func testUserAddedFoldersJoinTheListWhereverTheyLive() throws {
        try makeDir(".claude/projects")
        let elsewhere = home.appending(path: "configs/claude-work")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)

        let roots = ClaudeConfigRoots.discover(home: home, extraPaths: [elsewhere.path])

        XCTAssertTrue(roots.contains { $0.path == elsewhere.path })
        XCTAssertEqual(roots.count, 2)
    }

    func testMissingExtraFoldersAreSkipped() throws {
        try makeDir(".claude/projects")
        let roots = ClaudeConfigRoots.discover(
            home: home,
            extraPaths: [home.appending(path: "does-not-exist").path]
        )
        XCTAssertEqual(roots.count, 1)
    }
}
