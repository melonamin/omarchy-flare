#!/usr/bin/env bash
# Checks a running install end to end: the shell half answers, the compositor
# half is registered, and an event sent down the FIFO comes out as a drawn
# pulse. Draws a few highlights on screen; changes no settings.
#
# Usage: tests/integration.sh
set -euo pipefail

fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; exit 1; }
pass() { printf '\033[1;32mok\033[0m   %s\n' "$1"; }
skip() { printf '\033[1;33mskip\033[0m %s\n' "$1"; }

command -v omarchy-shell >/dev/null || fail "omarchy-shell not found"
command -v hyprctl >/dev/null || fail "hyprctl not found"

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

# Count flare's own binds -- unmodified, non-consuming, on the three mouse
# buttons -- rather than every non-consuming bind, so somebody else's binds
# cannot make this pass while ours are missing.
# `|| true` keeps a failing hyprctl (or empty output feeding json.load) from
# tripping errexit/pipefail into a raw traceback; the count check below turns
# it into a readable failure instead.
binds=$(hyprctl -j binds 2>/dev/null | python3 -c "
import sys, json
print(sum(1 for b in json.load(sys.stdin)
          if b.get('non_consuming') and b.get('modmask') == 0
          and b.get('key') in ('mouse:272', 'mouse:273', 'mouse:274')))" 2>/dev/null || true)
[[ ${binds:-0} -ge 6 ]] || fail "expected 6 non-consuming flare mouse binds, found ${binds:-0}"
pass "$binds non-consuming mouse binds registered"

# --- transport --------------------------------------------------------------

# With XDG_RUNTIME_DIR unset both halves deliberately skip the FIFO (the only
# candidate paths are world-writable) and route every event through IPC, so
# that degraded mode is exercised instead of failed.
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
  FIFO="$XDG_RUNTIME_DIR/flare.fifo"
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
else
  skip "XDG_RUNTIME_DIR unset; the FIFO fast path is deliberately off"

  before=$(field "['viaIpc']")
  # `event` is the canonical fallback the Lua side uses; each line is either
  # "<kind> <x> <y>" or a "!"-prefixed control word.
  for i in 1 2 3; do omarchy-shell flare event "primary-press 400 400" >/dev/null; done
  sleep 0.8
  after=$(field "['viaIpc']")

  (( after >= before + 3 )) || fail "sent 3 events, IPC tally went $before -> $after"
  pass "IPC delivered 3 events ($before -> $after)"
fi

drawn=$(field "['counts'].get('primary-press', 0)")
(( drawn > 0 )) || fail "events arrived but nothing was drawn"
pass "pulses drawn (primary-press total: $drawn)"

printf '\n\033[1;32mall good\033[0m\n'
