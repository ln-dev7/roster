import XCTest

/// The settings merge — the one place Roster writes into a file it does not
/// own, so it gets the paranoid treatment: additive, idempotent, and
/// everything foreign preserved bit for bit.
final class HookInstallerTests: XCTestCase {

    func testMergingEmptySettingsAddsAllSixEvents() {
        let merged = HookInstaller.merged([:])
        let hooks = merged["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks)
        for name in HookInstaller.eventNames {
            XCTAssertTrue(HookInstaller.isInstalled(in: merged),
                          "missing marker after merge")
            XCTAssertNotNil(hooks?[name], "no entry for \(name)")
        }
    }

    func testMergePreservesForeignHooksAndSettings() {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": [
                "Stop": [
                    ["matcher": "", "hooks": [["type": "command", "command": "say done"]]]
                ]
            ],
        ]

        let merged = HookInstaller.merged(existing)

        // Unrelated top-level settings survive.
        XCTAssertEqual(merged["model"] as? String, "opus")

        // The foreign Stop hook is still first; ours is appended after it.
        let stopEntries = (merged["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stopEntries?.count, 2)
        let firstCommand = ((stopEntries?.first?["hooks"] as? [[String: Any]])?
            .first?["command"]) as? String
        XCTAssertEqual(firstCommand, "say done")
    }

    func testMergeIsIdempotent() {
        let once = HookInstaller.merged([:])
        let twice = HookInstaller.merged(once)
        XCTAssertTrue((once as NSDictionary).isEqual(to: twice),
                      "installing twice must change nothing")
    }

    func testIsInstalledDetection() {
        XCTAssertFalse(HookInstaller.isInstalled(in: [:]))
        XCTAssertTrue(HookInstaller.isInstalled(in: HookInstaller.merged([:])))

        // Partial installs (a user removed one event) count as not
        // installed, so a reinstall completes the set.
        var partial = HookInstaller.merged([:])
        var hooks = partial["hooks"] as? [String: Any]
        hooks?["Stop"] = nil
        partial["hooks"] = hooks as Any
        XCTAssertFalse(HookInstaller.isInstalled(in: partial))
    }

    func testInstallOnDiskBacksUpAndWrites() throws {
        // A throwaway directory stands in for ~/.claude.
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "roster-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "settings.json")
        try Data(#"{"model":"opus"}"#.utf8).write(to: url)

        try HookInstaller.install(at: url)

        // Installed, previous content preserved, backup created.
        XCTAssertTrue(HookInstaller.isInstalled(at: url))
        let settings = try HookInstaller.loadSettings(at: url)
        XCTAssertEqual(settings["model"] as? String, "opus")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains("roster-backup") }
        XCTAssertEqual(backups.count, 1)

        // Reinstalling over a complete install is a no-op: no second backup.
        try HookInstaller.install(at: url)
        let backupsAfter = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains("roster-backup") }
        XCTAssertEqual(backupsAfter.count, 1)
    }

    func testCorruptSettingsAreNeverTouched() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "roster-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "settings.json")
        try Data("{ this is not json".utf8).write(to: url)

        XCTAssertThrowsError(try HookInstaller.install(at: url))

        // The broken file is exactly as we found it.
        let content = String(data: try Data(contentsOf: url), encoding: .utf8)
        XCTAssertEqual(content, "{ this is not json")
    }
}
