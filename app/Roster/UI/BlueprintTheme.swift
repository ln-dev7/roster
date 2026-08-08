import SwiftUI

/// The blueprint palette — architect's ink on paper in light mode, a night
/// blueprint in dark mode.
///
/// Everything in the room is drawn from these six colors. One deliberate
/// rule: no accent color in V0 — state is carried by shape (filled dot,
/// hollow dot, moving dot), not by hue. `warn` is the single exception,
/// reserved for the error state (increment 2).
struct BlueprintTheme {

    /// Paper / background of the room.
    let paper: Color
    /// Primary ink: walls, desks, agents.
    let ink: Color
    /// Secondary ink: chairs, labels, the walk path, dimension marks.
    let inkSoft: Color
    /// Barely-there ink: the drawing grid.
    let inkFaint: Color
    /// Soft halo behind an agent waiting at your desk.
    let glow: Color
    /// Error signal only.
    let warn: Color

    static let light = BlueprintTheme(
        paper: Color(red: 0.973, green: 0.965, blue: 0.941),          // #F8F6F0
        ink: Color(red: 0.200, green: 0.267, blue: 0.373),            // #33445F
        inkSoft: Color(red: 0.200, green: 0.267, blue: 0.373, opacity: 0.50),
        inkFaint: Color(red: 0.200, green: 0.267, blue: 0.373, opacity: 0.13),
        glow: Color(red: 0.200, green: 0.267, blue: 0.373, opacity: 0.16),
        warn: Color(red: 0.753, green: 0.357, blue: 0.357)            // #C05B5B
    )

    static let dark = BlueprintTheme(
        paper: Color(red: 0.055, green: 0.102, blue: 0.180),          // #0E1A2E
        ink: Color(red: 0.663, green: 0.761, blue: 0.910),            // #A9C2E8
        inkSoft: Color(red: 0.663, green: 0.761, blue: 0.910, opacity: 0.55),
        inkFaint: Color(red: 0.663, green: 0.761, blue: 0.910, opacity: 0.12),
        glow: Color(red: 0.663, green: 0.761, blue: 0.910, opacity: 0.20),
        warn: Color(red: 0.878, green: 0.529, blue: 0.529)            // #E08787
    )

    /// Follows the system appearance; no in-app switch needed.
    static func current(for scheme: ColorScheme) -> BlueprintTheme {
        scheme == .dark ? .dark : .light
    }
}
