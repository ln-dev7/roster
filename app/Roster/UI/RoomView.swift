import SwiftUI

/// The pixel office. A static scene painted once in a `Canvas` (floor,
/// walls, pods, lounge), with live layers on top: breathing monitor
/// glows, the agents with their name pills, and you at your desk.
///
/// Still calm, still cheap: SwiftUI is retained-mode, so nothing costs a
/// frame while nothing changes. The only per-frame work is the walk
/// itself (position tween + a 7 fps step timer that pauses when nobody
/// walks).
struct RoomView: View {

    let office: Office
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PixelPalette.current(for: colorScheme)
        let stationCount = office.workstations.count

        GeometryReader { geo in
            let (scale, offset) = RoomPlan.transform(in: geo.size)
            let map = { (p: CGPoint) in
                CGPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale)
            }

            ZStack {
                PixelSceneCanvas(palette: palette, stationCount: stationCount)

                // Screens glow while someone works at the pod.
                ForEach(office.workstations.indices, id: \.self) { index in
                    if office.hasWorkingAgent(onStation: index) {
                        let screen = RoomPlan.pod(index: index, of: stationCount).screen
                        ScreenGlow(palette: palette)
                            .frame(width: screen.width * scale, height: screen.height * scale)
                            .position(map(CGPoint(x: screen.midX, y: screen.midY)))
                    }
                }
                ScreenGlow(palette: palette)
                    .frame(width: RoomPlan.youScreen.width * scale,
                           height: RoomPlan.youScreen.height * scale)
                    .position(map(CGPoint(x: RoomPlan.youScreen.midX, y: RoomPlan.youScreen.midY)))

                // You, at your desk.
                PixelCharacter(
                    name: String(localized: "You"),
                    look: .you,
                    pose: .seated,
                    pillColor: Color(hex: 0x8A8F98),
                    scale: scale,
                    shadow: palette.shadow,
                    feet: map(RoomPlan.youSeat)
                )

                // The agents.
                ForEach(office.sessions) { session in
                    PixelAgentView(
                        office: office,
                        session: session,
                        pod: RoomPlan.pod(index: session.stationIndex, of: stationCount),
                        seatCount: office.seatCount(onStation: session.stationIndex),
                        scale: scale,
                        palette: palette,
                        map: map
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.4)))
                }
            }
        }
        .background(palette.floorB)
    }
}

// ─────────────────────────────────────────────────────────────────────────
// The static scene.
// ─────────────────────────────────────────────────────────────────────────

private struct PixelSceneCanvas: View {

    let palette: PixelPalette
    let stationCount: Int

    var body: some View {
        Canvas { context, size in
            let (scale, offset) = RoomPlan.transform(in: size)

            func fill(_ rect: CGRect, _ color: Color) {
                context.fill(
                    Path(CGRect(x: offset.x + rect.minX * scale,
                                y: offset.y + rect.minY * scale,
                                width: rect.width * scale,
                                height: rect.height * scale)),
                    with: .color(color)
                )
            }

            // ── Floor: a full-view wash, then the tile grid ─────────────
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(palette.floorB))
            // Checker tiles, extended past the scene so letterboxing
            // reads as more floor rather than as bars.
            let tile = 16 * scale
            var ty = offset.y.truncatingRemainder(dividingBy: 2 * tile) - 2 * tile
            var rowIndex = 0
            while ty < size.height {
                var tx = offset.x.truncatingRemainder(dividingBy: 2 * tile) - 2 * tile
                var colIndex = 0
                while tx < size.width {
                    if (rowIndex + colIndex) % 2 == 0 {
                        context.fill(Path(CGRect(x: tx, y: ty, width: tile, height: tile)),
                                     with: .color(palette.floorA))
                    }
                    tx += tile
                    colIndex += 1
                }
                ty += tile
                rowIndex += 1
            }
            // Grout lines.
            var lines = Path()
            var gx = offset.x.truncatingRemainder(dividingBy: tile)
            while gx < size.width {
                lines.move(to: CGPoint(x: gx, y: 0))
                lines.addLine(to: CGPoint(x: gx, y: size.height))
                gx += tile
            }
            var gy = offset.y.truncatingRemainder(dividingBy: tile)
            while gy < size.height {
                lines.move(to: CGPoint(x: 0, y: gy))
                lines.addLine(to: CGPoint(x: size.width, y: gy))
                gy += tile
            }
            context.stroke(lines, with: .color(palette.floorLine), lineWidth: max(1, scale * 0.6))

            // ── Wall band with windows, across the full width ───────────
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width,
                                     height: offset.y + RoomPlan.wallHeight * scale)),
                         with: .color(palette.wall))
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: offset.y + 3 * scale)),
                         with: .color(palette.wallTop))
            fill(CGRect(x: -200, y: RoomPlan.wallHeight, width: RoomPlan.size.width + 400, height: 2),
                 palette.shadow)
            for wx in RoomPlan.Furniture.windowXs {
                fill(CGRect(x: wx, y: 4, width: 26, height: 11), palette.windowFrame)
                fill(CGRect(x: wx + 1, y: 5, width: 24, height: 9), palette.windowGlass)
                fill(CGRect(x: wx + 1, y: 5, width: 24, height: 3), palette.windowLite)
                fill(CGRect(x: wx + 12, y: 5, width: 2, height: 9), palette.windowFrame)
            }

            // ── Desk pods ───────────────────────────────────────────────
            for index in 0..<stationCount {
                let pod = RoomPlan.pod(index: index, of: stationCount)
                carpet(pod.carpet, palette.carpet, palette.carpetDark, palette.carpetLine, fill)
                desk(pod.desk, monitor: pod.monitorFrame, screen: pod.screen, fill)
                // Chair.
                fill(pod.chair, palette.chair)
                fill(CGRect(x: pod.chair.minX, y: pod.chair.maxY - 4, width: pod.chair.width, height: 2), palette.chairDark)
                plant(at: pod.plantPot, fill)
            }

            // ── Your corner ─────────────────────────────────────────────
            carpet(RoomPlan.youZone, palette.rug, palette.rugDark, palette.rugLine, fill)
            desk(RoomPlan.youDesk, monitor: RoomPlan.youMonitorFrame, screen: RoomPlan.youScreen, fill)
            for pot in RoomPlan.youPlants { plant(at: pot, fill) }

            // ── Lounge ──────────────────────────────────────────────────
            carpet(RoomPlan.Furniture.loungeZone, palette.loungeCarpet,
                   palette.loungeCarpetDark, palette.loungeCarpetLine, fill)
            let sofa = RoomPlan.Furniture.sofa
            fill(CGRect(x: sofa.minX + 2, y: sofa.maxY, width: sofa.width - 2, height: 3), palette.shadow)
            fill(sofa, palette.sofa)
            fill(CGRect(x: sofa.minX, y: sofa.minY, width: sofa.width, height: 3), palette.sofaLite)
            fill(CGRect(x: sofa.minX, y: sofa.maxY - 3, width: sofa.width, height: 3), palette.sofaDark)
            fill(CGRect(x: sofa.minX + 13, y: sofa.minY + 2, width: 1, height: 8), palette.sofaDark)
            fill(CGRect(x: sofa.minX + 26, y: sofa.minY + 2, width: 1, height: 8), palette.sofaDark)
            fill(CGRect(x: sofa.minX - 3, y: sofa.minY, width: 3, height: 12), palette.sofaDark)
            fill(CGRect(x: sofa.maxX, y: sofa.minY, width: 3, height: 12), palette.sofaDark)
            let table = RoomPlan.Furniture.lowTable
            fill(CGRect(x: table.minX + 1, y: table.maxY, width: table.width - 2, height: 2), palette.shadow)
            fill(table, palette.lowTable)
            fill(CGRect(x: table.minX, y: table.maxY - 2, width: table.width, height: 2), palette.lowTableDark)
            plant(at: RoomPlan.Furniture.loungePlant, fill)

            // ── Ping-pong ───────────────────────────────────────────────
            let ping = RoomPlan.Furniture.pingPong
            fill(CGRect(x: ping.minX + 2, y: ping.maxY, width: ping.width - 2, height: 3), palette.shadow)
            fill(ping, palette.pingTop)
            fill(CGRect(x: ping.minX, y: ping.maxY - 3, width: ping.width, height: 3), palette.pingDark)
            fill(CGRect(x: ping.midX - 1, y: ping.minY, width: 2, height: ping.height), palette.pingLine)
            plant(at: RoomPlan.Furniture.pingPongPlant, fill)
        }
    }

    // Small drawing helpers, all in logical rects via the shared `fill`.

    private func carpet(_ zone: CGRect, _ main: Color, _ dark: Color, _ line: Color,
                        _ fill: (CGRect, Color) -> Void) {
        fill(zone, main)
        fill(CGRect(x: zone.minX, y: zone.minY, width: zone.width, height: 2), line)
        fill(CGRect(x: zone.minX, y: zone.maxY - 2, width: zone.width, height: 2), dark)
        fill(CGRect(x: zone.minX, y: zone.minY, width: 2, height: zone.height), line)
        fill(CGRect(x: zone.maxX - 2, y: zone.minY, width: 2, height: zone.height), dark)
    }

    private func desk(_ rect: CGRect, monitor: CGRect, screen: CGRect,
                      _ fill: (CGRect, Color) -> Void) {
        fill(CGRect(x: rect.minX + 2, y: rect.maxY, width: rect.width - 4, height: 3), palette.shadow)
        fill(rect, palette.desk)
        fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2), palette.deskLite)
        fill(CGRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2), palette.deskDark)
        fill(monitor, palette.monitor)
        fill(screen, palette.screenOff)
        fill(CGRect(x: monitor.midX - 1, y: monitor.maxY, width: 2, height: 2), palette.monitor)
    }

    private func plant(at pot: CGPoint, _ fill: (CGRect, Color) -> Void) {
        fill(CGRect(x: pot.x, y: pot.y, width: 8, height: 6), palette.pot)
        fill(CGRect(x: pot.x, y: pot.y + 4, width: 8, height: 2), palette.potDark)
        fill(CGRect(x: pot.x + 1, y: pot.y - 6, width: 6, height: 6), palette.plant)
        fill(CGRect(x: pot.x - 1, y: pot.y - 4, width: 3, height: 3), palette.plant)
        fill(CGRect(x: pot.x + 6, y: pot.y - 4, width: 3, height: 3), palette.plant)
        fill(CGRect(x: pot.x + 2, y: pot.y - 8, width: 4, height: 3), palette.plant)
        fill(CGRect(x: pot.x + 3, y: pot.y - 5, width: 2, height: 4), palette.plantDark)
    }
}

// ─────────────────────────────────────────────────────────────────────────
// A screen that breathes while its agent works.
// ─────────────────────────────────────────────────────────────────────────

private struct ScreenGlow: View {

    let palette: PixelPalette
    @State private var bright = false

    var body: some View {
        Rectangle()
            .fill(palette.screenOn)
            .opacity(bright ? 0.95 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                    bright = true
                }
            }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// One agent: sprite + name pill, moved by the same phase machinery as
// ever. The pill's dot carries the status color used across the app.
// ─────────────────────────────────────────────────────────────────────────

private struct PixelAgentView: View {

    let office: Office
    let session: AgentSession
    let pod: RoomPlan.Pod
    let seatCount: Int
    let scale: CGFloat
    let palette: PixelPalette
    let map: (CGPoint) -> CGPoint

    @State private var showActions = false

    private var name: String {
        office.workstations.indices.contains(session.stationIndex)
            ? office.workstations[session.stationIndex].name
            : "?"
    }

    private var feet: CGPoint {
        switch session.phase {
        case .seated:
            return pod.seat(slot: session.seatSlot, of: seatCount)
        case .standing:
            return pod.stand(slot: session.seatSlot)
        case .walking, .atDesk:
            return RoomPlan.arrival(deskSlot: session.deskSlot)
        case .walkingBack:
            return pod.stand(slot: session.seatSlot)
        }
    }

    private var isWalking: Bool {
        session.phase == .walking || session.phase == .walkingBack
    }

    private var transition: Animation {
        switch session.phase {
        case .walking, .walkingBack:
            return .easeInOut(duration: Choreo.walk)
        default:
            return .easeInOut(duration: Choreo.standUp)
        }
    }

    var body: some View {
        let mapped = map(feet)
        let spriteHeight = PixelSprite.logicalSize.height * scale
        let pillHeight: CGFloat = 20

        VStack(spacing: 2) {
            NamePill(name: name, color: session.status.uiColor)
            // The step timer only ticks while this agent walks.
            TimelineView(.animation(minimumInterval: 0.14, paused: !isWalking)) { timeline in
                let frame = Int(timeline.date.timeIntervalSinceReferenceDate / 0.14) % 2
                PixelSprite(
                    look: SpriteLook.derive(from: name, slot: session.seatSlot),
                    pose: pose(frame: frame),
                    scale: scale,
                    shadowColor: palette.shadow
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showActions = true }
        .popover(isPresented: $showActions, arrowEdge: .bottom) {
            AgentPopover(office: office, session: session)
        }
        // Feet-anchored: the container's center sits half its height above.
        .position(x: mapped.x, y: mapped.y - (spriteHeight + pillHeight + 2) / 2)
        .animation(transition, value: session.phase)
        .animation(.easeInOut(duration: Choreo.standUp), value: seatCount)
    }

    private func pose(frame: Int) -> SpritePose {
        switch session.phase {
        case .seated: return .seated
        case .standing, .atDesk: return .standing
        case .walking, .walkingBack: return .walking(frame: frame)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// You, seated at your desk. Not clickable — you know what you did.
// ─────────────────────────────────────────────────────────────────────────

private struct PixelCharacter: View {

    let name: String
    let look: SpriteLook
    let pose: SpritePose
    let pillColor: Color
    let scale: CGFloat
    let shadow: Color
    let feet: CGPoint

    var body: some View {
        let spriteHeight = PixelSprite.logicalSize.height * scale
        VStack(spacing: 2) {
            NamePill(name: name, color: pillColor)
            PixelSprite(look: look, pose: pose, scale: scale, shadowColor: shadow)
        }
        .position(x: feet.x, y: feet.y - (spriteHeight + 22) / 2)
        .allowsHitTesting(false)
    }
}
