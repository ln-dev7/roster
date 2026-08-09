import Foundation

/// Installs Roster's hooks into `~/.claude/settings.json`.
///
/// This is the app's only invasive act, so it is deliberately boring:
///
///   • each hook is one shell command that appends the event JSON to
///     Roster's spool file — no server, no network, works while Roster
///     is closed;
///   • `Notification` hooks are registered once per matcher, and each
///     command *tags* the line with its matcher (a tiny sed insert), so
///     Roster never has to guess the notification type from the payload;
///   • the merge first strips every previous Roster entry, then adds the
///     current set — additive for everything foreign, self-healing for us
///     (old installs upgrade in place);
///   • a timestamped backup of the file is written next to it before the
///     first modification.
///
/// The pure dictionary functions are separated from the file I/O so the
/// merge logic is unit-tested without touching a real home directory.
enum HookInstaller {

    /// The spool path appears verbatim in every command — it doubles as
    /// the marker by which we recognize our own entries, whatever their
    /// version.
    static let spoolMarker = "Roster/events.jsonl"

    /// Bumped when the installed command set changes; an install carrying
    /// an older tag reads as "not installed" and gets upgraded in place.
    static let versionTag = "#roster-v2"

    private static let spoolDir = "$HOME/Library/Application Support/Roster"
    private static let spoolFile = "\(spoolDir)/events.jsonl"

    /// Plain events: append stdin as-is. Claude Code runs hook commands
    /// through a shell, so `&&`, quotes and the trailing comment are fine.
    static let plainEvents = [
        "SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd",
    ]

    static let plainCommand =
        "mkdir -p \"\(spoolDir)\" && /bin/cat >> \"\(spoolFile)\" \(versionTag)"

    /// Notification matchers Roster cares about. Each gets its own hook
    /// entry whose command injects `"roster_matcher":"<type>"` into the
    /// JSON line before appending it.
    static let notificationMatchers = [
        "agent_needs_input", "permission_prompt", "idle_prompt", "agent_completed",
    ]

    static func notificationCommand(matcher: String) -> String {
        "mkdir -p \"\(spoolDir)\" && /usr/bin/sed -e 's/^{/{\"roster_matcher\":\"\(matcher)\",/' >> \"\(spoolFile)\" \(versionTag)"
    }

    // MARK: Pure merge logic (unit-tested)

    /// True when the file carries the complete, current Roster hook set.
    static func isInstalled(in root: [String: Any]) -> Bool {
        let hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in plainEvents {
            let entries = hooks[event] as? [[String: Any]] ?? []
            guard commands(in: entries).contains(where: isCurrentRosterCommand) else {
                return false
            }
        }

        let notification = hooks["Notification"] as? [[String: Any]] ?? []
        for matcher in notificationMatchers {
            let matched = notification.filter { ($0["matcher"] as? String) == matcher }
            guard commands(in: matched).contains(where: isCurrentRosterCommand) else {
                return false
            }
        }
        return true
    }

    /// Returns `root` with the previous Roster entries removed and the
    /// current set added. Foreign hooks and unrelated settings pass
    /// through untouched.
    static func merged(_ root: [String: Any]) -> [String: Any] {
        var result = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        // Strip every entry of ours — any version — from every event.
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries = entries.compactMap { entry in
                var entry = entry
                let kept = (entry["hooks"] as? [[String: Any]] ?? []).filter {
                    !(($0["command"] as? String)?.contains(spoolMarker) ?? false)
                }
                if kept.isEmpty { return nil }
                entry["hooks"] = kept
                return entry
            }
            hooks[event] = entries.isEmpty ? nil : entries
        }

        // Add the current set.
        for event in plainEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.append(entry(command: plainCommand))
            hooks[event] = entries
        }
        var notification = hooks["Notification"] as? [[String: Any]] ?? []
        for matcher in notificationMatchers {
            var item = entry(command: notificationCommand(matcher: matcher))
            item["matcher"] = matcher
            notification.append(item)
        }
        hooks["Notification"] = notification

        result["hooks"] = hooks
        return result
    }

    private static func entry(command: String) -> [String: Any] {
        ["hooks": [["type": "command", "command": command, "timeout": 10]]]
    }

    private static func commands(in entries: [[String: Any]]) -> [String] {
        entries.flatMap { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).compactMap {
                $0["command"] as? String
            }
        }
    }

    private static func isCurrentRosterCommand(_ command: String) -> Bool {
        command.contains(spoolMarker) && command.contains(versionTag)
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
