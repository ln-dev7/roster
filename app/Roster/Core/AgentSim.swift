import Foundation
import Observation

/// Where an agent is, and what that means.
///
/// This enum *is* the product: every visual in the room derives from it.
/// The prototype only exercises the walk; the waiting/error states join in
/// increment 2, and increment 3 will drive these phases from real Claude
/// Code events instead of buttons.
enum AgentPhase: Equatable {
    /// At its station, working. The calm default — nothing moves.
    case seated
    /// Just stood up, about to walk (also the pose beside the chair).
    case standing
    /// Crossing the room toward your desk. The three seconds that matter.
    case walking
    /// Arrived. Waits at your desk (halo) — in real life: waiting for review.
    case atDesk
    /// Heading back to its station.
    case walkingBack
}

/// One agent in the simulation. A struct on purpose: replacing an element in
/// `AgentSim.agents` is what lets `@Observable` notice the change.
struct SimAgent: Identifiable {
    let id: Int
    let name: String
    /// Index into `RoomPlan.stations`.
    let stationIndex: Int
    var phase: AgentPhase = .seated

    /// A choreography is running; the simulate button disables itself.
    var isBusy: Bool { phase != .seated }
}

/// Timing of the choreography, in seconds. Tuned by eye — these four numbers
/// are the feel of the whole app, so they live in one place with names.
enum Choreo {
    /// Getting up / sitting down.
    static let standUp: Double = 0.45
    /// A short beat between standing and setting off — people don't launch.
    static let beat: Double = 0.25
    /// The crossing itself.
    static let walk: Double = 2.9
    /// How long the prototype waits at your desk before heading back.
    /// (The real app will stay until you dismiss it.)
    static let deskPause: Double = 3.2
}

/// Fake data source for increment 1: three seated agents and one button per
/// agent that plays the full "finished work" choreography.
///
/// `@MainActor` because it drives UI state directly; `@Observable` so views
/// re-render on each phase change without any plumbing.
@MainActor
@Observable
final class AgentSim {

    var agents: [SimAgent] = RoomPlan.stations.enumerated().map { index, station in
        SimAgent(id: index, name: station.name, stationIndex: index)
    }

    /// Plays: stand up → beat → walk over → wait at the desk → walk back →
    /// sit down. Phase changes are plain assignments; the *views* decide how
    /// each transition animates (see `AgentDotView`), which keeps this model
    /// free of any SwiftUI import.
    func finishWork(agentID: Int) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }),
              agents[index].phase == .seated else { return }

        Task {
            setPhase(.standing, at: index)
            await pause(Choreo.standUp + Choreo.beat)

            setPhase(.walking, at: index)
            await pause(Choreo.walk)

            setPhase(.atDesk, at: index)
            await pause(Choreo.deskPause)

            setPhase(.walkingBack, at: index)
            await pause(Choreo.walk)

            setPhase(.seated, at: index)
        }
    }

    /// Everyone back to their seat, instantly. Handy while recording.
    func resetAll() {
        for index in agents.indices {
            agents[index].phase = .seated
        }
    }

    private func setPhase(_ phase: AgentPhase, at index: Int) {
        agents[index].phase = phase
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
