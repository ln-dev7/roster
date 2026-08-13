import Foundation

/// One event from a coding agent, already reduced to what Roster cares
/// about. Everything else in the payloads is dropped here, at the
/// boundary — the rest of the app never sees raw JSON.
///
/// Four dialects feed the same spool, told apart by the
/// `roster_provider` tag the relay injects: no tag = Claude Code (the
/// original inline hooks), "gemini" | "cursor" | "codex" for the rest.
/// `key` is the tool's session id, PREFIXED with its provider
/// ("gemini:<id>") so ids can never collide across tools — and so the
/// office knows which logo the desk wears.
///
/// `cwd` rides along on mid-session events so a session that started
/// *before* the hook was installed can still materialize in the room.
/// (The type keeps its historical name; renaming it to AgentEvent is
/// pure churn until it earns a header of its own.)
enum ClaudeEvent: Equatable {
    case sessionStart(key: String, cwd: String)
    case promptSubmitted(key: String, cwd: String?)
    case needsInput(key: String, cwd: String?)
    /// Explicit "the agent is done" notification — walks without the
    /// turn-duration rule (it is Claude Code's own completion signal).
    case completed(key: String, cwd: String?)
    case stopped(key: String, cwd: String?, summary: String?)
    case stopFailed(key: String, cwd: String?)
    case sessionEnd(key: String)
}

extension ClaudeEvent {

    /// The subset of the hook payload we read. Field names mirror the JSON
    /// (snake_case) on purpose — one less mapping to maintain when the
    /// format moves. `roster_matcher` is injected by our own Notification
    /// hooks (one per matcher), so the type never has to be guessed from
    /// an undocumented payload field.
    private struct RawPayload: Decodable {
        let hook_event_name: String?
        let session_id: String?
        let cwd: String?
        let transcript_path: String?
        let notification_type: String?
        let roster_matcher: String?
        let last_assistant_message: String?
    }

    /// Which dialect a spool line speaks — the tag the relay script
    /// injected, or Claude Code when there is none.
    private struct ProviderTag: Decodable {
        let roster_provider: String?
    }

    /// Parses one spool line. Returns nil for anything Roster ignores —
    /// unknown events, notification types that don't concern the room,
    /// malformed JSON. Silence, not crashes: the formats aren't ours.
    init?(jsonLine: String) {
        let trimmed = jsonLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let data = Data(trimmed.utf8)

        switch (try? JSONDecoder().decode(ProviderTag.self, from: data))?.roster_provider {
        case "gemini":
            guard let event = ClaudeEvent.gemini(data) else { return nil }
            self = event
            return
        case "cursor":
            guard let event = ClaudeEvent.cursor(data) else { return nil }
            self = event
            return
        case "codex":
            guard let event = ClaudeEvent.codex(data) else { return nil }
            self = event
            return
        default:
            break // Claude Code — the original dialect, below.
        }

        guard let payload = try? JSONDecoder().decode(RawPayload.self, from: data),
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
            // The tag our sed hook injected wins; notification_type is the
            // fallback in case the payload carries it natively.
            switch payload.roster_matcher ?? payload.notification_type {
            case "agent_needs_input", "permission_prompt", "idle_prompt":
                self = .needsInput(key: key, cwd: payload.cwd)
            case "agent_completed":
                self = .completed(key: key, cwd: payload.cwd)
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

    // MARK: The other dialects

    /// Gemini CLI hooks — verified against the official hooks reference:
    /// snake_case payload with the same core fields as Claude Code, event
    /// names of its own. `AfterAgent` carries the agent's final text.
    private static func gemini(_ data: Data) -> ClaudeEvent? {
        struct Payload: Decodable {
            let hook_event_name: String?
            let session_id: String?
            let cwd: String?
            let prompt_response: String?
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data),
              let event = p.hook_event_name,
              let id = p.session_id
        else { return nil }
        let key = "gemini:\(id)"

        switch event {
        case "SessionStart":
            guard let cwd = p.cwd else { return nil }
            return .sessionStart(key: key, cwd: cwd)
        case "BeforeAgent":
            return .promptSubmitted(key: key, cwd: p.cwd)
        case "Notification":
            // Today the only documented type is ToolPermission — exactly
            // "the agent is blocked on you".
            return .needsInput(key: key, cwd: p.cwd)
        case "AfterAgent":
            return .stopped(key: key, cwd: p.cwd, summary: p.prompt_response)
        case "SessionEnd":
            return .sessionEnd(key: key)
        default:
            return nil
        }
    }

    /// Cursor IDE hooks — Agent Chat / Cmd+K via hooks.json.
    /// `conversation_id` (or `session_id`) + `workspace_roots` on events,
    /// and a `status` on `stop`. sessionStart is pending-only in Office
    /// (same as Claude); the first prompt seats. sessionEnd retires.
    private static func cursor(_ data: Data) -> ClaudeEvent? {
        struct Payload: Decodable {
            let hook_event_name: String?
            let conversation_id: String?
            let session_id: String?
            let workspace_roots: [String]?
            let status: String?
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data),
              let event = p.hook_event_name,
              let id = p.conversation_id ?? p.session_id
        else { return nil }
        let key = "cursor:\(id)"
        let cwd = p.workspace_roots?.first

        switch event {
        case "sessionStart":
            // IDE may omit workspace_roots on a brand-new composer; without
            // a cwd we cannot place a desk, so wait for the first prompt.
            guard let cwd else { return nil }
            return .sessionStart(key: key, cwd: cwd)
        case "beforeSubmitPrompt":
            return .promptSubmitted(key: key, cwd: cwd)
        case "stop":
            switch p.status {
            case "error":
                return .stopFailed(key: key, cwd: cwd)
            case "aborted":
                // The user cancelled mid-turn; neither finished nor
                // failed — the room simply doesn't react.
                return nil
            default:
                return .stopped(key: key, cwd: cwd, summary: nil)
            }
        case "sessionEnd":
            return .sessionEnd(key: key)
        default:
            return nil
        }
    }

    /// Codex's notify — one event, "agent-turn-complete", kebab-case
    /// keys, delivered as the notify program's final argument (the relay
    /// script turns that into a spool line). No prompt events: the walk
    /// rule measures turn-to-turn time instead (see Office+Events).
    private static func codex(_ data: Data) -> ClaudeEvent? {
        struct Payload: Decodable {
            let type: String?
            let threadId: String?
            let cwd: String?
            let lastAssistantMessage: String?

            enum CodingKeys: String, CodingKey {
                case type
                case threadId = "thread-id"
                case cwd
                case lastAssistantMessage = "last-assistant-message"
            }
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data),
              p.type == "agent-turn-complete",
              let id = p.threadId
        else { return nil }
        return .stopped(key: "codex:\(id)", cwd: p.cwd,
                        summary: p.lastAssistantMessage)
    }

    /// Split a physical spool line into top-level JSON objects.
    ///
    /// Cursor IDE runs Claude Code's Roster `cat` hook alongside our
    /// tagged relay; when the cat write lacks a trailing newline the two
    /// objects glue onto one line. Healing that here recovers the tagged
    /// Cursor event without throwing away the whole line.
    static func jsonObjects(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.first == "{",
           (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil {
            return [trimmed]
        }

        var objects: [String] = []
        var depth = 0
        var inString = false
        var escape = false
        var start: String.Index?

        for i in trimmed.indices {
            let ch = trimmed[i]
            if inString {
                if escape {
                    escape = false
                } else if ch == "\\" {
                    escape = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }
            switch ch {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = i }
                depth += 1
            case "}":
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let start {
                    objects.append(String(trimmed[start...i]))
                }
            default:
                break
            }
        }
        return objects
    }

    /// The transcript path carried by a spool line, if any — used by the
    /// staleness sweep, not by the state machine. The key gets the same
    /// provider prefix as the events, so the sweep retires the right one.
    /// Cursor IDE uses `conversation_id`; Claude/Gemini use `session_id`.
    static func transcriptPath(fromJSONLine line: String) -> (key: String, path: String)? {
        struct Mini: Decodable {
            let roster_provider: String?
            let session_id: String?
            let conversation_id: String?
            let workspace_roots: [String]?
            let transcript_path: String?
        }
        guard let mini = try? JSONDecoder().decode(
            Mini.self,
            from: Data(line.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        ), let path = mini.transcript_path,
           let id = mini.session_id ?? mini.conversation_id
        else { return nil }
        // Cursor imports Claude Code's hooks, so every Cursor event also
        // reaches the spool untagged. `workspace_roots` is Cursor's own
        // field and gives those copies away — without it they would file an
        // unprefixed key no desk can ever match, leaving the sweep to
        // track a session that does not exist.
        let provider = mini.roster_provider
            ?? (mini.workspace_roots == nil ? nil : "cursor")
        let key = provider.map { "\($0):\(id)" } ?? id
        return (key, path)
    }
}
