import type { Metadata } from "next"
import { DM_Sans, Geist_Mono } from "next/font/google"
import { notFound } from "next/navigation"
import { hasLocale, NextIntlClientProvider } from "next-intl"
import { getTranslations, setRequestLocale } from "next-intl/server"

import "../globals.css"
import { ThemeProvider } from "@/components/theme-provider"
import { routing } from "@/i18n/routing"
import { cn } from "@/lib/utils"

const dmSans = DM_Sans({ subsets: ["latin"], variable: "--font-sans" })

const fontMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
})

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }))
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>
}): Promise<Metadata> {
  const { locale } = await params
  const t = await getTranslations({ locale, namespace: "meta" })

  return {
    metadataBase: new URL("https://roster.lndev.me"),
    title: t("title"),
    description: t("description"),
    alternates: {
      canonical: `/${locale}`,
      languages: { en: "/en", fr: "/fr" },
    },
    openGraph: {
      title: t("title"),
      description: t("description"),
      type: "website",
      url: `/${locale}`,
    },
  }
}

export default async function LocaleLayout({
  children,
  params,
}: Readonly<{
  children: React.ReactNode
  params: Promise<{ locale: string }>
}>) {
  const { locale } = await params
  if (!hasLocale(routing.locales, locale)) {
    notFound()
  }
  // Enables static rendering for both locales.
  setRequestLocale(locale)

  return (
    <html
      lang={locale}
      suppressHydrationWarning
      className={cn(
        "antialiased",
        fontMono.variable,
        "font-sans",
        dmSans.variable
      )}
    >
      <body>
        <ThemeProvider>
          {/* Messages are inherited from i18n/request.ts. */}
          <NextIntlClientProvider>{children}</NextIntlClientProvider>
        </ThemeProvider>
      </body>
    </html>
  )
}
