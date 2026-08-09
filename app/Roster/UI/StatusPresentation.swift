import SwiftUI

/// How a session status presents itself outside the room: the sidebar and
/// the detail card share these. (Inside the room, shape carries state; out
/// here in regular UI, a label and a color are the right vocabulary.)
extension SessionStatus {

    var uiLabel: String {
        switch self {
        case .working:
            return String(localized: "Working")
        case .waitingForInput:
            return String(localized: "Needs your input")
        case .finished:
            return String(localized: "Finished — waiting for your review")
        case .failed:
            return String(localized: "Last turn failed")
        }
    }

    var uiColor: Color {
        switch self {
        case .working: return .green
        case .waitingForInput: return .orange
        case .finished: return .purple
        case .failed: return .red
        }
    }
}
