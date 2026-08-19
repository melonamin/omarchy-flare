#!/usr/bin/env bash
# Enable Flare and put its widget on the bar.
#
# Nothing outside ~/.config/omarchy is touched. The Hyprland mouse binds are
# loaded by the plugin itself at runtime (see hypr/flare.lua), so there is no
# compositor config to edit and nothing left behind if the plugin is removed.

set -euo pipefail

PLUGIN_ID="melonamin.flare"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

say() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$1" >&2; }

command -v omarchy-shell >/dev/null || { warn "omarchy-shell not found — is this Omarchy?"; exit 1; }

# Running from a clone somewhere else: link it in. Running from inside the
# plugin directory (the `omarchy plugin add` case) there is nothing to do.
if [[ $SOURCE_DIR == "$PLUGIN_DIR" ]]; then
  say "already installed at $PLUGIN_DIR"
elif [[ -e $PLUGIN_DIR && ! -L $PLUGIN_DIR ]]; then
  warn "$PLUGIN_DIR exists and is not a symlink; leaving it alone"
else
  ln -sfn "$SOURCE_DIR" "$PLUGIN_DIR"
  say "linked $PLUGIN_DIR -> $SOURCE_DIR"
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || warn "could not reach omarchy-shell"
omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 || true

# `omarchy bar put` no-ops once the plugin is listed in plugins[], which
# enabling it for the service and panel kinds does, so place the widget here.
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
print("added the bar widget to the right section")
PYEOF

say "done — click somewhere to see a highlight"
