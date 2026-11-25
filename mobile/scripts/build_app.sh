#!/bin/bash
# Builds the iPhone and iPad app, unsigned, for a device and for the simulator. Nothing is installed.
# usage: mobile/scripts/build_app.sh <work folder, outside the repository> [iphoneos|iphonesimulator]...
set -euo pipefail
export OORT_MOBILE=$(cd "$(dirname "$0")/.." && pwd)
work=${1:?the work folder}; shift
mkdir -p "$work"; work=$(cd "$work" && pwd)
case "$work/" in "$(dirname "$OORT_MOBILE")"/*) echo "the work folder must be outside the repository"; exit 2;; esac
xcodegen generate -q --spec "$OORT_MOBILE/App/project.yml" --project "$work" --project-root "$work"
for sdk in "${@:-iphoneos iphonesimulator}"; do for one in $sdk; do
  name=iOS; [ "$one" = iphoneos ] || name="iOS Simulator"
  xcodebuild -project "$work/OortNX.xcodeproj" -scheme OortNX -configuration Release -destination "generic/platform=$name" \
    -derivedDataPath "$work/dd" ONLY_ACTIVE_ARCH=NO ARCHS=arm64 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= build > "$work/build-$one.log" 2>&1 \
    || { grep -E "error:|xcodebuild: error" "$work/build-$one.log" | sort -u | head -30; echo "FAILED: $one, log $work/build-$one.log"; exit 1; }
  app=$(ls -d "$work/dd/Build/Products/Release-$one/"*.app)
  echo "$one: $(du -sh "$app" | cut -f1) $(lipo -archs "$app/Oort NX") $(vtool -show-build "$app/Oort NX" | awk '/platform|minos|sdk/{printf "%s %s ", $1, $2}')"
done; done
