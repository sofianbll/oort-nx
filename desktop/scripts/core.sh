#!/bin/sh
# Build oort-core (Swift) and put it where Tauri expects its companion. usage: core.sh [scratch folder]
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
scratch=${1:-$root/.build}
cd "$root"
OORT_PORTABLE=1 swift build -c release --product oort-core --scratch-path "$scratch"
bin=$(OORT_PORTABLE=1 swift build -c release --product oort-core --scratch-path "$scratch" --show-bin-path)
mkdir -p desktop/src-tauri/binaries
cp "$bin/oort-core" "desktop/src-tauri/binaries/oort-core-$(rustc -vV | sed -n 's/^host: //p')"
