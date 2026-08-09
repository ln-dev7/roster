import { createNavigation } from "next-intl/navigation"

import { routing } from "./routing"

// Locale-aware drop-ins for Next's navigation APIs. Always import Link and
// usePathname from here, never from next/link — these keep the /en or /fr
// prefix intact when navigating.
export const { Link, redirect, usePathname, useRouter, getPathname } =
  createNavigation(routing)
