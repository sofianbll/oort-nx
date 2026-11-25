#!/bin/bash
# Renders the screens to PNG files with Mac Catalyst, in French and English.
# usage: mobile/scripts/capture.sh <work folder, outside the repository> <pictures folder> [screen,screen]
set -euo pipefail
export OORT_MOBILE=$(cd "$(dirname "$0")/.." && pwd)
work=${1:?the work folder}; mkdir -p "$work" "${2:?the pictures folder}"; work=$(cd "$work" && pwd); out=$(cd "$2" && pwd)
xcodegen generate -q --spec "$OORT_MOBILE/Capture/project.yml" --project "$work" --project-root "$work"
xcodebuild -project "$work/OortCapture.xcodeproj" -scheme OortCapture -configuration Debug -destination "platform=macOS,variant=Mac Catalyst,arch=arm64" \
  -derivedDataPath "$work/dd-capture" build > "$work/capture.log" 2>&1 || { grep -E "error:" "$work/capture.log" | sort -u | head -20; exit 1; }
for lang in ${OORT_CAPTURE_LANGS:-fr en}; do
  # No preference of the Mac is read or written.
  OORT_CAPTURE_DIR="$out/$lang" OORT_CAPTURE_ONLY="${3:-}" sandbox-exec -p "(version 1)(allow default)(deny network*)(deny mach-lookup (global-name \"com.apple.cfprefsd.daemon\") (global-name \"com.apple.cfprefsd.agent\"))(deny file-write* (subpath \"$HOME/Library/Preferences\"))" \
    "$work/dd-capture/Build/Products/Debug-maccatalyst/OortCapture.app/Contents/MacOS/OortCapture" -AppleLanguages "($lang)" -AppleLocale "$lang"
done
