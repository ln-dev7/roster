import { Download01Icon, GithubIcon } from "@hugeicons/core-free-icons"
import { HugeiconsIcon } from "@hugeicons/react"
import { getTranslations, setRequestLocale } from "next-intl/server"

import { FadeIn, Lift } from "@/components/site/animate"
import { HeroRoom } from "@/components/site/hero-room"
import { SiteFooter } from "@/components/site/site-footer"
import { SiteHeader } from "@/components/site/site-header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { DOWNLOAD_URL, GITHUB_URL, GOOD_FIRST_ISSUES_URL } from "@/lib/links"

/** The app's status colors — the same vocabulary as the room. */
const STATUS = {
  working: "#34c759",
  waiting: "#ff9500",
  finished: "#af52de",
  failed: "#ff3b30",
  you: "#8a8f98",
}

export default async function HomePage({
  params,
}: {
  params: Promise<{ locale: string }>
}) {
  const { locale } = await params
  setRequestLocale(locale)
  const t = await getTranslations()

  const tickerItems = (["t1", "t2", "t3", "t4", "t5", "t6"] as const).map(
    (key) => t(`ticker.${key}`)
  )
  const tickerDots = [
    STATUS.finished,
    STATUS.working,
    STATUS.waiting,
    STATUS.failed,
    STATUS.you,
    STATUS.working,
  ]

  const featureWashes = {
    f1: "var(--wash-rug)",
    f2: "var(--wash-carpet)",
    f3: "var(--wash-sofa)",
    f4: "var(--wash-plant)",
  } as const
  const featureDots = {
    f1: STATUS.finished,
    f2: STATUS.working,
    f3: STATUS.waiting,
    f4: STATUS.you,
  } as const

  return (
    <div id="top" className="min-h-svh">
      <SiteHeader />

      <main>
        {/* ── Hero ─────────────────────────────────────────────────── */}
        <section className="mx-auto w-full max-w-6xl px-6 pt-16 pb-10 sm:pt-24">
          <FadeIn className="mx-auto flex max-w-3xl flex-col items-center text-center">
            <Badge
              variant="outline"
              className="mb-6 rounded-full bg-card px-3 py-1 font-mono"
            >
              {t("hero.badge")}
            </Badge>
            <h1 className="text-4xl font-bold tracking-tight text-balance sm:text-6xl">
              {t.rich("hero.title", {
                mark: (chunks) => (
                  <span className="rounded-2xl bg-primary/15 px-2 text-primary [box-decoration-break:clone]">
                    {chunks}
                  </span>
                ),
              })}
            </h1>
            <p className="mt-6 max-w-2xl text-lg text-pretty text-muted-foreground">
              {t("hero.subtitle")}
            </p>
            <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
              <Button
                size="lg"
                className="rounded-full px-7"
                render={<a href={DOWNLOAD_URL} />}
              >
                <HugeiconsIcon icon={Download01Icon} data-icon="inline-start" />
                {t("hero.download")}
              </Button>
              <Button
                size="lg"
                variant="outline"
                className="rounded-full bg-card px-7"
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
          </FadeIn>

          {/* The room, live, in its own little macOS window. */}
          <FadeIn delay={0.15}>
            <figure className="relative mt-16">
              <div className="overflow-hidden rounded-3xl border bg-card shadow-2xl shadow-foreground/10">
                <div className="flex items-center gap-1.5 border-b px-4 py-3">
                  <span className="size-3 rounded-full bg-[#ff5f57]" />
                  <span className="size-3 rounded-full bg-[#febc2e]" />
                  <span className="size-3 rounded-full bg-[#28c840]" />
                  <span className="ml-3 font-mono text-xs font-medium tracking-[0.25em] text-muted-foreground">
                    ROSTER
                  </span>
                </div>
                <HeroRoom />
              </div>

              <figcaption className="mt-4 text-center font-mono text-xs text-muted-foreground/70">
                {t("hero.caption")}
                <span className="mt-1.5 block text-primary/80">
                  {t("hero.hint")}
                </span>
              </figcaption>
            </figure>
          </FadeIn>
        </section>

        {/* ── Status ticker ────────────────────────────────────────── */}
        <div className="overflow-hidden border-y bg-card/60 py-3 [mask-image:linear-gradient(to_right,transparent,black_8%,black_92%,transparent)]">
          <div className="roster-marquee flex w-max items-center gap-10">
            {[...tickerItems, ...tickerItems].map((item, index) => (
              <span
                key={index}
                className="flex items-center gap-2 font-mono text-xs whitespace-nowrap text-muted-foreground"
              >
                <span
                  className="size-1.5 shrink-0 rounded-full"
                  style={{ background: tickerDots[index % tickerDots.length] }}
                />
                {item}
              </span>
            ))}
          </div>
        </div>

        {/* ── Positioning ──────────────────────────────────────────── */}
        <section className="mx-auto w-full max-w-6xl px-6 py-24">
          <FadeIn className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              {t("positioning.title")}
            </h2>
            <p className="mt-5 text-lg text-muted-foreground">
              {t("positioning.body")}
            </p>
          </FadeIn>
        </section>

        {/* ── Features ─────────────────────────────────────────────── */}
        <section id="features" className="scroll-mt-24">
          <div className="mx-auto w-full max-w-6xl px-6 pb-24">
            <FadeIn>
              <p className="text-center font-mono text-xs tracking-widest text-primary uppercase">
                {t("features.eyebrow")}
              </p>
              <h2 className="mx-auto mt-3 max-w-xl text-center text-3xl font-bold tracking-tight sm:text-4xl">
                {t("features.title")}
              </h2>
            </FadeIn>

            <div className="mt-12 grid gap-5 sm:grid-cols-2">
              {(["f1", "f2", "f3", "f4"] as const).map((key, index) => (
                <FadeIn key={key} delay={index * 0.08}>
                  <Lift className="h-full">
                    <div
                      className="h-full rounded-[1.75rem] border p-8"
                      style={{ background: featureWashes[key] }}
                    >
                      <span
                        className="inline-block size-3 rounded-full"
                        style={{ background: featureDots[key] }}
                      />
                      <h3 className="mt-4 text-xl font-semibold tracking-tight">
                        {t(`features.${key}.title`)}
                      </h3>
                      <p className="mt-3 text-sm/6 text-muted-foreground">
                        {t(`features.${key}.body`)}
                      </p>
                    </div>
                  </Lift>
                </FadeIn>
              ))}
            </div>
          </div>
        </section>

        {/* ── How it works ─────────────────────────────────────────── */}
        <section id="how" className="scroll-mt-24 border-y bg-card/50">
          <div className="mx-auto w-full max-w-6xl px-6 py-24">
            <FadeIn>
              <p className="text-center font-mono text-xs tracking-widest text-primary uppercase">
                {t("how.eyebrow")}
              </p>
              <h2 className="mx-auto mt-3 max-w-xl text-center text-3xl font-bold tracking-tight sm:text-4xl">
                {t("how.title")}
              </h2>
            </FadeIn>

            <ol className="mt-12 grid gap-5 md:grid-cols-3">
              {(["s1", "s2", "s3"] as const).map((key, index) => (
                <FadeIn key={key} delay={index * 0.1}>
                  <li className="h-full rounded-3xl border bg-background p-7">
                    <span className="flex size-9 items-center justify-center rounded-full bg-primary/12 font-mono text-sm font-semibold text-primary">
                      {index + 1}
                    </span>
                    <h3 className="mt-4 font-semibold">
                      {t(`how.${key}.title`)}
                    </h3>
                    <p className="mt-2 text-sm/6 text-muted-foreground">
                      {t(`how.${key}.body`)}
                    </p>
                  </li>
                </FadeIn>
              ))}
            </ol>

            <FadeIn delay={0.2}>
              <p className="mt-8 rounded-3xl border border-primary/25 bg-primary/5 p-6 text-center text-sm/6">
                {t("how.privacy")}
              </p>
            </FadeIn>
          </div>
        </section>

        {/* ── Open source ──────────────────────────────────────────── */}
        <section className="mx-auto w-full max-w-6xl px-6 py-24">
          <FadeIn>
            <div
              className="flex flex-col items-start justify-between gap-8 rounded-[2rem] border p-10 md:flex-row md:items-center"
              style={{ background: "var(--wash-plant)" }}
            >
              <div className="max-w-xl">
                <p className="font-mono text-xs tracking-widest text-primary uppercase">
                  {t("open.eyebrow")}
                </p>
                <h2 className="mt-3 text-3xl font-bold tracking-tight">
                  {t("open.title")}
                </h2>
                <p className="mt-4 text-muted-foreground">{t("open.body")}</p>
              </div>
              <div className="flex flex-col gap-3">
                <Button
                  variant="outline"
                  className="rounded-full bg-card"
                  render={
                    <a href={GITHUB_URL} target="_blank" rel="noreferrer" />
                  }
                >
                  <HugeiconsIcon icon={GithubIcon} data-icon="inline-start" />
                  {t("open.star")}
                </Button>
                <Button
                  variant="ghost"
                  className="rounded-full"
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
          </FadeIn>
        </section>

        {/* ── FAQ ──────────────────────────────────────────────────── */}
        <section id="faq" className="scroll-mt-24">
          <div className="mx-auto w-full max-w-6xl px-6 pb-24">
            <FadeIn>
              <h2 className="text-center text-3xl font-bold tracking-tight sm:text-4xl">
                {t("faq.title")}
              </h2>
            </FadeIn>
            <dl className="mt-12 grid gap-5 md:grid-cols-2">
              {(["q1", "q2", "q3", "q4"] as const).map((key, index) => (
                <FadeIn key={key} delay={index * 0.06}>
                  <div className="h-full rounded-3xl border bg-card p-7">
                    <dt className="font-semibold">{t(`faq.${key}.q`)}</dt>
                    <dd className="mt-2 text-sm/6 text-muted-foreground">
                      {t(`faq.${key}.a`)}
                    </dd>
                  </div>
                </FadeIn>
              ))}
            </dl>
          </div>
        </section>

        {/* ── Closing CTA ──────────────────────────────────────────── */}
        <section className="mx-auto w-full max-w-6xl px-6 pb-24">
          <FadeIn>
            <div className="relative overflow-hidden rounded-[2.5rem] bg-primary px-8 py-20 text-center text-primary-foreground">
              <h2 className="text-3xl font-bold tracking-tight text-balance sm:text-4xl">
                {t("cta.title")}
              </h2>
              <p className="mx-auto mt-4 max-w-md text-primary-foreground/80">
                {t("cta.body")}
              </p>
              <div className="mt-9 flex flex-wrap items-center justify-center gap-3">
                <Button
                  size="lg"
                  className="rounded-full bg-white px-7 text-primary hover:bg-white/90"
                  render={<a href={DOWNLOAD_URL} />}
                >
                  <HugeiconsIcon
                    icon={Download01Icon}
                    data-icon="inline-start"
                  />
                  {t("cta.download")}
                </Button>
                <Button
                  size="lg"
                  variant="outline"
                  className="rounded-full border-white/40 bg-transparent px-7 text-primary-foreground hover:bg-white/10 hover:text-primary-foreground"
                  render={
                    <a href={GITHUB_URL} target="_blank" rel="noreferrer" />
                  }
                >
                  {t("cta.github")}
                </Button>
              </div>
            </div>
          </FadeIn>
        </section>
      </main>

      <SiteFooter />
    </div>
  )
}
