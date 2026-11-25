#!/bin/bash
# Packs the device build as an unsigned IPA and checks it. The player signs it with AltStore or SideStore.
# usage: mobile/scripts/package_ipa.sh <work folder of build_app.sh> <folder for the IPA>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=${1:?the work folder}; mkdir -p "${2:?the folder for the IPA}"; out=$(cd "$2" && pwd)
app=$(ls -d "$work/dd/Build/Products/Release-iphoneos/"*.app)
version=$(plutil -extract OortVersion raw "$app/Info.plist")
ipa="$out/Oort-NX-iOS-$version-unsigned.ipa"
pack=$(mktemp -d); trap 'rm -rf "$pack"' EXIT
mkdir "$pack/Payload"; ditto "$app" "$pack/Payload/$(basename "$app")"
rm -f "$ipa"; (cd "$pack" && zip -qryX "$ipa" Payload)
python3 -I "$here/check_ipa.py" "$ipa"
(cd "$out" && shasum -a 256 "$(basename "$ipa")" | tee "$(basename "$ipa").sha256")
