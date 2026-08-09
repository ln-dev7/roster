import SwiftUI
import UniformTypeIdentifiers

/// Settings (⌘,) — two panes, DockKeep style: General for the room's
/// behavior, Claude Code for the connection and its config folders.
struct SettingsView: View {

    let office: Office
    let source: ClaudeCodeSource

    var body: some View {
        TabView {
            GeneralSettings(office: office)
                .tabItem { Label("General", systemImage: "gearshape") }
            ClaudeSettings(source: source)
                .tabItem { Label("Claude Code", systemImage: "point.3.connected.trianglepath.dotted") }
        }
        .frame(width: 460)
    }
}

// ─────────────────────────────────────────────────────────────────────────

private struct GeneralSettings: View {

    let office: Office

    @AppStorage("keepOnTop") private var keepOnTop = false
    @AppStorage("notifyOnArrival") private var notifyOnArrival = true
    @AppStorage("finishThreshold") private var finishThreshold = 45.0

    var body: some View {
        Form {
            Section {
                Toggle("Keep window on top", isOn: $keepOnTop)
                Toggle("Notify when an agent reaches your desk", isOn: $notifyOnArrival)
            }

            Section {
                Slider(value: $finishThreshold, in: 0...120, step: 15) {
                    Text("Walk threshold")
                } minimumValueLabel: {
                    Text("0 s")
                } maximumValueLabel: {
                    Text("120 s")
                }
            } footer: {
                Text("A finished turn only earns the walk to your desk when the agent worked at least \(Int(finishThreshold)) seconds. Below that, it stays seated — quick replies shouldn't send anyone pacing.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: finishThreshold) {
            office.finishThreshold = finishThreshold
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────

private struct ClaudeSettings: View {

    let source: ClaudeCodeSource
    @State private var showFolderPicker = false

    var body: some View {
        Form {
            Section {
                ForEach(source.roots, id: \.self) { root in
                    rootRow(root)
                }
                Button("Add config folder…") {
                    showFolderPicker = true
                }
            } header: {
                Text("Config folders")
            } footer: {
                Text("Folders named ~/.claude* are found automatically. If your shell aliases point CLAUDE_CONFIG_DIR somewhere else, add that folder here.")
            }

            Section {
                Button("Install hooks in all folders") {
                    source.connect()
                }
            } footer: {
                Text("Adds Roster's event hooks to each folder's settings.json — a timestamped backup is written first. This is what unlocks the waiting, finished and error states.")
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                ClaudeConfigRoots.addExtra(url.path)
                source.refresh()
            }
        }
    }

    @ViewBuilder
    private func rootRow(_ root: URL) -> some View {
        let installed = HookInstaller.isInstalled(at: root.appending(path: "settings.json"))
        let isExtra = ClaudeConfigRoots.extras.contains(root.path)
        let display = root.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(display).font(.body.monospaced())
                Text(installed ? "Hooks installed" : "Presence only — hooks not installed")
                    .font(.caption)
                    .foregroundStyle(installed ? Color.green : Color.secondary)
            }
            Spacer()
            if isExtra {
                Button("Remove") {
                    ClaudeConfigRoots.removeExtra(root.path)
                    source.refresh()
                }
                .controlSize(.small)
            }
        }
    }
}
