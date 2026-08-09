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
            ensureSession(key: key, cwd: cwd)
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
            guard let id = externalToID[key] else { return nil }
            endSession(id)
            return nil
        }
    }

    /// Finds the session for a Claude Code `session_id`, creating it (and
    /// its workstation) when the event carries a `cwd` — this is what lets
    /// Roster pick up sessions that were already running when the hook was
    /// installed, or that lived while Roster was closed.
    @discardableResult
    private func ensureSession(key: String, cwd: String?) -> Int? {
        if let id = externalToID[key] { return id }
        guard let cwd,
              let stationIndex = workstationIndex(forPath: cwd),
              let id = startSession(onStation: stationIndex)
        else { return nil }
        externalToID[key] = id
        lastPromptAt[id] = now()
        return id
    }
}
