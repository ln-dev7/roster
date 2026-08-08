import Foundation

/// One event from Claude Code, already reduced to the six things Roster
/// cares about. Everything else in the hook payload is dropped here, at the
/// boundary — the rest of the app never sees raw JSON.
///
/// `key` is Claude Code's `session_id`; `cwd` rides along on mid-session
/// events so a session that started *before* the hook was installed can
/// still materialize in the room.
enum ClaudeEvent: Equatable {
    case sessionStart(key: String, cwd: String)
    case promptSubmitted(key: String, cwd: String?)
    case needsInput(key: String, cwd: String?)
    case stopped(key: String, cwd: String?, summary: String?)
    case stopFailed(key: String, cwd: String?)
    case sessionEnd(key: String)
}

extension ClaudeEvent {

    /// The subset of the hook payload we read. Field names mirror the JSON
    /// (snake_case) on purpose — one less mapping to maintain when the
    /// format moves.
    private struct RawPayload: Decodable {
        let hook_event_name: String?
        let session_id: String?
        let cwd: String?
        let notification_type: String?
        let last_assistant_message: String?
    }

    /// Parses one spool line. Returns nil for anything Roster ignores —
    /// unknown events, notification types that don't concern the room,
    /// malformed JSON. Silence, not crashes: the format isn't ours.
    init?(jsonLine: String) {
        let trimmed = jsonLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let payload = try? JSONDecoder().decode(RawPayload.self, from: Data(trimmed.utf8)),
              let event = payload.hook_event_name,
              let key = payload.session_id
        else { return nil }

        switch event {
        case "SessionStart":
            guard let cwd = payload.cwd else { return nil }
            self = .sessionStart(key: key, cwd: cwd)

        case "UserPromptSubmit":
            self = .promptSubmitted(key: key, cwd: payload.cwd)

        case "Notification":
            // Only the "the agent needs you" flavours reach the room.
            switch payload.notification_type {
            case "agent_needs_input", "permission_prompt", "idle_prompt":
                self = .needsInput(key: key, cwd: payload.cwd)
            default:
                return nil
            }

        case "Stop":
            self = .stopped(key: key, cwd: payload.cwd,
                            summary: payload.last_assistant_message)

        case "StopFailure":
            self = .stopFailed(key: key, cwd: payload.cwd)

        case "SessionEnd":
            self = .sessionEnd(key: key)

        default:
            return nil
        }
    }
}
