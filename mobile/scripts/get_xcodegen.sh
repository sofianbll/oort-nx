#!/bin/bash
# Fetches the pinned XcodeGen, checks its fingerprint and prints its path. usage: get_xcodegen.sh <folder outside the repository>
set -euo pipefail
version=2.46.0 digest=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
mkdir -p "${1:?a folder}"; cd "$1"
curl --fail --silent --show-error --location --retry 3 -o xcodegen.zip "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip"
echo "$digest  xcodegen.zip" | shasum -a 256 --check --quiet
unzip -qo xcodegen.zip
echo "$PWD/xcodegen/bin"
