import Foundation

// MARK: - Multi-provider wiring
//
// Every tool feeds the SAME spool file, each line tagged with its
// provider ("roster_provider":"gemini"|"cursor"|"codex") so the parser
// (ClaudeEvent.swift) can namespace session keys and pick a payload
// dialect. Claude Code keeps its original inline hooks (HookInstaller);
// the three tools below go through one shared helper script instead,
// because unlike Claude Code, none of them documents that hook commands
// run through a shell — a plain argv exec must work too.
//
// The verified facts these installers encode (see docs/providers.md for
// sources, all checked August 2026):
//
//   • Gemini CLI: hooks in ~/.gemini/settings.json under
//     hooks.<Event>[].hooks[] with {type:"command", command}; payload on
//     stdin with snake_case session_id/cwd/transcript_path; stdout must
//     be nothing but a final JSON object (the script prints "{}").
//   • Cursor: ~/.cursor/hooks.json, {"version":1, "hooks":{event:
//     [{"command": ...}]}}; payload on stdin with conversation_id and
//     workspace_roots; beforeSubmitPrompt/stop are informational, their
//     stdout is ignored.
//   • Codex: `notify = [argv...]` in ~/.codex/config.toml — ONE program,
//     called with the event JSON as the final ARGUMENT (not stdin),
//     single event type "agent-turn-complete".
//
// All of this is fresh territory: each installer is deliberately timid —
// backup first, additive merges, refuse rather than guess.

// MARK: The shared helper script

/// Writes `~/.roster/roster-hook.sh`, the one program every non-Claude
/// tool calls. Deliberately in a path with NO SPACES ("Application
/// Support" would break naive argv splitting in tools that don't use a
/// shell). The script tags the event with its provider and appends it to
/// the spool — stdin for hooks (Gemini, Cursor), $2 for Codex's notify.
enum HelperScript {

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".roster/roster-hook.sh")
    }

    static var contents: String {
        """
        #!/bin/sh
        # Roster's event relay (installed by Roster.app — safe to delete;
        # Roster reinstalls it on the next Connect).
        # $1 = provider tag. The event JSON arrives on stdin (hooks) or as
        # $2 (Codex notify). One JSON line is appended to Roster's spool.
        dir="$HOME/Library/Application Support/Roster"
        mkdir -p "$dir"
        if [ -n "$2" ]; then
          payload="$2"
        else
          # $( ) strips trailing newlines. That's the point: Gemini CLI
          # writes its payload WITHOUT one (verified live), and a missing
          # newline would glue two events onto a single spool line.
          payload=$(cat)
        fi
        [ -n "$payload" ] && printf '%s\\n' "$payload" | /usr/bin/sed -e "s/^{/{\\"roster_provider\\":\\"$1\\",/" >> "$dir/events.jsonl"
        # Gemini requires hook stdout to be nothing but JSON; everyone
        # else ignores stdout. An empty object satisfies both.
        printf '{}\\n'
        """
    }

    static var isInstalled: Bool {
        (try? String(contentsOf: url, encoding: .utf8)) == contents
    }

    /// Idempotent: rewrites only when missing or outdated, always 0755.
    static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        if (try? String(contentsOf: url, encoding: .utf8)) != contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// The command string configs point at, e.g. "…/roster-hook.sh gemini".
    static func command(provider: String) -> String {
        "\(url.path) \(provider)"
    }
}

// MARK: - Gemini CLI

/// Hooks into `~/.gemini/settings.json` — same spirit as Claude Code's
/// HookInstaller, adapted to Gemini's schema (entries carry a nested
/// `hooks` array and a millisecond timeout).
enum GeminiInstaller {

    static let events = [
        "SessionStart", "BeforeAgent", "AfterAgent", "Notification", "SessionEnd",
    ]

    /// Our entries are recognized by the helper-script path they call.
    static let marker = ".roster/roster-hook.sh"

    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".gemini/settings.json")
    }

    /// The tool is "present" when its config folder exists.
    static var toolDetected: Bool {
        FileManager.default.fileExists(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".gemini").path
        )
    }

    // Pure merge logic (unit-tested), mirroring HookInstaller.

    static func isInstalled(in root: [String: Any]) -> Bool {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            let entries = hooks[event] as? [[String: Any]] ?? []
            let commands = entries.flatMap { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).compactMap {
                    $0["command"] as? String
                }
            }
            guard commands.contains(where: { $0.contains(marker) }) else {
                return false
            }
        }
        return true
    }

    static func merged(_ root: [String: Any]) -> [String: Any] {
        var result = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        // Strip our previous entries, keep everything foreign.
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries = entries.compactMap { entry in
                var entry = entry
                let kept = (entry["hooks"] as? [[String: Any]] ?? []).filter {
                    !(($0["command"] as? String)?.contains(marker) ?? false)
                }
                if kept.isEmpty { return nil }
                entry["hooks"] = kept
                return entry
            }
            hooks[event] = entries.isEmpty ? nil : entries
        }

        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.append([
                "hooks": [[
                    "name": "roster",
                    "type": "command",
                    "command": HelperScript.command(provider: "gemini"),
                    "timeout": 10000,
                ]],
            ])
            hooks[event] = entries
        }
        result["hooks"] = hooks
        return result
    }

    static func isInstalled(at url: URL = defaultSettingsURL) -> Bool {
        guard HelperScript.isInstalled,
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return isInstalled(in: root)
    }

    static func install(at url: URL = defaultSettingsURL) throws {
        try HelperScript.install()
        let root = try loadJSONObject(at: url, toolName: "Gemini CLI")
        guard !isInstalled(in: root) else { return }
        try backup(url)
        let data = try JSONSerialization.data(
            withJSONObject: merged(root), options: [.prettyPrinted, .sortedKeys]
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Cursor

/// Hooks into `~/.cursor/hooks.json` — flat command entries under a
/// versioned root. Only the two informational hooks Roster needs; the
/// gating hooks (beforeShellExecution & co) are deliberately left alone,
/// because a wrong answer there would break the user's Cursor.
enum CursorInstaller {

    static let events = ["beforeSubmitPrompt", "stop"]
    static let marker = ".roster/roster-hook.sh"

    static var defaultHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cursor/hooks.json")
    }

    static var toolDetected: Bool {
        FileManager.default.fileExists(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".cursor").path
        )
    }

    static func isInstalled(in root: [String: Any]) -> Bool {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            let entries = hooks[event] as? [[String: Any]] ?? []
            let commands = entries.compactMap { $0["command"] as? String }
            guard commands.contains(where: { $0.contains(marker) }) else {
                return false
            }
        }
        return true
    }

    static func merged(_ root: [String: Any]) -> [String: Any] {
        var result = root
        result["version"] = result["version"] ?? 1
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries = entries.filter {
                !(($0["command"] as? String)?.contains(marker) ?? false)
            }
            hooks[event] = entries.isEmpty ? nil : entries
        }
        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.append(["command": HelperScript.command(provider: "cursor")])
            hooks[event] = entries
        }
        result["hooks"] = hooks
        return result
    }

    static func isInstalled(at url: URL = defaultHooksURL) -> Bool {
        guard HelperScript.isInstalled,
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return isInstalled(in: root)
    }

    static func install(at url: URL = defaultHooksURL) throws {
        try HelperScript.install()
        let root = try loadJSONObject(at: url, toolName: "Cursor")
        guard !isInstalled(in: root) else { return }
        try backup(url)
        let data = try JSONSerialization.data(
            withJSONObject: merged(root), options: [.prettyPrinted, .sortedKeys]
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Codex

/// Wires `notify` in `~/.codex/config.toml`. TOML is not JSON: rewriting
/// someone's config with a serializer we don't have would be reckless,
/// so this installer only ever APPENDS a clearly-marked block — and if a
/// foreign `notify` already exists it refuses with an explanation,
/// because Codex accepts exactly one notify program.
enum CodexInstaller {

    static let marker = ".roster/roster-hook.sh"

    static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/config.toml")
    }

    static var toolDetected: Bool {
        FileManager.default.fileExists(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".codex").path
        )
    }

    static func isInstalled(at url: URL = defaultConfigURL) -> Bool {
        guard HelperScript.isInstalled,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return false }
        return text.contains(marker)
    }

    /// True when the config already carries someone else's notify.
    static func hasForeignNotify(in text: String) -> Bool {
        guard !text.contains(marker) else { return false }
        return text.split(separator: "\n").contains { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("notify")
                && line.contains("=")
        }
    }

    static func install(at url: URL = defaultConfigURL) throws {
        try HelperScript.install()
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard !text.contains(marker) else { return }
        guard !hasForeignNotify(in: text) else {
            throw ProviderInstallError.codexNotifyTaken
        }
        try backup(url)
        let block = """

        # Added by Roster.app — appends turn events to Roster's spool.
        # Safe to remove; Roster re-adds it on the next Connect.
        notify = ["\(HelperScript.url.path)", "codex"]
        """
        let updated = text.isEmpty ? String(block.dropFirst()) : text + block + "\n"
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Shared bits

enum ProviderInstallError: Error, LocalizedError {
    case notJSON(String)
    case codexNotifyTaken

    var errorDescription: String? {
        switch self {
        case .notJSON(let name):
            return "\(name)'s config exists but is not valid JSON — not touching it."
        case .codexNotifyTaken:
            return "~/.codex/config.toml already has a notify program. Codex allows only one — chain \(HelperScript.url.path) codex from yours, or remove it and Connect again."
        }
    }
}

/// Missing file = empty object; present-but-not-JSON = hands off.
private func loadJSONObject(at url: URL, toolName: String) throws -> [String: Any] {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ProviderInstallError.notJSON(toolName)
    }
    return root
}

/// One timestamped backup next to the file, never overwritten.
private func backup(_ url: URL) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else { return }
    let stamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
    let backupURL = url.deletingLastPathComponent()
        .appending(path: url.lastPathComponent + ".roster-backup-\(stamp)")
    try? fm.copyItem(at: url, to: backupURL)
}
