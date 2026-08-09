import CoreGraphics

/// Fixed geometry of the pixel office, in *logical pixels*.
///
/// The scene is laid out once on a 384×220 canvas; the view scales it
/// uniformly to fit the window. Everything below is in that logical
/// space — the renderer multiplies by the scale factor at draw time.
///
/// Layout: desk pods along the top (one per project, spread by count),
/// your desk on its rug bottom-center, a lounge to the right, a
/// ping-pong table to the left. The central corridor between the pods
/// and your desk belongs to the walk.
enum RoomPlan {

    static let size = CGSize(width: 384, height: 220)

    /// The top wall band (with windows) is this tall.
    static let wallHeight: CGFloat = 18

    // ── Desk pods ─────────────────────────────────────────────────────────

    struct Pod {
        let x: CGFloat

        var carpet: CGRect { CGRect(x: x, y: 40, width: 56, height: 46) }
        var desk: CGRect { CGRect(x: x + 11, y: 52, width: 34, height: 12) }
        var monitorFrame: CGRect { CGRect(x: x + 22, y: 44, width: 12, height: 9) }
        var screen: CGRect { CGRect(x: x + 23, y: 45, width: 10, height: 6) }
        var chair: CGRect { CGRect(x: x + 23, y: 68, width: 10, height: 8) }
        var plantPot: CGPoint { CGPoint(x: x + 44, y: 80) }

        /// Where an agent sits (feet point). Alone it takes the chair;
        /// two colleagues spread around it.
        func seat(slot: Int, of count: Int) -> CGPoint {
            let center = CGPoint(x: x + 28, y: 76)
            guard count > 1 else { return center }
            return CGPoint(x: center.x + (slot == 0 ? -5 : 5), y: center.y)
        }

        /// Where an agent stands when it gets up, beside the pod.
        func stand(slot: Int) -> CGPoint {
            CGPoint(x: x + 42 + CGFloat(slot) * 10, y: 78)
        }
    }

    /// Pod geometry for station `index` in a room of `count` desks:
    /// spread along the top, centered as a group, mock-identical at 4.
    static func pod(index: Int, of count: Int) -> Pod {
        let podWidth: CGFloat = 56
        guard count > 1 else { return Pod(x: (size.width - podWidth) / 2) }
        let spacing = min(92, (size.width - 28 - podWidth) / CGFloat(count - 1))
        let span = podWidth + spacing * CGFloat(count - 1)
        let start = (size.width - span) / 2
        return Pod(x: start + spacing * CGFloat(index))
    }

    // ── Your corner ───────────────────────────────────────────────────────

    static let youZone = CGRect(x: 150, y: 140, width: 84, height: 60)
    static let youDesk = CGRect(x: 175, y: 160, width: 34, height: 12)
    static let youMonitorFrame = CGRect(x: 186, y: 152, width: 12, height: 9)
    static let youScreen = CGRect(x: 187, y: 153, width: 10, height: 6)
    /// Your character's feet.
    static let youSeat = CGPoint(x: 192, y: 186)
    static let youPlants: [CGPoint] = [
        CGPoint(x: 158, y: 194), CGPoint(x: 222, y: 194),
    ]

    /// Where a finished agent pulls up, on the far side of your desk.
    /// Several of them queue side by side, alternating left and right.
    static func arrival(deskSlot: Int) -> CGPoint {
        let offsets: [CGFloat] = [0, -14, 14, -28, 28, -42]
        let dx = offsets[min(deskSlot, offsets.count - 1)]
        return CGPoint(x: 192 + dx, y: 156)
    }

    // ── The rest of the furniture ─────────────────────────────────────────

    enum Furniture {
        /// Window x-positions in the top wall (each 26 wide).
        static let windowXs: [CGFloat] = [34, 106, 178, 250, 322]

        static let loungeZone = CGRect(x: 282, y: 146, width: 84, height: 50)
        static let sofa = CGRect(x: 302, y: 154, width: 40, height: 12)
        static let lowTable = CGRect(x: 312, y: 176, width: 18, height: 7)
        static let loungePlant = CGPoint(x: 350, y: 190)

        static let pingPong = CGRect(x: 32, y: 152, width: 40, height: 20)
        static let pingPongPlant = CGPoint(x: 20, y: 146)
    }

    // ── View transform ────────────────────────────────────────────────────

    /// Uniform scale-to-fit with centering; shared by the canvas and the
    /// overlay views so everything agrees on where a logical point lands.
    static func transform(in viewSize: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        let scale = min(viewSize.width / size.width, viewSize.height / size.height)
        let offset = CGPoint(
            x: (viewSize.width - size.width * scale) / 2,
            y: (viewSize.height - size.height * scale) / 2
        )
        return (scale, offset)
    }
}
