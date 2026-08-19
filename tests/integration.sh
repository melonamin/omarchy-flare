#!/usr/bin/env bash
# Checks a running install end to end: the shell half answers, the compositor
# half is registered, and an event sent down the FIFO comes out as a drawn
# pulse. Draws a few highlights on screen; changes no settings.
#
# Usage: tests/integration.sh
set -euo pipefail

fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; exit 1; }
pass() { printf '\033[1;32mok\033[0m   %s\n' "$1"; }

command -v omarchy-shell >/dev/null || fail "omarchy-shell not found"

status() { omarchy-shell flare status 2>/dev/null; }
field() { status | python3 -c "import sys,json;print(json.load(sys.stdin)$1)"; }

# --- shell half -------------------------------------------------------------

[[ -n $(status) ]] || fail "the flare service is not answering (is the plugin enabled?)"
pass "service responds"

[[ $(field "['enabled']") == True ]] || fail "highlighting is switched off; enable it and re-run"
pass "highlighting enabled"

# --- compositor half --------------------------------------------------------

[[ $(field "['binds']") == True ]] || fail "the plugin did not load its Hyprland Lua"
pass "Lua loaded"

binds=$(hyprctl binds | grep -cE '^bindn|^bindrn' || true)
[[ $binds -ge 6 ]] || fail "expected 6 non-consuming mouse binds, found $binds"
pass "$binds non-consuming mouse binds registered"

# --- transport --------------------------------------------------------------

FIFO="${XDG_RUNTIME_DIR:-/run/user/$UID}/flare.fifo"
[[ -p $FIFO ]] || fail "no FIFO at $FIFO"
pass "FIFO present"

before=$(field "['viaFifo']")
# Hold it open the way the Lua side does, so the reader never sees EOF.
exec 9<> "$FIFO"
for i in 1 2 3; do printf 'primary-press 400 400\n' >&9; sleep 0.1; done
exec 9>&-
sleep 0.8
after=$(field "['viaFifo']")

(( after >= before + 3 )) || fail "sent 3 events, FIFO tally went $before -> $after"
pass "FIFO delivered 3 events ($before -> $after)"

drawn=$(field "['counts'].get('primary-press', 0)")
(( drawn > 0 )) || fail "events arrived but nothing was drawn"
pass "pulses drawn (primary-press total: $drawn)"

printf '\n\033[1;32mall good\033[0m\n'
