import SwiftUI

/// The left panel: who's in the room and in what state, grouped by
/// urgency — what needs you first. Clicking a row opens the same popover
/// as clicking the agent in the room. The footer carries the in-app
/// Settings button (DockKeep habit) and the app version.
struct SidebarView: View {

    let office: Office
    let source: ClaudeCodeSource

    private var needsYou: [AgentSession] {
        office.sessions.filter { $0.status == .waitingForInput || $0.status == .failed }
    }
    private var atYourDesk: [AgentSession] {
        office.sessions.filter { $0.status == .finished }
    }
    private var working: [AgentSession] {
        office.sessions.filter { $0.status == .working }
    }
    private var emptyDesks: [Int] {
        office.workstations.indices.filter { index in
            !office.sessions.contains { $0.stationIndex == index }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: wordmark + connection dot.
            HStack(spacing: 8) {
                Text(verbatim: "ROSTER")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .kerning(3)
                Spacer()
                Circle()
                    .fill(source.state == .connected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .help(source.state == .connected
                          ? Text("Connected to Claude Code")
                          : Text("Presence only — hooks not installed"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if office.sessions.isEmpty && office.workstations.isEmpty {
                        Text("No sessions yet — open a Claude Code session.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                    }
                    sessionSection(title: "Needs you", sessions: needsYou)
                    sessionSection(title: "At your desk", sessions: atYourDesk)
                    sessionSection(title: "Working", sessions: working)
                    emptyDeskSection
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
            Divider()

            // Footer: Settings, right here in the app.
            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: appVersion)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func sessionSection(title: LocalizedStringKey, sessions: [AgentSession]) -> some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader(title, count: sessions.count)
                ForEach(sessions) { session in
                    SidebarSessionRow(office: office, session: session)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyDeskSection: some View {
        if !emptyDesks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("Empty desks", count: emptyDesks.count)
                ForEach(emptyDesks, id: \.self) { index in
                    HStack(spacing: 8) {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                        Text(verbatim: office.workstations[index].name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(verbatim: "\(count)")
                .foregroundStyle(.tertiary)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 6)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            .flatMap { $0 as? String } ?? ""
    }
}

/// One session in the list. Its own view so each row owns its popover.
private struct SidebarSessionRow: View {

    let office: Office
    let session: AgentSession
    @State private var showActions = false

    private var name: String {
        office.workstations.indices.contains(session.stationIndex)
            ? office.workstations[session.stationIndex].name
            : "?"
    }

    var body: some View {
        Button {
            showActions = true
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.status.uiColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name)
                        .font(.callout)
                    Text(verbatim: session.status.uiLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showActions, arrowEdge: .trailing) {
            AgentPopover(office: office, session: session)
        }
    }
}
