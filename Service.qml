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

  // Session-scoped master switch. `enabled` in shell.json is the persisted
  // default; this is the runtime override the toggle flips.
  property bool runtimeEnabled: true
  readonly property bool active: runtimeEnabled && settings.enabled !== false

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

  function toggle() {
    var next = !active
    runtimeEnabled = true
    write("enabled", next)
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
  // same reload path a hand edit would take.
  function write(key, value) {
    if (!shell || typeof shell.mutateShellConfig !== "function") {
      console.warn("flare: no shell config mutator available")
      return
    }
    shell.mutateShellConfig(function(config) {
      var entry = root.findEntry(config)
      if (entry) { entry[key] = value; return }
      if (!Array.isArray(config.plugins)) config.plugins = []
      var created = { id: root.pluginId }
      created[key] = value
      config.plugins.push(created)
    })
  }

  function reset() {
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    shell.mutateShellConfig(function(config) {
      var entry = root.findEntry(config)
      if (!entry) return
      for (var key in entry) {
        if (key !== "id") delete entry[key]
      }
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

  // A plugin that is a service, a panel and a bar widget at once can be
  // recorded in either place: enabling a bar widget files it under
  // bar.layout.<section>, while non-bar kinds live in plugins[]. Read both, and
  // let the bar entry win -- that is the one `omarchy bar set` edits.
  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function findEntry(parsed) {
    var layout = parsed && parsed.bar ? parsed.bar.layout : null
    if (isPlainObject(layout)) {
      for (var section in layout) {
        var items = layout[section]
        if (!Array.isArray(items)) continue
        for (var i = 0; i < items.length; i++) {
          if (items[i] && items[i].id === root.pluginId) return items[i]
        }
      }
    }
    var entries = parsed && Array.isArray(parsed.plugins) ? parsed.plugins : []
    for (var j = 0; j < entries.length; j++) {
      if (entries[j] && entries[j].id === root.pluginId) return entries[j]
    }
    return null
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

  function installBinds(force) {
    if (!luaPath) {
      console.warn("flare: no plugin source dir; cannot install the Hyprland binds")
      return
    }
    if (binder.running) return
    var quoted = "dofile('" + luaPath.replace(/'/g, "\\'") + "')"
    binder.command = ["hyprctl", "eval",
      force ? "_G.__flare_loaded = nil; " + quoted : quoted]
    binder.running = true
  }

  Process {
    id: binder
    onExited: function(code) {
      root.bindsInstalled = (code === 0)
      if (code !== 0) console.warn("flare: hyprctl eval failed with", code)
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
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string fifoPath: runtimeDir + "/flare.fifo"
  readonly property string ackPath: runtimeDir + "/flare.ack"

  // Counted per transport rather than inferred by subtraction: `consumed`
  // ticks before emit() decides whether to draw, so a difference against the
  // drawn totals means "filtered", not "arrived by IPC".
  property int consumed: 0
  property int viaIpc: 0

  Process {
    running: true
    // Hold a write end open on fd 3 as well as reading it, so `cat` never
    // sees EOF when the Lua side closes and reopens. Looping `cat` instead
    // drops whatever is written during the reopen gap.
    command: ["sh", "-c",
      "mkfifo -m 600 '" + root.fifoPath + "' 2>/dev/null; " +
      "exec 3<> '" + root.fifoPath + "'; exec cat <&3"]

    stdout: SplitParser {
      onRead: line => root.consume(line)
    }

    // Every plugin reload builds a fresh Service. Without this the previous
    // reader survives as an orphan and competes with the new one for the same
    // FIFO, so events go missing at random.
    Component.onDestruction: running = false
  }

  function consume(line) {
    var parts = String(line).trim().split(/\s+/)
    if (parts.length !== 3) return
    var px = parseFloat(parts[1])
    var py = parseFloat(parts[2])
    if (isNaN(px) || isNaN(py)) return
    consumed++
    emit(parts[0], px, py)
  }

  // Liveness stamp for the Lua side. It ticks from this event loop, so it
  // stops the moment the plugin stops draining -- which is exactly when the
  // compositor must go back to the shell-out path rather than risk blocking
  // on a full pipe.
  FileView {
    id: ackFile
    path: root.ackPath
    blockAllReads: true
    atomicWrites: false
  }

  Timer {
    running: true
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

    function status(): string {
      return JSON.stringify({
        enabled: root.active,
        size: root.pulseSize,
        shapes: {
          primary: root.settings.primary, secondary: root.settings.secondary,
          middle: root.settings.middle, drag: root.settings.drag
        },
        tint: String(root.tint),
        binds: root.bindsInstalled,
        viaFifo: root.consumed,
        viaIpc: root.viaIpc,
        counts: root.counts
      })
    }

    function ping(): string { return "ok" }
  }
}
