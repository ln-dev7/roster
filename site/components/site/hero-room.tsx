"use client"

import { useEffect, useRef } from "react"

/**
 * The product moment, rendered live: a blueprint room where the dockkeep
 * agent loops through the full choreography — works, stands up, crosses
 * along a self-drawing dashed path, waits at your desk with a halo, then
 * walks back and sits down.
 *
 * This mirrors the macOS app's actual design (same geometry, same timings)
 * so the site never oversells. Colors come from the --bp-* CSS variables,
 * which follow the theme: ink on paper in light, night blueprint in dark.
 */

const PHASES: Array<[name: string, duration: number]> = [
  ["work", 2600],
  ["stand", 450],
  ["walk", 2900],
  ["desk", 2600],
  ["back", 2900],
  ["sit", 450],
]
const TOTAL = PHASES.reduce((sum, [, duration]) => sum + duration, 0)

// Walker waypoints in the 960×540 design space.
const SEAT = { x: 400, y: 152 }
const STAND = { x: 434, y: 152 }
const DESK = { x: 480, y: 384 }

const easeInOutCubic = (t: number) =>
  t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
const lerp = (a: number, b: number, t: number) => a + (b - a) * t

function phaseAt(ms: number): [string, number] {
  let t = ms % TOTAL
  for (const [name, duration] of PHASES) {
    if (t < duration) return [name, t / duration]
    t -= duration
  }
  return ["work", 0]
}

export function HeroRoom() {
  const walkerRef = useRef<SVGGElement>(null)
  const glowRef = useRef<SVGCircleElement>(null)
  const pathRef = useRef<SVGLineElement>(null)

  useEffect(() => {
    // Frozen room for users who prefer reduced motion.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    let raf = 0
    const frame = (now: number) => {
      const [name, t] = phaseAt(now)
      const e = easeInOutCubic(t)

      let x = SEAT.x
      let y = SEAT.y
      let glow = 0
      if (name === "stand") {
        x = lerp(SEAT.x, STAND.x, e)
      } else if (name === "walk") {
        x = lerp(STAND.x, DESK.x, e)
        y = lerp(STAND.y, DESK.y, e)
      } else if (name === "desk") {
        x = DESK.x
        y = DESK.y
        glow = 0.9
      } else if (name === "back") {
        x = lerp(DESK.x, STAND.x, e)
        y = lerp(DESK.y, STAND.y, e)
      } else if (name === "sit") {
        x = lerp(STAND.x, SEAT.x, e)
      }

      walkerRef.current?.setAttribute("transform", `translate(${x},${y})`)
      glowRef.current?.setAttribute("opacity", String(glow))
      pathRef.current?.classList.toggle(
        "show",
        name === "stand" || name === "walk" || name === "back"
      )
      raf = requestAnimationFrame(frame)
    }
    raf = requestAnimationFrame(frame)
    return () => cancelAnimationFrame(raf)
  }, [])

  return (
    <svg
      viewBox="0 0 960 540"
      role="img"
      aria-label="Blueprint office where an agent walks from its desk to yours"
      className="block h-auto w-full"
      style={{ background: "var(--bp-paper)" }}
    >
      <defs>
        <pattern
          id="roster-grid"
          width="24"
          height="24"
          patternUnits="userSpaceOnUse"
        >
          <path
            d="M24 0H0V24"
            fill="none"
            stroke="var(--bp-ink-faint)"
            strokeWidth="1"
          />
        </pattern>
      </defs>

      <rect x="20" y="20" width="920" height="470" fill="url(#roster-grid)" />

      {/* Walls with a door gap at the bottom left, architect style. */}
      <path
        d="M 20 490 L 20 20 L 940 20 L 940 490 L 210 490 M 140 490 L 20 490"
        fill="none"
        stroke="var(--bp-ink)"
        strokeWidth="1.6"
      />
      <path
        d="M 210 490 A 70 70 0 0 0 140 420"
        fill="none"
        stroke="var(--bp-ink-soft)"
        strokeWidth="1"
        strokeDasharray="3 4"
      />
      <line
        x1="140"
        y1="490"
        x2="140"
        y2="420"
        stroke="var(--bp-ink)"
        strokeWidth="1.2"
      />

      {/* Dimension line, pure blueprint flavour. */}
      <g stroke="var(--bp-ink-soft)" strokeWidth="1">
        <line x1="20" y1="508" x2="940" y2="508" />
        <line x1="20" y1="503" x2="20" y2="513" />
        <line x1="940" y1="503" x2="940" y2="513" />
      </g>

      {/* Workstations: desk, monitor, chair. */}
      <g fill="none" stroke="var(--bp-ink)" strokeWidth="1.4">
        {/* circle — working: seated dot, breathing screen */}
        <g>
          <rect x="128" y="92" width="84" height="34" />
          <rect
            x="152"
            y="99"
            width="36"
            height="6"
            className="roster-screen"
            fill="var(--bp-ink)"
            stroke="none"
          />
          <circle cx="170" cy="152" r="10" stroke="var(--bp-ink-soft)" />
        </g>
        {/* dockkeep — the walker's station */}
        <g>
          <rect x="358" y="92" width="84" height="34" />
          <rect
            x="382"
            y="99"
            width="36"
            height="6"
            className="roster-screen"
            fill="var(--bp-ink)"
            stroke="none"
          />
          <circle cx="400" cy="152" r="10" stroke="var(--bp-ink-soft)" />
        </g>
        {/* blog — standing, waiting for input */}
        <g>
          <rect x="588" y="92" width="84" height="34" />
          <rect
            x="612"
            y="99"
            width="36"
            height="6"
            fill="var(--bp-ink)"
            stroke="none"
            opacity="0.85"
          />
          <circle cx="630" cy="152" r="10" stroke="var(--bp-ink-soft)" />
        </g>
        {/* api — empty station */}
        <g stroke="var(--bp-ink-soft)">
          <rect x="818" y="92" width="84" height="34" />
          <circle cx="860" cy="152" r="10" />
        </g>
      </g>

      <g
        fontFamily="var(--font-mono), ui-monospace, Menlo, monospace"
        fontSize="10"
        fill="var(--bp-ink-soft)"
        textAnchor="middle"
        letterSpacing="2.5"
      >
        <text x="170" y="198">
          CIRCLE
        </text>
        <text x="400" y="198">
          DOCKKEEP
        </text>
        <text x="630" y="198">
          BLOG
        </text>
        <text x="860" y="198">
          API
        </text>
      </g>

      {/* Your desk. */}
      <g>
        <rect
          x="400"
          y="400"
          width="160"
          height="44"
          fill="none"
          stroke="var(--bp-ink)"
          strokeWidth="1.6"
        />
        <rect
          x="406"
          y="406"
          width="148"
          height="32"
          fill="none"
          stroke="var(--bp-ink-faint)"
          strokeWidth="1"
        />
        <circle
          cx="480"
          cy="468"
          r="11"
          fill="none"
          stroke="var(--bp-ink-soft)"
          strokeWidth="1.4"
        />
        <text
          x="480"
          y="426"
          fontFamily="var(--font-mono), ui-monospace, Menlo, monospace"
          fontSize="10"
          fill="var(--bp-ink-soft)"
          textAnchor="middle"
          letterSpacing="3"
        >
          YOU
        </text>
      </g>

      {/* The walk path, revealed during the crossing. */}
      <line
        ref={pathRef}
        className="roster-walkpath"
        x1="434"
        y1="152"
        x2="480"
        y2="384"
        stroke="var(--bp-ink-soft)"
        strokeWidth="1.2"
        strokeDasharray="4 5"
      />

      {/* Static agents: working (filled) and waiting (hollow + ring). */}
      <circle cx="170" cy="152" r="7" fill="var(--bp-ink)" />
      <g>
        <circle
          className="roster-ring"
          cx="664"
          cy="152"
          r="10"
          fill="none"
          stroke="var(--bp-ink)"
          strokeWidth="1.4"
        />
        <circle
          cx="664"
          cy="152"
          r="7"
          fill="none"
          stroke="var(--bp-ink)"
          strokeWidth="1.8"
        />
      </g>

      {/* The walker, driven frame by frame. */}
      <g ref={walkerRef} transform="translate(400,152)">
        <circle ref={glowRef} r="13" fill="var(--bp-glow)" opacity="0" />
        <circle r="7" fill="var(--bp-ink)" />
      </g>
    </svg>
  )
}
