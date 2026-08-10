import XCTest

/// The event bridge: real Claude Code hook events driving the room,
/// including the one product rule that needs guarding — the walk must be
/// earned (short turns don't send agents pacing).
@MainActor
final class OfficeEventTests: XCTestCase {

    /// An office with an instant clock for choreographies and a manual
    /// clock for the walk rule. Move time with `advance(_:)`.
    private var office: Office!
    private var currentDate = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() async throws {
        currentDate = Date(timeIntervalSince1970: 1_000_000)
        office = Office(sleeper: { _ in })
        office.now = { [weak self] in self?.currentDate ?? Date() }
    }

    private func advance(_ seconds: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(seconds)
    }

    // MARK: Stations from repositories

    func testASessionStartAloneSeatsNobody() {
        // Claude Code 2.x pre-creates sessions ("new session — send a
        // prompt to start") and spawns a fresh one per background
        // conversation. A start is a slot, not a colleague.
        office.apply(.sessionStart(key: "slot", cwd: "/Users/me/dev/circle"))

        XCTAssertTrue(office.workstations.isEmpty, "a slot is not a colleague")
        XCTAssertTrue(office.sessions.isEmpty)
    }

    func testTheFirstPromptSeatsThePendingSessionAtItsRememberedCwd() {
        office.apply(.sessionStart(key: "s1", cwd: "/Users/me/dev/circle"))
        // Later hook events may omit cwd — the start's cwd is remembered.
        office.apply(.promptSubmitted(key: "s1", cwd: nil))

        XCTAssertEqual(office.workstations.count, 1)
        XCTAssertEqual(office.workstations[0].name, "circle")
        XCTAssertEqual(office.workstations[0].path, "/Users/me/dev/circle")
        XCTAssertEqual(office.sessions.count, 1)
        XCTAssertEqual(office.sessions[0].status, .working)
    }

    func testAScanDiscoveredSessionSeatsImmediately() {
        // The transcript/rollout scans prove real work — no prompt needed.
        office.seatActiveSession(key: "live", cwd: "/repo/circle")

        XCTAssertEqual(office.sessions.count, 1)
        XCTAssertEqual(office.sessions[0].status, .working)
    }

    func testAnAbandonedSlotEndsWithoutEverSitting() {
        office.apply(.sessionStart(key: "slot", cwd: "/repo/circle"))
        office.apply(.sessionEnd(key: "slot"))

        XCTAssertTrue(office.sessions.isEmpty)
        // The pending cwd died with it: a later cwd-less event can't
        // resurrect the slot.
        office.apply(.promptSubmitted(key: "slot", cwd: nil))
        XCTAssertTrue(office.sessions.isEmpty, "ended slots don't seat later")
    }

    func testTwoSessionsOnTheSameRepoGetTheirOwnDesks() {
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))
        office.apply(.sessionStart(key: "s2", cwd: "/repo/circle"))
        office.apply(.promptSubmitted(key: "s1", cwd: nil))
        office.apply(.promptSubmitted(key: "s2", cwd: nil))

        XCTAssertEqual(office.workstations.count, 2,
                       "one colleague per desk — even from the same folder")
        XCTAssertEqual(office.sessions.count, 2)
        XCTAssertEqual(office.seatCount(onStation: 0), 1)
        XCTAssertEqual(office.seatCount(onStation: 1), 1)
        XCTAssertEqual(office.displayName(forStation: 0), "circle · 1")
        XCTAssertEqual(office.displayName(forStation: 1), "circle · 2")
    }

    func testDuplicateSessionStartIsIgnored() {
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))
        office.apply(.promptSubmitted(key: "s1", cwd: nil))
        XCTAssertEqual(office.sessions.count, 1)
    }

    func testTheRoomCapsAtSixDesks() {
        for i in 1...7 {
            office.apply(.promptSubmitted(key: "s\(i)", cwd: "/repo/project\(i)"))
        }
        XCTAssertEqual(office.workstations.count, Office.maxStations)
        XCTAssertEqual(office.sessions.count, Office.maxStations,
                       "the seventh session has no desk and is not shown")
    }

    func testMidSessionEventMaterializesAnUnknownSession() {
        // Hook installed while a session was already running: the first
        // thing Roster sees is a prompt, not a SessionStart.
        office.apply(.promptSubmitted(key: "old", cwd: "/repo/blog"))
        XCTAssertEqual(office.workstations.count, 1)
        XCTAssertEqual(office.sessions.count, 1)
    }

    // MARK: The walk rule

    func testLongTurnEarnsTheWalk() async {
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))
        office.apply(.promptSubmitted(key: "s1", cwd: nil))
        advance(120)

        await office.apply(.stopped(key: "s1", cwd: nil, summary: "Refactored the sidebar."))?.value

        let session = office.sessions[0]
        XCTAssertEqual(session.status, .finished)
        XCTAssertEqual(session.phase, .atDesk)
        XCTAssertEqual(office.lastSummary[session.id], "Refactored the sidebar.")
    }

    func testShortTurnStaysSeated() async {
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))
        office.apply(.promptSubmitted(key: "s1", cwd: nil))
        advance(10)

        await office.apply(.stopped(key: "s1", cwd: nil, summary: "Sure."))?.value

        let session = office.sessions[0]
        XCTAssertEqual(session.status, .working)
        XCTAssertEqual(session.phase, .seated, "a 10-second reply is not walk-worthy")
    }

    func testNotificationStandsTheAgentUpAndPromptSeatsIt() {
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))

        office.apply(.needsInput(key: "s1", cwd: nil))
        XCTAssertEqual(office.sessions[0].status, .waitingForInput)
        XCTAssertEqual(office.sessions[0].phase, .standing)

        office.apply(.promptSubmitted(key: "s1", cwd: nil))
        XCTAssertEqual(office.sessions[0].status, .working)
        XCTAssertEqual(office.sessions[0].phase, .seated)
    }

    func testPromptAfterTheWalkBringsTheAgentHome() async {
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))
        office.apply(.promptSubmitted(key: "s1", cwd: nil))
        advance(120)
        await office.apply(.stopped(key: "s1", cwd: nil, summary: nil))?.value
        XCTAssertEqual(office.sessions[0].phase, .atDesk)

        await office.apply(.promptSubmitted(key: "s1", cwd: nil))?.value

        XCTAssertEqual(office.sessions[0].status, .working)
        XCTAssertEqual(office.sessions[0].phase, .seated)
    }

    func testAgentCompletedNotificationWalksWithoutTheDurationRule() async {
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))
        // No prompt, no time advance: the explicit signal is enough.
        await office.apply(.completed(key: "s1", cwd: nil))?.value

        XCTAssertEqual(office.sessions[0].status, .finished)
        XCTAssertEqual(office.sessions[0].phase, .atDesk)
    }

    // MARK: Failures and endings

    func testStopFailureMarksTheAgent() {
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))
        office.apply(.stopFailed(key: "s1", cwd: nil))
        XCTAssertEqual(office.sessions[0].status, .failed)
    }

    // MARK: Providers

    func testProviderPrefixedKeysDressTheirDesks() {
        office.apply(.promptSubmitted(key: "s1", cwd: "/repo/a"))
        office.apply(.promptSubmitted(key: "gemini:g1", cwd: "/repo/b"))
        office.apply(.promptSubmitted(key: "cursor:c1", cwd: "/repo/c"))
        office.apply(.stopped(key: "codex:t1", cwd: "/repo/d", summary: nil))

        XCTAssertEqual(office.workstations.map(\.provider),
                       [.claudeCode, .gemini, .cursor, .codex])
    }

    func testCodexEarnsTheWalkTurnToTurn() async {
        // Codex has no prompt events: the walk rule measures the time
        // between turn completions instead.
        office.apply(.stopped(key: "codex:t1", cwd: "/repo/d", summary: "First."))
        XCTAssertEqual(office.sessions[0].phase, .seated,
                       "the first turn just materialized the desk")

        advance(120)
        await office.apply(.stopped(key: "codex:t1", cwd: nil, summary: "Second."))?.value
        XCTAssertEqual(office.sessions[0].status, .finished)
        XCTAssertEqual(office.sessions[0].phase, .atDesk)
    }

    func testSessionEndRemovesTheAgentAndItsDesk() {
        office.apply(.sessionStart(key: "s1", cwd: "/repo/circle"))
        office.apply(.promptSubmitted(key: "s1", cwd: nil))
        office.apply(.sessionEnd(key: "s1"))

        XCTAssertTrue(office.sessions.isEmpty)
        XCTAssertTrue(office.workstations.isEmpty,
                      "desks live and die with their sessions")

        // The same session id ending twice is harmless.
        office.apply(.sessionEnd(key: "s1"))
        XCTAssertTrue(office.sessions.isEmpty)
    }

    func testEachTwinDeskDiesWithItsOwnSession() {
        office.apply(.promptSubmitted(key: "s1", cwd: "/repo/circle"))
        office.apply(.promptSubmitted(key: "s2", cwd: "/repo/circle"))

        office.apply(.sessionEnd(key: "s1"))
        XCTAssertEqual(office.workstations.count, 1,
                       "only s1's desk leaves; s2 keeps its own")
        XCTAssertEqual(office.sessions.count, 1)
        XCTAssertEqual(office.displayName(forStation: 0), "circle",
                       "the last twin drops its number")

        office.apply(.sessionEnd(key: "s2"))
        XCTAssertTrue(office.workstations.isEmpty)
    }
}

/// Parsing of raw spool lines into `ClaudeEvent`s.
final class ClaudeEventParsingTests: XCTestCase {

    func testParsesSessionStart() {
        let line = #"{"hook_event_name":"SessionStart","session_id":"abc","cwd":"/repo/x","source":"startup"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: line),
                       .sessionStart(key: "abc", cwd: "/repo/x"))
    }

    func testParsesStopWithSummary() {
        let line = #"{"hook_event_name":"Stop","session_id":"abc","cwd":"/repo/x","last_assistant_message":"Done."}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: line),
                       .stopped(key: "abc", cwd: "/repo/x", summary: "Done."))
    }

    func testOnlyRelevantNotificationTypesPass() {
        // The tag injected by our own sed hook.
        let tagged = #"{"roster_matcher":"agent_needs_input","hook_event_name":"Notification","session_id":"abc","cwd":"/r"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: tagged),
                       .needsInput(key: "abc", cwd: "/r"))

        // Fallback on a native notification_type field, if one exists.
        let native = #"{"hook_event_name":"Notification","session_id":"abc","cwd":"/r","notification_type":"permission_prompt"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: native),
                       .needsInput(key: "abc", cwd: "/r"))

        // Claude Code's own completion signal maps to the walk.
        let completed = #"{"roster_matcher":"agent_completed","hook_event_name":"Notification","session_id":"abc","cwd":"/r"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: completed),
                       .completed(key: "abc", cwd: "/r"))

        let irrelevant = #"{"hook_event_name":"Notification","session_id":"abc","notification_type":"auth_success"}"#
        XCTAssertNil(ClaudeEvent(jsonLine: irrelevant))
    }

    func testTranscriptPathExtraction() {
        let line = #"{"hook_event_name":"Stop","session_id":"abc","transcript_path":"/Users/x/.claude/projects/-repo/abc.jsonl"}"#
        let extracted = ClaudeEvent.transcriptPath(fromJSONLine: line)
        XCTAssertEqual(extracted?.key, "abc")
        XCTAssertEqual(extracted?.path, "/Users/x/.claude/projects/-repo/abc.jsonl")
    }

    func testGarbageAndUnknownEventsAreIgnored() {
        XCTAssertNil(ClaudeEvent(jsonLine: ""))
        XCTAssertNil(ClaudeEvent(jsonLine: "not json at all"))
        XCTAssertNil(ClaudeEvent(jsonLine: #"{"hook_event_name":"PreToolUse","session_id":"abc"}"#))
        XCTAssertNil(ClaudeEvent(jsonLine: #"{"hook_event_name":"Stop"}"#), "no session_id")
    }

    // MARK: The other dialects

    func testGeminiDialect() {
        let start = #"{"roster_provider":"gemini","hook_event_name":"SessionStart","session_id":"g1","cwd":"/repo/x"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: start),
                       .sessionStart(key: "gemini:g1", cwd: "/repo/x"))

        let before = #"{"roster_provider":"gemini","hook_event_name":"BeforeAgent","session_id":"g1","cwd":"/repo/x","prompt":"go"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: before),
                       .promptSubmitted(key: "gemini:g1", cwd: "/repo/x"))

        let after = #"{"roster_provider":"gemini","hook_event_name":"AfterAgent","session_id":"g1","cwd":"/repo/x","prompt_response":"Done."}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: after),
                       .stopped(key: "gemini:g1", cwd: "/repo/x", summary: "Done."))

        let notification = #"{"roster_provider":"gemini","hook_event_name":"Notification","session_id":"g1","notification_type":"ToolPermission","message":"…"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: notification),
                       .needsInput(key: "gemini:g1", cwd: nil))

        let end = #"{"roster_provider":"gemini","hook_event_name":"SessionEnd","session_id":"g1","reason":"exit"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: end), .sessionEnd(key: "gemini:g1"))
    }

    func testCursorDialect() {
        let prompt = #"{"roster_provider":"cursor","hook_event_name":"beforeSubmitPrompt","conversation_id":"c1","workspace_roots":["/repo/x"],"prompt":"go"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: prompt),
                       .promptSubmitted(key: "cursor:c1", cwd: "/repo/x"))

        let done = #"{"roster_provider":"cursor","hook_event_name":"stop","conversation_id":"c1","workspace_roots":["/repo/x"],"status":"completed"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: done),
                       .stopped(key: "cursor:c1", cwd: "/repo/x", summary: nil))

        let failed = #"{"roster_provider":"cursor","hook_event_name":"stop","conversation_id":"c1","workspace_roots":["/repo/x"],"status":"error"}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: failed),
                       .stopFailed(key: "cursor:c1", cwd: "/repo/x"))

        let aborted = #"{"roster_provider":"cursor","hook_event_name":"stop","conversation_id":"c1","workspace_roots":["/repo/x"],"status":"aborted"}"#
        XCTAssertNil(ClaudeEvent(jsonLine: aborted),
                     "a cancelled turn is neither finished nor failed")
    }

    func testCodexDialect() {
        let turn = #"{"roster_provider":"codex","type":"agent-turn-complete","thread-id":"t1","cwd":"/repo/x","last-assistant-message":"Shipped."}"#
        XCTAssertEqual(ClaudeEvent(jsonLine: turn),
                       .stopped(key: "codex:t1", cwd: "/repo/x", summary: "Shipped."))

        XCTAssertNil(ClaudeEvent(
            jsonLine: #"{"roster_provider":"codex","type":"something-else","thread-id":"t1"}"#
        ))
    }
}
