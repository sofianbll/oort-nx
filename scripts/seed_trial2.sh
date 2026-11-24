#!/usr/bin/env bash
# Run before first launch of the trial 2 Dev app, with both launchers closed.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(swift build --jobs 4 --show-bin-path)"
if [ ! -f "$BIN/ArcanePorting.o" ] || [ ! -d "$BIN/NXLibrary_NXLibraryCore.bundle" ]; then
  echo "Build the Debug checkout first (swift build --jobs 4)." >&2
  exit 1
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp/}/oort-trial2-seed.XXXXXX")"
trap 'rm -f "$WORK/seed" "$WORK/NXLibrary_NXLibraryCore.bundle"; rmdir "$WORK"' EXIT
ln -s "$BIN/NXLibrary_NXLibraryCore.bundle" "$WORK/NXLibrary_NXLibraryCore.bundle"
swiftc -j 4 -I "$BIN" scripts/seed_trial2.swift "$BIN/NXLibraryCore.o" "$BIN/ArcanePorting.o" "$BIN/OortCore.o" -o "$WORK/seed"
"$WORK/seed" "$@"
