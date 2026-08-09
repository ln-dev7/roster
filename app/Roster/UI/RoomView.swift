import AppKit
import SwiftUI

/// The pixel office. A static scene painted once in a `Canvas` (floor,
/// walls, pods, lounge), the voxel 3D characters in a transparent
/// SceneKit overlay, and regular SwiftUI on top: name pills, tap targets,
/// the selection ring.
///
/// The whole scene lives inside a two-axis `ScrollView`. At ×1 the room
/// fits the window exactly; the zoom buttons grow the content so a
/// crowded room can be inspected up close. Zooming is deliberately NOT
/// animated: the 2D canvas and the 3D layer must land on the same frame
/// at the same instant, and a snap is exactly what a pixel app does.
///
/// Clicking an agent (or its desk) selects it — the detail card that
/// opens on the right belongs to `ContentView`; the room only owns the
/// selection value. Clicking the floor clears it, like in Gather.
///
/// The arrow keys move YOUR character. Walk anywhere; stop moving near
/// your chair and you sit back down.
struct RoomView: View {

    let office: Office
    /// The selected session id, shared with the sidebar and the card.
    @Binding var selection: Int?

    @Environment(\.colorScheme) private var colorScheme

    /// Zoom factor on top of scale-to-fit. Values below 1 would only add
    /// empty margins around the scene, so the range starts at 1.
    @State private var zoom: CGFloat = 1

    // ── Your character ──────────────────────────────────────────────────
    @State private var youFeet: CGPoint = RoomPlan.youSeat
    @State private var youWalking = false
    /// The NSEvent monitor that feeds the arrow keys. Stored to remove it.
    @State private var keyMonitor: Any?
    /// Debounce: stop "walking" shortly after the last key event.
    @State private var settleTask: Task<Void, Never>?

    private static let zoomRange: ClosedRange<CGFloat> = 1...3
    /// The 3D layer needs an id for you; sessions start at 1, so -1 is safe.
    private static let youFigureID = -1

    var body: some View {
        let palette = PixelPalette.current(for: colorScheme)

        GeometryReader { geo in
            let fit = RoomPlan.transform(in: geo.size).scale
            let content = CGSize(
                width: max(geo.size.width, RoomPlan.size.width * fit * zoom),
                height: max(geo.size.height, RoomPlan.size.height * fit * zoom)
            )

            ScrollView([.horizontal, .vertical]) {
                room(contentSize: content, palette: palette)
                    .frame(width: content.width, height: content.height)
            }
            .background(palette.floorB)
            .overlay(alignment: .bottomTrailing) {
                ZoomControls(zoom: $zoom, range: Self.zoomRange)
                    .padding(10)
            }
        }
        .onAppear(perform: startListeningToArrowKeys)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            settleTask?.cancel()
        }
    }

    /// Everything inside the scroll content, at one moment's transform.
    @ViewBuilder
    private func room(contentSize: CGSize, palette: PixelPalette) -> some View {
        let stationCount = office.workstations.count
        let (scale, offset) = RoomPlan.transform(in: contentSize)
        let map = { (p: CGPoint) in
            CGPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale)
        }

        ZStack {
            PixelSceneCanvas(palette: palette, stationCount: stationCount)
                // Clicking the floor deselects — the card slides away.
                .onTapGesture { selection = nil }

            // Invisible tap targets over each pod's carpet: clicking a
            // desk selects whoever works there. The agent targets above
            // win the hit-test when you aim at them directly.
            ForEach(office.workstations.indices, id: \.self) { index in
                let carpet = RoomPlan.pod(index: index, of: stationCount).carpet
                Color.clear
                    .frame(width: carpet.width * scale, height: carpet.height * scale)
                    .contentShape(Rectangle())
                    // The gesture attaches BEFORE `.position` — after it,
                    // the positioned wrapper fills the whole room and one
                    // desk would swallow every click.
                    .onTapGesture {
                        selection = office.sessions
                            .first { $0.stationIndex == index }?.id
                    }
                    .position(map(CGPoint(x: carpet.midX, y: carpet.midY)))
            }

            // Screens glow while someone works at the pod. Not clickable:
            // they must never shade the desk's tap target below.
            ForEach(office.workstations.indices, id: \.self) { index in
                if office.hasWorkingAgent(onStation: index) {
                    let screen = RoomPlan.pod(index: index, of: stationCount).screen
                    ScreenGlow(palette: palette)
                        .frame(width: screen.width * scale, height: screen.height * scale)
                        .position(map(CGPoint(x: screen.midX, y: screen.midY)))
                        .allowsHitTesting(false)
                }
            }
            ScreenGlow(palette: palette)
                .frame(width: RoomPlan.youScreen.width * scale,
                       height: RoomPlan.youScreen.height * scale)
                .position(map(CGPoint(x: RoomPlan.youScreen.midX, y: RoomPlan.youScreen.midY)))
                .allowsHitTesting(false)

            // The bodies — one SceneKit overlay for everyone, you included.
            // Clicks fall straight through it (see ClickThroughSCNView).
            VoxelSceneView(
                figures: figures(stationCount: stationCount),
                scale: scale,
                offset: offset,
                contentSize: contentSize
            )
            .frame(width: contentSize.width, height: contentSize.height)
            .allowsHitTesting(false)

            // Your name pill, floating above your head.
            NamePill(name: String(localized: "You"), color: Color(hex: 0x8A8F98))
                .position(x: map(youFeet).x,
                          y: map(youFeet).y - VoxelBuilder.figureSize.height * scale - 12)
                .animation(.linear(duration: 0.13), value: youFeet)
                .allowsHitTesting(false)

            // The agents' 2D halves: pill, tap target, selection ring.
            ForEach(office.sessions) { session in
                AgentOverlay(
                    office: office,
                    session: session,
                    feetLogical: feet(of: session, stationCount: stationCount),
                    isSelected: selection == session.id,
                    scale: scale,
                    offset: offset,
                    onTap: { selection = session.id }
                )
                .transition(.opacity)
            }
        }
    }

    // ── Figures for the 3D layer ────────────────────────────────────────

    private func figures(stationCount: Int) -> [VoxelFigure] {
        var list = office.sessions.map { session in
            VoxelFigure(
                id: session.id,
                look: look(for: session),
                feet: feet(of: session, stationCount: stationCount),
                pose: pose(of: session),
                moveDuration: session.phase == .walking || session.phase == .walkingBack
                    ? Choreo.walk : Choreo.standUp,
                linearMove: false
            )
        }
        list.append(VoxelFigure(
            id: Self.youFigureID,
            look: .you,
            feet: youFeet,
            pose: youPose,
            moveDuration: 0.13,
            linearMove: true
        ))
        return list
    }

    /// Feet position in logical coordinates — the one place the phase
    /// turns into geometry, shared by the 3D layer and the 2D overlays.
    private func feet(of session: AgentSession, stationCount: Int) -> CGPoint {
        let pod = RoomPlan.pod(index: session.stationIndex, of: stationCount)
        switch session.phase {
        case .seated:
            return pod.seat(slot: session.seatSlot,
                            of: office.seatCount(onStation: session.stationIndex))
        case .standing, .walkingBack:
            return pod.stand(slot: session.seatSlot)
        case .walking, .atDesk:
            return RoomPlan.arrival(deskSlot: session.deskSlot)
        }
    }

    private func pose(of session: AgentSession) -> VoxelPose {
        switch session.phase {
        case .seated: return .seated
        case .standing, .atDesk: return .standing
        case .walking, .walkingBack: return .walking
        }
    }

    /// The look derives from the workstation's ID (the repository path),
    /// not its display name — two folders both named "api" get different
    /// outfits, which is half the disambiguation.
    private func look(for session: AgentSession) -> SpriteLook {
        let key = office.workstations.indices.contains(session.stationIndex)
            ? office.workstations[session.stationIndex].id
            : "?"
        return SpriteLook.derive(from: key, slot: session.seatSlot)
    }

    // ── Arrow keys ──────────────────────────────────────────────────────

    private var youPose: VoxelPose {
        if youWalking { return .walking }
        return youFeet == RoomPlan.youSeat ? .seated : .standing
    }

    private func startListeningToArrowKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Leave modified arrows (⌘←…) and text editing alone.
            guard event.modifierFlags
                .intersection([.command, .option, .control, .shift]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText)
            else { return event }

            switch event.keyCode {
            case 123: move(dx: -1, dy: 0)   // ←
            case 124: move(dx: 1, dy: 0)    // →
            case 125: move(dx: 0, dy: 1)    // ↓
            case 126: move(dx: 0, dy: -1)   // ↑
            default: return event
            }
            return nil // consumed
        }
    }

    /// One key event = one step. Key auto-repeat makes holding the key a
    /// continuous walk; the linear per-step animation keeps it smooth.
    private func move(dx: CGFloat, dy: CGFloat) {
        let step: CGFloat = 4
        withAnimation(.linear(duration: 0.13)) {
            youFeet = CGPoint(
                x: min(max(youFeet.x + dx * step, 8), RoomPlan.size.width - 8),
                y: min(max(youFeet.y + dy * step, RoomPlan.wallHeight + 8),
                       RoomPlan.size.height - 4)
            )
        }
        youWalking = true

        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            youWalking = false
            // Close enough to the chair: sit back down.
            if abs(youFeet.x - RoomPlan.youSeat.x) < 7,
               abs(youFeet.y - RoomPlan.youSeat.y) < 7 {
                withAnimation(.linear(duration: 0.13)) {
                    youFeet = RoomPlan.youSeat
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Zoom controls: the little − / % / ＋ capsule in the room's corner.
// The percent label doubles as the reset button.
// ─────────────────────────────────────────────────────────────────────────

private struct ZoomControls: View {

    @Binding var zoom: CGFloat
    let range: ClosedRange<CGFloat>

    /// One press multiplies (or divides) by this — small enough to feel
    /// smooth, big enough to matter.
    private let step: CGFloat = 1.25

    var body: some View {
        HStack(spacing: 0) {
            button("minus", help: "Zoom out", disabled: zoom <= range.lowerBound) {
                zoom = max(range.lowerBound, zoom / step)
            }
            Button {
                zoom = range.lowerBound
            } label: {
                Text(verbatim: "\(Int((zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reset zoom")
            button("plus", help: "Zoom in", disabled: zoom >= range.upperBound) {
                zoom = min(range.upperBound, zoom * step)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    private func button(_ symbol: String, help: LocalizedStringKey,
                        disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
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
// One agent's 2D half: the name pill, the tap target and the selection
// ring. The body itself lives in the SceneKit layer — this overlay rides
// exactly on top of it, animated with the same durations, so the pill
// follows the walk.
// ─────────────────────────────────────────────────────────────────────────

private struct AgentOverlay: View {

    let office: Office
    let session: AgentSession
    /// Feet position in LOGICAL coordinates. The overlay maps them itself,
    /// so the animation can key on the logical value: a walk animates, but
    /// a zoom (which only changes the mapping) snaps — in step with the
    /// 3D layer, which follows the same rule.
    let feetLogical: CGPoint
    let isSelected: Bool
    let scale: CGFloat
    let offset: CGPoint
    let onTap: () -> Void

    private var transition: Animation {
        switch session.phase {
        case .walking, .walkingBack:
            return .easeInOut(duration: Choreo.walk)
        default:
            return .easeInOut(duration: Choreo.standUp)
        }
    }

    var body: some View {
        let bodyHeight = VoxelBuilder.figureSize.height * scale
        let bodyWidth = VoxelBuilder.figureSize.width * scale
        let pillHeight: CGFloat = 20
        let feet = CGPoint(x: offset.x + feetLogical.x * scale,
                           y: offset.y + feetLogical.y * scale)

        VStack(spacing: 2) {
            NamePill(name: office.displayName(for: session),
                     color: session.status.uiColor)
            // The invisible half: where the 3D body stands, for clicking.
            Color.clear
                .frame(width: bodyWidth + 4, height: bodyHeight)
        }
        .background(alignment: .bottom) {
            if isSelected {
                Ellipse()
                    .stroke(session.status.uiColor, lineWidth: 2)
                    .frame(width: 15 * scale, height: 6 * scale)
                    .offset(y: 2 * scale)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // Feet-anchored: the container's center sits half its height above.
        .position(x: feet.x, y: feet.y - (bodyHeight + pillHeight + 2) / 2)
        .animation(transition, value: feetLogical)
    }
}
