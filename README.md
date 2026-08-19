# Flare for Omarchy

Animated click highlights drawn over everything, so an audience can see *when*
and *where* you clicked during a demo or screen recording. This is the Omarchy
(Hyprland + Quickshell) port of [Flare for macOS](https://github.com/amebalabs/Flare).

## How it works

macOS lets Flare observe clicks with a `CGEventTap`. Wayland has no equivalent —
no client may observe input it does not have focus for — so the compositor does
the observing instead:

```
                    ┌─ loads hypr/flare.lua via `hyprctl eval` at startup,
                    │  and again whenever Hyprland reloads its config
                    ▼
click ──▶ Hyprland non-consuming mouse bind  (hypr/flare.lua)
             │  reads hl.get_cursor_pos() in-process
             ▼
          $XDG_RUNTIME_DIR/flare.fifo    (fallback: omarchy-shell flare pulse)
             │
             ▼
          Service.qml    state, settings, transport, master switch
             ├─▶ Flare.qml         one click-through overlay per display
             └─▶ SettingsPanel.qml bar button and settings popup
```

The plugin declares three kinds. `Service.qml` is the headless singleton the
other two read, so the renderer and the toggle never have to know about each
other -- the pattern omarchy documents for plugins that pair a panel with a
service.

The binds are **non-consuming**: Hyprland runs the dispatcher *and* delivers the
click to the window under the pointer, so highlighting never costs you a click.
No elevated permissions, no `input` group, no reading `/dev/input`.

The overlays are visual-only — `WlrLayer.Overlay` with an empty input region
(`mask: Region {}`) — and stay unmapped while idle so an always-on fullscreen
surface never stops the compositor handing a fullscreen client direct scanout.

## Install

```bash
omarchy plugin add https://github.com/melonamin/omarchy-flare.git
~/.config/omarchy/plugins/melonamin.flare/install.sh
```

The second line enables the plugin and puts its widget on the bar -- the two
things `omarchy plugin add` cannot do for a plugin that is a service, a panel,
and a bar widget at once.

Nothing outside `~/.config/omarchy` is written. Flare needs mouse binds inside
Hyprland, but rather than have you paste a `require` into `hyprland.lua`, the
plugin loads its own Lua with `hyprctl eval` when the shell starts, and again
whenever Hyprland reloads its config (a reload drops every bind). Remove the
plugin and nothing is left behind in your compositor config; the binds go on
the next reload.

Running `./install.sh` from a clone anywhere else works too, linking that
checkout into `~/.config/omarchy/plugins/melonamin.flare`.

## Settings

Click the bar widget to open the settings panel; right-click it to toggle
highlighting without opening anything. The panel header carries the master
switch and a reset-to-defaults button. Everything in the panel writes straight
to this plugin's entry in `~/.config/omarchy/shell.json`, which you can also
edit by hand -- it hot-reloads on save.

```json
{
  "plugins": [
    {
      "id": "melonamin.flare",
      "enabled": true,
      "primary": "circle",
      "secondary": "square",
      "middle": "diamond",
      "drag": "circle",
      "size": 64,
      "speed": 0.48,
      "intensity": 1.0,
      "tint": "auto"
    }
  ]
}
```

| Key | Values | Default |
|---|---|---|
| `enabled` | `true`, `false` | `true` |
| `primary` | `none`, `circle`, `square`, `diamond`, `triangle`, `star` | `circle` |
| `secondary` | as above | `square` |
| `middle` | as above | `diamond` |
| `drag` | as above | `circle` |
| `releases` | `true`, `false` -- the quieter contracting echo on button-up. Not in the panel; JSON only | `false` |
| `size` | 32-160, the peak ring diameter in px | `64` |
| `speed` | 0.16-1.20, pulse lifetime in seconds | `0.48` |
| `intensity` | 0.20-1.40; the soft glow appears at 0.70 and above | `1.0` |
| `tint` | `auto` (theme accent), `blue`, `purple`, `pink`, `red`, `orange`, `yellow`, `green`, `graphite` | `auto` |

Setting a button to `none` switches that button off -- there is no separate
enable flag per interaction.

The shape picker is a row of square cells, one per button. Each draws its
current outline with the same geometry the pulses use, and opens a strip of
the six choices when clicked.

Each interaction is distinguishable by shape and motion rather than color
(§5.2): a primary press expands a ring around a center dot, a release contracts
a lighter one, a secondary click adds a `+` crosshair, and a middle click turns
that crosshair 45 degrees into an `x`.

Numbers replaced the macOS four-step presets, but the old preset names
(`regular`, `normal`, `bright`, ...) and the old global `shape` key still parse,
so an entry written against an earlier version keeps the look it had.

## Commands

```bash
omarchy-shell flare status     # JSON: enabled, appearance, live counts, FIFO tally
omarchy-shell flare toggle     # session-scoped master switch (same as clicking the widget)
omarchy-shell flare pulse primary-press 1280 720   # draw one, for testing
```

The bar widget is the menu-bar item's counterpart: it draws a miniature of the
pulse itself (no font glyph to install) and clicking it toggles highlighting.

## Transport

Events reach the plugin over a FIFO at `$XDG_RUNTIME_DIR/flare.fifo`, with a
per-event shell-out to `omarchy-shell` as the fallback. Measured on a 5120x2880
@2x desktop:

| Path | Per event |
|---|---|
| FIFO | **0.017 ms** |
| `omarchy-shell` spawn | 18.8 ms |

That ~1100x gap is what makes a 30 Hz drag trail affordable; per-event process
spawns cost real CPU at that rate.

Writing to a FIFO blocks once its buffer fills, and the Lua binds run on the
compositor's thread, so a stalled reader must never be able to freeze Hyprland.
Two things prevent it:

- Lua opens the FIFO `"r+"` (`O_RDWR`). Measured: opens in 0.0 ms with no reader
  attached, and holding a read end means a write never raises `SIGPIPE`.
- The plugin stamps an advancing counter into `flare.ack` once a second **from
  its own event loop**, so the stamp stops the moment the plugin stops draining.
  Lua checks it every 100 writes and abandons the FIFO after 2 stale reads.

That bounds the unread backlog at 200 writes (~5.2 KB) against a measured 64 KB
(2,500 writes) before a write would block — a 12x margin. On fallback Lua retries
the FIFO every 20 events, so a shell restart heals itself.

## Screen sharing

Share the **whole screen**, not a window or a browser tab. Flare draws on its
own layer-shell surface, and only a full-output capture composites that in:

| What you share | Capture path | Flare visible |
|---|---|---|
| Entire screen / output | `zwlr_screencopy` over the composited output | yes |
| A single window | `hyprland_toplevel_export`, that window's own buffer | **no** |
| A browser tab | the browser renders the tab itself, no compositor involved | **no** |

This is how Wayland works rather than something the plugin can fix: one client
cannot draw into another client's buffer, so a window share can only ever
contain that window. Meet, Zoom, Discord and OBS window-capture all behave the
same way.

Screenshots are a different story -- a "window" screenshot from
`omarchy-capture-screenshot windows` is a *region of the output*, so Flare does
appear in those.

## Known limits

- **Pointer-locked clients** (games, some remote-desktop apps) grab the pointer,
  so binds may not fire there.
- **Extra mouse buttons** beyond primary/secondary/middle (`mouse:275`+) are not
  bound. Adding one is a line in `BUTTONS` in `hypr/flare.lua` plus a matching
  entry in `FlareModel.KINDS`.

## Troubleshooting

Hyprland Lua timers cannot be stopped once created, so the drag trail is a chain
of one-shots retired by a generation counter. If anything ever does get stuck,
`hyprctl reload` clears all Lua timers and re-registers the binds.

After editing the QML, `omarchy-shell shell rescanPlugins` usually suffices; a
`keepLoaded` panel sometimes keeps the old instance, in which case
`omarchy restart shell` picks up the change.

If clicks are not highlighting, check both halves:

```bash
omarchy-shell flare status              # "binds":true means the Lua loaded
hyprctl binds | grep -cE '^bindn|^bindrn'   # 6 = three buttons, press+release
```

`viaFifo` climbing as you click means events are arriving; `counts` staying
empty while it climbs means they are arriving but being filtered -- the master
switch is off, or that button is set to `none`.
