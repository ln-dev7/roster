import { defineRouting } from "next-intl/routing"

// The two locales live as URL prefixes: roster.lndev.me/en, /fr.
// English is the default and the development language.
export const routing = defineRouting({
  locales: ["en", "fr"],
  defaultLocale: "en",
})
