#!/bin/bash
# End-to-end checks against the built apps.
#
# These exercise real behaviour — launching, holding assertions, releasing —
# rather than mocking it, because every bug worth catching here lives in the
# interaction with macOS rather than in our own logic.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APPS=(GazeFocus WakeHold AFK)

PASS=0
FAIL=0
FAILURES=()

pass() { PASS=$((PASS+1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); FAILURES+=("$1 — $2"); echo "  ✗ $1 — $2"; }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1" "${3:-failed}"; fi; }
suite() { echo ""; echo "$1"; }

# Record the crash-report baseline so new crashes during the run are visible.
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
crash_count() { ls "$CRASH_DIR" 2>/dev/null | grep -cE "^(GazeFocus|WakeHold|AFK)" || echo 0; }
CRASHES_BEFORE=$(crash_count)

# Leave the machine as we found it.
CLAMSHELL_BEFORE=$(pmset -g 2>/dev/null | grep -c "SleepDisabled.*1" || echo 0)

echo "Integration tests"
echo "================="

# ---------------------------------------------------------------- bundles
suite "Bundles"
for app in "${APPS[@]}"; do
  if [ -d "$DIST/$app.app" ]; then pass "$app.app exists"; else fail "$app.app exists" "missing"; continue; fi

  codesign --verify "$DIST/$app.app" 2>/dev/null
  check "$app signature is valid" $?

  ARCHS=$(lipo -archs "$DIST/$app.app/Contents/MacOS/$app" 2>/dev/null)
  if [[ "$ARCHS" == *"arm64"* && "$ARCHS" == *"x86_64"* ]]; then
    pass "$app is universal ($ARCHS)"
  else
    fail "$app is universal" "got '$ARCHS'"
  fi

  PLIST="$DIST/$app.app/Contents/Info.plist"
  UIELEMENT=$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$PLIST" 2>/dev/null)
  [ "$UIELEMENT" = "true" ] && pass "$app is menu-bar only" || fail "$app is menu-bar only" "LSUIElement=$UIELEMENT"

  MINOS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST" 2>/dev/null)
  [ "$MINOS" = "14.0" ] && pass "$app targets macOS 14" || fail "$app targets macOS 14" "got $MINOS"

  [ -f "$DIST/$app.app/Contents/Resources/AppIcon.icns" ] \
    && pass "$app has an icon" || fail "$app has an icon" "missing AppIcon.icns"
done

# GazeFocus is the only app that may declare camera use; the others must not.
CAM=$(/usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" "$DIST/GazeFocus.app/Contents/Info.plist" 2>/dev/null)
[ -n "$CAM" ] && pass "GazeFocus declares camera usage" || fail "GazeFocus declares camera usage" "absent"
for app in WakeHold AFK; do
  if /usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" "$DIST/$app.app/Contents/Info.plist" >/dev/null 2>&1; then
    fail "$app does not request the camera" "it declares camera usage"
  else
    pass "$app does not request the camera"
  fi
done

# ---------------------------------------------------------------- no network
suite "Network isolation"
for app in "${APPS[@]}"; do
  # The apps claim to be incapable of network access; confirm no entitlement
  # grants it rather than taking the claim on trust.
  ENTS=$(codesign -d --entitlements - --xml "$DIST/$app.app" 2>/dev/null | tr -d '\n')
  if echo "$ENTS" | grep -q "network.client\|network.server"; then
    fail "$app has no network entitlement" "network entitlement present"
  else
    pass "$app has no network entitlement"
  fi
done

# ---------------------------------------------------------------- diagnostics
suite "Diagnostics"
for app in "${APPS[@]}"; do
  OUT=$("$DIST/$app.app/Contents/MacOS/$app" --diagnose 2>&1)
  RC=$?
  check "$app --diagnose exits cleanly" $RC "exit $RC"
  [ -n "$OUT" ] && pass "$app --diagnose produces output" || fail "$app --diagnose produces output" "empty"
done

GF=$("$DIST/GazeFocus.app/Contents/MacOS/GazeFocus" --diagnose 2>&1)
echo "$GF" | grep -q "camera:" && pass "GazeFocus reports camera state" || fail "GazeFocus reports camera state" "absent"
echo "$GF" | grep -q "accessibility:" && pass "GazeFocus reports accessibility state" || fail "GazeFocus reports accessibility state" "absent"
echo "$GF" | grep -q "blocking reason:" && pass "GazeFocus reports guard state" || fail "GazeFocus reports guard state" "absent"

AF=$("$DIST/AFK.app/Contents/MacOS/AFK" --diagnose 2>&1)
echo "$AF" | grep -q "screen lock:" && pass "AFK reports lock capability" || fail "AFK reports lock capability" "absent"
echo "$AF" | grep -q "system call available" \
  && pass "AFK can use the system lock" \
  || fail "AFK can use the system lock" "falling back to the shortcut"

# ---------------------------------------------------------------- launch/quit
suite "Launch and quit"
for app in "${APPS[@]}"; do
  killall "$app" 2>/dev/null; sleep 1
  open "$DIST/$app.app"
  sleep 4
  if pgrep -x "$app" >/dev/null; then pass "$app launches"; else fail "$app launches" "not running"; continue; fi

  # A menu-bar app must not appear in the Dock or steal focus.
  ACTIVE=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
  [ "$ACTIVE" != "$app" ] && pass "$app does not steal focus" || fail "$app does not steal focus" "it is frontmost"

  # Idle CPU must be negligible; these run all day.
  sleep 3
  CPU=$(ps -o %cpu= -p "$(pgrep -x "$app" | head -1)" 2>/dev/null | tr -d ' ')
  if [ -n "$CPU" ] && awk "BEGIN{exit !($CPU < 25)}"; then
    pass "$app idles below 25% CPU (${CPU}%)"
  else
    fail "$app idles below 25% CPU" "got ${CPU}%"
  fi

  killall "$app" 2>/dev/null
  sleep 2
  pgrep -x "$app" >/dev/null && fail "$app quits" "still running" || pass "$app quits"

  # Quitting must never leave the Mac unable to sleep.
  if pmset -g assertions 2>/dev/null | grep -q "($app)"; then
    fail "$app releases assertions on quit" "assertion still held"
  else
    pass "$app releases assertions on quit"
  fi
done

# ---------------------------------------------------------------- restart churn
suite "Rapid restart"
for i in 1 2 3; do
  open "$DIST/WakeHold.app"; sleep 2; killall WakeHold 2>/dev/null; sleep 1
done
sleep 1
pgrep -x WakeHold >/dev/null && fail "survives rapid restarts" "still running" || pass "survives rapid restarts"
pmset -g assertions 2>/dev/null | grep -q "(WakeHold)" \
  && fail "no assertion leaked by restarts" "leaked" || pass "no assertion leaked by restarts"

# ---------------------------------------------------------------- WakeHold
suite "WakeHold — detection under load"
for i in 1 2 3; do yes > /dev/null & done
LOAD_PIDS=$(jobs -p)
sleep 1
OUT=$("$DIST/WakeHold.app/Contents/MacOS/WakeHold" --diagnose 2>&1)
kill $LOAD_PIDS 2>/dev/null; killall yes 2>/dev/null

echo "$OUT" | grep -q "Qualified" && pass "reports qualified apps" || fail "reports qualified apps" "section missing"
if echo "$OUT" | grep -A3 "Over threshold" | grep -q "yes"; then
  pass "detects synthetic CPU load"
else
  fail "detects synthetic CPU load" "the 'yes' processes were not seen"
fi
# A regression in the mach timebase conversion shows up as absurdly low CPU.
CPUVAL=$(echo "$OUT" | grep -oE "[0-9]+% CPU" | head -1 | grep -oE "[0-9]+")
if [ -n "$CPUVAL" ] && [ "$CPUVAL" -gt 50 ]; then
  pass "CPU figures are plausible (${CPUVAL}%)"
else
  fail "CPU figures are plausible" "top reading was ${CPUVAL:-none}% under 3x full load"
fi

# ---------------------------------------------------------------- AFK
suite "AFK — session lifecycle"
DRY=$("$DIST/AFK.app/Contents/MacOS/AFK" --dry-run 12 2>&1)
RC=$?
check "dry run exits cleanly" $RC "exit $RC"
echo "$DRY" | grep -q "armed:" && pass "arms a session" || fail "arms a session" "never armed"
echo "$DRY" | grep -q "assertion visible to system: AFK" \
  && pass "takes a real assertion" || fail "takes a real assertion" "none seen"
echo "$DRY" | grep -q "released cleanly" \
  && pass "releases on cancel" || fail "releases on cancel" "assertion still held"
echo "$DRY" | grep -q "report: ended because" \
  && pass "produces a session report" || fail "produces a session report" "no report"

sleep 1
pmset -g assertions 2>/dev/null | grep -q "(AFK)" \
  && fail "no assertion outlives the dry run" "leaked" || pass "no assertion outlives the dry run"

# ---------------------------------------------------------------- aftermath
suite "System left clean"
CLAMSHELL_AFTER=$(pmset -g 2>/dev/null | grep -c "SleepDisabled.*1" || echo 0)
[ "$CLAMSHELL_AFTER" = "$CLAMSHELL_BEFORE" ] \
  && pass "clamshell sleep setting unchanged" \
  || fail "clamshell sleep setting unchanged" "was $CLAMSHELL_BEFORE, now $CLAMSHELL_AFTER"

CRASHES_AFTER=$(crash_count)
[ "$CRASHES_AFTER" = "$CRASHES_BEFORE" ] \
  && pass "no crash reports generated" \
  || fail "no crash reports generated" "$((CRASHES_AFTER - CRASHES_BEFORE)) new"

for app in "${APPS[@]}"; do killall "$app" 2>/dev/null; done

echo ""
echo "────────────────────────────────────────────────────────────"
echo "$((PASS + FAIL)) checks · $PASS passed · $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "FAILURES:"
  for f in "${FAILURES[@]}"; do echo "  • $f"; done
  exit 1
fi
echo ""
echo "all green"
