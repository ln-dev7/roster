import SceneKit
import SwiftUI

// MARK: - The voxel colleagues
//
// The characters are REAL 3D — SceneKit nodes lit by a real light — but
// sculpted out of boxes, like pixels given volume. That's the trick that
// lets a 3D person stand in a pixel room without breaking it.
//
// One single transparent `SCNView` overlays the whole room; every
// character is a node inside it, positioned in *view points* so it lands
// exactly where the 2D layers (name pills, tap targets, canvas) expect
// it. The camera is orthographic and looks straight at the scene, which
// makes that mapping exact: a node at (x, y) projects to the pixel
// (x, y), always. The 3D-ness comes from the model itself — volume,
// lighting, and characters turning toward where they walk.

/// Where a body is, posture-wise. Deliberately smaller than `AgentPhase`:
/// the room's five phases collapse to three body poses.
enum VoxelPose: Equatable {
    case seated
    case standing
    case walking
}

/// Everything the 3D layer needs to know about one character, per frame.
/// A plain value: SwiftUI hands the array to `VoxelSceneView`, which diffs
/// it against its scene graph.
struct VoxelFigure: Equatable, Identifiable {
    let id: Int
    let look: SpriteLook
    /// Feet position in LOGICAL room coordinates (see RoomPlan).
    let feet: CGPoint
    let pose: VoxelPose
    /// How long a change of `feet` should take on screen. The walk is
    /// 2.9 s, standing up 0.45 s. Zero (or less) means "set directly" —
    /// your avatar's 60 Hz steps use that.
    let moveDuration: Double
}

// MARK: - The scene view

/// An `SCNView` that lets every click fall through to the SwiftUI layers
/// beneath it. Selection stays where it always was — in SwiftUI.
final class ClickThroughSCNView: SCNView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The bridge between SwiftUI and SceneKit. `updateNSView` runs on every
/// relevant change (a session moved, the zoom changed, a desk appeared)
/// and reconciles the scene graph: new figures fade in, gone ones fade
/// out, moved ones get a ROUTE.
///
/// Everybody moves the same way — the way your avatar does: a 60 Hz
/// mover loop advances each en-route figure toward its target at
/// constant speed (distance ÷ choreography duration), updating positions
/// directly. People walk at a steady pace; easing curves are for
/// furniture. Positions are kept in LOGICAL coordinates, so a zoom or a
/// resize mid-walk just remaps the current spot instead of teleporting
/// anyone to their destination.
struct VoxelSceneView: NSViewRepresentable {

    var figures: [VoxelFigure]
    /// The shared room transform (RoomPlan.transform of the content size).
    var scale: CGFloat
    var offset: CGPoint
    var contentSize: CGSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = ClickThroughSCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30

        let scene = SCNScene()
        view.scene = scene
        VoxelBuilder.addLights(to: scene)

        let camera = SCNCamera()
        // Orthographic: no perspective, so scene units == view points and
        // the 3D layer stays glued to the 2D one at any zoom.
        camera.usesOrthographicProjection = true
        camera.zNear = 1
        camera.zFar = 4000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)

        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard let scene = view.scene else { return }
        let c = context.coordinator

        // Camera follows the content size (zoom, window resize).
        if let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: false) {
            cameraNode.position = SCNVector3(contentSize.width / 2, contentSize.height / 2, 600)
            cameraNode.camera?.orthographicScale = Double(contentSize.height / 2)
        }

        let geometryChanged = scale != c.scale || offset != c.offset || contentSize != c.contentSize
        c.scale = scale
        c.offset = offset
        c.contentSize = contentSize

        var seen = Set<Int>()
        for figure in figures {
            seen.insert(figure.id)
            let isNew = c.nodes[figure.id] == nil
            let node = c.nodes[figure.id] ?? {
                let fresh = VoxelBuilder.character(look: figure.look)
                fresh.opacity = 0
                fresh.runAction(.fadeIn(duration: 0.35))
                scene.rootNode.addChildNode(fresh)
                c.nodes[figure.id] = fresh
                return fresh
            }()
            node.scale = SCNVector3(scale, scale, scale)

            let current = c.positions[figure.id] ?? figure.feet
            if isNew {
                c.positions[figure.id] = figure.feet
                node.position = c.scenePosition(forFeet: figure.feet)
            } else if geometryChanged {
                // The transform moved, not the person: remap wherever the
                // figure currently is — mid-walk included.
                node.position = c.scenePosition(forFeet: current)
            }

            // A new destination becomes a route; the mover loop walks it
            // at constant speed. Your avatar's 60 Hz steps (duration 0)
            // are applied directly — they ARE the mover, upstream.
            let knownTarget = c.routes[figure.id]?.target ?? current
            if figure.feet != knownTarget {
                turnTowards(figure.feet, from: current, id: figure.id, node: node, c: c)
                if figure.moveDuration <= 0 {
                    c.routes[figure.id] = nil
                    c.positions[figure.id] = figure.feet
                    node.position = c.scenePosition(forFeet: figure.feet)
                } else {
                    let distance = hypot(figure.feet.x - current.x,
                                         figure.feet.y - current.y)
                    c.routes[figure.id] = (
                        target: figure.feet,
                        speed: max(8, distance / figure.moveDuration)
                    )
                    c.startMoverIfNeeded()
                }
            }

            if c.poses[figure.id] != figure.pose {
                VoxelBuilder.apply(figure.pose, to: node)
                // Sitting is the one pose that re-faces the camera.
                if figure.pose == .seated {
                    c.yaws[figure.id] = VoxelBuilder.restingYaw
                }
            }
            c.poses[figure.id] = figure.pose
        }

        // Whoever is no longer in the room fades out, then leaves the
        // scene graph for good.
        for (id, node) in c.nodes where !seen.contains(id) {
            node.runAction(.sequence([.fadeOut(duration: 0.3), .removeFromParentNode()]))
            c.nodes[id] = nil
            c.positions[id] = nil
            c.routes[id] = nil
            c.poses[id] = nil
            c.yaws[id] = nil
        }
    }

    /// Turn toward the direction of travel — walking away shows the back
    /// of the head. Only when the heading actually changes: re-issuing
    /// the same turn sixty times a second would fight itself.
    private func turnTowards(
        _ target: CGPoint, from current: CGPoint,
        id: Int, node: SCNNode, c: Coordinator
    ) {
        let dx = target.x - current.x
        let dy = target.y - current.y
        guard abs(dx) + abs(dy) > 0.1 else { return }
        let yaw = (atan2(dx, dy) * 50).rounded() / 50
        if c.yaws[id] != yaw {
            c.yaws[id] = yaw
            VoxelBuilder.turn(node, yaw: yaw)
        }
    }

    static func dismantleNSView(_ nsView: SCNView, coordinator: Coordinator) {
        coordinator.mover?.cancel()
    }

    @MainActor
    final class Coordinator {
        var nodes: [Int: SCNNode] = [:]
        /// Where each figure IS right now, in logical coordinates. The
        /// single source of truth for on-screen placement.
        var positions: [Int: CGPoint] = [:]
        /// Where each figure is heading, and how fast (logical px/s).
        var routes: [Int: (target: CGPoint, speed: CGFloat)] = [:]
        var poses: [Int: VoxelPose] = [:]
        /// Last heading applied per figure, so a steady walk issues one
        /// turn, not one per frame.
        var yaws: [Int: CGFloat] = [:]
        var scale: CGFloat = 0
        var offset: CGPoint = .zero
        var contentSize: CGSize = .zero
        /// The 60 Hz mover; alive exactly while someone is en route.
        var mover: Task<Void, Never>?

        /// Logical feet → scene position. SceneKit's Y grows upward while
        /// the view's grows downward, hence the flip. Z spreads characters
        /// in depth so someone lower in the room renders in front.
        func scenePosition(forFeet feet: CGPoint) -> SCNVector3 {
            SCNVector3(
                offset.x + feet.x * scale,
                contentSize.height - (offset.y + feet.y * scale),
                feet.y * 0.1 * scale
            )
        }

        func startMoverIfNeeded() {
            guard mover == nil else { return }
            mover = Task { @MainActor [weak self] in
                var lastTick = ContinuousClock.now
                while !Task.isCancelled {
                    guard let self, !self.routes.isEmpty else { break }
                    // Tight tolerance keeps the tick regular — irregular
                    // steps read as juddery walking.
                    try? await Task.sleep(for: .milliseconds(16),
                                          tolerance: .milliseconds(2))
                    let now = ContinuousClock.now
                    let elapsed = lastTick.duration(to: now)
                    lastTick = now
                    let dt = min(
                        Double(elapsed.components.seconds)
                            + Double(elapsed.components.attoseconds) * 1e-18,
                        0.05
                    )
                    self.tick(dt: CGFloat(dt))
                }
                self?.mover = nil
            }
        }

        /// One tick: every en-route figure takes a constant-speed step.
        private func tick(dt: CGFloat) {
            for (id, route) in routes {
                guard var position = positions[id], let node = nodes[id] else {
                    routes[id] = nil
                    continue
                }
                let dx = route.target.x - position.x
                let dy = route.target.y - position.y
                let distance = (dx * dx + dy * dy).squareRoot()
                let step = route.speed * dt
                if distance <= step {
                    position = route.target
                    routes[id] = nil
                } else {
                    position.x += dx / distance * step
                    position.y += dy / distance * step
                }
                positions[id] = position
                node.position = scenePosition(forFeet: position)
            }
        }
    }
}

// MARK: - The character model

/// Builds and animates the voxel body. Everything is measured in LOGICAL
/// room pixels (the node's scale maps them to view points), with the feet
/// at the local origin — same convention as the old flat sprite.
enum VoxelBuilder {

    /// The body's logical footprint — the 2D layers (tap target, pill
    /// placement) size themselves from this.
    static let figureSize = CGSize(width: 12, height: 17)

    /// The resting three-quarter turn: enough to see two sides of every
    /// box, which is what reads as "3D" even when nobody moves.
    static let restingYaw: CGFloat = -0.22

    // ── Assembly ────────────────────────────────────────────────────────

    static func character(look: SpriteLook) -> SCNNode {
        let root = SCNNode()

        // The soft blob under the feet. Parented to the root (not the
        // trunk) so it never spins with the body.
        let shadow = SCNPlane(width: 11, height: 3)
        shadow.cornerRadius = 1.5
        let shadowMaterial = SCNMaterial()
        shadowMaterial.diffuse.contents = NSColor.black
        shadowMaterial.transparency = 0.22
        shadowMaterial.lightingModel = .constant
        shadowMaterial.writesToDepthBuffer = false
        shadow.materials = [shadowMaterial]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.position = SCNVector3(0, 0.8, -3)
        shadowNode.renderingOrder = -1
        root.addChildNode(shadowNode)

        // Everything visible hangs off the trunk, which is what rotates.
        let trunk = SCNNode()
        trunk.name = "trunk"
        trunk.eulerAngles = SCNVector3(0, restingYaw, 0)
        root.addChildNode(trunk)

        // The hips group is what a chair lowers.
        let hips = SCNNode()
        hips.name = "hips"
        trunk.addChildNode(hips)

        let shoe = darker(look.pants)

        // Legs: containers anchored AT the hip, limbs hanging below the
        // origin — rotating the container swings the whole leg.
        for (name, x) in [("legL", CGFloat(-1.8)), ("legR", CGFloat(1.8))] {
            let leg = SCNNode()
            leg.name = name
            leg.position = SCNVector3(x, 5, 0)
            let pant = box(2, 4, 2.4, color: look.pants)
            pant.position = SCNVector3(0, -2, 0)
            leg.addChildNode(pant)
            let foot = box(2.2, 1.2, 2.9, color: shoe)
            foot.position = SCNVector3(0, -4.5, 0.2)
            leg.addChildNode(foot)
            hips.addChildNode(leg)
        }

        let torso = box(7, 6, 3.6, color: look.shirt)
        torso.position = SCNVector3(0, 8, 0)
        hips.addChildNode(torso)

        // Arms: same trick — anchored at the shoulder.
        for (name, x) in [("armL", CGFloat(-4.4)), ("armR", CGFloat(4.4))] {
            let arm = SCNNode()
            arm.name = name
            arm.position = SCNVector3(x, 10.6, 0)
            let sleeve = box(1.8, 3.4, 2.2, color: look.shirt)
            sleeve.position = SCNVector3(0, -1.6, 0)
            arm.addChildNode(sleeve)
            let hand = box(1.7, 1.9, 2.1, color: look.skin)
            hand.position = SCNVector3(0, -4.2, 0)
            arm.addChildNode(hand)
            hips.addChildNode(arm)
        }

        let head = box(6, 6, 5.6, color: look.skin)
        head.position = SCNVector3(0, 14, 0)
        hips.addChildNode(head)

        let cap = box(6.6, 2.4, 6.2, color: look.hair)
        cap.position = SCNVector3(0, 16.2, 0)
        hips.addChildNode(cap)
        let back = box(6.6, 4.6, 1.4, color: look.hair)
        back.position = SCNVector3(0, 14.4, -2.4)
        hips.addChildNode(back)

        for x in [CGFloat(-1.4), CGFloat(1.4)] {
            let eye = box(0.9, 1.2, 0.3, color: NSColor(white: 0.12, alpha: 1))
            eye.position = SCNVector3(x, 13.8, 2.85)
            hips.addChildNode(eye)
        }

        return root
    }

    // ── Poses & motion ──────────────────────────────────────────────────

    static func apply(_ pose: VoxelPose, to root: SCNNode) {
        guard let trunk = root.childNode(withName: "trunk", recursively: false),
              let hips = trunk.childNode(withName: "hips", recursively: false)
        else { return }
        let limbs = ["legL", "legR", "armL", "armR"].compactMap {
            hips.childNode(withName: $0, recursively: false)
        }
        guard limbs.count == 4 else { return }
        for limb in limbs { limb.removeAction(forKey: "swing") }
        let settle = 0.16

        switch pose {
        case .seated:
            // Thighs forward, body down onto the chair, hands toward the
            // keyboard. Facing the camera, like the room always drew it.
            hips.runAction(.move(to: SCNVector3(0, -3.6, 0), duration: settle))
            limbs[0].runAction(.rotateTo(x: -1.25, y: 0, z: 0, duration: settle))
            limbs[1].runAction(.rotateTo(x: -1.25, y: 0, z: 0, duration: settle))
            limbs[2].runAction(.rotateTo(x: -0.8, y: 0, z: 0, duration: settle))
            limbs[3].runAction(.rotateTo(x: -0.8, y: 0, z: 0, duration: settle))
            turn(root, yaw: restingYaw)

        case .standing:
            // Deliberately NO turn here: stop walking away and you stay
            // with your back to the camera, like a person would. Only
            // sitting down re-faces the room.
            hips.runAction(.move(to: SCNVector3(0, 0, 0), duration: settle))
            for limb in limbs {
                limb.runAction(.rotateTo(x: 0, y: 0, z: 0, duration: settle))
            }

        case .walking:
            hips.runAction(.move(to: SCNVector3(0, 0, 0), duration: 0.1))
            // Opposite limbs swing together: left leg with right arm.
            swing(limbs[0], forward: true)
            swing(limbs[1], forward: false)
            swing(limbs[2], forward: false)
            swing(limbs[3], forward: true)
        }
    }

    /// Rotates the body toward a yaw angle (radians around the vertical).
    static func turn(_ root: SCNNode, yaw: CGFloat) {
        guard let trunk = root.childNode(withName: "trunk", recursively: false) else { return }
        let action = SCNAction.rotateTo(
            x: 0, y: yaw, z: 0, duration: 0.18, usesShortestUnitArc: true
        )
        action.timingMode = .easeInEaseOut
        trunk.removeAction(forKey: "turn")
        trunk.runAction(action, forKey: "turn")
    }

    private static func swing(_ limb: SCNNode, forward: Bool) {
        let ahead = SCNAction.rotateTo(x: 0.55, y: 0, z: 0, duration: 0.18)
        let behind = SCNAction.rotateTo(x: -0.55, y: 0, z: 0, duration: 0.18)
        ahead.timingMode = .easeInEaseOut
        behind.timingMode = .easeInEaseOut
        let cycle = SCNAction.repeatForever(
            .sequence(forward ? [ahead, behind] : [behind, ahead])
        )
        limb.runAction(cycle, forKey: "swing")
    }

    // ── Shared bits ─────────────────────────────────────────────────────

    /// One light setup for the room overlay and the card's portrait: a
    /// warm-white sun from the upper left plus a generous ambient, so
    /// every box face gets its own shade — that's the whole 3D effect.
    static func addLights(to scene: SCNScene) {
        let sun = SCNLight()
        sun.type = .directional
        sun.color = NSColor(white: 1.0, alpha: 1)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.55, -0.7, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(white: 0.62, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    private static func box(
        _ w: CGFloat, _ h: CGFloat, _ d: CGFloat, color: NSColor
    ) -> SCNNode {
        let geometry = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .blinn
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private static func box(
        _ w: CGFloat, _ h: CGFloat, _ d: CGFloat, color: Color
    ) -> SCNNode {
        box(w, h, d, color: NSColor(color))
    }

    private static func darker(_ color: Color) -> NSColor {
        NSColor(color).blended(withFraction: 0.4, of: .black) ?? NSColor(color)
    }
}

// MARK: - The card's portrait

/// A tiny stand-alone scene for the detail card: the same character,
/// slowly turning on itself. Perspective camera here — a portrait is
/// allowed some depth.
struct VoxelPortrait: NSViewRepresentable {

    let look: SpriteLook

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = ClickThroughSCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30

        let scene = SCNScene()
        view.scene = scene
        VoxelBuilder.addLights(to: scene)

        let camera = SCNCamera()
        camera.fieldOfView = 30
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 11, 46)
        cameraNode.look(at: SCNVector3(0, 8.4, 0))
        scene.rootNode.addChildNode(cameraNode)

        context.coordinator.look = look
        install(look: look, in: scene)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        // Rebuild only when the card switched to another agent.
        guard context.coordinator.look != look, let scene = view.scene else { return }
        context.coordinator.look = look
        scene.rootNode.childNode(withName: "figure", recursively: false)?
            .removeFromParentNode()
        install(look: look, in: scene)
    }

    private func install(look: SpriteLook, in scene: SCNScene) {
        let figure = VoxelBuilder.character(look: look)
        figure.name = "figure"
        scene.rootNode.addChildNode(figure)
        if let trunk = figure.childNode(withName: "trunk", recursively: false) {
            trunk.runAction(
                .repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 12))
            )
        }
    }

    final class Coordinator {
        var look: SpriteLook?
    }
}
