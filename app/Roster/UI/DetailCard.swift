import SwiftUI

/// The Gather-style profile card, floating over the room's right edge.
///
/// Clicking an agent in the room or a row in the sidebar selects it; this
/// card shows who it is, what it last said, and the three actions. Unlike
/// the old popover it stays open while you watch the room — it goes away
/// when you press ✕, click the floor, or the session ends (`ContentView`
/// stops rendering it the moment the session is gone).
struct DetailCard: View {

    let office: Office
    let session: AgentSession
    /// The card never owns the selection; closing is the parent's move.
    let onClose: () -> Void

    private var workstation: Workstation? {
        guard office.workstations.indices.contains(session.stationIndex) else { return nil }
        return office.workstations[session.stationIndex]
    }

    private var name: String { workstation?.name ?? "unknown" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            portrait
            VStack(alignment: .leading, spacing: 10) {
                header
                summary
                Divider()
                actions
            }
            .padding(14)
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
    }

    /// A big pixel portrait on a wash of the status color — the card's
    /// Gather moment. Same sprite as in the room, just larger.
    private var portrait: some View {
        ZStack {
            session.status.uiColor.opacity(0.15)
            PixelSprite(
                look: SpriteLook.derive(from: name, slot: session.seatSlot),
                pose: .standing,
                scale: 5,
                shadowColor: .black.opacity(0.15)
            )
        }
        .frame(height: 110)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: name)
                .font(.title3.weight(.semibold))
            HStack(spacing: 6) {
                Circle()
                    .fill(session.status.uiColor)
                    .frame(width: 8, height: 8)
                Text(verbatim: session.status.uiLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let path = workstation?.path {
                Text(verbatim: path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// The last thing the agent said (from the Stop hook).
    @ViewBuilder
    private var summary: some View {
        if let text = office.lastSummary[session.id], !text.isEmpty {
            ScrollView {
                Text(text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 150)
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text("No summary yet — it appears after the agent's first finished turn.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// The three actions. The folder ones are disabled for demo desks
    /// (no repository behind them); "Reviewed" appears once there is
    /// something to review.
    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if let path = workstation?.path {
                        WorkspaceActions.openInVSCode(path: path)
                    }
                } label: {
                    Text("Open in VS Code").frame(maxWidth: .infinity)
                }
                .disabled(workstation?.path == nil)

                Button {
                    if let path = workstation?.path {
                        WorkspaceActions.openTerminal(path: path)
                    }
                } label: {
                    Text("Open Terminal").frame(maxWidth: .infinity)
                }
                .disabled(workstation?.path == nil)
            }
            .buttonStyle(.bordered)

            if session.status == .finished {
                Button {
                    office.resumeWorking(session.id)
                } label: {
                    Text("Reviewed").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.small)
    }
}
