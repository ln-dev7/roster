import SwiftUI

/// The application entry point.
///
/// `@main` marks the struct launched at startup. An `App` holds scenes; a
/// `WindowGroup` describes a standard macOS window. One window is the whole
/// product — the room *is* the app.
///
/// The office and its data source are created HERE, once, because two
/// scenes need them: the room window and the Settings window. (Same
/// reasoning as DockKeep's updater living in the App struct.)
@main
struct RosterApp: App {

    @State private var office: Office
    @State private var source: ClaudeCodeSource

    /// Sparkle, wired but silent until the update feed ships (see
    /// UpdaterModel). One long-lived instance, as Sparkle expects.
    @StateObject private var updater = UpdaterModel()

    /// Same storage keys as ContentView/Settings: the menus drive what the
    /// window does. `@AppStorage` persists them across launches.
    @AppStorage("showSimulationPanel") private var showSimulationPanel = false
    @AppStorage("keepOnTop") private var keepOnTop = false
    @AppStorage("showSidebar") private var showSidebar = true
    /// Onboarding flag: false until the welcome card was dismissed once.
    /// Help → "Welcome to Roster" simply flips it back.
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    init() {
        let office = Office()
        _office = State(initialValue: office)
        _source = State(initialValue: ClaudeCodeSource(office: office))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(office: office, source: source)
        }
        // Content runs to the top edge; the traffic lights float over it.
        // The room looks better without a title bar chopping it off.
        .windowStyle(.hiddenTitleBar)
        // A comfortable default that shows the whole room at design scale.
        // The room view rescales itself, so free resizing is safe.
        .defaultSize(width: 1040, height: 660)
        .commands {
            // One window is the whole app; "New Window" would only confuse.
            CommandGroup(replacing: .newItem) {}

            // Right under "About Roster", where every Mac user looks for
            // it. Disabled until the update feed exists.
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }

            // The sidebar toggle, in the View menu with the standard macOS
            // shortcut (⌃⌘S, same as Finder or Mail).
            CommandGroup(after: .sidebar) {
                Toggle("Show Sidebar", isOn: $showSidebar)
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }

            // Floating window level, in the View menu where it belongs.
            CommandGroup(after: .windowSize) {
                Toggle("Keep on Top", isOn: $keepOnTop)
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }

            // Help: reopen the welcome card instead of a help book nobody
            // would read.
            CommandGroup(replacing: .help) {
                Button("Welcome to Roster") {
                    hasSeenWelcome = false
                }
            }

            // The simulation panel: our permanent GIF-recording studio,
            // hidden by default once real sessions feed the room.
            CommandMenu("Debug") {
                Toggle("Show Simulation Panel", isOn: $showSimulationPanel)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        // Gives "Settings…" its usual place in the app menu and ⌘, for free.
        Settings {
            SettingsView(office: office, source: source)
        }
    }
}
