#!/usr/bin/env bash
# scripts/build_app.sh [destination.app]
# NX_VERSION sets the app version (default: the version in progress, from the VERSION file); NX_RELEASE=1
# marks a release copy, the only kind that updates itself. scripts/release.sh sets both; a plain build sets
# neither, so a development copy carries the version being worked on and says it is a development build.
# A development copy is "Oort NX Dev" (default ~/Applications/Oort NX Dev.app), the maintainer's test copy,
# beside the released "Oort NX" that updates itself. The development marker selects separate launcher
# data/preferences and a distinct bundle ID, so framework-owned preferences are separate too.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${NX_RELEASE:-0}" = "1" ]; then
  NAME="Oort NX"
  BUNDLE_ID="local.nxlibrary"
  APP="${1:-$HOME/Applications/$NAME.app}"
else
  NAME="Oort NX Dev"
  BUNDLE_ID="local.nxlibrary.development"
  APP="${1:-$HOME/Applications/$NAME.app}"
fi
CONFIG="${NX_BUILD_CONFIG:-release}"
VERSION="${NX_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
  echo "error: NX_VERSION must be dotted numbers, got '$VERSION'" >&2
  exit 1
fi
RELEASE_KEY="  <key>NXLibraryDevelopmentProfile</key><true/>"
[ "${NX_RELEASE:-0}" = "1" ] && RELEASE_KEY="  <key>NXLibraryRelease</key><true/>"
# release.sh validates reachability; reject incomplete/malformed pins in direct builds too.
ENGINE_REPO="${NX_ENGINE_REPO:-}"
ENGINE_COMMIT="${NX_ENGINE_COMMIT:-}"
if [[ -n "$ENGINE_REPO$ENGINE_COMMIT" ]] &&
   ! [[ "$ENGINE_REPO" =~ ^https://github\.com/[A-Za-z0-9_-]+/[A-Za-z0-9_-][A-Za-z0-9_.-]*$ && "$ENGINE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: NX_ENGINE_REPO and NX_ENGINE_COMMIT must name a GitHub HTTPS repository and a full lowercase SHA" >&2
  exit 1
fi
NEXTENDO_CLIENT_ID="${DM_NEXTENDO_CLIENT_ID:-}"
GOOGLE_CLIENT_ID="${ARCANE_GOOGLE_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${ARCANE_GOOGLE_CLIENT_SECRET:-}"
unset ARCANE_GOOGLE_CLIENT_ID ARCANE_GOOGLE_CLIENT_SECRET
if [[ -n "$NEXTENDO_CLIENT_ID" && ! "$NEXTENDO_CLIENT_ID" =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
  echo "error: DM_NEXTENDO_CLIENT_ID must be a valid public client ID" >&2
  exit 1
fi
if [ -z "${DEVELOPER_DIR:-}" ]; then
  if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  elif [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  fi
fi

cd "$ROOT"
swift build -c "$CONFIG" --product NXLibrary

BIN="$ROOT/.build/$CONFIG/NXLibrary"
DESTINATION="$APP"
STAGE="$(mktemp -d "${TMPDIR:-/tmp/}nxlibrary-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/NXLibrary.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/NXLibrary"
LOCALIZATION_BUNDLE="$ROOT/.build/$CONFIG/NXLibrary_NXLibraryCore.bundle"
[ -d "$LOCALIZATION_BUNDLE" ] || { echo "error: compiled localization bundle missing" >&2; exit 1; }
cp -R "$LOCALIZATION_BUNDLE" "$APP/Contents/Resources/"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
for icon in "$ROOT"/Resources/AppIcon-Particles-*.png; do
  cp "$icon" "$APP/Contents/Resources/"
done
# macOS draws the Icon Composer icon natively instead of framing the ICNS fallback.
ICON_BUILD="$STAGE/icon"
mkdir -p "$ICON_BUILD"
xcrun actool "$ROOT/Resources/AppIcon.icon" --compile "$ICON_BUILD" \
  --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon --include-all-app-icons \
  --output-partial-info-plist "$STAGE/icon.plist"
test -s "$ICON_BUILD/Assets.car"
cp "$ICON_BUILD/Assets.car" "$APP/Contents/Resources/"
[ -f "$ROOT/LICENSE" ] && cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
[ -f "$ROOT/NOTICE" ] && cp "$ROOT/NOTICE" "$APP/Contents/Resources/NOTICE"
cp -R "$ROOT/Resources/ThirdPartyLicenses" "$APP/Contents/Resources/"
if [ "${NX_RELEASE:-0}" = "1" ]; then
  RCLONE_VERSION=1.75.2
  RCLONE_SHA256=610ab7d48615135dfc60b763858b11a426a0d3d1160c1bb76fb0ae6011b02edd
  RCLONE_BASE="https://downloads.rclone.org/v$RCLONE_VERSION"
  RCLONE_NAME="rclone-v$RCLONE_VERSION-osx-arm64"
  curl -qfsSL --proto '=https' --proto-redir '=https' --max-time 120 "$RCLONE_BASE/SHA256SUMS" -o "$STAGE/SHA256SUMS"
  grep -Fx "$RCLONE_SHA256  $RCLONE_NAME.zip" "$STAGE/SHA256SUMS" >/dev/null \
    || { echo "error: official rclone checksum differs from the pin" >&2; exit 1; }
  curl -qfsSL --proto '=https' --proto-redir '=https' --max-time 120 "$RCLONE_BASE/$RCLONE_NAME.zip" -o "$STAGE/$RCLONE_NAME.zip"
  (cd "$STAGE" && printf '%s  %s.zip\n' "$RCLONE_SHA256" "$RCLONE_NAME" | shasum -a 256 -c -)
  mkdir -p "$APP/Contents/Helpers"
  unzip -p "$STAGE/$RCLONE_NAME.zip" "$RCLONE_NAME/rclone" > "$APP/Contents/Helpers/rclone"
  chmod 755 "$APP/Contents/Helpers/rclone"
  codesign --force --sign - "$APP/Contents/Helpers/rclone"
fi
cp "$ROOT/scripts/validate_update.py" "$APP/Contents/Resources/validate_update.py"
[ -d "$ROOT/Resources/Selene" ] && cp -R "$ROOT/Resources/Selene" "$APP/Contents/Resources/Selene"
[ -d "$ROOT/Resources/Brands" ] && cp -R "$ROOT/Resources/Brands" "$APP/Contents/Resources/Brands"
# Python and build tools from scripts/bundle_runtime.sh. Without it, a developer
# build falls back to ~/nxnative/.venv and the PATH tools.
if [ -d "$ROOT/work/Runtime" ]; then
  python3 "$ROOT/scripts/check_publication.py" --runtime "$ROOT/work/Runtime"
  cp -R "$ROOT/work/Runtime" "$APP/Contents/Resources/Runtime"
else
  echo "note: no work/Runtime; this build uses ~/nxnative/.venv (run scripts/bundle_runtime.sh)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>
    <string>en</string><string>it</string><string>fr</string><string>de</string><string>es</string><string>pt-BR</string><string>zh-Hans</string>
  </array>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>NXLibrary</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSSupportsGameMode</key><false/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 bium. MIT. Not affiliated with Nintendo.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
$RELEASE_KEY
</dict>
</plist>
PLIST
/usr/bin/plutil -insert CFBundleIconName -string AppIcon "$APP/Contents/Info.plist"
if [[ -n "$NEXTENDO_CLIENT_ID" ]]; then
  /usr/bin/plutil -insert DMNextendoClientID -string "$NEXTENDO_CLIENT_ID" "$APP/Contents/Info.plist"
fi
if [[ -n "$ENGINE_REPO" ]]; then
  /usr/bin/plutil -insert NXLibraryEngineRepository -string "$ENGINE_REPO" "$APP/Contents/Info.plist"
  /usr/bin/plutil -insert NXLibraryEngineCommit -string "$ENGINE_COMMIT" "$APP/Contents/Info.plist"
fi

# Exercise the real profile/defaults accessor under this bundle identity, without
# opening the app or importing data. Unit-test hosts have a different identity.
PROFILE_PROBE="$STAGE/ProfileCheck.app"
mkdir -p "$PROFILE_PROBE/Contents/MacOS"
cp "$APP/Contents/Info.plist" "$PROFILE_PROBE/Contents/Info.plist"
ARCANE_GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" ARCANE_GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
  python3 "$ROOT/scripts/inject_google_client.py" "$APP/Contents/Info.plist"
unset GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET
swiftc -I "$ROOT/.build/$CONFIG" "$ROOT/scripts/check_app_profile.swift" \
  "$ROOT/.build/$CONFIG/NXLibraryCore.o" -o "$PROFILE_PROBE/Contents/MacOS/NXLibrary"
"$PROFILE_PROBE/Contents/MacOS/NXLibrary"

python3 "$ROOT/scripts/check_localizations.py" --app "$APP"
if [ "${NX_RELEASE:-0}" = "1" ]; then
  python3 "$ROOT/scripts/check_publication.py" --app "$APP"
fi
swiftc -I "$ROOT/.build/$CONFIG" "$ROOT/scripts/install_built_app.swift" \
  "$ROOT/.build/$CONFIG/NXLibraryCore.o" "$ROOT/.build/$CONFIG/ArcanePorting.o" -o "$STAGE/install-app"
"$STAGE/install-app" "$APP" "$DESTINATION"
echo "Built $DESTINATION"
