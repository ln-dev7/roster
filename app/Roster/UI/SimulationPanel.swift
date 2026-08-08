import SwiftUI

/// Debug controls for the prototype: one "finished" button per agent, and a
/// reset. This panel is scaffolding — it moves behind a hidden menu once real
/// sessions drive the room, and doubles as the GIF-recording rig forever.
struct SimulationPanel: View {

    let sim: AgentSim

    var body: some View {
        HStack(spacing: 12) {
            Text("Simulate")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(sim.agents) { agent in
                Button("\(agent.name) finished") {
                    sim.finishWork(agentID: agent.id)
                }
                .disabled(agent.isBusy)
            }

            Spacer()

            Button("Reset") {
                sim.resetAll()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
