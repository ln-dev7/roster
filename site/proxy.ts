import createMiddleware from "next-intl/middleware"

import { routing } from "./i18n/routing"

// Next 16 renamed the middleware convention to proxy; next-intl's handler
// plugs in unchanged. It redirects / to the best-matching locale and keeps
// the /en /fr prefixes consistent.
export default createMiddleware(routing)

export const config = {
  // Skip API routes, Next internals and any file with an extension.
  matcher: "/((?!api|trpc|_next|_vercel|.*\\..*).*)",
}
