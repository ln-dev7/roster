import { Download01Icon, GithubIcon } from "@hugeicons/core-free-icons"
import { HugeiconsIcon } from "@hugeicons/react"
import { getTranslations, setRequestLocale } from "next-intl/server"

import { HeroRoom } from "@/components/site/hero-room"
import { SiteFooter } from "@/components/site/site-footer"
import { SiteHeader } from "@/components/site/site-header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import { GITHUB_URL, GOOD_FIRST_ISSUES_URL, RELEASES_URL } from "@/lib/links"

export default async function HomePage({
  params,
}: {
  params: Promise<{ locale: string }>
}) {
  const { locale } = await params
  setRequestLocale(locale)
  const t = await getTranslations()

  return (
    <div id="top" className="min-h-svh">
      <SiteHeader />

      <main>
        {/* ── Hero ─────────────────────────────────────────────────── */}
        <section className="mx-auto w-full max-w-6xl px-6 pt-20 pb-16 sm:pt-28">
          <div className="mx-auto flex max-w-3xl flex-col items-center text-center">
            <Badge variant="outline" className="mb-6 font-mono">
              {t("hero.badge")}
            </Badge>
            <h1 className="text-4xl font-semibold tracking-tighter text-balance sm:text-6xl">
              {t("hero.title")}
            </h1>
            <p className="mt-5 max-w-2xl text-lg text-pretty text-muted-foreground">
              {t("hero.subtitle")}
            </p>
            <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
              <Button size="lg" render={<a href={RELEASES_URL} />}>
                <HugeiconsIcon icon={Download01Icon} data-icon="inline-start" />
                {t("hero.download")}
              </Button>
              <Button
                size="lg"
                variant="outline"
                render={
                  <a href={GITHUB_URL} target="_blank" rel="noreferrer" />
                }
              >
                <HugeiconsIcon icon={GithubIcon} data-icon="inline-start" />
                {t("hero.github")}
              </Button>
            </div>
            <p className="mt-4 font-mono text-xs text-muted-foreground/70">
              {t("hero.note")}
            </p>
          </div>

          {/* The room, live. */}
          <figure className="mt-14">
            <div className="overflow-hidden rounded-2xl ring-1 ring-foreground/10">
              <HeroRoom />
            </div>
            <figcaption className="mt-3 text-center font-mono text-xs text-muted-foreground/70">
              {t("hero.caption")}
            </figcaption>
          </figure>
        </section>

        {/* ── Positioning ──────────────────────────────────────────── */}
        <section className="border-y bg-card/50">
          <div className="mx-auto w-full max-w-6xl px-6 py-20">
            <div className="mx-auto max-w-2xl text-center">
              <h2 className="text-3xl font-semibold tracking-tight">
                {t("positioning.title")}
              </h2>
              <p className="mt-4 text-muted-foreground">
                {t("positioning.body")}
              </p>
            </div>
          </div>
        </section>

        {/* ── Features ─────────────────────────────────────────────── */}
        <section id="features" className="scroll-mt-14">
          <div className="mx-auto w-full max-w-6xl px-6 py-24">
            <p className="font-mono text-xs tracking-widest text-primary uppercase">
              {t("features.eyebrow")}
            </p>
            <h2 className="mt-3 max-w-xl text-3xl font-semibold tracking-tight">
              {t("features.title")}
            </h2>

            <div className="mt-10 grid gap-4 sm:grid-cols-2">
              {(["f1", "f2", "f3", "f4"] as const).map((key) => (
                <Card key={key} className="bg-card">
                  <CardHeader>
                    <CardTitle>{t(`features.${key}.title`)}</CardTitle>
                    <CardDescription className="text-sm/6">
                      {t(`features.${key}.body`)}
                    </CardDescription>
                  </CardHeader>
                </Card>
              ))}
            </div>
          </div>
        </section>

        {/* ── How it works ─────────────────────────────────────────── */}
        <section id="how" className="scroll-mt-14 border-y bg-card/50">
          <div className="mx-auto w-full max-w-6xl px-6 py-24">
            <p className="font-mono text-xs tracking-widest text-primary uppercase">
              {t("how.eyebrow")}
            </p>
            <h2 className="mt-3 max-w-xl text-3xl font-semibold tracking-tight">
              {t("how.title")}
            </h2>

            <ol className="mt-10 grid gap-4 md:grid-cols-3">
              {(["s1", "s2", "s3"] as const).map((key, index) => (
                <li key={key} className="rounded-2xl border bg-background p-6">
                  <span className="font-mono text-xs text-muted-foreground/70">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <h3 className="mt-2 font-medium">{t(`how.${key}.title`)}</h3>
                  <p className="mt-2 text-sm/6 text-muted-foreground">
                    {t(`how.${key}.body`)}
                  </p>
                </li>
              ))}
            </ol>

            <p className="mt-8 rounded-2xl border border-primary/25 bg-primary/5 p-5 text-sm/6">
              {t("how.privacy")}
            </p>
          </div>
        </section>

        {/* ── Open source ──────────────────────────────────────────── */}
        <section className="mx-auto w-full max-w-6xl px-6 py-24">
          <div className="flex flex-col items-start justify-between gap-8 md:flex-row md:items-center">
            <div className="max-w-xl">
              <p className="font-mono text-xs tracking-widest text-primary uppercase">
                {t("open.eyebrow")}
              </p>
              <h2 className="mt-3 text-3xl font-semibold tracking-tight">
                {t("open.title")}
              </h2>
              <p className="mt-4 text-muted-foreground">{t("open.body")}</p>
            </div>
            <div className="flex flex-col gap-3">
              <Button
                variant="outline"
                render={
                  <a href={GITHUB_URL} target="_blank" rel="noreferrer" />
                }
              >
                <HugeiconsIcon icon={GithubIcon} data-icon="inline-start" />
                {t("open.star")}
              </Button>
              <Button
                variant="ghost"
                render={
                  <a
                    href={GOOD_FIRST_ISSUES_URL}
                    target="_blank"
                    rel="noreferrer"
                  />
                }
              >
                {t("open.issues")}
              </Button>
            </div>
          </div>
        </section>

        {/* ── FAQ ──────────────────────────────────────────────────── */}
        <section id="faq" className="scroll-mt-14 border-t">
          <div className="mx-auto w-full max-w-6xl px-6 py-24">
            <h2 className="text-3xl font-semibold tracking-tight">
              {t("faq.title")}
            </h2>
            <dl className="mt-10 grid gap-x-12 gap-y-10 md:grid-cols-2">
              {(["q1", "q2", "q3", "q4"] as const).map((key) => (
                <div key={key}>
                  <dt className="font-medium">{t(`faq.${key}.q`)}</dt>
                  <dd className="mt-2 text-sm/6 text-muted-foreground">
                    {t(`faq.${key}.a`)}
                  </dd>
                </div>
              ))}
            </dl>
          </div>
        </section>

        {/* ── Closing CTA ──────────────────────────────────────────── */}
        <section className="mx-auto w-full max-w-6xl px-6 pb-24">
          <div className="rounded-3xl border bg-card px-8 py-16 text-center">
            <h2 className="text-3xl font-semibold tracking-tight text-balance">
              {t("cta.title")}
            </h2>
            <p className="mt-3 text-muted-foreground">{t("cta.body")}</p>
            <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
              <Button size="lg" render={<a href={RELEASES_URL} />}>
                <HugeiconsIcon icon={Download01Icon} data-icon="inline-start" />
                {t("cta.download")}
              </Button>
              <Button
                size="lg"
                variant="outline"
                render={
                  <a href={GITHUB_URL} target="_blank" rel="noreferrer" />
                }
              >
                {t("cta.github")}
              </Button>
            </div>
          </div>
        </section>
      </main>

      <SiteFooter />
    </div>
  )
}
