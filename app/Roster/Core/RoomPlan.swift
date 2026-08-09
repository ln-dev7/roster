import CoreGraphics

/// Fixed geometry of the room, in *design units*.
///
/// The room is laid out once on a 960×540 canvas and the view scales the
/// whole thing to fit the window — much easier to reason about than
/// proportional layout, and it guarantees the composition never degrades.
/// Every point below lives in this design space.
///
/// Stations are now *computed*: give an index and the total count, get the
/// geometry. The room spreads one to six desks evenly along the top wall.
enum RoomPlan {

    static let canvasSize = CGSize(width: 960, height: 540)

    /// Inner face of the walls.
    static let wall = CGRect(x: 20, y: 20, width: 920, height: 470)

    /// Spacing of the drafting grid.
    static let gridStep: CGFloat = 24

    // ── Workstations ─────────────────────────────────────────────────────

    /// Pure geometry of one desk; names live in `Workstation`.
    struct Station: Equatable {
        let centerX: CGFloat

        /// The desk, seen from above.
        var deskRect: CGRect { CGRect(x: centerX - 42, y: 92, width: 84, height: 34) }
        /// The monitor bar on the desk (outline when off; the view overlays
        /// a breathing fill while someone works).
        var monitorRect: CGRect { CGRect(x: centerX - 18, y: 99, width: 36, height: 6) }
        /// The chair.
        var chairCenter: CGPoint { CGPoint(x: centerX, y: 152) }
        /// Project name, lettered like a drawing annotation.
        var labelPoint: CGPoint { CGPoint(x: centerX, y: 193) }

        /// Where an agent sits. Alone it takes the chair; when two share
        /// the station they spread symmetrically around it.
        func seatPoint(slot: Int, of count: Int) -> CGPoint {
            guard count > 1 else { return chairCenter }
            let dx: CGFloat = slot == 0 ? -14 : 14
            return CGPoint(x: chairCenter.x + dx, y: chairCenter.y)
        }

        /// Where an agent stands when it gets up; the second occupant
        /// stands a step further out so the two never overlap.
        func standPoint(slot: Int) -> CGPoint {
            CGPoint(x: centerX + 34 + CGFloat(slot) * 24, y: 152)
        }
    }

    /// Geometry of station `index` in a room of `count` desks: evenly
    /// spread along the top wall, centered as a group.
    static func station(index: Int, of count: Int) -> Station {
        let usable = wall.insetBy(dx: 80, dy: 0)
        let n = CGFloat(max(count, 1))
        let spacing = usable.width / n
        let centerX = usable.minX + spacing * (CGFloat(index) + 0.5)
        return Station(centerX: centerX)
    }

    // ── Your desk ────────────────────────────────────────────────────────

    static let myDesk = CGRect(x: 400, y: 400, width: 160, height: 44)
    static let myDeskInner = CGRect(x: 406, y: 406, width: 148, height: 32)
    static let myChairCenter = CGPoint(x: 480, y: 468)
    static let myLabelPoint = CGPoint(x: 480, y: 422)

    /// Where a finished agent pulls up, on the far side of your desk.
    static let arrivalPoint = CGPoint(x: 480, y: 384)

    /// Several finished agents queue side by side: first in the middle,
    /// the next ones alternating left and right.
    static func arrival(deskSlot: Int) -> CGPoint {
        let offsets: [CGFloat] = [0, -30, 30, -58, 58, -86]
        let dx = offsets[min(deskSlot, offsets.count - 1)]
        return CGPoint(x: arrivalPoint.x + dx, y: arrivalPoint.y)
    }

    // ── Door (bottom-left), drawn like an architect would ────────────────

    static let doorHinge = CGPoint(x: 140, y: 490)
    static let doorWidth: CGFloat = 70

    // ── Sheet dressing ────────────────────────────────────────────────────
    //
    // The room stays sparse — no furniture clusters, they read as clutter.
    // What remains is the architect's *sheet* vocabulary: window symbols in
    // the walls, a few plant bushes in the corners, the title block and the
    // north arrow. Pure line work, nothing animated, and nothing anywhere
    // near the walking corridor.

    enum Furniture {
        /// Window segments in the top wall (x, width); the symbol is a
        /// paper gap crossed by two parallel lines.
        static let windows: [(x: CGFloat, width: CGFloat)] = [
            (255, 60), (545, 60), (715, 60),
        ]

        /// Plant bushes: center + radius, tucked in the corners.
        static let plants: [(center: CGPoint, radius: CGFloat)] = [
            (CGPoint(x: 62, y: 58), 11),
            (CGPoint(x: 62, y: 448), 11),
            (CGPoint(x: 895, y: 452), 11),
        ]

        /// Title block, bottom right of the sheet.
        static let cartouche = CGRect(x: 690, y: 496, width: 250, height: 26)
        static let cartoucheDividerXs: [CGFloat] = [780, 866]
        static let cartoucheLabels: [(text: String, x: CGFloat)] = [
            ("ROSTER", 735), ("FLOOR PLAN", 823), ("1:50", 903),
        ]

        static let northArrowCenter = CGPoint(x: 920, y: 50)

        /// The dimension line stops before the cartouche.
        static let dimensionMaxX: CGFloat = 660
    }
}
