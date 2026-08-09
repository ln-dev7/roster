import AppKit
import Combine
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
/// Named spots in the office. Walking into one does something: a
/// colleague's pod opens its card, the fun corners show a tip bubble.
/// Your own desk deliberately does nothing — it's home, not a stop.
private enum Place: Equatable {
    case station(Int)
    case lounge
    case pingPong
}

/// Clicking an agent (or its desk) selects it — the detail card that
/// opens on the right belongs to `ContentView`; the room only owns the
/// selection value. Clicking the floor clears it, like in Gather.
///
/// The arrow keys move YOUR character — a real little game loop: held
/// keys feed a direction, a 60 Hz task advances the feet, diagonals
/// included. When the room is zoomed in, the scroll follows you around.
/// Stop moving near your chair and you sit back down.
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
    /// The arrow keys currently held down (their key codes). keyDown adds,
    /// keyUp removes — no reliance on the keyboard's auto-repeat, which is
    /// what made the first version stutter.
    @State private var pressedArrows: Set<UInt16> = []
    /// The 60 Hz walk loop; alive exactly while a key is held.
    @State private var walkLoop: Task<Void, Never>?
    /// The auto-walk (double-click a spot, or the "Back to your desk"
    /// button). Any arrow key cancels it — you take the wheel back.
    @State private var autoWalkTask: Task<Void, Never>?
    /// The NSEvent monitor that feeds the arrow keys. Stored to remove it.
    @State private var keyMonitor: Any?

    // ── Places (proximity interactions) ─────────────────────────────────
    /// Where your avatar currently stands, zone-wise (see `Place` below).
    @State private var currentPlace: Place?
    /// A card opened by walking up to a colleague — closed again when you
    /// walk away. A card the user opened by hand is left alone.
    @State private var proximitySelectedID: Int?

    /// The room is drawn LARGER than the window on purpose — Gather's
    /// big plan. The camera follows you instead of shrinking the world,
    /// and the floating detail card stops mattering: whatever it covers,
    /// one step brings back into view. Zooming out to the range's floor
    /// (~0.65) still shows the whole office at once.
    private static let basePlan: CGFloat = 1.5
    private static let zoomRange: ClosedRange<CGFloat> = 0.65...3
    /// The 3D layer needs an id for you; sessions start at 1, so -1 is safe.
    private static let youFigureID = -1
    /// The scroll anchor that rides on your feet (camera follow).
    private static let youAnchorID = "you-anchor"

    var body: some View {
        let palette = PixelPalette.current(for: colorScheme)

        GeometryReader { geo in
            let fit = RoomPlan.transform(in: geo.size).scale * Self.basePlan
            let scale = fit * zoom
            let content = CGSize(
                width: max(geo.size.width, RoomPlan.size.width * scale),
                height: max(geo.size.height, RoomPlan.size.height * scale)
            )
            let offset = CGPoint(
                x: (content.width - RoomPlan.size.width * scale) / 2,
                y: (content.height - RoomPlan.size.height * scale) / 2
            )

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    room(scale: scale, offset: offset,
                         contentSize: content, palette: palette)
                        .frame(width: content.width, height: content.height)
                }
                // Open on the middle of the office, not its top-left tile.
                .defaultScrollAnchor(.center)
                .background(palette.floorB)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 8) {
                        if youFeet != RoomPlan.youSeat {
                            BackToDeskButton {
                                startAutoWalk(to: RoomPlan.youSeat)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                        ZoomControls(zoom: $zoom, range: Self.zoomRange)
                    }
                    .padding(10)
                    .animation(.easeOut(duration: 0.2),
                               value: youFeet == RoomPlan.youSeat)
                }
                // Walking into a place shows its tip, bottom center —
                // except a colleague's pod, which opens the card instead.
                .overlay(alignment: .bottom) {
                    if let place = tipPlace {
                        TipBubble(place: place)
                            .padding(.bottom, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // The camera follows your avatar — walk to the far side
                // of the office and the office comes with you.
                .onChange(of: youFeet) {
                    followAvatar(proxy)
                    updatePlace()
                }
                .onChange(of: zoom) {
                    followAvatar(proxy)
                }
                // Selecting an agent (sidebar click included) pans the
                // plan to its desk, slightly left of center so the
                // floating card never sits on top of it.
                .onChange(of: selection) {
                    if let selection {
                        proxy.scrollTo("agent-\(selection)",
                                       anchor: UnitPoint(x: 0.38, y: 0.5))
                    }
                }
            }
        }
        .onAppear(perform: startListeningToArrowKeys)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            walkLoop?.cancel()
            walkLoop = nil
            autoWalkTask?.cancel()
            autoWalkTask = nil
        }
        // If the app loses focus mid-walk the keyUp never reaches us —
        // clear the keys so nobody walks into a wall forever.
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didResignActiveNotification
            )
        ) { _ in
            pressedArrows.removeAll()
        }
    }

    /// Keeps your avatar centered. The plan is bigger than the window by
    /// default, so this is simply how the room is looked at; when the
    /// user zooms all the way out, scrollTo quietly has nothing to do.
    private func followAvatar(_ proxy: ScrollViewProxy) {
        proxy.scrollTo(Self.youAnchorID, anchor: .center)
    }

    // ── Proximity ───────────────────────────────────────────────────────

    /// The tip bubble shows for furniture places, and never while you're
    /// still in your chair — the launch state must stay silent.
    private var tipPlace: Place? {
        guard let currentPlace, youPose != .seated else { return nil }
        if case .station = currentPlace { return nil }
        return currentPlace
    }

    /// Zone hit-testing, slightly inflated so "next to" counts as "at".
    private func place(at feet: CGPoint) -> Place? {
        let count = office.workstations.count
        for index in 0..<count {
            let carpet = RoomPlan.pod(index: index, of: count).carpet
            if carpet.insetBy(dx: -4, dy: -4).contains(feet) {
                return .station(index)
            }
        }
        if RoomPlan.Furniture.loungeZone.insetBy(dx: -4, dy: -4).contains(feet) {
            return .lounge
        }
        if RoomPlan.Furniture.pingPong.insetBy(dx: -8, dy: -8).contains(feet) {
            return .pingPong
        }
        return nil
    }

    /// Called on every step. Entering a colleague's pod opens its card —
    /// the office version of walking up to someone in Gather; leaving
    /// closes it again (only if the visit opened it). Everywhere else,
    /// the tip bubble follows from `tipPlace`.
    private func updatePlace() {
        let newPlace = place(at: youFeet)
        guard newPlace != currentPlace else { return }

        if let id = proximitySelectedID {
            if selection == id { selection = nil }
            proximitySelectedID = nil
        }

        withAnimation(.easeOut(duration: 0.25)) {
            currentPlace = newPlace
        }

        if case .station(let index) = newPlace,
           let sessionID = office.sessions
               .first(where: { $0.stationIndex == index })?.id {
            selection = sessionID
            proximitySelectedID = sessionID
        }
    }

    /// Everything inside the scroll content, at one moment's transform.
    @ViewBuilder
    private func room(scale: CGFloat, offset: CGPoint,
                      contentSize: CGSize, palette: PixelPalette) -> some View {
        let stationCount = office.workstations.count
        let map = { (p: CGPoint) in
            CGPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale)
        }

        ZStack {
            PixelSceneCanvas(palette: palette, stationCount: stationCount,
                             scale: scale, offset: offset)
                // Double-clicking the floor sends you there, Gather-style
                // (declared BEFORE the single tap so it wins the race).
                .onTapGesture(count: 2) { location in
                    let logical = CGPoint(
                        x: (location.x - offset.x) / scale,
                        y: (location.y - offset.y) / scale
                    )
                    startAutoWalk(to: logical)
                }
                // Clicking the floor deselects — the card slides away.
                .onTapGesture { selection = nil }

            // The invisible anchor the camera-follow scrolls to.
            Color.clear
                .frame(width: 1, height: 1)
                .position(map(youFeet))
                .id(Self.youAnchorID)
                .allowsHitTesting(false)

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

            // Your name pill, floating above your head. The tiny linear
            // animation makes it trail the body by a breath — game-style.
            NamePill(name: String(localized: "You"), color: Color(hex: 0x8A8F98))
                .position(x: map(youFeet).x,
                          y: map(youFeet).y - VoxelBuilder.figureSize.height * scale - 12)
                .animation(.linear(duration: 0.1), value: youFeet)
                .allowsHitTesting(false)

            // Each desk wears its provider's badge — the little logo of
            // the tool running there (Claude today; see docs/providers.md
            // for tomorrow's mixed office).
            ForEach(office.workstations.indices, id: \.self) { index in
                let pod = RoomPlan.pod(index: index, of: stationCount)
                Image(office.workstations[index].provider.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 6.5 * scale, height: 6.5 * scale)
                    .position(map(CGPoint(x: pod.desk.maxX - 6, y: pod.desk.minY + 6)))
                    .allowsHitTesting(false)
            }

            // The agents' 2D halves: pill, tap target, selection ring.
            // The id is the pan-to-selection scroll target.
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
                .id("agent-\(session.id)")
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
                    ? Choreo.walk : Choreo.standUp
            )
        }
        list.append(VoxelFigure(
            id: Self.youFigureID,
            look: .you,
            feet: youFeet,
            // While walking, feet move ~60×/s: duration 0 tells the 3D
            // layer to set positions directly. The final sit-back-down
            // snap (not walking) gets a small glide instead.
            pose: youPose,
            moveDuration: youWalking ? 0 : 0.18
        ))
        return list
    }

    /// Feet position in logical coordinates — the one place the phase
    /// turns into geometry, shared by the 3D layer and the 2D overlays.
    /// One colleague per desk, so everyone takes the chair (slot 0).
    private func feet(of session: AgentSession, stationCount: Int) -> CGPoint {
        let pod = RoomPlan.pod(index: session.stationIndex, of: stationCount)
        switch session.phase {
        case .seated:
            return pod.seat(slot: 0, of: 1)
        case .standing, .walkingBack:
            return pod.stand(slot: 0)
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

    /// The look derives from the workstation's unique ID (path + serial),
    /// not its display name — twin desks get different outfits, which is
    /// half the disambiguation.
    private func look(for session: AgentSession) -> SpriteLook {
        let key = office.workstations.indices.contains(session.stationIndex)
            ? office.workstations[session.stationIndex].id
            : "?"
        return SpriteLook.derive(from: key)
    }

    // ── Arrow keys ──────────────────────────────────────────────────────

    /// Key codes: ← 123, → 124, ↓ 125, ↑ 126.
    private static let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]

    private var youPose: VoxelPose {
        if youWalking { return .walking }
        return youFeet == RoomPlan.youSeat ? .seated : .standing
    }

    private func startListeningToArrowKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp]
        ) { event in
            // Leave modified arrows (⌘←…) and text editing alone.
            guard Self.arrowKeyCodes.contains(event.keyCode),
                  event.modifierFlags
                      .intersection([.command, .option, .control, .shift]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText)
            else { return event }

            if event.type == .keyDown {
                // Auto-repeats are consumed but ignored: the walk loop is
                // the clock, the keyboard only says which keys are held.
                if !event.isARepeat {
                    // Touching the arrows takes over from the auto-walk.
                    autoWalkTask?.cancel()
                    autoWalkTask = nil
                    pressedArrows.insert(event.keyCode)
                    startWalkLoopIfNeeded()
                }
            } else {
                pressedArrows.remove(event.keyCode)
            }
            return nil // consumed
        }
    }

    /// The game loop: ~60 ticks a second while any arrow is held, each
    /// tick advancing the feet by speed × elapsed time. Frame-rate
    /// independent, diagonal-friendly, and perfectly smooth because the
    /// 3D layer sets positions directly at this rate.
    private func startWalkLoopIfNeeded() {
        guard walkLoop == nil else { return }
        youWalking = true
        walkLoop = Task { @MainActor in
            var lastTick = ContinuousClock.now
            while !Task.isCancelled, !pressedArrows.isEmpty {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let elapsed = lastTick.duration(to: now)
                lastTick = now
                // Seconds, capped: a hiccup must not teleport anyone.
                let dt = min(
                    Double(elapsed.components.seconds)
                        + Double(elapsed.components.attoseconds) * 1e-18,
                    0.05
                )
                step(dt: dt)
            }
            walkLoop = nil
            youWalking = false
            // Stopped close to the chair: sit back down (small glide —
            // see the figure's moveDuration when not walking).
            if abs(youFeet.x - RoomPlan.youSeat.x) < 7,
               abs(youFeet.y - RoomPlan.youSeat.y) < 7 {
                youFeet = RoomPlan.youSeat
            }
        }
    }

    /// One tick of walking: held keys → a unit direction → a step.
    private func step(dt: Double) {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if pressedArrows.contains(123) { dx -= 1 }
        if pressedArrows.contains(124) { dx += 1 }
        if pressedArrows.contains(126) { dy -= 1 }
        if pressedArrows.contains(125) { dy += 1 }
        guard dx != 0 || dy != 0 else { return }

        // Normalized so diagonals aren't faster, like every game ever.
        let length = (dx * dx + dy * dy).squareRoot()
        let speed: CGFloat = 62 // logical pixels per second
        youFeet = CGPoint(
            x: min(max(youFeet.x + dx / length * speed * dt, 8),
                   RoomPlan.size.width - 8),
            y: min(max(youFeet.y + dy / length * speed * dt,
                       RoomPlan.wallHeight + 8),
                   RoomPlan.size.height - 4)
        )
    }

    /// The auto-walk: double-click a spot (or press "Back to your desk")
    /// and you hurry there — brisker than the arrow keys, because a
    /// destination is a decision. Ends seated when the target is close
    /// enough to your chair.
    private func startAutoWalk(to destination: CGPoint) {
        // Clamp into the walkable floor, and snap chair-adjacent targets
        // onto the chair so arriving means sitting down.
        var target = CGPoint(
            x: min(max(destination.x, 8), RoomPlan.size.width - 8),
            y: min(max(destination.y, RoomPlan.wallHeight + 8),
                   RoomPlan.size.height - 4)
        )
        if abs(target.x - RoomPlan.youSeat.x) < 10,
           abs(target.y - RoomPlan.youSeat.y) < 10 {
            target = RoomPlan.youSeat
        }

        pressedArrows.removeAll()
        autoWalkTask?.cancel()
        youWalking = true
        autoWalkTask = Task { @MainActor in
            var lastTick = ContinuousClock.now
            let speed: CGFloat = 130 // in a hurry — roughly twice the stroll
            while !Task.isCancelled, pressedArrows.isEmpty {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let elapsed = lastTick.duration(to: now)
                lastTick = now
                let dt = min(
                    Double(elapsed.components.seconds)
                        + Double(elapsed.components.attoseconds) * 1e-18,
                    0.05
                )
                let dx = target.x - youFeet.x
                let dy = target.y - youFeet.y
                let distance = (dx * dx + dy * dy).squareRoot()
                let stride = speed * CGFloat(dt)
                if distance <= stride {
                    youFeet = target
                    break
                }
                youFeet = CGPoint(x: youFeet.x + dx / distance * stride,
                                  y: youFeet.y + dy / distance * stride)
            }
            autoWalkTask = nil
            if pressedArrows.isEmpty { youWalking = false }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Proximity extras: the walk-home button and the place tips.
// ─────────────────────────────────────────────────────────────────────────

/// Lives next to the zoom capsule whenever you're away from your chair.
private struct BackToDeskButton: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.caption.weight(.semibold))
                Text("Back to your desk")
                    .font(.caption.weight(.medium))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }
}

/// The little bottom-center card that greets you in each corner of the
/// office — one flavor line, one real tip. Gather teaches by wandering;
/// so does Roster.
private struct TipBubble: View {

    let place: Place

    private var icon: String {
        switch place {
        case .lounge: return "sofa.fill"
        case .pingPong, .station: return "figure.table.tennis"
        }
    }

    private var title: LocalizedStringKey {
        switch place {
        case .lounge: return "The lounge"
        case .pingPong, .station: return "The ping-pong table"
        }
    }

    private var message: LocalizedStringKey {
        switch place {
        case .lounge:
            return "Agents never take a break — you're allowed to. Tip: ⌥⌘T keeps the room floating on top while you work."
        case .pingPong, .station:
            return "Always free: the agents forfeit by default. Tip: hold two arrow keys to walk diagonally."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .allowsHitTesting(false)
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
                zoom = 1 // back to the big plan, not to fit-the-window
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
    /// The shared transform, injected: the room may be recentered inside
    /// its content (detail-card inset), so the canvas must not compute
    /// its own.
    let scale: CGFloat
    let offset: CGPoint

    var body: some View {
        Canvas { context, size in
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
        // Linear on purpose: the 3D bodies walk at constant speed, and
        // the pill must ride exactly on top of the head.
        switch session.phase {
        case .walking, .walkingBack:
            return .linear(duration: Choreo.walk)
        default:
            return .linear(duration: Choreo.standUp)
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
