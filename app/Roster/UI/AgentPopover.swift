import SwiftUI

/// What you get when you click an agent: who it is, what it last said,
/// and the three actions. Nothing more — this is a tooltip with hands,
/// not a dashboard.
struct AgentPopover: View {

    let office: Office
    let session: AgentSession

    private var workstation: Workstation? {
        guard office.workstations.indices.contains(session.stationIndex) else { return nil }
        return office.workstations[session.stationIndex]
    }

    private var statusLabel: String {
        switch session.status {
        case .working: return "Working"
        case .waitingForInput: return "Needs your input"
        case .finished: return "Finished — waiting for your review"
        case .failed: return "Last turn failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Identity.
            VStack(alignment: .leading, spacing: 2) {
                Text(workstation?.name ?? "unknown")
                    .font(.headline)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // The last thing the agent said (from the Stop hook).
            if let summary = office.lastSummary[session.id], !summary.isEmpty {
                ScrollView {
                    Text(summary)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No summary yet — it appears after the agent's first finished turn.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            // The three actions. The folder ones are disabled for demo
            // desks (no repository behind them); "Reviewed" always works.
            HStack(spacing: 8) {
                Button("Open in VS Code") {
                    if let path = workstation?.path {
                        WorkspaceActions.openInVSCode(path: path)
                    }
                }
                .disabled(workstation?.path == nil)

                Button("Open Terminal") {
                    if let path = workstation?.path {
                        WorkspaceActions.openTerminal(path: path)
                    }
                }
                .disabled(workstation?.path == nil)

                Spacer()

                if session.status == .finished {
                    Button("Reviewed") {
                        office.resumeWorking(session.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
    }
}
