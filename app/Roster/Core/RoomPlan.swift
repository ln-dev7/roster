import CoreGraphics

/// Fixed geometry of the room, in *design units*.
///
/// The room is laid out once on a 960×540 canvas and the view scales the
/// whole thing to fit the window — much easier to reason about than
/// proportional layout, and it guarantees the composition never degrades.
/// Every point below lives in this design space.
enum RoomPlan {

    static let canvasSize = CGSize(width: 960, height: 540)

    /// Inner face of the walls.
    static let wall = CGRect(x: 20, y: 20, width: 920, height: 470)

    /// Spacing of the drafting grid.
    static let gridStep: CGFloat = 24

    // ── Workstations ─────────────────────────────────────────────────────

    /// One project = one workstation. Three fake ones for the prototype;
    /// increment 3 will create these from real repositories.
    struct Station {
        let name: String
        let centerX: CGFloat

        /// The desk, seen from above.
        var deskRect: CGRect { CGRect(x: centerX - 42, y: 92, width: 84, height: 34) }
        /// The monitor: a filled bar on the desk.
        var monitorRect: CGRect { CGRect(x: centerX - 18, y: 99, width: 36, height: 6) }
        /// The chair — also where a seated agent sits.
        var chairCenter: CGPoint { CGPoint(x: centerX, y: 152) }
        /// Where an agent stands when it gets up.
        var standPoint: CGPoint { CGPoint(x: centerX + 34, y: 152) }
        /// Project name, lettered like a drawing annotation.
        var labelPoint: CGPoint { CGPoint(x: centerX, y: 193) }
    }

    static let stations: [Station] = [
        Station(name: "circle", centerX: 190),
        Station(name: "dockkeep", centerX: 480),
        Station(name: "blog", centerX: 770),
    ]

    // ── Your desk ────────────────────────────────────────────────────────

    static let myDesk = CGRect(x: 400, y: 400, width: 160, height: 44)
    static let myDeskInner = CGRect(x: 406, y: 406, width: 148, height: 32)
    static let myChairCenter = CGPoint(x: 480, y: 468)
    static let myLabelPoint = CGPoint(x: 480, y: 422)

    /// Where a finished agent pulls up, on the far side of your desk.
    static let arrivalPoint = CGPoint(x: 480, y: 384)

    // ── Door (bottom-left), drawn like an architect would ────────────────

    static let doorHinge = CGPoint(x: 140, y: 490)
    static let doorWidth: CGFloat = 70
}
