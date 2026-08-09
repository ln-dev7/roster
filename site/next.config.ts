import type { NextConfig } from "next"
import createNextIntlPlugin from "next-intl/plugin"

// Wires the i18n/request.ts config into the App Router.
const withNextIntl = createNextIntlPlugin()

const nextConfig: NextConfig = {}

export default withNextIntl(nextConfig)
