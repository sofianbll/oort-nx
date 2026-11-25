#!/bin/bash
# Runs the app's tests on one simulator and keeps its pictures, its accessibility report and its logs.
# usage: mobile/scripts/test_app.sh <work folder> <results folder> <device name> <iOS version> <fr|en> <dark|light> [still] [test,test]
# A test is a method of OortUITests, a "Class/method", or a whole class. With none, the whole of OortUITests runs.
# Both folders are outside the repository. "still" turns Reduce Motion on. Only invented games are used.
set -euo pipefail
export OORT_MOBILE=$(cd "$(dirname "$0")/.." && pwd)
work=${1:?the work folder} out=${2:?the results folder} device=${3:?a device} os=${4:?an iOS version} lang=${5:?fr or en} look=${6:?dark or light} still=${7:-} only=${8:-}
mkdir -p "$work" "$out/shots"; work=$(cd "$work" && pwd); out=$(cd "$out" && pwd)
xcodegen generate -q --spec "$OORT_MOBILE/UITests/project.yml" --project "$work" --project-root "$work"
[ "$(plutil -extract OortTrialMute raw -expect bool "$work/Gen/Info.plist")" = true ] ||
  { echo "Refusing to launch the app without its UI-test mute setting." >&2; exit 1; }
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name, version = sys.argv[1:]
runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + version.replace(".", "-")
print(next(d["udid"] for d in json.load(sys.stdin)["devices"][runtime] if d["name"] == name))' "$device" "$os")
xcrun simctl bootstatus "$udid" -b
xcrun simctl ui "$udid" appearance "$look"
xcrun simctl spawn "$udid" defaults write com.apple.Accessibility ReduceMotionEnabled -bool "$([ "$still" = still ] && echo YES || echo NO)"
tests=(); wanted=0
for one in ${only//,/ } ; do
  case "$one" in
    */*) tests+=("-only-testing:OortUITests/$one"); wanted=$((wanted + 1)) ;;
    test*) tests+=("-only-testing:OortUITests/OortUITests/$one"); wanted=$((wanted + 1)) ;;
    *) tests+=("-only-testing:OortUITests/$one"); wanted=$((wanted + $(grep -c "func test" "$OORT_MOBILE/UITests/$one.swift"))) ;;
  esac
done
if [ -z "$only" ]; then tests=("-only-testing:OortUITests/OortUITests"); wanted=$(grep -c "func test" "$OORT_MOBILE/UITests/OortUITests.swift"); fi
status=0
TEST_RUNNER_OORT_OUT="$out/shots" TEST_RUNNER_OORT_LANG="$lang" TEST_RUNNER_OORT_STILL="$still" \
  xcodebuild test -project "$work/OortNXTests.xcodeproj" -scheme OortUITests -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$work/dd-tests" -resultBundlePath "$work/tests-$lang-$look.xcresult" -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual "${tests[@]}" > "$out/xcodebuild.txt" 2>&1 || status=$?
grep -E "error:|Test Case .*(passed|failed)|Executed |TEST (FAILED|SUCCEEDED)" "$out/xcodebuild.txt" | sort -u | tail -80 || true
# What the app and the system said, to read where time went.
xcrun simctl spawn "$udid" log show --last 90m --style compact --predicate 'process == "Oort NX" AND NOT subsystem CONTAINS "xctest"' 2>/dev/null | gzip > "$out/app-log.gz" || true
# A test that did not run, or kept no picture, proves nothing.
passed=$(grep -cE "Test Case .* passed \(" "$out/xcodebuild.txt" || true)
[ "$passed" -eq "$wanted" ] || { echo "$passed tests passed of $wanted"; status=1; }
[ -n "$(ls "$out/shots")" ] || { echo "no picture was kept"; status=1; }
# A crash of the app, whatever the tests say.
crashes=$(find "$HOME/Library/Logs/DiagnosticReports" "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Logs" -name 'Oort NX*.ips' 2>/dev/null || true)
if [ -n "$crashes" ]; then echo "The app crashed:"; echo "$crashes"; mkdir -p "$out/crashes"; echo "$crashes" | while read -r one; do cp "$one" "$out/crashes/"; done; status=1; fi
exit "$status"
