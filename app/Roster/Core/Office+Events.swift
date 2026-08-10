import Foundation

/// The bridge between Claude Code's events and the room, and the home of
/// the one product rule that isn't obvious: **the walk must be earned**.
///
/// `Stop` fires at the end of *every* turn — even a two-second "yes, go
/// ahead". If every stop sent the agent pacing to your desk, the room would
/// be a corridor. So: a turn only earns the traversée when the agent worked
/// at least `finishThreshold` seconds since your last prompt. Short turns
/// just keep the agent seated.
extension Office {

    /// Feeds one event into the room. Returns the choreography task when
    /// the event starts one, so tests can await the animation's logic.
    @discardableResult
    func apply(_ event: ClaudeEvent) -> Task<Void, Never>? {
        switch event {
        case .sessionStart(let key, let cwd):
            // A SessionStart means "a slot exists", NOT "someone works":
            // Claude Code 2.x pre-creates sessions ("new session — send
            // a prompt to start") and spawns a fresh one per background
            // conversation, so seating here would fill the room with
            // empty colleagues. Remember the cwd; the first meaningful
            // event — a prompt, a question, a turn — spends it and earns
            // the desk. (Sessions found by the activity scans seat
            // immediately via `seatActiveSession`: a transcript being
            // written IS meaningful.)
            if externalToID[key] == nil {
                pendingCwd[key] = cwd
            }
            return nil

        case .promptSubmitted(let key, let cwd):
            guard let id = ensureSession(key: key, cwd: cwd) else { return nil }
            lastPromptAt[id] = now()
            // A prompt while the agent waits (for input, or at your desk
            // after finishing) means you answered: back to work.
            return resumeWorking(id)

        case .needsInput(let key, let cwd):
            guard let id = ensureSession(key: key, cwd: cwd) else { return nil }
            needsInput(id)
            return nil

        case .completed(let key, let cwd):
            // Claude Code's own "agent completed" signal: no duration rule,
            // the walk is explicitly earned.
            guard let id = ensureSession(key: key, cwd: cwd) else { return nil }
            return finish(id)

        case .stopped(let key, let cwd, let summary):
            guard let id = ensureSession(key: key, cwd: cwd) else { return nil }
            if let summary, !summary.isEmpty {
                lastSummary[id] = summary
            }
            let workedFor = lastPromptAt[id].map { now().timeIntervalSince($0) } ?? 0
            // Reset the clock at every stop too. Harmless for tools with
            // prompt events (the next prompt overwrites it) and essential
            // for Codex, which only ever says "turn complete": there, the
            // walk rule measures turn-to-turn time.
            lastPromptAt[id] = now()
            if workedFor >= finishThreshold {
                return finish(id)
            } else {
                // Not walk-worthy; just make sure the agent is seated and
                // working (it may have been standing on a permission ask).
                return resumeWorking(id)
            }

        case .stopFailed(let key, let cwd):
            guard let id = ensureSession(key: key, cwd: cwd) else { return nil }
            fail(id)
            return nil

        case .sessionEnd(let key):
            // Abandoned slots end too — without ever having been seated.
            pendingCwd[key] = nil
            guard let id = externalToID[key] else { return nil }
            endSession(id)
            return nil
        }
    }

    /// Presence discovered by the activity scans — a transcript or Codex
    /// rollout that is actively being written. That IS proof of work, so
    /// the session seats immediately, unlike a hook SessionStart (which
    /// only registers a slot; see `apply`).
    @discardableResult
    func seatActiveSession(key: String, cwd: String) -> Int? {
        ensureSession(key: key, cwd: cwd)
    }

    /// Finds the session for a Claude Code `session_id`, creating it — and
    /// its OWN desk, one colleague per desk — when the event carries a
    /// `cwd` (or its SessionStart registered one earlier). This is what
    /// lets Roster pick up sessions that were already running when the
    /// hook was installed, or that lived while Roster was closed.
    @discardableResult
    private func ensureSession(key: String, cwd: String?) -> Int? {
        if let id = externalToID[key] { return id }
        guard let path = cwd ?? pendingCwd[key],
              let stationIndex = addWorkstation(
                  forPath: path,
                  provider: ProviderKind(sessionKey: key)
              ),
              let id = startSession(onStation: stationIndex)
        else { return nil }
        pendingCwd[key] = nil
        externalToID[key] = id
        lastPromptAt[id] = now()
        return id
    }
}
