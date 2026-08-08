import SwiftUI

/// The room. A static blueprint drawn once in a `Canvas`, with live views
/// (agents, walk paths, monitor lights) layered on top.
///
/// Why this split: the `Canvas` costs nothing while nothing changes — SwiftUI
/// is retained-mode, so a calm room is a *free* room (the reason we chose
/// SwiftUI over SpriteKit, whose render loop never sleeps). The few looping
/// animations (monitor breathing, waiting ring) are opacity/scale tweens the
/// system runs out-of-process; the app's CPU stays at zero between events.
struct RoomView: View {

    let office: Office
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = BlueprintTheme.current(for: colorScheme)
        let stationCount = office.workstations.count

        GeometryReader { geo in
            // Uniform scale-to-fit of the 960×540 design canvas.
            let scale = min(geo.size.width / RoomPlan.canvasSize.width,
                            geo.size.height / RoomPlan.canvasSize.height)

            ZStack {
                BlueprintCanvas(theme: theme,
                                stationNames: office.workstations.map(\.name))
                MonitorLights(office: office, theme: theme)

                // Paths under the dots, dots on top.
                ForEach(office.sessions) { session in
                    WalkPathView(
                        session: session,
                        station: RoomPlan.station(index: session.stationIndex, of: stationCount),
                        theme: theme
                    )
                }
                ForEach(office.sessions) { session in
                    AgentDotView(
                        session: session,
                        station: RoomPlan.station(index: session.stationIndex, of: stationCount),
                        seatCount: office.seatCount(onStation: session.stationIndex),
                        theme: theme
                    )
                    // Fade/scale on session start & end. Callers wrap the
                    // structural mutations in `withAnimation` to trigger it.
                    .transition(.opacity.combined(with: .scale(scale: 0.4)))
                }
            }
            .frame(width: RoomPlan.canvasSize.width, height: RoomPlan.canvasSize.height)
            .scaleEffect(scale)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .background(theme.paper)
    }
}

// ─────────────────────────────────────────────────────────────────────────
// The static drawing: walls, grid, door, desks, labels, your desk.
// Redrawn only when the station list or the theme changes.
// ─────────────────────────────────────────────────────────────────────────

private struct BlueprintCanvas: View {

    let theme: BlueprintTheme
    let stationNames: [String]

    var body: some View {
        Canvas { context, _ in
            drawGrid(in: context)
            drawWallsAndDoor(in: context)
            drawDimensionLine(in: context)
            for (index, name) in stationNames.enumerated() {
                let station = RoomPlan.station(index: index, of: stationNames.count)
                draw(station: station, named: name, in: context)
            }
            drawMyDesk(in: context)
        }
    }

    /// The drafting grid, clipped to the room.
    private func drawGrid(in context: GraphicsContext) {
        var grid = Path()
        let wall = RoomPlan.wall
        var x = wall.minX + RoomPlan.gridStep
        while x < wall.maxX {
            grid.move(to: CGPoint(x: x, y: wall.minY))
            grid.addLine(to: CGPoint(x: x, y: wall.maxY))
            x += RoomPlan.gridStep
        }
        var y = wall.minY + RoomPlan.gridStep
        while y < wall.maxY {
            grid.move(to: CGPoint(x: wall.minX, y: y))
            grid.addLine(to: CGPoint(x: wall.maxX, y: y))
            y += RoomPlan.gridStep
        }
        context.stroke(grid, with: .color(theme.inkFaint), lineWidth: 1)
    }

    /// The walls are one open path with a gap at the bottom-left: the door.
    /// The door itself is a leaf line plus the dashed swing arc — drawn the
    /// way an architect draws one.
    private func drawWallsAndDoor(in context: GraphicsContext) {
        let wall = RoomPlan.wall
        let hinge = RoomPlan.doorHinge
        let doorEnd = CGPoint(x: hinge.x + RoomPlan.doorWidth, y: wall.maxY)

        var walls = Path()
        walls.move(to: CGPoint(x: hinge.x, y: wall.maxY))
        walls.addLine(to: CGPoint(x: wall.minX, y: wall.maxY))
        walls.addLine(to: CGPoint(x: wall.minX, y: wall.minY))
        walls.addLine(to: CGPoint(x: wall.maxX, y: wall.minY))
        walls.addLine(to: CGPoint(x: wall.maxX, y: wall.maxY))
        walls.addLine(to: doorEnd)
        context.stroke(walls, with: .color(theme.ink), style: StrokeStyle(lineWidth: 1.6))

        // Door leaf, opened into the room.
        var leaf = Path()
        leaf.move(to: hinge)
        leaf.addLine(to: CGPoint(x: hinge.x, y: wall.maxY - RoomPlan.doorWidth))
        context.stroke(leaf, with: .color(theme.ink), lineWidth: 1.2)

        // Swing arc.
        var swing = Path()
        swing.addArc(center: hinge,
                     radius: RoomPlan.doorWidth,
                     startAngle: .degrees(270),
                     endAngle: .degrees(0),
                     clockwise: false)
        context.stroke(swing, with: .color(theme.inkSoft),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
    }

    /// A decorative dimension line below the room — pure blueprint flavour.
    private func drawDimensionLine(in context: GraphicsContext) {
        let wall = RoomPlan.wall
        let y = wall.maxY + 18
        var dims = Path()
        dims.move(to: CGPoint(x: wall.minX, y: y))
        dims.addLine(to: CGPoint(x: wall.maxX, y: y))
        dims.move(to: CGPoint(x: wall.minX, y: y - 5))
        dims.addLine(to: CGPoint(x: wall.minX, y: y + 5))
        dims.move(to: CGPoint(x: wall.maxX, y: y - 5))
        dims.addLine(to: CGPoint(x: wall.maxX, y: y + 5))
        context.stroke(dims, with: .color(theme.inkSoft), lineWidth: 1)
    }

    private func draw(station: RoomPlan.Station, named name: String,
                      in context: GraphicsContext) {
        // Desk; monitor as an outline — its light is a live overlay.
        context.stroke(Path(station.deskRect), with: .color(theme.ink),
                       style: StrokeStyle(lineWidth: 1.4))
        context.stroke(Path(station.monitorRect), with: .color(theme.inkSoft),
                       style: StrokeStyle(lineWidth: 1))

        // Chair.
        let chair = CGRect(x: station.chairCenter.x - 10, y: station.chairCenter.y - 10,
                           width: 20, height: 20)
        context.stroke(Path(ellipseIn: chair), with: .color(theme.inkSoft),
                       style: StrokeStyle(lineWidth: 1.2))

        // Project name, lettered like a plan annotation.
        var label = context.resolve(
            Text(name.uppercased())
                .font(.system(size: 10, design: .monospaced))
                .kerning(2.5)
        )
        label.shading = .color(theme.inkSoft)
        context.draw(label, at: station.labelPoint, anchor: .center)
    }

    private func drawMyDesk(in context: GraphicsContext) {
        context.stroke(Path(RoomPlan.myDesk), with: .color(theme.ink),
                       style: StrokeStyle(lineWidth: 1.6))
        context.stroke(Path(RoomPlan.myDeskInner), with: .color(theme.inkFaint),
                       style: StrokeStyle(lineWidth: 1))

        let chair = CGRect(x: RoomPlan.myChairCenter.x - 11, y: RoomPlan.myChairCenter.y - 11,
                           width: 22, height: 22)
        context.stroke(Path(ellipseIn: chair), with: .color(theme.inkSoft),
                       style: StrokeStyle(lineWidth: 1.4))

        var label = context.resolve(
            Text("LN")
                .font(.system(size: 10, design: .monospaced))
                .kerning(3)
        )
        label.shading = .color(theme.inkSoft)
        context.draw(label, at: RoomPlan.myLabelPoint, anchor: .center)
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Monitor lights: the bar "breathes" while someone at the station works.
// ─────────────────────────────────────────────────────────────────────────

private struct MonitorLights: View {

    let office: Office
    let theme: BlueprintTheme

    var body: some View {
        let count = office.workstations.count
        ForEach(office.workstations.indices, id: \.self) { index in
            if office.hasWorkingAgent(onStation: index) {
                BreathingBar(rect: RoomPlan.station(index: index, of: count).monitorRect,
                             theme: theme)
            }
        }
    }
}

private struct BreathingBar: View {

    let rect: CGRect
    let theme: BlueprintTheme
    @State private var bright = false

    var body: some View {
        Rectangle()
            .fill(theme.ink)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .opacity(bright ? 0.9 : 0.35)
            .onAppear {
                // A slow tween the render server runs on its own — the app
                // process does no per-frame work for this.
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                    bright = true
                }
            }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// The dashed walk path: draws itself ahead of the agent, retracts after.
// ─────────────────────────────────────────────────────────────────────────

private struct WalkPathView: View {

    let session: AgentSession
    let station: RoomPlan.Station
    let theme: BlueprintTheme

    /// On screen for the whole trip: from standing up (only when the stand
    /// is the prelude to a walk, i.e. status is `finished`) to sitting back
    /// down after the return leg.
    private var isVisible: Bool {
        if session.phase == .walkingBack { return true }
        guard session.status == .finished else { return false }
        switch session.phase {
        case .standing, .walking, .atDesk: return true
        default: return false
        }
    }

    var body: some View {
        LineShape(from: station.standPoint(slot: session.seatSlot),
                  to: RoomPlan.arrival(deskSlot: session.deskSlot))
            // trim + dash = the line draws itself point by point. A cheap
            // effect that reads beautifully on a blueprint.
            .trim(from: 0, to: isVisible ? 1 : 0)
            .stroke(theme.inkSoft, style: StrokeStyle(lineWidth: 1.2, dash: [4, 5]))
            .animation(.easeOut(duration: 0.6), value: isVisible)
    }
}

/// A straight segment in design coordinates. (`Shape` because that is what
/// `.trim` needs to operate on.)
private struct LineShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

// ─────────────────────────────────────────────────────────────────────────
// One agent: a dot of ink. Its position derives from its phase; its look
// derives from its status. Shape carries state — no accent colors.
// ─────────────────────────────────────────────────────────────────────────

private struct AgentDotView: View {

    let session: AgentSession
    let station: RoomPlan.Station
    /// Occupants of this agent's station, for seat spreading.
    let seatCount: Int
    let theme: BlueprintTheme

    private var position: CGPoint {
        switch session.phase {
        case .seated:
            return station.seatPoint(slot: session.seatSlot, of: seatCount)
        case .standing:
            return station.standPoint(slot: session.seatSlot)
        case .walking, .atDesk:
            return RoomPlan.arrival(deskSlot: session.deskSlot)
        case .walkingBack:
            return station.standPoint(slot: session.seatSlot)
        }
    }

    /// Each transition picks its own curve: the walk is a long ease-in-out
    /// (people accelerate then settle), getting up is a short one. The
    /// `.animation(_:value:)` modifier below re-reads this every time the
    /// phase changes, so the right duration applies to the right leg.
    private var transition: Animation {
        switch session.phase {
        case .walking, .walkingBack:
            return .easeInOut(duration: Choreo.walk)
        default:
            return .easeInOut(duration: Choreo.standUp)
        }
    }

    var body: some View {
        ZStack {
            // Halo when waiting at your desk.
            Circle()
                .fill(theme.glow)
                .frame(width: 30, height: 30)
                .opacity(session.phase == .atDesk ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: session.phase == .atDesk)

            // Pulsing ring while the agent waits on you. Inserted only in
            // that state, so its animation starts fresh each time.
            if session.status == .waitingForInput {
                PulseRing(theme: theme)
            }

            dot
        }
        .position(position)
        // Movement animation, keyed on the phase…
        .animation(transition, value: session.phase)
        // …plus a short slide when a colleague joins/leaves the station and
        // the seat re-centers, or when the room re-spreads its desks.
        .animation(.easeInOut(duration: Choreo.standUp), value: seatCount)
        .animation(.easeInOut(duration: Choreo.standUp), value: station)
    }

    /// Filled = working/finished · hollow = waiting on you · warn + cross =
    /// failed. The vocabulary of the legend, in one place.
    @ViewBuilder
    private var dot: some View {
        switch session.status {
        case .failed:
            ZStack {
                Circle().fill(theme.warn).frame(width: 14, height: 14)
                CrossMark()
                    .stroke(theme.paper, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 7, height: 7)
            }
        case .waitingForInput:
            Circle()
                .strokeBorder(theme.ink, lineWidth: 2)
                .frame(width: 15, height: 15)
        case .working, .finished:
            Circle().fill(theme.ink).frame(width: 14, height: 14)
        }
    }
}

/// The expanding, fading ring of the "needs you" state.
private struct PulseRing: View {

    let theme: BlueprintTheme
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(theme.ink, lineWidth: 1.4)
            .frame(width: 20, height: 20)
            .scaleEffect(expanded ? 1.8 : 0.8)
            .opacity(expanded ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 2.8).repeatForever(autoreverses: false)) {
                    expanded = true
                }
            }
    }
}

/// A small ×, used only for the error state.
private struct CrossMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
