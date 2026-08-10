import SwiftUI
import UniformTypeIdentifiers

/// Settings (⌘,) — two panes, DockKeep style: General for the room's
/// behavior, Agents for the connections (Claude Code's config folders
/// plus every other detected tool).
struct SettingsView: View {

    let office: Office
    let source: ClaudeCodeSource
    /// The app-wide Sparkle updater (owned by RosterApp) — the General
    /// pane hosts the manual "Check for Updates…" button.
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        TabView {
            GeneralSettings(office: office, updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
            ClaudeSettings(source: source)
                .tabItem { Label("Agents", systemImage: "point.3.connected.trianglepath.dotted") }
        }
        .frame(width: 460)
    }
}

// ─────────────────────────────────────────────────────────────────────────

private struct GeneralSettings: View {

    let office: Office
    @ObservedObject var updater: UpdaterModel

    @AppStorage("keepOnTop") private var keepOnTop = false
    @AppStorage("notifyOnArrival") private var notifyOnArrival = true
    @AppStorage("finishThreshold") private var finishThreshold = 45.0

    /// The app-level language override — read once at open; the picker
    /// writes it back. `.system` means "no override".
    @State private var language = AppLanguage.current()
    /// True after the picker changed anything: the new language only
    /// applies at next launch (strings load once, at startup).
    @State private var needsRelaunch = false

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

            Section {
                AvatarStylePicker()
            } header: {
                Text("Your avatar")
            } footer: {
                Text("Agents pick their own outfits — one per desk, stable across launches. These choices only dress you.")
            }

            Section {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                if needsRelaunch {
                    HStack {
                        Text("Takes effect after relaunch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Relaunch now") { Self.relaunch() }
                            .controlSize(.small)
                    }
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version")
                        Text(verbatim: Self.versionString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            } footer: {
                Text("Roster checks once a day on its own; updates install only when you say so.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: finishThreshold) {
            office.finishThreshold = finishThreshold
        }
        .onChange(of: language) {
            language.apply()
            needsRelaunch = true
        }
    }

    private static var versionString: String {
        let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// `open -n` from a detached shell after a beat, then quit — the
    /// standard self-relaunch dance (the delay lets this instance die
    /// before the new one grabs the window position).
    private static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.4; /usr/bin/open -n \"$0\"",
                          Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// The per-app language override, through the standard macOS mechanism:
/// an `AppleLanguages` array in the app's own defaults — exactly what
/// System Settings → Language & Region → Applications writes. No
/// override means "follow the system".
private enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, french

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .english: "English"     // a language reads best in itself,
        case .french: "Français"     // so these two stay untranslated
        }
    }

    /// What's in the defaults right now.
    static func current() -> AppLanguage {
        guard let id = Bundle.main.bundleIdentifier,
              let langs = UserDefaults.standard
                  .persistentDomain(forName: id)?["AppleLanguages"] as? [String],
              let first = langs.first
        else { return .system }
        return first.hasPrefix("fr") ? .french : .english
    }

    /// Writes (or clears) the override. Takes effect at next launch —
    /// bundles resolve their .lproj once, at startup.
    func apply() {
        switch self {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .french:
            UserDefaults.standard.set(["fr"], forKey: "AppleLanguages")
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
                if source.providerStatuses.isEmpty {
                    Text("None detected — install Gemini CLI, Cursor or Codex and this list fills in by itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(source.providerStatuses) { status in
                    providerRow(status)
                }
            } header: {
                Text("Other coding agents")
            } footer: {
                Text("Tools found on this Mac. Connect wires each one to the room through its own mechanism (hooks or notify), always after a timestamped backup of its config.")
            }

            Section {
                Button("Connect everything") {
                    source.connect()
                }
            } footer: {
                Text("Adds Roster's event wiring to every Claude Code folder and every detected tool — each config is backed up first. This is what unlocks the waiting, finished and error states.")
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
    private func providerRow(_ status: ClaudeCodeSource.ProviderStatus) -> some View {
        let display = status.configPath.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
        HStack(spacing: 8) {
            Image(status.kind.logoAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: status.kind.displayName)
                Text(verbatim: display)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status.installed ? "Connected" : "Not connected")
                .font(.caption)
                .foregroundStyle(status.installed ? Color.green : Color.secondary)
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
