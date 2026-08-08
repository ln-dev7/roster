import SwiftUI

/// Debug controls: spawn agents on stations and push each one through every
/// domain event the real data source will send in increment 3. This panel is
/// scaffolding — it moves behind a hidden menu later, and doubles as the
/// GIF-recording rig forever.
struct SimulationPanel: View {

    let office: Office

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Simulate")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(RoomPlan.stations.indices, id: \.self) { index in
                    Button("+ \(RoomPlan.stations[index].name)") {
                        // withAnimation drives the dot's insertion
                        // transition (fade + scale) in RoomView.
                        withAnimation(.easeOut(duration: 0.45)) {
                            office.startSession(onStation: index)
                        }
                    }
                    .disabled(!office.canAddSession(onStation: index))
                }

                Spacer()

                Button("Reset") {
                    withAnimation(.easeOut(duration: 0.45)) {
                        office.reset()
                    }
                }
            }

            ForEach(office.sessions) { session in
                HStack(spacing: 6) {
                    Text(label(for: session))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)

                    Button("Needs input") { office.needsInput(session.id) }
                        .disabled(session.status != .working)
                    Button("Finished") { office.finish(session.id) }
                        .disabled(session.status == .finished || session.status == .failed)
                    Button("Answered") { office.resumeWorking(session.id) }
                        .disabled(session.status == .working)
                    Button("Error") { office.fail(session.id) }
                        .disabled(session.status == .failed)
                    Button("End") {
                        withAnimation(.easeOut(duration: 0.45)) {
                            office.endSession(session.id)
                        }
                    }

                    Spacer()
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func label(for session: AgentSession) -> String {
        "\(RoomPlan.stations[session.stationIndex].name) · agent \(session.id)"
    }
}
