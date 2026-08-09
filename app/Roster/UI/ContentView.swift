import SwiftUI

/// Root view: connection banner when needed, the room, and the simulation
/// panel (visible until Roster is connected, then on demand via the Debug
/// menu — it doubles as the GIF-recording studio).
struct ContentView: View {

    /// Owned by `RosterApp` (the Settings scene needs them too); this view
    /// only uses them.
    let office: Office
    let source: ClaudeCodeSource

    /// Toggled from the Debug menu (same key there).
    @AppStorage("showSimulationPanel") private var showSimulationPanel = false

    /// Toggled from the View menu and Settings (same key): floating window
    /// level, so the room stays visible in a corner while you work.
    @AppStorage("keepOnTop") private var keepOnTop = false

    /// The selected session (room click, desk click or sidebar row — all
    /// the same value). Non-nil opens the detail card over the room; the
    /// card vanishes on ✕, on a floor click, or when the session ends —
    /// a stale id simply stops resolving and nothing renders.
    @State private var selectedSessionID: Int?

    private var isPanelVisible: Bool {
        // Before connection the panel is the only way to see the product
        // move, so it stays. After that, it's opt-in.
        showSimulationPanel || source.state != .connected
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(office: office, source: source, selection: $selectedSessionID)
            Divider()

            VStack(spacing: 0) {
                switch source.state {
                case .notConnected:
                    ConnectBanner(source: source)
                case .failed(let message):
                    ErrorBanner(message: message, source: source)
                case .checking, .connected:
                    EmptyView()
                }

                // The room, with the Gather-style detail card floating
                // over its right edge when an agent is selected.
                ZStack(alignment: .topTrailing) {
                    RoomView(office: office, selection: $selectedSessionID)

                    if let id = selectedSessionID, let session = office.session(id) {
                        DetailCard(office: office, session: session) {
                            selectedSessionID = nil
                        }
                        .padding(12)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.22), value: selectedSessionID)

                if isPanelVisible {
                    Divider()
                    SimulationPanel(office: office)
                }
            }
        }
        // Below this the room becomes hard to read; the window is free to
        // grow as much as it likes.
        .frame(minWidth: 960, minHeight: 500)
        .task {
            // Wire the arrival notification: core fires the callback, the
            // app layer decides what it means. [weak office] breaks the
            // cycle (the closure is stored on the office itself).
            office.onAgentArrived = { [weak office] session in
                // Live read so the Settings toggle applies immediately.
                let wantsNotification = (UserDefaults.standard
                    .object(forKey: "notifyOnArrival") as? Bool) ?? true
                guard wantsNotification,
                      let office,
                      office.workstations.indices.contains(session.stationIndex)
                else { return }
                Notifier.agentArrived(
                    project: office.workstations[session.stationIndex].name
                )
            }
            Notifier.requestPermissionIfNeeded()

            // Settings persisted from previous launches.
            office.finishThreshold = (UserDefaults.standard
                .object(forKey: "finishThreshold") as? Double) ?? 45
            WindowLevel.apply(keepOnTop: keepOnTop)

            source.refresh()
            // No hook yet → show something alive rather than an empty room.
            if source.state != .connected && office.workstations.isEmpty {
                office.seedDemo()
            }
        }
        .onChange(of: keepOnTop) {
            WindowLevel.apply(keepOnTop: keepOnTop)
        }
    }
}

/// One calm sentence and one button. Installing the hook is the app's only
/// invasive act, so the banner says exactly what it touches.
private struct ConnectBanner: View {

    let source: ClaudeCodeSource

    var body: some View {
        HStack(spacing: 10) {
            Text("Sessions appear automatically (read-only). Connect to unlock the waiting, finished and error states — adds a small hook to ~/.claude/settings.json, after backing it up.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Connect") {
                withAnimation(.easeOut(duration: 0.45)) {
                    source.connect()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4))
    }
}

private struct ErrorBanner: View {

    let message: String
    let source: ClaudeCodeSource

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
            Spacer()
            Button("Retry") { source.connect() }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4))
    }
}

#Preview {
    let office = Office()
    return ContentView(office: office, source: ClaudeCodeSource(office: office))
}
