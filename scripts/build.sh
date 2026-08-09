#!/bin/bash
#
# Builds a signed, notarized, stapled .dmg of Roster.
#
#   ./scripts/build.sh              build the version in app/project.yml
#   ./scripts/build.sh 0.2.0        bump to 0.2.0 first, then build
#   ./scripts/build.sh --finish ID  pick up an earlier run whose notarization
#                                   was still queued when it was interrupted
#
# Produces dist/Roster.dmg — plus dist/appcast-item.txt when a Sparkle
# signing key exists in the keychain (it holds the signature the release
# step needs once the update feed goes live).
#
# The .dmg keeps the same filename at every version on purpose. GitHub serves
# releases/latest/download/<name>, so a fixed name gives the website one
# download link that never has to be edited again.
#
# Nothing here touches the network except notarization.
# (Adapted from DockKeep's build.sh.)

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="Roster"
DMG_NAME="Roster.dmg"
TEAM_ID="JDWTCZR377"
NOTARY_PROFILE="notary"

BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
ARCHIVE="$BUILD_DIR/Roster.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGE_DIR="$BUILD_DIR/dmg"

bold() { printf "\n\033[1m▸ %s\033[0m\n" "$1"; }
fail() { printf "\033[31m✗ %s\033[0m\n" "$1" >&2; exit 1; }
ok()   { printf "\033[32m✓ %s\033[0m\n" "$1"; }
warn() { printf "\033[33m  %s\033[0m\n" "$1"; }

# ── Mode ─────────────────────────────────────────────────────────────────────
# Apple's notary service usually answers in minutes, but it can sit in a queue
# for an hour with no incident declared. The ticket is bound to the exact file
# that was submitted, so when that happens there is nothing to rebuild — the
# disk image in dist/ is still the one Apple is looking at.
FINISH_ID=""
if [ "${1:-}" = "--finish" ]; then
  FINISH_ID="${2:-}"
  [ -n "$FINISH_ID" ] || fail "--finish needs the submission id, e.g. --finish 8233a150-…"
  shift 2 || true
fi

# ── Optional version bump ────────────────────────────────────────────────────
if [ -z "$FINISH_ID" ] && [ $# -ge 1 ]; then
  NEW_VERSION="$1"
  [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must look like 1.2.3, got '$NEW_VERSION'"
  bold "Bumping to $NEW_VERSION"
  CURRENT_BUILD=$(grep -E '^\s+CURRENT_PROJECT_VERSION:' app/project.yml | tr -dc '0-9')
  NEXT_BUILD=$((CURRENT_BUILD + 1))
  # Sparkle compares CURRENT_PROJECT_VERSION, so it must only ever go up.
  /usr/bin/sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION:).*/\1 \"$NEW_VERSION\"/" app/project.yml
  /usr/bin/sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION:).*/\1 $NEXT_BUILD/" app/project.yml
  ok "project.yml now at $NEW_VERSION (build $NEXT_BUILD)"
fi

VERSION=$(grep -E '^\s+MARKETING_VERSION:' app/project.yml | sed -E 's/.*"([^"]+)".*/\1/')
BUILD_NUMBER=$(grep -E '^\s+CURRENT_PROJECT_VERSION:' app/project.yml | tr -dc '0-9')
[ -n "$VERSION" ] || fail "Could not read MARKETING_VERSION from app/project.yml"

# ── Preflight ────────────────────────────────────────────────────────────────
bold "Checking the toolchain"

command -v xcodegen >/dev/null || fail "xcodegen not found — brew install xcodegen"
command -v xcodebuild >/dev/null || fail "xcodebuild not found — install Xcode"

security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application" \
  || fail "No 'Developer ID Application' certificate in the keychain. Xcode › Settings › Accounts › Manage Certificates."
ok "Developer ID certificate present"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "Notary profile '$NOTARY_PROFILE' not usable. Create it once with:
    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <you@example.com> --team-id $TEAM_ID --password <app-specific-password>"
ok "Notary profile '$NOTARY_PROFILE' reachable"

# Sparkle's update signature is optional until the feed goes live: without a
# generated key pair (Sparkle's generate_keys) the release simply ships
# without an appcast item, which is fine while SUFeedURL isn't set either.
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -type f -name sign_update -path '*Sparkle*' 2>/dev/null | head -1 || true)
if [ -n "$SIGN_UPDATE" ]; then
  ok "sign_update found"
else
  warn "Sparkle's sign_update not found — the update feed item will be skipped."
fi

DMG="$DIST_DIR/$DMG_NAME"

if [ -n "$FINISH_ID" ]; then
  [ -f "$DMG" ] || fail "dist/$DMG_NAME is gone — nothing to finish. Run ./scripts/build.sh"
  bold "Finishing Roster $VERSION (build $BUILD_NUMBER)"
  printf "  submission %s\n  image      %s, %s bytes, untouched since it was submitted\n" \
    "$FINISH_ID" "$DMG_NAME" "$(stat -f%z "$DMG")"
else

# ── Clean ────────────────────────────────────────────────────────────────────
bold "Building Roster $VERSION (build $BUILD_NUMBER)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

( cd app && xcodegen ) >/dev/null
ok "Project generated"

# ── Archive ──────────────────────────────────────────────────────────────────
xcodebuild archive \
  -project "app/Roster.xcodeproj" \
  -scheme "Roster" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  | grep -E "error:|warning:|BUILD" || true

[ -d "$ARCHIVE" ] || fail "Archive failed"
ok "Archived"

# ── Export a signed .app ─────────────────────────────────────────────────────
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "scripts/ExportOptions.plist" \
  | grep -E "error:|Exported" || true

APP="$EXPORT_DIR/$APP_NAME.app"
[ -d "$APP" ] || fail "Export failed — no $APP_NAME.app in $EXPORT_DIR"
ok "Exported and signed"

# ── Verify the signature before wasting a notarization round trip ────────────
bold "Verifying the signature"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
codesign --display --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" | sed 's/^/  /'
codesign --display --entitlements - "$APP" >/dev/null 2>&1

# Every nested bundle Sparkle brings has to be signed too, or notarization
# rejects the whole thing with a list of unsigned binaries.
NESTED=$(find "$APP/Contents/Frameworks" \( -name "*.app" -o -name "*.xpc" -o -name "*.framework" \) 2>/dev/null || true)
if [ -n "$NESTED" ]; then
  while IFS= read -r bundle; do
    codesign --verify --strict "$bundle" 2>/dev/null \
      && printf "  ✓ %s\n" "$(basename "$bundle")" \
      || fail "Nested bundle not properly signed: $bundle"
  done <<< "$NESTED"
fi
ok "Signature valid, nested bundles included"

# ── Build the .dmg ───────────────────────────────────────────────────────────
bold "Building the disk image"
rm -rf "$STAGE_DIR"; mkdir -p "$STAGE_DIR"
cp -R "$APP" "$STAGE_DIR/"
rm -f "$DMG"

# create-dmg lays out the window: our blueprint background, the app on the
# left, the Applications folder on the right. It is not required — a plain
# image installs perfectly well — so its absence downgrades the look rather
# than failing the release.
if command -v create-dmg >/dev/null && [ -f "shared/assets/dmg-background.png" ]; then
  # The window, in points. These four numbers are also written at the top of
  # scripts/make-dmg-background.py, and the two files have to agree: the
  # artwork reserves a place for each icon and this is what puts the icon
  # there.
  WINDOW_W=660
  WINDOW_H=380
  ICON_Y=222

  # A bare PNG carries no indication of its scale, so Finder draws it at one
  # pixel per point. A multi-representation TIFF is the only way to say "the
  # same picture at two densities", so one point stays one point.
  BACKGROUND="shared/assets/dmg-background.png"
  if [ -f "shared/assets/dmg-background@2x.png" ] && command -v tiffutil >/dev/null; then
    if tiffutil -cathidpicheck \
         "shared/assets/dmg-background.png" \
         "shared/assets/dmg-background@2x.png" \
         -out "$BUILD_DIR/dmg-background.tiff" >/dev/null 2>&1; then
      BACKGROUND="$BUILD_DIR/dmg-background.tiff"
    else
      warn "tiffutil refused the pair — using the 1x background"
    fi
  fi

  # It adds the Applications link itself, which is why the staging folder holds
  # nothing but the app.
  create-dmg \
    --volname "$APP_NAME $VERSION" \
    --background "$BACKGROUND" \
    --window-pos 200 120 \
    --window-size "$WINDOW_W" "$WINDOW_H" \
    --icon-size 128 \
    --icon "$APP_NAME.app" 180 "$ICON_Y" \
    --app-drop-link 480 "$ICON_Y" \
    --hide-extension "$APP_NAME.app" \
    --no-internet-enable \
    "$DMG" "$STAGE_DIR" >/dev/null 2>&1 || true

  # create-dmg exits non-zero on harmless things such as a slow unmount, so
  # trust the file rather than the exit code.
  [ -f "$DMG" ] || fail "create-dmg produced nothing. Run it without the output
  redirection to see why, or uninstall it to fall back to a plain image."
  ok "$(basename "$DMG") built with its window laid out ($(du -h "$DMG" | cut -f1))"
else
  ln -s /Applications "$STAGE_DIR/Applications"
  hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG" >/dev/null
  ok "$(basename "$DMG") built, plain ($(du -h "$DMG" | cut -f1))"
  warn "brew install create-dmg for the laid-out window"
fi

# The disk image is signed as well, so Gatekeeper trusts it before it is even
# opened.
codesign --sign "Developer ID Application" --timestamp "$DMG"
ok "Disk image signed"

fi   # end of the build stages skipped by --finish

# ── Notarize ─────────────────────────────────────────────────────────────────
if [ -n "$FINISH_ID" ]; then
  bold "Waiting on the existing submission"
  # notarytool gives up the moment one poll fails, so a dropped Wi-Fi ends an
  # hours-long wait with a network error. The submission itself lives on
  # Apple's servers and is untouched by anything that happens here, so the only
  # sane response is to poll again. A genuine rejection is told apart from a
  # lost connection and stops immediately — retrying that would be pointless.
  attempt=1
  max_attempts=30
  while true; do
    if reply=$(xcrun notarytool wait "$FINISH_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1); then
      printf "%s\n" "$reply" | sed 's/^/  /'
      break
    fi
    printf "%s\n" "$reply" | sed 's/^/  /'

    if printf "%s" "$reply" | grep -qE "Invalid|Rejected"; then
      fail "Apple rejected this submission. Find out why with:
    xcrun notarytool log $FINISH_ID --keychain-profile $NOTARY_PROFILE"
    fi

    if [ "$attempt" -ge "$max_attempts" ]; then
      fail "Gave up after $max_attempts polls. Nothing is lost — the submission is
  still on Apple's side. Once the network is back:
    ./scripts/build.sh --finish $FINISH_ID"
    fi

    warn "poll $attempt could not reach Apple (network?), retrying in 60s"
    attempt=$((attempt + 1))
    sleep 60
  done
else
  bold "Notarizing (this goes to Apple and usually takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | sed 's/^/  /'
fi

xcrun stapler staple "$DMG" | sed 's/^/  /'
ok "Stapled"

# ── Final verification, the way a user's Mac will see it ─────────────────────
bold "Verifying as Gatekeeper would"
spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /'
xcrun stapler validate "$DMG" | sed 's/^/  /'
ok "Gatekeeper accepts it"

# ── Sparkle signature for the appcast (optional until the feed ships) ────────
if [ -n "$SIGN_UPDATE" ]; then
  bold "Signing the update for Sparkle"
  if SIG_LINE=$("$SIGN_UPDATE" "$DMG" 2>/dev/null); then
    LENGTH=$(stat -f%z "$DMG")
    {
      echo "version=$BUILD_NUMBER"
      echo "shortVersion=$VERSION"
      echo "length=$LENGTH"
      echo "signature=$(echo "$SIG_LINE" | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')"
    } > "$DIST_DIR/appcast-item.txt"
    ok "Signature written to dist/appcast-item.txt"
  else
    warn "sign_update has no key in the keychain (run Sparkle's generate_keys once) — skipping the appcast item."
  fi
fi

printf "\n\033[1mDone.\033[0m  dist/%s — Roster %s (build %s)\n" "$DMG_NAME" "$VERSION" "$BUILD_NUMBER"
printf "Publish it with:  ./scripts/release.sh\n\n"
