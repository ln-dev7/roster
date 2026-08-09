"use client"

import { motion, useReducedMotion } from "motion/react"
import type { ReactNode } from "react"

/**
 * The site's micro-animation vocabulary, built on motion.dev. Three moves
 * only — enter, float, lift — used everywhere so the page feels playful
 * without ever feeling busy. All of them respect reduced-motion.
 */

const ENTER_EASE = [0.21, 0.47, 0.32, 0.98] as const

/** Fades content up as it scrolls into view. */
export function FadeIn({
  children,
  delay = 0,
  className,
}: {
  children: ReactNode
  delay?: number
  className?: string
}) {
  const reduce = useReducedMotion()
  if (reduce) return <div className={className}>{children}</div>
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={{ duration: 0.6, delay, ease: ENTER_EASE }}
    >
      {children}
    </motion.div>
  )
}

/** A gentle endless bob — the floating name pills around the hero. */
export function Float({
  children,
  delay = 0,
  className,
}: {
  children: ReactNode
  delay?: number
  className?: string
}) {
  const reduce = useReducedMotion()
  if (reduce) return <div className={className}>{children}</div>
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, scale: 0.8 }}
      whileInView={{ opacity: 1, scale: 1 }}
      viewport={{ once: true }}
      transition={{ duration: 0.5, delay, ease: ENTER_EASE }}
    >
      <motion.div
        animate={{ y: [0, -7, 0] }}
        transition={{
          duration: 4.2,
          delay,
          repeat: Infinity,
          ease: "easeInOut",
        }}
      >
        {children}
      </motion.div>
    </motion.div>
  )
}

/** Cards rise slightly under the cursor — Gather-style tactility. */
export function Lift({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <motion.div
      className={className}
      whileHover={{ y: -5 }}
      transition={{ type: "spring", stiffness: 320, damping: 22 }}
    >
      {children}
    </motion.div>
  )
}
