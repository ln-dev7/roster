import { GithubIcon } from "@hugeicons/core-free-icons"
import { HugeiconsIcon } from "@hugeicons/react"
import { getTranslations } from "next-intl/server"

import { LocaleSwitcher } from "@/components/site/locale-switcher"
import { RosterMark } from "@/components/site/roster-mark"
import { ThemeToggle } from "@/components/site/theme-toggle"
import { Button } from "@/components/ui/button"
import { GITHUB_URL, RELEASES_URL } from "@/lib/links"

export async function SiteHeader() {
  const t = await getTranslations("nav")

  return (
    // Gather-style floating pill: the nav hovers over the page instead of
    // ruling a line across it.
    <header className="sticky top-4 z-50 px-4">
      <div className="mx-auto flex h-14 w-full max-w-5xl items-center justify-between gap-4 rounded-full border bg-background/85 px-5 shadow-lg shadow-foreground/5 backdrop-blur-md">
        <a href="#top" className="flex items-center gap-2.5">
          <RosterMark className="size-[18px] text-foreground" />
          <span className="font-mono text-sm font-medium tracking-[0.25em]">
            ROSTER
          </span>
        </a>

        <nav className="hidden items-center gap-6 text-sm text-muted-foreground md:flex">
          <a
            href="#features"
            className="transition-colors hover:text-foreground"
          >
            {t("features")}
          </a>
          <a href="#how" className="transition-colors hover:text-foreground">
            {t("how")}
          </a>
          <a href="#faq" className="transition-colors hover:text-foreground">
            {t("faq")}
          </a>
        </nav>

        <div className="flex items-center gap-1.5">
          <LocaleSwitcher />
          <ThemeToggle />
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={t("github")}
            render={
              // Base UI button: `render` swaps the root element for our
              // anchor while keeping the button styling and behavior.
              <a href={GITHUB_URL} target="_blank" rel="noreferrer" />
            }
          >
            <HugeiconsIcon icon={GithubIcon} />
          </Button>
          <Button
            size="sm"
            className="ml-1 hidden rounded-full sm:inline-flex"
            render={<a href={RELEASES_URL} />}
          >
            {t("download")}
          </Button>
        </div>
      </div>
    </header>
  )
}
