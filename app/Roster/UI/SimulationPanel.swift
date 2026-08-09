import SwiftUI

/// Debug controls: spawn agents on stations and push each one through every
/// domain event the real data source sends. Hidden behind the Debug menu
/// once connected — and kept forever as the GIF-recording rig.
struct SimulationPanel: View {

    let office: Office

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Simulate")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                if office.workstations.isEmpty {
                    Button("Seed demo room") {
                        withAnimation(.easeOut(duration: 0.45)) {
                            office.seedDemo()
                        }
                    }
                } else {
                    // One colleague per desk: adding an agent always adds
                    // a fresh desk with it. withAnimation drives the
                    // insertion transition (fade + scale) in RoomView;
                    // `_ =` because spawnDemoAgent returns the new id and
                    // withAnimation would otherwise adopt (and propagate)
                    // that as its own return type.
                    Button("+ Agent") {
                        withAnimation(.easeOut(duration: 0.45)) {
                            _ = office.spawnDemoAgent()
                        }
                    }
                    .disabled(office.workstations.count >= Office.maxStations)
                }

                Spacer()

                Button("Reset demo") {
                    withAnimation(.easeOut(duration: 0.45)) {
                        office.clearRoom()
                        office.seedDemo()
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
        let station = office.workstations.indices.contains(session.stationIndex)
            ? office.workstations[session.stationIndex].name
            : "?"
        return "\(station) · agent \(session.id)"
    }
}
