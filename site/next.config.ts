import type { NextConfig } from "next"
import createNextIntlPlugin from "next-intl/plugin"

// Wires the i18n/request.ts config into the App Router.
const withNextIntl = createNextIntlPlugin()

const nextConfig: NextConfig = {
  // Safety net for the bare domain. The proxy normally 307s "/" to the
  // visitor's locale, but config-level redirects are applied by the
  // routing layer even where the proxy doesn't run (observed on the
  // first Vercel deployment, where / returned a 404 while /en and /fr
  // were fine). Costs nothing when the proxy works: redirects are
  // evaluated first anyway.
  redirects: async () => [
    { source: "/", destination: "/en", permanent: false },
  ],
}

export default withNextIntl(nextConfig)
