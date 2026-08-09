"use client"

import { useLocale } from "next-intl"

import { Link, usePathname } from "@/i18n/navigation"
import { cn } from "@/lib/utils"

/**
 * EN / FR switcher. With only two locales, two explicit links beat a
 * dropdown — one click, both options always visible.
 */
export function LocaleSwitcher() {
  const locale = useLocale()
  const pathname = usePathname()

  return (
    <div className="flex items-center gap-0.5 font-mono text-xs">
      {(["en", "fr"] as const).map((candidate) => (
        <Link
          key={candidate}
          href={pathname}
          locale={candidate}
          aria-current={locale === candidate ? "true" : undefined}
          className={cn(
            "rounded-md px-1.5 py-1 uppercase transition-colors",
            locale === candidate
              ? "text-foreground"
              : "text-muted-foreground/60 hover:text-foreground"
          )}
        >
          {candidate}
        </Link>
      ))}
    </div>
  )
}
