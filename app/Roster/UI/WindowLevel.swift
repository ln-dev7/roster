import AppKit

/// The "keep on top" toggle: a floating window level keeps the little room
/// visible in a corner while you work — one of the two reasons Roster
/// exists (the other walks to your desk).
enum WindowLevel {

    static func apply(keepOnTop: Bool) {
        for window in NSApp.windows where window.isVisible {
            window.level = keepOnTop ? .floating : .normal
        }
    }
}
