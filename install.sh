#!/usr/bin/env bash
# Install Flare's two halves: the shell plugin and the Hyprland mouse binds.
#
# The omarchy plugin installer deliberately never runs hooks or touches your
# Hyprland config, so the compositor-side binds are wired up here instead.

set -euo pipefail

PLUGIN_ID="melonamin.flare"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
HYPR_DIR="$HOME/.config/hypr"
HYPR_ENTRY="$HYPR_DIR/hyprland.lua"
REQUIRE_LINE='require("hypr.flare")'

say() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$1" >&2; }

[[ -d $HYPR_DIR ]] || { warn "no $HYPR_DIR — is this an Omarchy machine?"; exit 1; }

# --- shell plugin -----------------------------------------------------------

if [[ -e $PLUGIN_DIR && ! -L $PLUGIN_DIR ]]; then
  warn "$PLUGIN_DIR exists and is not a symlink; leaving it alone"
else
  ln -sfn "$SOURCE_DIR" "$PLUGIN_DIR"
  say "linked $PLUGIN_DIR -> $SOURCE_DIR"
fi

# --- hyprland binds ---------------------------------------------------------

cp "$SOURCE_DIR/hypr/flare.lua" "$HYPR_DIR/flare.lua"
say "installed $HYPR_DIR/flare.lua"

if grep -qF "$REQUIRE_LINE" "$HYPR_ENTRY"; then
  say "$HYPR_ENTRY already requires hypr.flare"
else
  cp "$HYPR_ENTRY" "$HYPR_ENTRY.flare.bak"
  printf '\n-- Flare click highlighting.\n%s\n' "$REQUIRE_LINE" >> "$HYPR_ENTRY"
  say "added $REQUIRE_LINE to $HYPR_ENTRY (backup at $HYPR_ENTRY.flare.bak)"
fi

# --- activate ---------------------------------------------------------------

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || warn "could not reach omarchy-shell"

if omarchy-shell -q shell listPlugins 2>/dev/null | grep -q "\"$PLUGIN_ID\""; then
  omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 || true
fi

# Place the bar widget. `omarchy bar put` no-ops when the plugin is already
# listed in plugins[] (which enabling it for the service/panel kinds does), so
# fall back to editing the layout directly.
python3 - "$PLUGIN_ID" <<'PYEOF'
import json, os, sys

plugin_id = sys.argv[1]
path = os.path.expanduser("~/.config/omarchy/shell.json")
with open(path) as handle:
    config = json.load(handle)

layout = config.setdefault("bar", {}).setdefault("layout", {})
if any(e.get("id") == plugin_id for items in layout.values() for e in items):
    print("bar widget already placed")
    raise SystemExit

section = layout.setdefault("right", [])
anchor = next((i for i, e in enumerate(section) if e.get("id") == "omarchy.power"), len(section))
section.insert(anchor, {"id": plugin_id})

with open(path, "w") as handle:
    json.dump(config, handle, indent=2)
print("added bar widget to the right section")
PYEOF

hyprctl reload >/dev/null
say "reloaded Hyprland"

say "done — click somewhere to see a highlight"
