import Foundation
import Observation

// MARK: - Domain model
//
// Two separate ideas, kept deliberately apart:
//
//   • `SessionStatus` — what the agent session IS (the domain truth, driven
//     by real Claude Code hooks through `Office.apply(_:)`).
//   • `AgentPhase`   — where its dot is in the room (pure presentation,
//     produced from status changes by the choreography below).
//
// The walk is not a status. "Finished" is a status; the crossing is just
// how the room tells you about it.

/// What a session is doing, as the data source sees it.
enum SessionStatus: Equatable {
    /// Heads-down at its station. The calm default.
    case working
    /// Blocked on you: a question or a permission prompt.
    case waitingForInput
    /// Done with its task; waiting for your review.
    case finished
    /// The turn ended in an error.
    case failed
}

/// Where the agent's dot is, or is heading. Every visual derives from this.
enum AgentPhase: Equatable {
    case seated
    case standing
    case walking
    case atDesk
    case walkingBack
}

/// One desk in the room = one project (a repository, in real life).
/// A desk exists exactly as long as a session works there — when the
/// last one ends, the desk leaves with it (see `endSession`).
struct Workstation: Identifiable, Equatable {
    /// Stable identity: the repository path for real stations, a "demo-…"
    /// string for simulated ones.
    let id: String
    var name: String
    /// Filesystem path of the repository, when this is a real project.
    var path: String?
}

/// One live agent session. A value type on purpose: replacing an element of
/// `Office.sessions` is exactly what lets `@Observable` notice a change.
struct AgentSession: Identifiable, Equatable {
    let id: Int
    /// Index into `Office.workstations` — the project this agent works on.
    let stationIndex: Int
    var status: SessionStatus = .working
    var phase: AgentPhase = .seated
    /// 0 or 1 — two agents can share one station.
    var seatSlot: Int = 0
    /// Position in the queue at your desk, assigned when the walk starts.
    var deskSlot: Int = 0
}

/// Timing of the choreography, in seconds. These numbers are the feel of the
/// whole app; they live here, named, and nowhere else.
enum Choreo {
    /// Getting up / sitting down.
    static let standUp: Double = 0.45
    /// A short beat between standing and setting off — people don't launch.
    static let beat: Double = 0.25
    /// The crossing itself.
    static let walk: Double = 2.9
}

// MARK: - Office

/// The room's state machine. UI-free (no SwiftUI import) so the test bundle
/// compiles it directly and exercises every transition.
///
/// The public methods are the exact vocabulary the event source speaks
/// (`startSession`, `needsInput`, `finish`, `fail`, `endSession`) — the
/// simulation panel and `Office.apply(_:)` are just two different callers.
@MainActor
@Observable
final class Office {

    /// The room never draws more desks than this — beyond six the drawing
    /// stops being readable at a glance, which is the whole point.
    static let maxStations = 6

    private(set) var workstations: [Workstation] = []
    private(set) var sessions: [AgentSession] = []

    // `@ObservationIgnored`: bookkeeping the UI never reads directly, so it
    // should not participate in change tracking.
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private var generations: [Int: Int] = [:]

    // ── Plumbing for the real event source (see Office+Events.swift) ────
    /// Claude Code session_id → our session id.
    @ObservationIgnored var externalToID: [String: Int] = [:]
    /// When each session last received a prompt — used by the walk rule.
    @ObservationIgnored var lastPromptAt: [Int: Date] = [:]
    /// Last assistant message per session — shown by the detail card, so
    /// it participates in observation (unlike the bookkeeping above).
    var lastSummary: [Int: String] = [:]

    /// Fired when an agent reaches your desk after the walk. The app layer
    /// plugs the macOS notification in here; the core stays UI-free.
    @ObservationIgnored var onAgentArrived: ((AgentSession) -> Void)?
    /// A turn shorter than this doesn't earn a walk: quick chat replies
    /// would send agents pacing constantly. Tunable; 45 s felt right.
    @ObservationIgnored var finishThreshold: TimeInterval = 45
    /// Injected clock for the walk rule, so tests can time-travel.
    @ObservationIgnored var now: () -> Date = { Date() }

    /// Injected sleeper. Tests pass an instant (or logging) one, so the
    /// whole choreography runs — and is asserted — in microseconds.
    /// `@MainActor` on the closure type lets test sleepers read the office
    /// state directly (everything here lives on the main actor anyway).
    /// (A `let` is never observation-tracked, no attribute needed.)
    private let sleeper: @MainActor (Double) async -> Void

    init(sleeper: @escaping @MainActor (Double) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }) {
        self.sleeper = sleeper
    }

    // MARK: Queries

    func session(_ id: Int) -> AgentSession? {
        sessions.first { $0.id == id }
    }

    /// How many agents currently occupy a station (drives seat spreading).
    func seatCount(onStation stationIndex: Int) -> Int {
        sessions.filter { $0.stationIndex == stationIndex }.count
    }

    /// Stations hold at most two agents — beyond that the drawing lies.
    func canAddSession(onStation stationIndex: Int) -> Bool {
        seatCount(onStation: stationIndex) < 2
    }

    /// True when someone at this station is actually working — the monitor
    /// "breathes" only then.
    func hasWorkingAgent(onStation stationIndex: Int) -> Bool {
        sessions.contains {
            $0.stationIndex == stationIndex && $0.status == .working && $0.phase == .seated
        }
    }

    // MARK: Workstations

    /// Returns the station index for a repository, creating the desk on
    /// first sight. Nil when the room is full (capped, not scrolled).
    func workstationIndex(forPath path: String) -> Int? {
        if let existing = workstations.firstIndex(where: { $0.id == path }) {
            return existing
        }
        guard workstations.count < Self.maxStations else { return nil }
        let name = (path as NSString).lastPathComponent
        workstations.append(Workstation(id: path, name: name, path: path))
        return workstations.count - 1
    }

    /// Three fake desks with one working agent each — the demo room, used
    /// until real sessions exist, and forever by the GIF studio.
    func seedDemo() {
        guard workstations.isEmpty else { return }
        for name in ["circle", "dockkeep", "blog"] {
            workstations.append(Workstation(id: "demo-\(name)", name: name, path: nil))
            startSession(onStation: workstations.count - 1)
        }
    }

    /// Removes a desk and re-points every session past it — desks live and
    /// die with their sessions, so indices must stay dense.
    private func removeWorkstation(at stationIndex: Int) {
        guard workstations.indices.contains(stationIndex) else { return }
        workstations.remove(at: stationIndex)
        for i in sessions.indices where sessions[i].stationIndex > stationIndex {
            sessions[i].stationIndex -= 1
        }
    }

    /// Empties the room completely (demo reset).
    func clearRoom() {
        for session in sessions { invalidateChoreography(for: session.id) }
        generations.removeAll()
        externalToID.removeAll()
        lastPromptAt.removeAll()
        lastSummary.removeAll()
        sessions.removeAll()
        workstations.removeAll()
    }

    // MARK: Domain events

    /// A new agent sits down at a station. Returns its id, or nil if the
    /// station is full.
    @discardableResult
    func startSession(onStation stationIndex: Int) -> Int? {
        guard workstations.indices.contains(stationIndex),
              canAddSession(onStation: stationIndex) else { return nil }
        let taken = Set(sessions.filter { $0.stationIndex == stationIndex }.map(\.seatSlot))
        let slot = taken.contains(0) ? 1 : 0
        let id = nextID
        nextID += 1
        sessions.append(AgentSession(id: id, stationIndex: stationIndex, seatSlot: slot))
        return id
    }

    /// The agent is blocked on you: it stands up next to its chair and its
    /// ring starts pulsing (the view reads `status` for that).
    func needsInput(_ id: Int) {
        guard let i = index(of: id), sessions[i].status == .working else { return }
        invalidateChoreography(for: id)
        sessions[i].status = .waitingForInput
        sessions[i].phase = .standing
    }

    /// You answered (or reviewed): back to the chair, back to work.
    /// Returns the walking-back task when there is one, so tests can await
    /// the full return leg.
    @discardableResult
    func resumeWorking(_ id: Int) -> Task<Void, Never>? {
        guard let i = index(of: id) else { return nil }
        let generation = invalidateChoreography(for: id)
        sessions[i].status = .working

        // From your desk it walks back; from anywhere else it just sits.
        guard sessions[i].phase == .atDesk || sessions[i].phase == .walking else {
            sessions[i].phase = .seated
            return nil
        }
        return Task {
            guard setPhase(.walkingBack, of: id, ifGeneration: generation) else { return }
            await sleeper(Choreo.walk)
            guard setPhase(.seated, of: id, ifGeneration: generation) else { return }
        }
    }

    /// The agent finished its task: the traversée. Stand up, beat, cross,
    /// then wait at your desk until you resume or end the session.
    /// Returns the choreography task so tests (and only tests) can await it.
    @discardableResult
    func finish(_ id: Int) -> Task<Void, Never>? {
        guard let i = index(of: id),
              sessions[i].status == .working || sessions[i].status == .waitingForInput
        else { return nil }

        let generation = invalidateChoreography(for: id)
        sessions[i].status = .finished
        // Join the back of the queue at your desk.
        sessions[i].deskSlot = sessions
            .filter { $0.id != id && ($0.phase == .walking || $0.phase == .atDesk) }
            .count

        return Task {
            guard setPhase(.standing, of: id, ifGeneration: generation) else { return }
            await sleeper(Choreo.standUp + Choreo.beat)
            guard setPhase(.walking, of: id, ifGeneration: generation) else { return }
            await sleeper(Choreo.walk)
            guard setPhase(.atDesk, of: id, ifGeneration: generation) else { return }
            // Arrived. Stays at the desk — and the app layer may notify.
            if let session = session(id) {
                onAgentArrived?(session)
            }
        }
    }

    /// The turn blew up. The agent pulls back to its station, standing, and
    /// the view marks it with the warn cross. `resumeWorking` or
    /// `endSession` clears it.
    func fail(_ id: Int) {
        guard let i = index(of: id) else { return }
        invalidateChoreography(for: id)
        sessions[i].status = .failed
        sessions[i].phase = .standing
    }

    /// The session is gone; the agent fades out (the view's removal
    /// transition handles the fade — wrap calls in `withAnimation`).
    /// When it was the desk's last occupant, the desk leaves with it:
    /// the room only ever shows what's alive.
    func endSession(_ id: Int) {
        invalidateChoreography(for: id)
        generations[id] = nil
        lastPromptAt[id] = nil
        lastSummary[id] = nil
        if let key = externalToID.first(where: { $0.value == id })?.key {
            externalToID[key] = nil
        }

        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let stationIndex = sessions[index].stationIndex
        sessions.remove(at: index)

        if !sessions.contains(where: { $0.stationIndex == stationIndex }) {
            removeWorkstation(at: stationIndex)
        }
    }

    // MARK: Choreography plumbing

    /// Each domain event bumps the session's generation; a running
    /// choreography checks it before every step and quietly dies when it
    /// went stale. This is what makes an event landing mid-walk safe.
    @discardableResult
    private func invalidateChoreography(for id: Int) -> Int {
        let next = (generations[id] ?? 0) + 1
        generations[id] = next
        return next
    }

    /// Applies a phase only if the choreography that requested it is still
    /// the current one. Returns false to tell the task to stop.
    private func setPhase(_ phase: AgentPhase, of id: Int, ifGeneration generation: Int) -> Bool {
        guard generations[id] == generation, let i = index(of: id) else { return false }
        sessions[i].phase = phase
        return true
    }

    private func index(of id: Int) -> Int? {
        sessions.firstIndex { $0.id == id }
    }
}
