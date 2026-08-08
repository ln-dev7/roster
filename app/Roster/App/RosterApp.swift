import SwiftUI

/// The application entry point.
///
/// `@main` marks the struct launched at startup. An `App` holds scenes; a
/// `WindowGroup` describes a standard macOS window. One window is the whole
/// product for now — the room *is* the app.
@main
struct RosterApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
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
        }
    }
}
