"use client"

import { useEffect, useRef } from "react"

/**
 * The product moment, rendered live: the pixel office from the macOS app,
 * with the app's ACTUAL movement rules —
 *
 *   • people walk at constant speed (easing curves are for furniture);
 *   • they face where they're going: front coming toward you, BACK when
 *     they leave, profile when they cross the room sideways;
 *   • legs actually walk (two frames, like the app's swing);
 *   • seated means seated — compact, on the chair.
 *
 * Two loops run at once: dockkeep does the finished-work crossing to your
 * desk and back, and YOUR avatar wanders to the ping-pong table and
 * returns — the arrow-keys feature, demoed. Same geometry (×2.5), same
 * palette, same timings as the app, so the site never oversells.
 */

// ── Timelines ────────────────────────────────────────────────────────────

const WALKER_PHASES: Array<[name: string, duration: number]> = [
  ["work", 2600],
  ["stand", 450],
  ["walk", 2900],
  ["desk", 2600],
  ["back", 2900],
  ["sit", 450],
]

const YOU_PHASES: Array<[name: string, duration: number]> = [
  ["sit", 4200],
  ["out", 2600],
  ["pause", 2000],
  ["home", 2600],
  ["settle", 500],
]

const sum = (phases: Array<[string, number]>) =>
  phases.reduce((total, [, duration]) => total + duration, 0)
const WALKER_TOTAL = sum(WALKER_PHASES)
const YOU_TOTAL = sum(YOU_PHASES)

// Waypoints in the 960×550 design space (app logical coords × 2.5).
const SEAT = { x: 480, y: 190 }
const STAND = { x: 515, y: 195 }
const DESK = { x: 480, y: 390 }
const YOU_SEAT = { x: 480, y: 465 }
const PONG = { x: 152, y: 452 }

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

function phaseAt(
  ms: number,
  phases: Array<[string, number]>,
  total: number
): [string, number] {
  let t = ms % total
  for (const [name, duration] of phases) {
    if (t < duration) return [name, t / duration]
    t -= duration
  }
  return [phases[0][0], 0]
}

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

// ── The room ─────────────────────────────────────────────────────────────

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

export function HeroRoom() {
  const walkerRef = useRef<SVGGElement>(null)
  const youRef = useRef<SVGGElement>(null)
  const dotRef = useRef<SVGCircleElement>(null)
  const glowRef = useRef<SVGCircleElement>(null)

  useEffect(() => {
    // Frozen room for users who prefer reduced motion.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const setVariant = (root: SVGGElement | null, name: string) => {
      root?.querySelectorAll<SVGGElement>("[data-v]").forEach((g) => {
        g.style.display = g.dataset.v === name ? "" : "none"
      })
    }

    let raf = 0
    const frame = (now: number) => {
      const gait = (Math.floor(now / 140) % 2) as 0 | 1

      // ── dockkeep: the finished-work crossing ──
      {
        const [name, t] = phaseAt(now, WALKER_PHASES, WALKER_TOTAL)
        let x = SEAT.x
        let y = SEAT.y
        let glow = 0
        let dot = STATUS.working
        let variant = "seated"
        if (name === "stand") {
          x = lerp(SEAT.x, STAND.x, easeInOut(t))
          y = lerp(SEAT.y, STAND.y, easeInOut(t))
          variant = "stand"
          dot = STATUS.finished
        } else if (name === "walk") {
          // Constant speed, like the app: people walk, they don't glide.
          x = lerp(STAND.x, DESK.x, t)
          y = lerp(STAND.y, DESK.y, t)
          variant = `wf${gait}`
          dot = STATUS.finished
        } else if (name === "desk") {
          x = DESK.x
          y = DESK.y
          glow = 0.22
          variant = "stand"
          dot = STATUS.finished
        } else if (name === "back") {
          // Walking away — you see the back of the head, like in the app.
          x = lerp(DESK.x, STAND.x, t)
          y = lerp(DESK.y, STAND.y, t)
          variant = `wb${gait}`
        } else if (name === "sit") {
          x = lerp(STAND.x, SEAT.x, easeInOut(t))
          y = lerp(STAND.y, SEAT.y, easeInOut(t))
          variant = "stand"
        }
        walkerRef.current?.setAttribute("transform", `translate(${x},${y})`)
        setVariant(walkerRef.current, variant)
        dotRef.current?.setAttribute("fill", dot)
        glowRef.current?.setAttribute("opacity", String(glow))
      }

      // ── you: a stroll to the ping-pong table (the arrow keys, demoed) ──
      {
        const [name, t] = phaseAt(now, YOU_PHASES, YOU_TOTAL)
        let x = YOU_SEAT.x
        let y = YOU_SEAT.y
        let variant = "seated"
        if (name === "out") {
          x = lerp(YOU_SEAT.x, PONG.x, t)
          y = lerp(YOU_SEAT.y, PONG.y, t)
          variant = `yl${gait}`
        } else if (name === "pause") {
          x = PONG.x
          y = PONG.y
          variant = "stand"
        } else if (name === "home") {
          x = lerp(PONG.x, YOU_SEAT.x, t)
          y = lerp(PONG.y, YOU_SEAT.y, t)
          variant = `yr${gait}`
        } else if (name === "settle") {
          x = YOU_SEAT.x
          y = YOU_SEAT.y
          variant = "stand"
        }
        youRef.current?.setAttribute("transform", `translate(${x},${y})`)
        setVariant(youRef.current, variant)
      }

      raf = requestAnimationFrame(frame)
    }
    raf = requestAnimationFrame(frame)
    return () => cancelAnimationFrame(raf)
  }, [])

  return (
    <svg
      viewBox="0 0 960 550"
      role="img"
      aria-label="Pixel office where an agent walks from its desk to yours while your avatar strolls to the ping-pong table"
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

      {/* ── The cast ── */}

      {/* circle — seated, working */}
      <g transform="translate(250,190)">
        <Body look={CIRCLE_LOOK} pose="seated" />
        <g transform="translate(0,-58)">
          <Pill name="circle" color={STATUS.working} />
        </g>
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

      {/* you — seated at your desk, until you go stretch your legs */}
      <g ref={youRef} transform="translate(480,465)">
        <Variants
          look={YOU_LOOK}
          initial="seated"
          variants={[
            { name: "seated", pose: "seated" },
            { name: "stand", pose: "stand" },
            { name: "yl0", pose: "walk", facing: "left", frame: 0 },
            { name: "yl1", pose: "walk", facing: "left", frame: 1 },
            { name: "yr0", pose: "walk", facing: "right", frame: 0 },
            { name: "yr1", pose: "walk", facing: "right", frame: 1 },
          ]}
        />
        <g transform="translate(0,-58)">
          <Pill name="You" color="#8a8f98" />
        </g>
      </g>

      {/* dockkeep — the walker, driven frame by frame */}
      <g ref={walkerRef} transform="translate(480,190)">
        <circle ref={glowRef} cy="-21" r="30" fill={STATUS.finished} opacity="0" />
        <Variants
          look={WALKER_LOOK}
          initial="seated"
          variants={[
            { name: "seated", pose: "seated" },
            { name: "stand", pose: "stand" },
            { name: "wf0", pose: "walk", facing: "front", frame: 0 },
            { name: "wf1", pose: "walk", facing: "front", frame: 1 },
            { name: "wb0", pose: "walk", facing: "back", frame: 0 },
            { name: "wb1", pose: "walk", facing: "back", frame: 1 },
          ]}
        />
        <g transform="translate(0,-58)">
          <Pill name="dockkeep" color={STATUS.working} dotRef={dotRef} />
        </g>
      </g>
    </svg>
  )
}
