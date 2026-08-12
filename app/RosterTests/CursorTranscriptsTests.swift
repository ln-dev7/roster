import XCTest

/// Pure helpers for Cursor IDE transcript presence — never touches the
/// real `~/.cursor` tree.
final class CursorTranscriptsTests: XCTestCase {

    func testWorkspacePathRequiresAnExistingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "roster-cursor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Build a slug from the temp path the same way Cursor encodes
        // workspaces: strip the leading slash, swap `/` for `-`.
        let slug = String(dir.path.dropFirst()).replacingOccurrences(of: "/", with: "-")
        XCTAssertEqual(CursorTranscripts.workspacePath(fromProjectSlug: slug), dir.path)

        XCTAssertNil(CursorTranscripts.workspacePath(fromProjectSlug: "Users-nobody-no-such-path"),
                     "ambiguous or missing paths must yield nil")
        XCTAssertNil(CursorTranscripts.workspacePath(fromProjectSlug: ""))
    }

    func testWarmParentTranscriptsSkipSubagentsAndColdFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appending(path: "roster-cursor-projects-\(UUID().uuidString)")
        let workspace = fm.temporaryDirectory
            .appending(path: "roster-ws-\(UUID().uuidString)")
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: workspace)
        }

        let slug = String(workspace.path.dropFirst()).replacingOccurrences(of: "/", with: "-")
        let conversation = root
            .appending(path: slug)
            .appending(path: "agent-transcripts")
            .appending(path: "conv-1")
        try fm.createDirectory(at: conversation, withIntermediateDirectories: true)

        let parent = conversation.appending(path: "conv-1.jsonl")
        try Data("{}\n".utf8).write(to: parent)

        let subagents = conversation.appending(path: "subagents")
        try fm.createDirectory(at: subagents, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: subagents.appending(path: "child.jsonl"))

        let coldConversation = root
            .appending(path: slug)
            .appending(path: "agent-transcripts")
            .appending(path: "conv-old")
        try fm.createDirectory(at: coldConversation, withIntermediateDirectories: true)
        let cold = coldConversation.appending(path: "conv-old.jsonl")
        try Data("{}\n".utf8).write(to: cold)
        let old = Date().addingTimeInterval(-3600)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: cold.path)

        let hits = CursorTranscripts.warmParentTranscripts(
            under: root, aliveWindow: 300, now: Date()
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].key, "cursor:conv-1")
        XCTAssertEqual(hits[0].cwd, workspace.path)
        // Directory enumeration resolves /var to /private/var; the same
        // file either way.
        XCTAssertEqual(hits[0].url.resolvingSymlinksInPath(),
                       parent.resolvingSymlinksInPath())
    }
}
