import { getTranslations } from "next-intl/server"

import { RosterMark } from "@/components/site/roster-mark"
import { Separator } from "@/components/ui/separator"
import {
  AUTHOR_URL,
  DOCKKEEP_URL,
  GITHUB_URL,
  GOOD_FIRST_ISSUES_URL,
  ISSUES_URL,
  LICENSE_URL,
  RELEASES_URL,
} from "@/lib/links"

export async function SiteFooter() {
  const t = await getTranslations("footer")
  const year = new Date().getFullYear()

  const columns = [
    {
      title: t("product"),
      links: [
        { label: t("download"), href: RELEASES_URL },
        { label: t("releases"), href: `${GITHUB_URL}/releases` },
        { label: t("roadmap"), href: ISSUES_URL },
      ],
    },
    {
      title: t("project"),
      links: [
        { label: t("github"), href: GITHUB_URL },
        { label: t("license"), href: LICENSE_URL },
        { label: t("issues"), href: GOOD_FIRST_ISSUES_URL },
      ],
    },
    {
      title: t("author"),
      links: [
        { label: t("site"), href: AUTHOR_URL },
        { label: t("dockkeep"), href: DOCKKEEP_URL },
      ],
    },
  ]

  return (
    <footer className="border-t">
      <div className="mx-auto w-full max-w-6xl px-6 py-16">
        <div className="flex flex-col justify-between gap-12 md:flex-row">
          <div className="max-w-xs space-y-3">
            <div className="flex items-center gap-2.5">
              <RosterMark className="size-[18px] text-foreground" />
              <span className="font-mono text-sm font-medium tracking-[0.25em]">
                ROSTER
              </span>
            </div>
            <p className="text-sm text-muted-foreground">{t("tagline")}</p>
          </div>

          <div className="grid grid-cols-2 gap-10 sm:grid-cols-3">
            {columns.map((column) => (
              <div key={column.title} className="space-y-3">
                <h3 className="font-mono text-xs tracking-widest text-muted-foreground/70 uppercase">
                  {column.title}
                </h3>
                <ul className="space-y-2 text-sm">
                  {column.links.map((link) => (
                    <li key={link.href}>
                      <a
                        href={link.href}
                        target="_blank"
                        rel="noreferrer"
                        className="text-muted-foreground transition-colors hover:text-foreground"
                      >
                        {link.label}
                      </a>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>

        <Separator className="my-8" />

        <p className="text-xs text-muted-foreground/70">
          {t("copyright", { year })}
        </p>
      </div>
    </footer>
  )
}
