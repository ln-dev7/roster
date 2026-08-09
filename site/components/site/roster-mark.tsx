/**
 * The Roster glyph: a tiny room seen from above — four walls, one agent.
 * Drawn inline so it inherits currentColor; the dot takes the accent.
 */
export function RosterMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 18 18" fill="none" className={className} aria-hidden>
      <rect
        x="1.5"
        y="1.5"
        width="15"
        height="15"
        stroke="currentColor"
        strokeWidth="1.5"
      />
      <circle cx="11.5" cy="11.5" r="2.5" fill="var(--primary)" />
    </svg>
  )
}
