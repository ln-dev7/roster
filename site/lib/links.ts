// Every external URL of the site, in one place.
export const GITHUB_URL = "https://github.com/ln-dev7/roster"
export const RELEASES_URL = "https://github.com/ln-dev7/roster/releases/latest"
// GitHub keeps this one pointing at the newest release's Roster.dmg
// (release.sh always uploads the asset under that fixed name), so the
// site's download buttons never go stale.
export const DOWNLOAD_URL = `${RELEASES_URL}/download/Roster.dmg`
export const ISSUES_URL = `${GITHUB_URL}/issues`
export const GOOD_FIRST_ISSUES_URL = `${GITHUB_URL}/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22`
export const LICENSE_URL = `${GITHUB_URL}/blob/master/LICENSE`
export const AUTHOR_URL = "https://lndev.me"
export const DOCKKEEP_URL = "https://dockkeep.lndev.me"
