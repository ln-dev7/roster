import Foundation

/// Where a provider stands with its tool's configuration.
///
/// Lived inside `ClaudeCodeSource` until other coding agents (Gemini CLI,
/// Codex, Cursor…) came into view — the states turn out to be the same
/// for every tool, so they moved up here.
enum ConnectionState: Equatable {
    /// Not looked yet (first millisecond of app life).
    case checking
    /// Events not wired — the room runs on presence detection alone.
    case notConnected
    /// Events wired, the feed is being tailed.
    case connected
    /// Wiring failed; the message is shown to the user.
    case failed(String)
}

/// One coding-agent CLI feeding the room.
///
/// This is the seam where multi-tool support will grow (see
/// docs/providers.md for the per-tool research). The contract is small on
/// purpose:
///
///   • A provider watches its tool however that tool allows — hooks and a
///     spool file for Claude Code, a notify program for Codex, log
///     tailing for Gemini CLI — and translates everything into
///     `ClaudeEvent`s applied to the one shared `Office`. The room never
///     learns where an event came from.
///   • `refresh()` must be safe to call at any time, read-only, and
///     idempotent: it (re)discovers config roots and starts the feeds.
///   • `connect()` is the only write a provider may perform (installing
///     hooks, editing a config) — always consent-gated by the UI, always
///     after a backup.
///
/// `ClaudeCodeSource` is the first and, today, only conformer. When the
/// second one lands, `ClaudeEvent` should be renamed `AgentEvent` and the
/// app should hold `[any AgentProvider]` — mechanical changes, kept out
/// of today's diff on purpose.
@MainActor
protocol AgentProvider: AnyObject {

    /// Shown in the sidebar dot and the connect banner.
    var state: ConnectionState { get }

    /// The tool's config folders currently being watched.
    var roots: [URL] { get }

    /// Events accepted so far — visible in logs, handy when debugging.
    var eventsProcessed: Int { get }

    /// Re-discover roots and make sure the feeds run. Read-only.
    func refresh()

    /// Wire the tool's events up (the one consented write).
    func connect()
}

extension ClaudeCodeSource: AgentProvider {}
