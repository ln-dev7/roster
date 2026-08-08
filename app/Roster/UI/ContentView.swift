import SwiftUI

/// Root view: connection banner when needed, the room, and the simulation
/// panel (visible until Roster is connected, then on demand via the Debug
/// menu — it doubles as the GIF-recording studio).
struct ContentView: View {

    /// One `Office`, one source feeding it. Created together here so the
    /// source can hold the office; `@State` keeps both alive for the life
    /// of the window.
    @State private var office: Office
    @State private var source: ClaudeCodeSource

    /// Toggled from the Debug menu (same key there).
    @AppStorage("showSimulationPanel") private var showSimulationPanel = false

    init() {
        let office = Office()
        _office = State(initialValue: office)
        _source = State(initialValue: ClaudeCodeSource(office: office))
    }

    private var isPanelVisible: Bool {
        // Before connection the panel is the only way to see the product
        // move, so it stays. After that, it's opt-in.
        showSimulationPanel || source.state != .connected
    }

    var body: some View {
        VStack(spacing: 0) {
            switch source.state {
            case .notConnected:
                ConnectBanner(source: source)
            case .failed(let message):
                ErrorBanner(message: message, source: source)
            case .checking, .connected:
                EmptyView()
            }

            RoomView(office: office)

            if isPanelVisible {
                Divider()
                SimulationPanel(office: office)
            }
        }
        // Below this the room becomes hard to read; the window is free to
        // grow as much as it likes.
        .frame(minWidth: 720, minHeight: 500)
        .task {
            source.refresh()
            // No hook yet → show something alive rather than an empty room.
            if source.state != .connected && office.workstations.isEmpty {
                office.seedDemo()
            }
        }
    }
}

/// One calm sentence and one button. Installing the hook is the app's only
/// invasive act, so the banner says exactly what it touches.
private struct ConnectBanner: View {

    let source: ClaudeCodeSource

    var body: some View {
        HStack(spacing: 10) {
            Text("Demo data. Connect Roster to Claude Code — adds a small hook to ~/.claude/settings.json (a backup is made first).")
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
    ContentView()
}
