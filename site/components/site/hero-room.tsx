"use client"

import { useEffect, useRef } from "react"

/**
 * The product moment, rendered live — and playable.
 *
 * Two agents take turns doing the finished-work crossing: dockkeep works,
 * finishes, walks to your desk, waits for review, walks back and sits;
 * then circle does the same; repeat. You sit at your desk the whole time,
 * like in real life — UNLESS the visitor presses W-A-S-D (physical keys,
 * so Z-Q-S-D on an AZERTY keyboard): then your avatar walks around the
 * office, exactly like the app's movement. Release the keys near your
 * chair and you sit back down.
 *
 * Movement rules mirror the app: constant speed (people walk, they don't
 * glide), characters face where they're going — back of the head on the
 * way out — and legs actually alternate. Same geometry (×2.5), palette
 * and timings as the app, so the site never oversells.
 */

// ── The walkers' shared timeline ─────────────────────────────────────────

const WALK_PHASES: Array<[name: string, duration: number]> = [
  ["work", 2000],
  ["stand", 450],
  ["walk", 2900],
  ["desk", 2600],
  ["back", 2900],
  ["sit", 450],
]
const WALK_TOTAL = WALK_PHASES.reduce((total, [, d]) => total + d, 0)
/** dockkeep goes first, then circle — one full crossing each. */
const CYCLE = WALK_TOTAL * 2

// Waypoints in the 960×550 design space (app logical coords × 2.5).
const DK_SEAT = { x: 480, y: 190 }
const DK_STAND = { x: 515, y: 195 }
const C_SEAT = { x: 250, y: 190 }
const C_STAND = { x: 285, y: 195 }
const DESK = { x: 480, y: 390 }
const YOU_SEAT = { x: 480, y: 465 }

// The app's status colors (SessionStatus.uiColor).
const STATUS = {
  working: "#34c759",
  waiting: "#ff9500",
  finished: "#af52de",
}

// The app's day palette (PixelPalette.day), verbatim.
const P = {
  floorA: "#ebdcc0",
  floorB: "#e4d3b2",
  floorLine: "#dccba6",
  wall: "#6e6880",
  wallTop: "#8b85a0",
  windowGlass: "#bbdce8",
  windowLite: "#d8eef6",
  windowFrame: "#565064",
  carpet: "#928bc8",
  carpetDark: "#817ab7",
  carpetLine: "#9e97d2",
  rug: "#8fb6c9",
  rugDark: "#7fa6ba",
  rugLine: "#9fc4d5",
  loungeCarpet: "#c9b7d9",
  loungeCarpetDark: "#b9a7c9",
  desk: "#b5804c",
  deskDark: "#8f6138",
  deskLite: "#c69261",
  monitor: "#2e3247",
  screenOn: "#a8e0ee",
  screenOff: "#47506b",
  chair: "#4e5273",
  chairDark: "#3d4059",
  sofa: "#e58544",
  sofaDark: "#c96b2f",
  sofaLite: "#f09a5c",
  lowTable: "#c9a26b",
  lowTableDark: "#a98249",
  plant: "#63a85c",
  plantDark: "#417f42",
  pot: "#b06b41",
  potDark: "#8e5330",
  pingTop: "#45a06f",
  pingLine: "#f2f0e8",
  pingDark: "#357d56",
  shadow: "rgb(61 46 26 / 0.18)",
}

const lerp = (a: number, b: number, t: number) => a + (b - a) * t
const easeInOut = (t: number) =>
  t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2

/** Darkens (f < 1) or lightens (f > 1) a #rrggbb color — the fake light. */
function shade(hex: string, f: number): string {
  const n = parseInt(hex.slice(1), 16)
  const ch = (v: number) => Math.max(0, Math.min(255, Math.round(v * f)))
  const r = ch((n >> 16) & 255)
  const g = ch((n >> 8) & 255)
  const b = ch(n & 255)
  return `#${((r << 16) | (g << 8) | b).toString(16).padStart(6, "0")}`
}

// ── One voxel colleague ──────────────────────────────────────────────────

type Look = { skin: string; hair: string; shirt: string; pants: string }
type Facing = "front" | "back" | "left" | "right"

/**
 * The body, feet at (0, 0), ~30×48 px, shaded like the app's 3D bodies —
 * lit from the upper left, darker on the right faces. `seated` is the
 * compact on-the-chair pose; walking alternates the legs and bobs.
 */
function Body({
  look,
  pose,
  facing = "front",
  frame = 0,
}: {
  look: Look
  pose: "seated" | "stand" | "walk"
  facing?: Facing
  frame?: 0 | 1
}) {
  const { skin, hair, shirt, pants } = look

  if (pose === "seated") {
    return (
      <g>
        <ellipse cx="0" cy="0" rx="13" ry="4" fill={P.shadow} />
        <rect x="-8.75" y="-20" width="17.5" height="12" fill={shirt} />
        <rect x="5.25" y="-20" width="3.5" height="12" fill={shade(shirt, 0.82)} />
        <rect x="-8.75" y="-20" width="17.5" height="2.5" fill={shade(shirt, 1.12)} />
        <rect x="-7.5" y="-35" width="15" height="15" fill={skin} />
        <rect x="4.5" y="-35" width="3" height="15" fill={shade(skin, 0.85)} />
        <rect x="-8.25" y="-38.5" width="16.5" height="6.5" fill={hair} />
        <rect x="-8.25" y="-38.5" width="16.5" height="2" fill={shade(hair, 1.3)} />
        <rect x="-8.25" y="-33.5" width="2.5" height="5" fill={hair} />
        <rect x="5.75" y="-33.5" width="2.5" height="5" fill={shade(hair, 0.8)} />
        <rect x="-4" y="-28.5" width="2.4" height="3.2" fill="#1f1f1f" />
        <rect x="1.6" y="-28.5" width="2.4" height="3.2" fill="#1f1f1f" />
      </g>
    )
  }

  // Walking: one leg grounded, one lifted, swapped each frame; the body
  // bobs on the off-beat — the app's two-frame gait.
  const liftLeft = pose === "walk" && frame === 1 ? -2.2 : 0
  const liftRight = pose === "walk" && frame === 0 ? -2.2 : 0
  const bob = pose === "walk" && frame === 1 ? -1.2 : 0

  return (
    <g>
      <ellipse cx="0" cy="0" rx="13" ry="4" fill={P.shadow} />

      <g transform={`translate(0,${liftLeft})`}>
        <rect x="-9.5" y="-12.5" width="9" height="10" fill={pants} />
        <rect x="-10.5" y="-3.5" width="10.5" height="3.5" fill={shade(pants, 0.55)} />
      </g>
      <g transform={`translate(0,${liftRight})`}>
        <rect x="0.5" y="-12.5" width="9" height="10" fill={shade(pants, 0.88)} />
        <rect x="0.5" y="-3.5" width="10.5" height="3.5" fill={shade(pants, 0.55)} />
      </g>

      <g transform={`translate(0,${bob})`}>
        {/* torso, right face in shade */}
        <rect x="-8.75" y="-27.5" width="17.5" height="15" fill={shirt} />
        <rect x="5.25" y="-27.5" width="3.5" height="15" fill={shade(shirt, 0.82)} />
        <rect x="-8.75" y="-27.5" width="17.5" height="2.5" fill={shade(shirt, 1.12)} />
        {/* arms + hands */}
        <rect x="-13.25" y="-26.5" width="4.5" height="9" fill={shade(shirt, 0.9)} />
        <rect x="8.75" y="-26.5" width="4.5" height="9" fill={shade(shirt, 0.78)} />
        <rect x="-13.25" y="-17.5" width="4.5" height="4.5" fill={skin} />
        <rect x="8.75" y="-17.5" width="4.5" height="4.5" fill={shade(skin, 0.85)} />
        {/* head */}
        <rect x="-7.5" y="-42.5" width="15" height="15" fill={skin} />
        <rect x="4.5" y="-42.5" width="3" height="15" fill={shade(skin, 0.85)} />
        {facing === "back" ? (
          // From behind, the head is mostly hair — no face at all.
          <>
            <rect x="-8.25" y="-46" width="16.5" height="17" fill={hair} />
            <rect x="-8.25" y="-46" width="16.5" height="2" fill={shade(hair, 1.3)} />
            <rect x="4.75" y="-46" width="3.5" height="17" fill={shade(hair, 0.8)} />
          </>
        ) : (
          <>
            <rect x="-8.25" y="-46" width="16.5" height="6.5" fill={hair} />
            <rect x="-8.25" y="-46" width="16.5" height="2" fill={shade(hair, 1.3)} />
            <rect x="-8.25" y="-41" width="2.5" height="5" fill={hair} />
            <rect x="5.75" y="-41" width="2.5" height="5" fill={shade(hair, 0.8)} />
            {facing === "front" && (
              <>
                <rect x="-4" y="-36" width="2.4" height="3.2" fill="#1f1f1f" />
                <rect x="1.6" y="-36" width="2.4" height="3.2" fill="#1f1f1f" />
              </>
            )}
            {facing === "left" && (
              <rect x="-6" y="-36" width="2.4" height="3.2" fill="#1f1f1f" />
            )}
            {facing === "right" && (
              <rect x="3.6" y="-36" width="2.4" height="3.2" fill="#1f1f1f" />
            )}
          </>
        )}
      </g>
    </g>
  )
}

/** The Gather-ism: a floating name pill with a status dot. */
function Pill({
  name,
  color,
  dotRef,
}: {
  name: string
  color: string
  dotRef?: React.Ref<SVGCircleElement>
}) {
  const width = name.length * 6.4 + 26
  return (
    <g>
      <rect
        x={-width / 2}
        y="-9"
        width={width}
        height="18"
        rx="9"
        fill="rgb(0 0 0 / 0.85)"
      />
      <circle ref={dotRef} cx={-width / 2 + 10} cy="0" r="3.5" fill={color} />
      <text
        x="5"
        y="3.5"
        fontSize="10.5"
        fontWeight="500"
        fill="#ffffff"
        textAnchor="middle"
        fontFamily="var(--font-sans), system-ui, sans-serif"
      >
        {name}
      </text>
    </g>
  )
}

/** A potted plant, the app's `plant(at:)` at ×2.5. */
function Plant({ x, y }: { x: number; y: number }) {
  return (
    <g transform={`translate(${x},${y})`}>
      <rect x="2.5" y="-15" width="15" height="15" fill={P.plant} />
      <rect x="-2.5" y="-10" width="7.5" height="7.5" fill={P.plant} />
      <rect x="15" y="-10" width="7.5" height="7.5" fill={P.plant} />
      <rect x="5" y="-20" width="10" height="7.5" fill={P.plant} />
      <rect x="7.5" y="-12.5" width="5" height="10" fill={P.plantDark} />
      <rect x="0" y="0" width="20" height="15" fill={P.pot} />
      <rect x="0" y="10" width="20" height="5" fill={P.potDark} />
    </g>
  )
}

/** One desk pod: carpet, desk, monitor, chair, plant. */
function Pod({ x, screen }: { x: number; screen: "breathing" | "off" }) {
  return (
    <g transform={`translate(${x},0)`}>
      <rect x="0" y="100" width="140" height="115" fill={P.carpet} />
      <rect x="0" y="100" width="140" height="5" fill={P.carpetLine} />
      <rect x="0" y="210" width="140" height="5" fill={P.carpetDark} />
      <rect x="0" y="100" width="5" height="115" fill={P.carpetLine} />
      <rect x="135" y="100" width="5" height="115" fill={P.carpetDark} />
      <rect x="32.5" y="160" width="75" height="7.5" fill={P.shadow} />
      <rect x="27.5" y="130" width="85" height="30" fill={P.desk} />
      <rect x="27.5" y="130" width="85" height="5" fill={P.deskLite} />
      <rect x="27.5" y="155" width="85" height="5" fill={P.deskDark} />
      <rect x="55" y="110" width="30" height="22.5" fill={P.monitor} />
      <rect
        x="57.5"
        y="112.5"
        width="25"
        height="15"
        fill={screen === "breathing" ? P.screenOn : P.screenOff}
        className={screen === "breathing" ? "roster-screen" : undefined}
      />
      <rect x="57.5" y="170" width="25" height="20" fill={P.chair} />
      <rect x="57.5" y="180" width="25" height="5" fill={P.chairDark} />
      <Plant x={110} y={200} />
    </g>
  )
}

// ── The cast ─────────────────────────────────────────────────────────────

const CIRCLE_LOOK: Look = {
  skin: "#f2c9a0",
  hair: "#2e2a28",
  shirt: "#4c8bf5",
  pants: "#31374f",
}
const BLOG_LOOK: Look = {
  skin: "#c68642",
  hair: "#1f1f1f",
  shirt: "#e08a3c",
  pants: "#4a3a30",
}
const WALKER_LOOK: Look = {
  skin: "#f2c9a0",
  hair: "#d9a441",
  shirt: "#7c6fd0",
  pants: "#3a3f52",
}
const YOU_LOOK: Look = {
  skin: "#8d5524",
  hair: "#101010",
  shirt: "#3a3f52",
  pants: "#23263a",
}

/** All poses of one character, stacked; the loop shows exactly one. */
function Variants({
  look,
  initial,
  variants,
}: {
  look: Look
  initial: string
  variants: Array<{
    name: string
    pose: "seated" | "stand" | "walk"
    facing?: Facing
    frame?: 0 | 1
  }>
}) {
  return (
    <>
      {variants.map((v) => (
        <g
          key={v.name}
          data-v={v.name}
          style={{ display: v.name === initial ? undefined : "none" }}
        >
          <Body look={look} pose={v.pose} facing={v.facing} frame={v.frame} />
        </g>
      ))}
    </>
  )
}

const WALKER_VARIANTS = [
  { name: "seated", pose: "seated" },
  { name: "stand", pose: "stand" },
  { name: "wf0", pose: "walk", facing: "front", frame: 0 },
  { name: "wf1", pose: "walk", facing: "front", frame: 1 },
  { name: "wb0", pose: "walk", facing: "back", frame: 0 },
  { name: "wb1", pose: "walk", facing: "back", frame: 1 },
] as const

const YOU_VARIANTS = [
  { name: "seated", pose: "seated" },
  { name: "stand", pose: "stand" },
  { name: "f0", pose: "walk", facing: "front", frame: 0 },
  { name: "f1", pose: "walk", facing: "front", frame: 1 },
  { name: "b0", pose: "walk", facing: "back", frame: 0 },
  { name: "b1", pose: "walk", facing: "back", frame: 1 },
  { name: "l0", pose: "walk", facing: "left", frame: 0 },
  { name: "l1", pose: "walk", facing: "left", frame: 1 },
  { name: "r0", pose: "walk", facing: "right", frame: 0 },
  { name: "r1", pose: "walk", facing: "right", frame: 1 },
] as const

function isTypingTarget(target: EventTarget | null) {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable ||
      target.tagName === "INPUT" ||
      target.tagName === "TEXTAREA" ||
      target.tagName === "SELECT")
  )
}

export function HeroRoom() {
  const dkRef = useRef<SVGGElement>(null)
  const dkDotRef = useRef<SVGCircleElement>(null)
  const dkGlowRef = useRef<SVGCircleElement>(null)
  const cRef = useRef<SVGGElement>(null)
  const cDotRef = useRef<SVGCircleElement>(null)
  const cGlowRef = useRef<SVGCircleElement>(null)
  const youRef = useRef<SVGGElement>(null)

  useEffect(() => {
    // Frozen room for users who prefer reduced motion.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const setVariant = (root: SVGGElement | null, name: string) => {
      root?.querySelectorAll<SVGGElement>("[data-v]").forEach((g) => {
        g.style.display = g.dataset.v === name ? "" : "none"
      })
    }

    // ── Your avatar: W-A-S-D by PHYSICAL position (e.code), so it's
    // Z-Q-S-D on an AZERTY keyboard, same spot under the fingers. ──
    const you = {
      x: YOU_SEAT.x,
      y: YOU_SEAT.y,
      keys: new Set<string>(),
    }
    const MOVE_CODES = ["KeyW", "KeyA", "KeyS", "KeyD"]
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.metaKey || event.ctrlKey || event.altKey) return
      if (isTypingTarget(event.target)) return
      if (!MOVE_CODES.includes(event.code)) return
      you.keys.add(event.code)
    }
    const onKeyUp = (event: KeyboardEvent) => {
      you.keys.delete(event.code)
    }
    const onBlur = () => you.keys.clear()
    window.addEventListener("keydown", onKeyDown)
    window.addEventListener("keyup", onKeyUp)
    window.addEventListener("blur", onBlur)

    /** One walker's whole life, from its timeline slice. t < 0 = off
     *  duty: seated at its desk, working. */
    const drive = (
      root: SVGGElement | null,
      dot: SVGCircleElement | null,
      glow: SVGCircleElement | null,
      seat: { x: number; y: number },
      standSpot: { x: number; y: number },
      t: number,
      gait: 0 | 1
    ) => {
      let x = seat.x
      let y = seat.y
      let glowOpacity = 0
      let dotColor = STATUS.working
      let variant = "seated"
      if (t >= 0) {
        let remaining = t
        let name = "work"
        let progress = 0
        for (const [phase, duration] of WALK_PHASES) {
          if (remaining < duration) {
            name = phase
            progress = remaining / duration
            break
          }
          remaining -= duration
        }
        if (name === "stand") {
          x = lerp(seat.x, standSpot.x, easeInOut(progress))
          y = lerp(seat.y, standSpot.y, easeInOut(progress))
          variant = "stand"
          dotColor = STATUS.finished
        } else if (name === "walk") {
          // Constant speed, like the app: people walk, they don't glide.
          x = lerp(standSpot.x, DESK.x, progress)
          y = lerp(standSpot.y, DESK.y, progress)
          variant = `wf${gait}`
          dotColor = STATUS.finished
        } else if (name === "desk") {
          x = DESK.x
          y = DESK.y
          glowOpacity = 0.22
          variant = "stand"
          dotColor = STATUS.finished
        } else if (name === "back") {
          // Walking away — you see the back of the head.
          x = lerp(DESK.x, standSpot.x, progress)
          y = lerp(DESK.y, standSpot.y, progress)
          variant = `wb${gait}`
        } else if (name === "sit") {
          x = lerp(standSpot.x, seat.x, easeInOut(progress))
          y = lerp(standSpot.y, seat.y, easeInOut(progress))
          variant = "stand"
        }
      }
      root?.setAttribute("transform", `translate(${x},${y})`)
      setVariant(root, variant)
      dot?.setAttribute("fill", dotColor)
      glow?.setAttribute("opacity", String(glowOpacity))
    }

    let raf = 0
    let lastNow = 0
    const frame = (now: number) => {
      const gait = (Math.floor(now / 140) % 2) as 0 | 1
      const dt = lastNow ? Math.min((now - lastNow) / 1000, 0.05) : 0
      lastNow = now

      // ── The two walkers take turns: dockkeep, then circle. ──
      const cycleT = now % CYCLE
      drive(
        dkRef.current, dkDotRef.current, dkGlowRef.current,
        DK_SEAT, DK_STAND,
        cycleT < WALK_TOTAL ? cycleT : -1,
        gait
      )
      drive(
        cRef.current, cDotRef.current, cGlowRef.current,
        C_SEAT, C_STAND,
        cycleT >= WALK_TOTAL ? cycleT - WALK_TOTAL : -1,
        gait
      )

      // ── You: driven by the visitor's keys, or peacefully seated. ──
      {
        const left = you.keys.has("KeyA") ? 1 : 0
        const right = you.keys.has("KeyD") ? 1 : 0
        const up = you.keys.has("KeyW") ? 1 : 0
        const down = you.keys.has("KeyS") ? 1 : 0
        const dx = right - left
        const dy = down - up
        let variant: string
        if (dx !== 0 || dy !== 0) {
          const length = Math.hypot(dx, dy)
          const speed = 155 // design px/s — the app's 62 logical px/s
          you.x = Math.min(Math.max(you.x + (dx / length) * speed * dt, 20), 940)
          you.y = Math.min(Math.max(you.y + (dy / length) * speed * dt, 68), 532)
          const facing =
            Math.abs(dx) >= Math.abs(dy)
              ? dx < 0 ? "l" : "r"
              : dy < 0 ? "b" : "f"
          variant = `${facing}${gait}`
        } else if (
          Math.hypot(you.x - YOU_SEAT.x, you.y - YOU_SEAT.y) < 16
        ) {
          // Close enough to the chair: sit back down, like the app.
          you.x = YOU_SEAT.x
          you.y = YOU_SEAT.y
          variant = "seated"
        } else {
          variant = "stand"
        }
        youRef.current?.setAttribute("transform", `translate(${you.x},${you.y})`)
        setVariant(youRef.current, variant)
      }

      raf = requestAnimationFrame(frame)
    }
    raf = requestAnimationFrame(frame)
    return () => {
      cancelAnimationFrame(raf)
      window.removeEventListener("keydown", onKeyDown)
      window.removeEventListener("keyup", onKeyUp)
      window.removeEventListener("blur", onBlur)
    }
  }, [])

  return (
    <svg
      viewBox="0 0 960 550"
      role="img"
      aria-label="Pixel office where agents take turns walking to your desk; the W, A, S and D keys move your avatar"
      className="block h-auto w-full"
      style={{ background: P.floorB }}
    >
      {/* ── Floor: checker tiles + grout ── */}
      <defs>
        <pattern id="roster-tiles" width="80" height="80" patternUnits="userSpaceOnUse">
          <rect width="80" height="80" fill={P.floorB} />
          <rect width="40" height="40" fill={P.floorA} />
          <rect x="40" y="40" width="40" height="40" fill={P.floorA} />
          <path
            d="M40 0V80 M0 40H80 M80 0V80 M0 80H80"
            stroke={P.floorLine}
            strokeWidth="1.5"
          />
        </pattern>
      </defs>
      <rect x="0" y="45" width="960" height="505" fill="url(#roster-tiles)" />

      {/* ── Wall band with windows ── */}
      <rect x="0" y="0" width="960" height="45" fill={P.wall} />
      <rect x="0" y="0" width="960" height="7.5" fill={P.wallTop} />
      <rect x="0" y="45" width="960" height="5" fill={P.shadow} />
      {[85, 265, 445, 625, 805].map((wx) => (
        <g key={wx}>
          <rect x={wx} y="10" width="65" height="27.5" fill={P.windowFrame} />
          <rect x={wx + 2.5} y="12.5" width="60" height="22.5" fill={P.windowGlass} />
          <rect x={wx + 2.5} y="12.5" width="60" height="7.5" fill={P.windowLite} />
          <rect x={wx + 30} y="12.5" width="5" height="22.5" fill={P.windowFrame} />
        </g>
      ))}

      {/* ── Desk pods (circle, dockkeep, blog) ── */}
      <Pod x={180} screen="breathing" />
      <Pod x={410} screen="breathing" />
      <Pod x={640} screen="off" />

      {/* ── Your corner ── */}
      <g>
        <rect x="375" y="350" width="210" height="150" fill={P.rug} />
        <rect x="375" y="350" width="210" height="5" fill={P.rugLine} />
        <rect x="375" y="495" width="210" height="5" fill={P.rugDark} />
        <rect x="375" y="350" width="5" height="150" fill={P.rugLine} />
        <rect x="580" y="350" width="5" height="150" fill={P.rugDark} />
        <rect x="442.5" y="430" width="75" height="7.5" fill={P.shadow} />
        <rect x="437.5" y="400" width="85" height="30" fill={P.desk} />
        <rect x="437.5" y="400" width="85" height="5" fill={P.deskLite} />
        <rect x="437.5" y="425" width="85" height="5" fill={P.deskDark} />
        <rect x="465" y="380" width="30" height="22.5" fill={P.monitor} />
        <rect
          x="467.5"
          y="382.5"
          width="25"
          height="15"
          fill={P.screenOn}
          className="roster-screen"
        />
        <Plant x={387.5} y={470} />
        <Plant x={547.5} y={470} />
      </g>

      {/* ── Lounge ── */}
      <g>
        <rect x="705" y="365" width="210" height="125" fill={P.loungeCarpet} />
        <rect x="705" y="485" width="210" height="5" fill={P.loungeCarpetDark} />
        <rect x="760" y="415" width="95" height="7.5" fill={P.shadow} />
        <rect x="755" y="385" width="100" height="30" fill={P.sofa} />
        <rect x="755" y="385" width="100" height="7.5" fill={P.sofaLite} />
        <rect x="755" y="407.5" width="100" height="7.5" fill={P.sofaDark} />
        <rect x="747.5" y="385" width="7.5" height="30" fill={P.sofaDark} />
        <rect x="855" y="385" width="7.5" height="30" fill={P.sofaDark} />
        <rect x="780" y="440" width="45" height="17.5" fill={P.lowTable} />
        <rect x="780" y="452.5" width="45" height="5" fill={P.lowTableDark} />
        <Plant x={865} y={470} />
      </g>

      {/* ── Ping-pong ── */}
      <g>
        <rect x="85" y="430" width="95" height="7.5" fill={P.shadow} />
        <rect x="80" y="380" width="100" height="50" fill={P.pingTop} />
        <rect x="80" y="422.5" width="100" height="7.5" fill={P.pingDark} />
        <rect x="127.5" y="380" width="5" height="50" fill={P.pingLine} />
        <Plant x={40} y={370} />
      </g>

      {/* blog — standing beside its chair, needs input */}
      <g transform="translate(745,195)">
        <circle
          className="roster-ring"
          cx="0"
          cy="-21"
          r="26"
          fill="none"
          stroke={STATUS.waiting}
          strokeWidth="2"
        />
        <Body look={BLOG_LOOK} pose="stand" />
        <g transform="translate(0,-58)">
          <Pill name="blog" color={STATUS.waiting} />
        </g>
      </g>

      {/* circle — walker #2, takes its turn after dockkeep */}
      <g ref={cRef} transform="translate(250,190)">
        <circle ref={cGlowRef} cy="-21" r="30" fill={STATUS.finished} opacity="0" />
        <Variants look={CIRCLE_LOOK} initial="seated" variants={[...WALKER_VARIANTS]} />
        <g transform="translate(0,-58)">
          <Pill name="circle" color={STATUS.working} dotRef={cDotRef} />
        </g>
      </g>

      {/* you — at your desk; the visitor's W-A-S-D takes you for a walk */}
      <g ref={youRef} transform="translate(480,465)">
        <Variants look={YOU_LOOK} initial="seated" variants={[...YOU_VARIANTS]} />
        <g transform="translate(0,-58)">
          <Pill name="You" color="#8a8f98" />
        </g>
      </g>

      {/* dockkeep — walker #1 */}
      <g ref={dkRef} transform="translate(480,190)">
        <circle ref={dkGlowRef} cy="-21" r="30" fill={STATUS.finished} opacity="0" />
        <Variants look={WALKER_LOOK} initial="seated" variants={[...WALKER_VARIANTS]} />
        <g transform="translate(0,-58)">
          <Pill name="dockkeep" color={STATUS.working} dotRef={dkDotRef} />
        </g>
      </g>
    </svg>
  )
}
