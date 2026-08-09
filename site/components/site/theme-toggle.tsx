"use client"

import * as React from "react"
import { Moon02Icon, Sun01Icon } from "@hugeicons/core-free-icons"
import { HugeiconsIcon } from "@hugeicons/react"
import { useTheme } from "next-themes"

import { Button } from "@/components/ui/button"

/**
 * Light / dark toggle. The icon renders only on the client because the
 * resolved theme is unknown on the server — rendering the wrong icon first
 * would cause a hydration mismatch. `useSyncExternalStore` with different
 * server/client snapshots is the effect-free way to know we've hydrated.
 */
const emptySubscribe = () => () => {}

export function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme()
  const mounted = React.useSyncExternalStore(
    emptySubscribe,
    () => true,
    () => false
  )

  return (
    <Button
      variant="ghost"
      size="icon-sm"
      aria-label="Toggle theme"
      onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
    >
      {mounted ? (
        <HugeiconsIcon
          icon={resolvedTheme === "dark" ? Sun01Icon : Moon02Icon}
        />
      ) : (
        <HugeiconsIcon icon={Moon02Icon} className="opacity-0" />
      )}
    </Button>
  )
}
