#!/bin/bash
# Proves the Linux packages on a machine without Swift: the .deb installed and the AppImage as it is, each opened on a
# virtual screen, driven by real keys, with invented games. usage: prove.sh <deb> <AppImage> <out>
set -uo pipefail
deb=$(realpath "$1"); image=$(realpath "$2"); mkdir -p "$3"; out=$(realpath "$3")
here=$(cd "$(dirname "$0")" && pwd); run=$(mktemp -d); failures=0
check() { if [ "$1" = 0 ]; then echo "ok $2"; else echo "FAIL $2"; failures=$((failures + 1)); fi; }

command -v swift cargo rustc | grep -v "$HOME/.cargo" || true
python3 "$here/../../scripts/fixtures.py" "$run" --steam || exit 1
sudo apt-get install -y "$deb"; check $? "the .deb installs with its dependencies"
dpkg -L oort-nx | grep -v '/hicolor/'
core=/usr/bin/oort-core; app=/usr/bin/oort-desktop
ldd $core; ! ldd $core | grep -qi 'swift\|not found'; check $? "the core needs no Swift library"
! ldd $app | grep -q 'not found'; check $? "the window finds its libraries"
for file in NOTICE LICENSE.txt licenses/Swift-LICENSE.txt licenses/ICU-LICENSE.txt licenses/THIRD-PARTY-RUST.txt; do test -f "/usr/lib/Oort NX/$file"; check $? "$file is there"; done
env -i PATH=/usr/bin:/bin HOME="$run" $core --data "$run/core" --resources "/usr/lib/Oort NX" --system linux <<< '{"id":1,"method":"hello"}' | grep -q '"system":"linux"'; check $? "the installed core answers"

# A library, as the app itself writes it.
setup() { printf '%s\n' "{\"id\":1,\"method\":\"folders.add\",\"params\":{\"path\":\"$run/games\"}}" '{"id":2,"method":"settings.set","params":{"id":"librarySort","value":"name"}}' '{"id":3,"method":"settings.save"}' '{"id":4,"method":"guide","params":{"seen":true}}' | $core --data "$1" --resources "/usr/lib/Oort NX" --system linux > /dev/null; }
export DISPLAY=:77
Xvfb :77 -screen 0 1440x900x24 > /dev/null 2>&1 & xvfb=$!
sleep 2; openbox > /dev/null 2>&1 & sleep 1
shot() { import -window root "$out/$1.png"; colors=$(identify -format %k "$out/$1.png"); [ "$colors" -gt 200 ]; check $? "$1: $colors colours on screen"; }
keys() { for k in "$@"; do xdotool key "$k"; sleep 0.4; done; sleep 0.8; }

try() { # name, program
  local name=$1; shift
  local data="$run/data-$name"; setup "$data"
  env -i PATH=/usr/bin:/bin HOME="$run/home-$name" DISPLAY=$DISPLAY OORT_DATA="$data" OORT_LANGUAGE=fr APPIMAGE_EXTRACT_AND_RUN=1 dbus-run-session -- "$@" > "$out/$name.txt" 2>&1 & local pid=$!
  local window=""
  for _ in $(seq 60); do window=$(xdotool search --onlyvisible --name '^Oort NX$' 2>/dev/null | head -1); [ -n "$window" ] && break; sleep 0.5; done
  [ -n "$window" ]; check $? "$name: the window opens"
  [ -z "$window" ] && { cat "$out/$name.txt"; return; }
  xdotool windowsize "$window" 1440 900 windowfocus "$window"; sleep 5
  shot "$name-home"
  keys m; shot "$name-settings"; keys Escape
  # Broken Compass, then Harbour: the shelf by name starts with Projects and Add game.
  local at; at=$(python3 - "$data" "$run" <<'PY'
import json, subprocess, sys
r = subprocess.run(["/usr/bin/oort-core", "--data", sys.argv[1], "--resources", "/usr/lib/Oort NX", "--system", "linux"], input='{"id":1,"method":"library","params":{"tab":"All games","sort":"name"}}\n', capture_output=True, text=True)
print([g["name"] for g in json.loads(r.stdout)["result"]["games"]].index("Coast Runner") + 2)
PY
)
  keys Home; for _ in $(seq "$at"); do xdotool key Right; sleep 0.1; done; sleep 0.8; shot "$name-game"
  keys x; shot "$name-page"; keys Escape
  xdotool key Return; sleep 1; shot "$name-launch"; sleep 8
  xdotool search --onlyvisible --name '^Oort NX$' > /dev/null; check $? "$name: the window is back after the game"
  shot "$name-back"
  python3 - "$data" <<'PY'
import datetime, json, sys
s = json.load(open(sys.argv[1] + "/sessions.json"))
at = lambda k: datetime.datetime.fromisoformat(s[-1][k].replace("Z", "+00:00"))
length = (at("endedAt") - at("startedAt")).total_seconds()
print("session", length, "s")
assert 3 <= length <= 8, "the session lasts as long as the game its launcher started"
PY
  check $? "$name: a game is followed and its time kept"
  xdotool windowclose "$window" 2>/dev/null; sleep 3
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; pkill -x oort-desktop 2>/dev/null; sleep 1
  ! pgrep -x oort-core > /dev/null; check $? "$name: nothing is left running"
  ! grep -q 'GStreamer element .* not found' "$out/$name.txt"; check $? "$name: what plays the sounds is there"
  grep -v '^$' "$out/$name.txt" | tail -15
}
# The first steps, with an invented Steam where a Linux one is, its link opened by the desktop as any other.
first() {
  local data="$run/data-first" home="$run/home-first" pid window="" at
  mkdir -p "$home/.local/share/applications" "$home/.config"; ln -sfn "$run/Steam" "$home/.local/share/Steam"
  printf '[Desktop Entry]\nType=Application\nName=Invented Steam\nExec=%s %%u\nMimeType=x-scheme-handler/steam;\n' "$run/steam.sh" > "$home/.local/share/applications/invented-steam.desktop"
  printf '[Default Applications]\nx-scheme-handler/steam=invented-steam.desktop\n' > "$home/.config/mimeapps.list"
  env -i PATH=/usr/bin:/bin HOME="$home" DISPLAY=$DISPLAY OORT_DATA="$data" OORT_LANGUAGE=fr dbus-run-session -- $app > "$out/first.txt" 2>&1 & pid=$!
  for _ in $(seq 60); do window=$(xdotool search --onlyvisible --name '^Oort NX$' 2>/dev/null | head -1); [ -n "$window" ] && break; sleep 0.5; done
  [ -n "$window" ]; check $? "first: the window opens"; [ -z "$window" ] && return
  xdotool windowsize "$window" 1440 900 windowfocus "$window"; sleep 5; shot first-1-welcome
  keys Return; shot first-2-controller; keys Return; sleep 2; shot first-3-games; keys Return; shot first-4-online; keys Return; shot first-5-done; keys Return; sleep 1; shot first-6-library
  python3 -c "import json,sys; c=json.load(open(sys.argv[1]+'/choices.json')); print(c); assert c['steam'] is True and c['online'] is False and c['guideDone'] is True" "$data"; check $? "first: the steps are kept: Steam on, nothing online"
  at=$(python3 - "$data" "$home" <<'PY'
import json, subprocess, sys
r = subprocess.run(["/usr/bin/oort-core", "--data", sys.argv[1], "--resources", "/usr/lib/Oort NX", "--system", "linux", "--home", sys.argv[2]], input='{"id":1,"method":"library","params":{"tab":"All games"}}\n', capture_output=True, text=True)
names = [g["name"] for g in json.loads(r.stdout)["result"]["games"]]
print(names, file=sys.stderr); print(names.index("Quiet Harbour") + 2)
PY
)
  keys Home; for _ in $(seq "$at"); do xdotool key Right; sleep 0.1; done; sleep 0.8; shot first-7-steam-game
  xdotool key Return; sleep 1.2; shot first-8-waiting; sleep 22
  python3 - "$data" <<'PY'
import datetime, json, sys
s = json.load(open(sys.argv[1] + "/sessions.json"))
at = lambda k: datetime.datetime.fromisoformat(s[-1][k].replace("Z", "+00:00"))
length = (at("endedAt") - at("startedAt")).total_seconds()
print("session", length, "s")
assert len(s) == 1 and 3 <= length <= 9, "the session lasts as long as the game Steam started"
PY
  check $? "first: a game started through Steam is followed"
  xdotool search --onlyvisible --name '^Oort NX$' > /dev/null; check $? "first: the window is back"; shot first-9-back
  xdotool windowclose "$window" 2>/dev/null; sleep 3; kill $pid 2>/dev/null; wait $pid 2>/dev/null; pkill -x oort-desktop 2>/dev/null; sleep 1
}
first
try deb $app
chmod +x "$image"; try appimage "$image"
sudo apt-get remove -y oort-nx > /dev/null; test ! -e $app; check $? "the .deb is removed"
test -f "$run/data-deb/library.json"; check $? "the player's library is left"
kill $xvfb
echo "$failures failures"; [ $failures = 0 ]
