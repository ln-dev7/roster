import SwiftUI

/// The left panel: who's in the room and in what state, grouped by
/// urgency — what needs you first. Clicking a row selects the agent, the
/// same selection as clicking it in the room: the detail card opens on
/// the right. The footer carries the in-app Settings button (DockKeep
/// habit) and the app version.
struct SidebarView: View {

    let office: Office
    let source: ClaudeCodeSource
    /// Shared with the room and the detail card.
    @Binding var selection: Int?

    private var needsYou: [AgentSession] {
        office.sessions.filter { $0.status == .waitingForInput || $0.status == .failed }
    }
    private var atYourDesk: [AgentSession] {
        office.sessions.filter { $0.status == .finished }
    }
    private var working: [AgentSession] {
        office.sessions.filter { $0.status == .working }
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
                    if office.sessions.isEmpty {
                        Text("No sessions yet — open a Claude Code session.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                    }
                    sessionSection(title: "Needs you", sessions: needsYou)
                    sessionSection(title: "At your desk", sessions: atYourDesk)
                    sessionSection(title: "Working", sessions: working)
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
                    SidebarSessionRow(office: office, session: session, selection: $selection)
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

/// One session in the list. Clicking it selects the agent — the row gets
/// a quiet tint while its detail card is open.
private struct SidebarSessionRow: View {

    let office: Office
    let session: AgentSession
    @Binding var selection: Int?

    private var name: String {
        office.displayName(for: session)
    }

    var body: some View {
        Button {
            selection = session.id
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
        .background(
            selection == session.id ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
    }
}
