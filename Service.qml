import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "FlareModel.js" as FlareModel

// Flare's shared state: settings, appearance, the click transport, and the
// master switch. The panel renders from it and the bar widget toggles it, so
// neither has to know the other exists.
Item {
  id: root

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "melonamin.flare"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"

  // Raised for every interaction that should be drawn, carrying the shape
  // resolved for that button. The panel listens.
  signal pulseRequested(string kind, real x, real y, string shape)

  property var settings: FlareModel.settingsFrom(null)

  // Master switch. Persisted as `enabled` on this plugin's shell.json entry,
  // so it survives a shell restart.
  //
  // Presentation mode implies it: a mode that swallows every click while
  // drawing nothing is worse than useless. This is deliberately not a write to
  // `enabled` -- the saved preference is left alone and simply overridden for
  // as long as the mode is on, so exiting restores it with nothing to undo.
  readonly property bool active: presenting || settings.enabled !== false

  // "auto" follows the current Omarchy theme accent, the way the macOS build
  // follows the system accent color.
  readonly property color tint: {
    var named = FlareModel.TINTS[settings.tint]
    return named ? named : Color.accent
  }

  readonly property real pulseSize: settings.size
  readonly property real intensity: settings.intensity
  readonly property real duration: settings.speed

  readonly property var appearance: ({
    size: pulseSize,
    intensity: intensity,
    duration: duration,
    tint: tint,
    // Half the largest container, so a click just off a screen still renders
    // the part of its pulse that spills onto it.
    reach: FlareModel.containerFor("primary-press", pulseSize,
      FlareModel.strokeFor(pulseSize, intensity)) / 2
  })

  // Rolling tally per interaction, so `flare status` can show that capture is
  // actually live the way the macOS build's status line does (§5.4).
  property var counts: ({})

  // Presentation mode: clicks still highlight, but Hyprland stops forwarding
  // them, so nothing underneath reacts. Deliberately not persisted -- it is a
  // mode you are in, not a preference, and a restart should never leave you
  // unable to click.
  property bool presenting: false

  function toggle() {
    var next = !active
    if (!write("enabled", next)) return active
    // Flip the local copy too: `settings` otherwise only updates after the
    // shell.json round trip, so a second toggle inside that window would read
    // this one's stale state and undo it. The reload confirms the same value.
    var updated = {}
    for (var key in settings) updated[key] = settings[key]
    updated.enabled = next
    settings = updated
    return next
  }

  function emit(kind, globalX, globalY) {
    if (!active) return
    if (FlareModel.KINDS.indexOf(kind) === -1) {
      console.warn("flare: unknown interaction '" + kind + "'")
      return
    }
    // A button set to "none" -- or a release with the echo switched off --
    // resolves to no shape and draws nothing (§5.4).
    var shape = FlareModel.shapeForKind(settings, kind)
    if (!shape) return

    var next = {}
    for (var key in counts) next[key] = counts[key]
    next[kind] = (next[kind] || 0) + 1
    counts = next

    pulseRequested(kind, globalX, globalY, shape)
  }

  // ---------------------------------------------------------- persistence

  // Settings live inline on this plugin's entry in shell.json, which the shell
  // owns; going through its mutator keeps writes atomic and picked up by the
  // same reload path a hand edit would take. Returns whether the write was
  // handed off, so callers do not report a change that never happened.
  function write(key, value) {
    if (!shell || typeof shell.mutateShellConfig !== "function") {
      console.warn("flare: no shell config mutator available")
      return false
    }
    shell.mutateShellConfig(function(config) {
      FlareModel.writeEntry(config, root.pluginId, key, value)
    })
    return true
  }

  function reset() {
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    shell.mutateShellConfig(function(config) {
      FlareModel.resetEntries(config, root.pluginId)
    })
  }

  // ----------------------------------------------------------- settings

  FileView {
    path: root.configPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.settings = FlareModel.settingsFrom(null)
  }

  // Entry lookup lives in FlareModel so the node suite can cover it; the
  // model file documents how bar and plugins[] entries interact.
  function findEntry(parsed) {
    var all = FlareModel.findEntries(parsed, root.pluginId)
    return all.length > 0 ? all[0] : null
  }

  function applyConfig(raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (error) {
      console.warn("flare: could not parse shell.json:", error)
      return
    }
    root.settings = FlareModel.settingsFrom(findEntry(parsed))
  }

  // ------------------------------------------------------- compositor half

  // Wayland lets no client observe input it does not have focus for, so the
  // binds have to live in Hyprland. Rather than have the user paste a require
  // into hyprland.lua, the plugin loads its own Lua through `hyprctl eval`.
  // Nothing outside this directory is ever written.
  readonly property string sourceDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : ""
  readonly property string luaPath: sourceDir ? sourceDir + "/hypr/flare.lua" : ""

  property bool bindsInstalled: false

  function installBinds(afterReload) {
    if (!luaPath) {
      console.warn("flare: no plugin source dir; cannot install the Hyprland binds")
      return
    }
    // A request that lands while an eval is in flight is queued, not dropped:
    // it means a reload just wiped whatever the running eval installed.
    if (binder.running) {
      binder.queued = true
      if (afterReload) binder.queuedStale = true
      return
    }
    // Loading the file only defines things; install() registers the binds and
    // is guarded, so re-running it is safe.
    binder.command = ["hyprctl", "eval",
      "dofile('" + luaPath.replace(/'/g, "\\'") + "'); "
      + "flare.install('" + String(settings.shortcut).replace(/'/g, "") + "', "
      + (afterReload ? "true" : "false") + ")"]
    binder.running = true
  }

  // Nothing compositor-side changes: the binds stay exactly as they are and an
  // input-accepting surface goes on top instead.
  function setPresenting(on) {
    presenting = on
  }

  function togglePresenting() { setPresenting(!presenting) }

  // Hyprland refuses a keybind whose key+modifier another bind already owns,
  // and says nothing about it. Without this check a shortcut that collides
  // just never works, with no way to tell why.
  property bool shortcutRegistered: false

  Process {
    id: shortcutCheck
    command: ["sh", "-c", "hyprctl binds | grep -c 'Flare: presentation mode'"]
    stdout: StdioCollector {
      onStreamFinished: {
        var found = parseInt(String(text).trim(), 10) > 0
        root.shortcutRegistered = found
        if (!found && root.settings.shortcut !== "") {
          console.warn("flare: the shortcut '" + root.settings.shortcut
            + "' did not register -- another bind already owns that key."
            + " Pick a free one with the `shortcut` setting.")
        }
      }
    }
  }

  Process {
    id: binder
    property bool queued: false
    // Carried through the queue: a reload landing mid-eval is exactly the case
    // where the handles the next run would unbind are already freed.
    property bool queuedStale: false
    onExited: function(code) {
      root.bindsInstalled = (code === 0)
      if (code !== 0) console.warn("flare: hyprctl eval failed with", code)
      else if (!shortcutCheck.running) shortcutCheck.running = true
      if (queued) {
        queued = false
        var stale = queuedStale
        queuedStale = false
        root.installBinds(stale)
      }
    }
  }

  // Not Component.onCompleted: the service loader assigns `manifest` after
  // construction, so the source dir is still empty at that point.
  onLuaPathChanged: if (luaPath) installBinds()

  // A config reload drops every bind Hyprland holds, including ours, and Lua
  // event handlers registered by the eval do not survive it either -- so the
  // shell, which does survive, is what puts them back.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") reinstall.restart()
    }
  }

  Timer {
    id: reinstall
    interval: 400
    // A reload wiped the binds, so the "already loaded" guard inside the Lua
    // has to be cleared before it will register them again.
    onTriggered: root.installBinds(true)
  }

  // ---------------------------------------------------------- transport

  // The Hyprland binds prefer a FIFO over shelling out per event. Draining it
  // here costs one persistent `cat` instead of a `qs ipc` startup per pulse,
  // which is what makes a 30 Hz drag trail affordable.
  //
  // The FIFO lives in XDG_RUNTIME_DIR because that directory is private to
  // this user. With it unset the only candidates are world-writable, where
  // anyone could pre-create the paths, so the fast path is skipped entirely
  // and every event arrives through IPC instead.
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string fifoPath: runtimeDir ? runtimeDir + "/flare.fifo" : ""
  readonly property string ackPath: runtimeDir ? runtimeDir + "/flare.ack" : ""

  // Counted per transport rather than inferred by subtraction: `consumed`
  // ticks before emit() decides whether to draw, so a difference against the
  // drawn totals means "filtered", not "arrived by IPC".
  property int consumed: 0
  property int viaIpc: 0

  Process {
    id: reader
    property bool retiring: false
    running: root.fifoPath !== ""
    // Hold a write end open on fd 3 as well as reading it, so `cat` never
    // sees EOF when the Lua side closes and reopens. Looping `cat` instead
    // drops whatever is written during the reopen gap.
    //
    // Bail out unless the path really is a FIFO: mkfifo fails silently when
    // something else already sits there, and reading a regular file would
    // deliver its contents as events. The path rides in as a positional
    // argument rather than being spliced into the script, so no character in
    // it can escape the quoting.
    command: ["sh", "-c",
      'mkfifo -m 600 "$1" 2>/dev/null; ' +
      '[ -p "$1" ] || exit 1; ' +
      'exec 3<> "$1"; exec cat <&3',
      "flare-fifo", root.fifoPath]

    stdout: SplitParser {
      onRead: line => root.route(line, true)
    }

    // The `running` binding points at a value that never changes, so a
    // one-shot failure (mkfifo race, something else squatting on the path)
    // would otherwise kill the fast path until a shell restart. Say why, and
    // keep retrying so removing the obstruction is enough to recover.
    onExited: function(code) {
      if (retiring) return
      console.warn("flare: FIFO reader exited with", code,
        "- is something other than a FIFO at " + root.fifoPath + "?")
      readerRetry.restart()
    }

    // Every plugin reload builds a fresh Service. Without this the previous
    // reader survives as an orphan and competes with the new one for the same
    // FIFO, so events go missing at random. `retiring` keeps that deliberate
    // stop from logging and scheduling a retry on a dying object.
    Component.onDestruction: { retiring = true; running = false }
  }

  Timer {
    id: readerRetry
    interval: 5000
    // Doubling toward a minute keeps a persistent obstruction from turning
    // into a warning every five seconds for the rest of the session.
    onTriggered: {
      interval = Math.min(interval * 2, 60000)
      reader.running = true
    }
  }

  // Routes one line from either transport; `viaFifoTransport` picks which
  // tally a pulse lands in, so the status counters keep telling the transports
  // apart. Control messages belong to neither tally.
  function route(line, viaFifoTransport) {
    var text = String(line).trim()

    // Control messages from the Lua binds, distinguished from pulses by a
    // leading "!" so they can never be mistaken for an interaction name.
    if (text.charAt(0) === "!") {
      if (text === "!toggle") togglePresenting()
      else if (text === "!exit") setPresenting(false)
      return
    }

    var parts = text.split(/\s+/)
    if (parts.length !== 3) return
    var px = parseFloat(parts[1])
    var py = parseFloat(parts[2])
    if (isNaN(px) || isNaN(py)) return
    if (viaFifoTransport) consumed++
    else viaIpc++
    emit(parts[0], px, py)
  }

  // Liveness stamp for the Lua side. Gated on the reader process itself, not
  // just this event loop: a dead reader with a live heartbeat would keep the
  // compositor writing into a pipe nobody drains -- exactly the blocking the
  // ack exists to prevent.
  FileView {
    id: ackFile
    path: root.ackPath
    // Write-only: without this the view preloads the (usually absent) file at
    // startup and logs a spurious read failure.
    preload: false
    blockAllReads: true
    atomicWrites: false
  }

  Timer {
    running: root.ackPath !== "" && reader.running
    repeat: true
    interval: 1000
    triggeredOnStart: true
    property int tick: 0
    onTriggered: {
      tick++
      ackFile.setText(String(tick) + "\n")
    }
  }

  // ---------------------------------------------------------------- ipc

  IpcHandler {
    target: "flare"

    // Called by the Hyprland mouse binds when the FIFO is unavailable.
    // Coordinates are Hyprland layout coordinates, which is also what
    // Quickshell reports for each screen's origin.
    function pulse(kind: string, x: string, y: string): string {
      var px = parseFloat(x)
      var py = parseFloat(y)
      if (isNaN(px) || isNaN(py)) return "bad coordinates"
      root.viaIpc++
      root.emit(kind, px, py)
      return "ok"
    }

    function toggle(): string {
      return root.toggle() ? "on" : "off"
    }

    // The Lua fallback path routes everything through here when the FIFO is
    // unavailable: pulses (tallied as IPC) and control messages alike.
    function event(line: string): string {
      root.route(line, false)
      return "ok"
    }

    function present(state: string): string {
      if (state === "on") root.setPresenting(true)
      else if (state === "off") root.setPresenting(false)
      else root.togglePresenting()
      return root.presenting ? "on" : "off"
    }

    function status(): string {
      return JSON.stringify({
        enabled: root.active,
        presenting: root.presenting,
        size: root.pulseSize,
        shapes: {
          primary: root.settings.primary, secondary: root.settings.secondary,
          middle: root.settings.middle, drag: root.settings.drag
        },
        tint: String(root.tint),
        binds: root.bindsInstalled,
        shortcut: root.settings.shortcut,
        shortcutRegistered: root.shortcutRegistered,
        viaFifo: root.consumed,
        viaIpc: root.viaIpc,
        counts: root.counts
      })
    }

    function ping(): string { return "ok" }
  }
}
