#!/usr/bin/env bash
# scripts/build_dmg.sh [--plain] [app] — packs a built Oort NX into dist/Oort NX.dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAIN=0
if [ "${1:-}" = --plain ]; then PLAIN=1; shift; fi
[ "$#" -le 1 ] || { echo "usage: scripts/build_dmg.sh [--plain] [app]" >&2; exit 2; }
APP="${1:-$HOME/Applications/Oort NX.app}"
OUT="$ROOT/dist/Oort NX.dmg"

fail() { echo "build_dmg: $*" >&2; exit 1; }
[ -d "$APP" ] || { echo "build_dmg: no app at $APP (run scripts/build_app.sh)" >&2; exit 1; }
[ ! -d "$OUT" ] || fail "output must be a file: $OUT"
[ -d "$APP/Contents/Resources/Runtime" ] || echo "warning: $APP has no bundled runtime" >&2
codesign --verify --deep --strict "$APP"

if [ "$PLAIN" = 0 ]; then
  PYTHON="${OORT_DMG_PYTHON:-python3}"
  "$PYTHON" -I -c 'import dmgbuild' 2>/dev/null \
    || fail "install scripts/dmg-requirements.txt in a venv and set OORT_DMG_PYTHON to its python, or use --plain"
  command -v swift >/dev/null \
    || fail "Swift is required to draw the background; use --plain for an unstyled image"
fi

mkdir -p "$ROOT/dist"
TEMP="$(mktemp -d "$ROOT/dist/.dmg.XXXXXX")"
MOUNT="$TEMP/mount"
ATTACHED=0
cleanup() {
  if [ "$ATTACHED" = 1 ] && ! hdiutil detach "$MOUNT" >/dev/null; then
    echo "build_dmg: could not detach $MOUNT; leaving $TEMP untouched" >&2
    return 1
  fi
  rm -rf "$TEMP"
}
trap cleanup EXIT
STAGE="$TEMP/stage"
mkdir "$STAGE" "$MOUNT"
ditto --norsrc "$APP" "$STAGE/Oort NX.app"
finder_file="$(find "$STAGE/Oort NX.app" \( -iname .DS_Store -o -name '._*' \) -print -quit)"
[ -z "$finder_file" ] || fail "unexpected Finder metadata file in the app bundle"
IMAGE="$TEMP/installer.dmg"
if [ "$PLAIN" = 0 ]; then
  "$PYTHON" -EsB "$ROOT/scripts/style_dmg.py" "$STAGE/Oort NX.app" "$IMAGE" >/dev/null
else
  ln -s /Applications "$STAGE/Applications"
  # macOS 26+ deprecates hdiutil create. Keep the legacy path for older hosts.
  if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from --format UDZO --volumeName "Oort NX" "$STAGE" "$IMAGE" >/dev/null
  else
    hdiutil create -volname "Oort NX" -srcfolder "$STAGE" -format UDZO "$IMAGE" >/dev/null
  fi
fi

hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$IMAGE" >/dev/null
ATTACHED=1
codesign --verify --deep --strict "$MOUNT/Oort NX.app"
[ "$(readlink "$MOUNT/Applications")" = /Applications ] || fail "Applications shortcut missing"
if [ "$PLAIN" = 0 ]; then
  for file in .DS_Store .background.tiff .VolumeIcon.icns; do
    [ -s "$MOUNT/$file" ] || fail "$file missing from the image"
  done
  [[ "$(/usr/bin/GetFileInfo -a "$MOUNT")" == *C* ]] || fail "custom volume icon flag missing"
fi
hdiutil detach "$MOUNT" >/dev/null
ATTACHED=0
mv -f "$IMAGE" "$OUT"
echo "Built $OUT ($(du -h "$OUT" | awk '{print $1}'))"
