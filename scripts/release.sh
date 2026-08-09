#!/bin/bash
#
# Publishes the .dmg that build.sh produced: a GitHub release, and — once the
# update feed exists — the Sparkle appcast item.
#
#   ./scripts/release.sh                    publish the version in app/project.yml
#   ./scripts/release.sh --dry-run          show what would happen, change nothing
#   ./scripts/release.sh --at <commit>      tag that commit instead of master's head
#
# Run ./scripts/build.sh first. This step only publishes; it never compiles,
# so what goes out is exactly the disk image that was verified.
#
# --at exists because notarization can take a day, and master moves in the
# meantime. A tag is a claim about which source produced the binary people
# download, so when the app's code has changed since the build, point it at the
# commit that was actually built rather than quietly tagging something else.
# git log --format="%h %ad %s" --date=iso -- app/ shows when app code last moved.
# (Adapted from DockKeep's release.sh.)

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
REPO="ln-dev7/roster"
DMG="$ROOT/dist/Roster.dmg"
ITEM="$ROOT/dist/appcast-item.txt"
APPCAST="$ROOT/site/public/appcast.xml"

DRY=false
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=true; shift ;;
    --at)      TARGET="${2:-}"; shift 2 || true ;;
    *)         printf "Unknown argument: %s\n" "$1" >&2; exit 1 ;;
  esac
done

bold() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }
fail() { printf "\033[31m✗ %s\033[0m\n" "$1" >&2; exit 1; }
ok()   { printf "\033[32m✓ %s\033[0m\n" "$1"; }
run()  { if $DRY; then printf "  would run: %s\n" "$*"; else "$@"; fi; }

# ── Preflight ────────────────────────────────────────────────────────────────
[ -f "$DMG" ] || fail "dist/Roster.dmg missing — run ./scripts/build.sh first"
command -v gh >/dev/null || fail "gh not found — brew install gh, then gh auth login"
gh auth status >/dev/null 2>&1 || fail "gh is not logged in — run: gh auth login"

# The stapled ticket is what lets the app open on a Mac that has never seen it.
xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "The .dmg is not stapled. Re-run ./scripts/build.sh"

VERSION=$(grep -E '^\s+MARKETING_VERSION:' app/project.yml | sed -E 's/.*"([^"]+)".*/\1/')
TAG="v$VERSION"

if [ -f "$ITEM" ]; then
  # shellcheck disable=SC1090
  source "$ITEM"   # version, shortVersion, length, signature
  [ "$shortVersion" = "$VERSION" ] \
    || fail "dist/ holds $shortVersion but project.yml says $VERSION. Re-run ./scripts/build.sh"
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  fail "Release $TAG already exists. Bump the version: ./scripts/build.sh <new-version>"
fi

# A tag can only point at something GitHub already has.
if [ -n "$TARGET" ]; then
  RESOLVED=$(git rev-parse --verify --quiet "$TARGET^{commit}") \
    || fail "Not a commit: $TARGET"
  git merge-base --is-ancestor "$RESOLVED" "origin/master" 2>/dev/null \
    || fail "$TARGET is not on origin/master yet — git push first, then re-run"
  TARGET="$RESOLVED"
fi

bold "Publishing Roster $VERSION"
printf "  tag        %s\n  asset      %s (%s bytes)\n  repository %s\n" \
  "$TAG" "$(basename "$DMG")" "$(stat -f%z "$DMG")" "$REPO"
if [ -n "$TARGET" ]; then
  printf "  tagging    %s — %s\n" "${TARGET:0:9}" "$(git log -1 --format=%s "$TARGET")"
else
  printf "  tagging    origin/master's head\n"
fi
$DRY && printf "\n\033[33m  dry run — nothing will be changed\033[0m\n"

# ── Release notes ────────────────────────────────────────────────────────────
NOTES_FILE="$ROOT/dist/notes.md"
if [ ! -f "$NOTES_FILE" ]; then
  cat > "$NOTES_FILE" <<EOF
Roster $VERSION

Your coding agents, in a room. They come to your desk when they're done.

Requires macOS 14 or later. Signed with a Developer ID and notarized by
Apple. Everything runs locally — no account, no telemetry.
EOF
  ok "Wrote default notes to dist/notes.md — edit it and re-run to change them"
fi

# ── GitHub release ───────────────────────────────────────────────────────────
bold "Creating the GitHub release"
if [ -n "$TARGET" ]; then
  run gh release create "$TAG" "$DMG" \
    --repo "$REPO" \
    --target "$TARGET" \
    --title "Roster $VERSION" \
    --notes-file "$NOTES_FILE"
else
  run gh release create "$TAG" "$DMG" \
    --repo "$REPO" \
    --title "Roster $VERSION" \
    --notes-file "$NOTES_FILE"
fi
ok "Release $TAG created"

# ── Sparkle appcast (only once the feed exists) ──────────────────────────────
if [ -f "$ITEM" ] && [ -f "$APPCAST" ]; then
  bold "Adding the item to the update feed"
  NOTES_HTML="$ROOT/dist/notes.html"
  [ -f "$NOTES_HTML" ] || printf '<p>Roster %s.</p>\n' "$VERSION" > "$NOTES_HTML"
  if $DRY; then
    printf "  would run: scripts/make-appcast.py --version %s ...\n" "$VERSION"
  else
    python3 scripts/make-appcast.py \
      --appcast "$APPCAST" \
      --version "$version" \
      --short-version "$VERSION" \
      --length "$length" \
      --signature "$signature" \
      --notes "$(cat "$NOTES_HTML")" \
      --url "https://github.com/$REPO/releases/download/$TAG/Roster.dmg"
    ok "site/public/appcast.xml updated — commit and deploy the site"
  fi
else
  printf "\n  No appcast item or no feed yet — Sparkle stays silent, as planned.\n"
fi

printf "\n\033[1mPublished.\033[0m\n"
printf "  The stable download link is releases/latest/download/Roster.dmg,\n"
printf "  which now resolves to %s on its own.\n\n" "$TAG"
