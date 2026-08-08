import Foundation

/// Installs Roster's hook into `~/.claude/settings.json`.
///
/// This is the app's only invasive act, so it is deliberately boring:
///
///   • the hook is one shell command that appends the event JSON to
///     Roster's spool file — no server, no network, works while Roster
///     is closed;
///   • the merge is additive and idempotent: everything already in the
///     file is preserved, and installing twice changes nothing;
///   • a timestamped backup of the file is written next to it before the
///     first modification.
///
/// The pure dictionary functions are separated from the file I/O so the
/// merge logic is unit-tested without touching a real home directory.
enum HookInstaller {

    /// The six events the room feeds on.
    static let eventNames = [
        "SessionStart", "UserPromptSubmit", "Notification",
        "Stop", "StopFailure", "SessionEnd",
    ]

    /// The spool path appears verbatim in the command — it doubles as the
    /// marker by which we recognize our own entries.
    static let spoolMarker = "Roster/events.jsonl"

    /// Appends stdin (the hook payload) to the spool, creating the folder
    /// on first use. `$HOME` is expanded by the shell at event time.
    static let command = #"/bin/sh -c 'mkdir -p "$HOME/Library/Application Support/Roster" && /bin/cat >> "$HOME/Library/Application Support/Roster/events.jsonl"'"#

    // MARK: Pure merge logic (unit-tested)

    /// True when every event Roster needs already carries our command.
    static func isInstalled(in root: [String: Any]) -> Bool {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return eventNames.allSatisfy { name in
            containsMarker(hooks[name] as? [[String: Any]] ?? [])
        }
    }

    /// Returns `root` with Roster's entries added where missing. Foreign
    /// hooks and unrelated settings pass through untouched.
    static func merged(_ root: [String: Any]) -> [String: Any] {
        var result = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for name in eventNames {
            var entries = hooks[name] as? [[String: Any]] ?? []
            if !containsMarker(entries) {
                entries.append([
                    "hooks": [
                        ["type": "command", "command": command, "timeout": 10]
                    ]
                ])
            }
            hooks[name] = entries
        }

        result["hooks"] = hooks
        return result
    }

    private static func containsMarker(_ entries: [[String: Any]]) -> Bool {
        for entry in entries {
            for hook in entry["hooks"] as? [[String: Any]] ?? [] {
                if let command = hook["command"] as? String, command.contains(spoolMarker) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: File I/O

    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/settings.json")
    }

    /// Reads the settings file (missing file = empty settings).
    /// Throws when the file exists but isn't a JSON object — in that case
    /// we must NOT touch it.
    static func loadSettings(at url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return object
    }

    /// Backup → merge → atomic write. Safe to call when already installed.
    static func install(at url: URL = defaultSettingsURL) throws {
        let settings = try loadSettings(at: url)
        guard !isInstalled(in: settings) else { return }

        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)

        // One backup per install attempt, timestamped, never overwritten.
        if fm.fileExists(atPath: url.path) {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent()
                .appending(path: "settings.json.roster-backup-\(stamp)")
            try? fm.copyItem(at: url, to: backup)
        }

        let data = try JSONSerialization.data(
            withJSONObject: merged(settings),
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    /// Convenience for the UI: current install state on disk.
    static func isInstalled(at url: URL = defaultSettingsURL) -> Bool {
        guard let settings = try? loadSettings(at: url) else { return false }
        return isInstalled(in: settings)
    }

    enum InstallError: Error, LocalizedError {
        case unreadableSettings
        var errorDescription: String? {
            "~/.claude/settings.json exists but is not valid JSON — not touching it."
        }
    }
}
