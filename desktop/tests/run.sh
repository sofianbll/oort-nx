#!/bin/sh
# Run the real window (debug build, Mac) with a script in the page. usage: run.sh <script.js> <out folder> [WxH]
# The home, the app's data and the games are throwaway; nothing of the player's is read.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=$1; out=$2; size=${3:-1440x900}
run=${OORT_RUN:?folder made by scripts/fixtures.py}
app=${OORT_APP:?the debug binary}
mkdir -p "$out" "$run/home" "$run/tmp"
# The page learns where to put its pictures.
{ printf 'window.OUT=%s;window.RUN=%s;window.TAG=%s;\n' "\"$out\"" "\"$run\"" "\"${OORT_TAG:-}\""; cat "$here/lib.js" "$script"; } > "$run/probe.js"
HOME="$run/home" CFFIXED_USER_HOME="$run/home" TMPDIR="$run/tmp" OORT_DATA="${OORT_DATA:-$run/data}" OORT_LANGUAGE="${OORT_LANGUAGE:-fr}" \
  OORT_RESOURCES="$here/../src-tauri" OORT_PROBE="$run/probe.js" OORT_SIZE="$size" "$app"
