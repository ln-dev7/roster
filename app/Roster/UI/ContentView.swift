import SwiftUI

/// Root view: the room on top, the simulation panel underneath.
///
/// The panel is temporary furniture — once real Claude Code sessions feed the
/// room (increment 3), it moves behind a hidden debug menu and becomes our
/// GIF-recording studio. It never ships as visible UI.
struct ContentView: View {

    /// `@State` + `@Observable` model: SwiftUI keeps this single instance
    /// alive for the life of the window and re-renders whatever reads it.
    /// (`@Observable` is the macOS 14 replacement for ObservableObject —
    /// views track exactly the properties they touch, nothing more.)
    @State private var office = Office()

    var body: some View {
        VStack(spacing: 0) {
            RoomView(office: office)
            Divider()
            SimulationPanel(office: office)
        }
        // Below this the room becomes hard to read; the window is free to
        // grow as much as it likes.
        .frame(minWidth: 720, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
