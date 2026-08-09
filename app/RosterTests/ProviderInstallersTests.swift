import XCTest

/// The pure merge logic of the Gemini / Cursor / Codex installers.
/// Only the dictionary functions are tested — the file I/O paths write
/// into real home-directory configs and helper scripts, exactly what a
/// test suite must never touch (same reasoning as HookInstallerTests).
final class ProviderInstallersTests: XCTestCase {

    // MARK: Gemini

    func testGeminiMergeAddsEveryEventAndKeepsForeignHooks() {
        let existing: [String: Any] = [
            "theme": "dark",
            "hooks": [
                "BeforeTool": [
                    ["matcher": "write_file",
                     "hooks": [["type": "command", "command": "/usr/local/bin/lint"]]],
                ],
            ],
        ]

        let merged = GeminiInstaller.merged(existing)

        XCTAssertTrue(GeminiInstaller.isInstalled(in: merged))
        XCTAssertEqual(merged["theme"] as? String, "dark",
                       "unrelated settings pass through")
        let hooks = merged["hooks"] as? [String: Any]
        let foreign = hooks?["BeforeTool"] as? [[String: Any]]
        XCTAssertEqual(foreign?.count, 1, "foreign hooks survive")
        for event in GeminiInstaller.events {
            XCTAssertNotNil(hooks?[event], "\(event) must be wired")
        }
    }

    func testGeminiMergeIsSelfHealing() {
        let once = GeminiInstaller.merged([:])
        let twice = GeminiInstaller.merged(once)
        let hooks = twice["hooks"] as? [String: Any]
        for event in GeminiInstaller.events {
            let entries = hooks?[event] as? [[String: Any]] ?? []
            XCTAssertEqual(entries.count, 1,
                           "re-installing must not duplicate \(event)")
        }
    }

    // MARK: Cursor

    func testCursorMergeVersionsTheFileAndKeepsForeignCommands() {
        let existing: [String: Any] = [
            "hooks": [
                "afterFileEdit": [["command": "hooks/audit.sh"]],
                "stop": [["command": "notify-me"]],
            ],
        ]

        let merged = CursorInstaller.merged(existing)

        XCTAssertTrue(CursorInstaller.isInstalled(in: merged))
        XCTAssertEqual(merged["version"] as? Int, 1)
        let hooks = merged["hooks"] as? [String: Any]
        let stop = hooks?["stop"] as? [[String: Any]] ?? []
        XCTAssertEqual(stop.count, 2, "the foreign stop hook survives next to ours")
        let audit = hooks?["afterFileEdit"] as? [[String: Any]] ?? []
        XCTAssertEqual(audit.count, 1, "events Roster doesn't use pass through")
    }

    func testCursorMergeIsSelfHealing() {
        let twice = CursorInstaller.merged(CursorInstaller.merged([:]))
        let hooks = twice["hooks"] as? [String: Any]
        for event in CursorInstaller.events {
            XCTAssertEqual((hooks?[event] as? [[String: Any]])?.count, 1)
        }
    }

    // MARK: Codex

    func testCodexRecognizesAForeignNotify() {
        XCTAssertTrue(CodexInstaller.hasForeignNotify(
            in: "model = \"o4\"\nnotify = [\"/usr/local/bin/ding\"]\n"
        ))
        XCTAssertFalse(CodexInstaller.hasForeignNotify(
            in: "model = \"o4\"\n"
        ))
        XCTAssertFalse(CodexInstaller.hasForeignNotify(
            in: "notify = [\"/Users/me/.roster/roster-hook.sh\", \"codex\"]\n"
        ), "our own notify is not foreign")
        XCTAssertFalse(CodexInstaller.hasForeignNotify(
            in: "# notify = [\"commented-out\"]\n"
        ), "a commented notify is no notify")
    }
}
