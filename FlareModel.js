// Appearance settings and pulse geometry, ported from the macOS build's
// Presets.swift and PulseFactory.swift so both platforms draw the same pulse.

// The buttons that can be highlighted independently. "drag" is the trail left
// while a button is held.
var BUTTONS = ["primary", "secondary", "middle", "drag"]

var BUTTON_LABELS = {
  primary: "Left", secondary: "Right", middle: "Middle", drag: "Drag"
}

// Shapes a pulse outline can take. "none" turns that button off entirely,
// which is why it lives in the picker list rather than the geometry list.
var SHAPES = ["circle", "square", "diamond", "triangle", "star"]
var SHAPE_OPTIONS = ["none"].concat(SHAPES)

var KINDS = [
  "primary-press", "primary-release",
  "secondary-press", "secondary-release",
  "middle-press", "middle-release",
  "drag"
]

// Bounds for the continuous controls. The macOS presets sit inside these:
// size 44/64/88/116, duration 0.28/0.48/0.72/1.00, intensity 0.28/0.70/1.00/1.35.
var SIZE_MIN = 32, SIZE_MAX = 160
var SPEED_MIN = 0.16, SPEED_MAX = 1.20
var INTENSITY_MIN = 0.20, INTENSITY_MAX = 1.40

// Named tints, mirroring the macOS accent palette. "auto" follows the theme.
var TINTS = {
  auto: null,
  blue: "#3478f6", purple: "#8944ab", pink: "#f74f9e", red: "#e0383e",
  orange: "#f7821b", yellow: "#ffc502", green: "#62ba46", graphite: "#8c8c8c"
}
var TINT_OPTIONS = ["auto", "blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"]

var DEFAULTS = {
  enabled: true,
  size: 64,
  speed: 0.48,
  intensity: 1.00,
  releases: false,
  tint: "auto",
  // Keybind that toggles presentation mode. Empty string registers nothing.
  // SUPER+ALT is the roomiest modifier set in a stock Omarchy: SUPER+SHIFT
  // already binds 26 keys, P among them (Google Photos).
  shortcut: "SUPER + ALT + P",
  primary: "circle",
  secondary: "square",
  middle: "diamond",
  drag: "circle"
}

// Older entries stored preset names rather than numbers; keep reading them so
// an existing shell.json does not silently snap back to the defaults.
var LEGACY_SIZES = { compact: 44, regular: 64, large: 88, veryLarge: 116 }
var LEGACY_SPEEDS = { snappy: 0.28, normal: 0.48, slow: 0.72, verySlow: 1.00 }
var LEGACY_INTENSITIES = { subtle: 0.28, medium: 0.70, bright: 1.00, beacon: 1.35 }

// Key spellings older entries used, kept beside the aliases settingsFrom
// honours. A reset must delete these too, or the stale key keeps overriding
// the default it aliases; add to this list whenever settingsFrom learns a new
// legacy spelling.
var LEGACY_KEYS = ["shape", "duration"]

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

// `omarchy bar set` writes every value as a string unless --json is used, so
// "120" has to mean 120 here or a perfectly good setting silently reverts.
function numberOr(value, legacy, fallback, low, high) {
  if (typeof value === "number" && !isNaN(value)) return clamp(value, low, high)
  if (typeof value === "string") {
    if (legacy[value] !== undefined) return legacy[value]
    var parsed = parseFloat(value)
    if (!isNaN(parsed)) return clamp(parsed, low, high)
  }
  return fallback
}

// Same reason: "false" arrives as a string and must not read as true.
// "1" and "0" are accepted because that is what people type at a prompt.
function boolOr(value, fallback) {
  if (typeof value === "boolean") return value
  if (typeof value === "string") {
    if (value === "true" || value === "1") return true
    if (value === "false" || value === "0") return false
  }
  return fallback
}

function shapeOr(value, fallback) {
  return SHAPE_OPTIONS.indexOf(value) !== -1 ? value : fallback
}

// Merge a shell.json plugin entry over the shipped defaults.
function settingsFrom(entry) {
  var out = {}
  for (var key in DEFAULTS) out[key] = DEFAULTS[key]
  if (!entry || typeof entry !== "object") return out

  if (entry.enabled !== undefined) out.enabled = boolOr(entry.enabled, DEFAULTS.enabled)
  if (entry.releases !== undefined) out.releases = boolOr(entry.releases, DEFAULTS.releases)
  if (typeof entry.tint === "string" && TINTS[entry.tint] !== undefined) out.tint = entry.tint
  if (typeof entry.shortcut === "string") out.shortcut = entry.shortcut

  out.size = numberOr(entry.size, LEGACY_SIZES, DEFAULTS.size, SIZE_MIN, SIZE_MAX)
  out.speed = numberOr(entry.speed !== undefined ? entry.speed : entry.duration,
    LEGACY_SPEEDS, DEFAULTS.speed, SPEED_MIN, SPEED_MAX)
  out.intensity = numberOr(entry.intensity, LEGACY_INTENSITIES,
    DEFAULTS.intensity, INTENSITY_MIN, INTENSITY_MAX)

  for (var i = 0; i < BUTTONS.length; i++) {
    var button = BUTTONS[i]
    // A single global `shape` was the old spelling; fall back to it so an
    // existing config keeps the look it had.
    var fallback = shapeOr(entry.shape, DEFAULTS[button])
    out[button] = shapeOr(entry[button], fallback)
  }
  return out
}

// -------------------------------------------------------------- entries

// A plugin that is a service, a panel and a bar widget at once can be
// recorded in either place: enabling a bar widget files it under
// bar.layout.<section>, while non-bar kinds live in plugins[]. Read both,
// bar entries first, and let the first entry win -- the bar one is what
// `omarchy bar set` edits.
function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function findEntries(parsed, pluginId) {
  var found = []
  var layout = parsed && parsed.bar ? parsed.bar.layout : null
  if (isPlainObject(layout)) {
    for (var section in layout) {
      var items = layout[section]
      if (!Array.isArray(items)) continue
      for (var i = 0; i < items.length; i++) {
        if (items[i] && items[i].id === pluginId) found.push(items[i])
      }
    }
  }
  var entries = parsed && Array.isArray(parsed.plugins) ? parsed.plugins : []
  for (var j = 0; j < entries.length; j++) {
    if (entries[j] && entries[j].id === pluginId) found.push(entries[j])
  }
  return found
}

// Written to every entry, not just the winning one: reads let the bar entry
// shadow the plugins[] one, so a stale value left on the loser would
// resurface the moment the widget is removed from the bar.
function writeEntry(config, pluginId, key, value) {
  var entries = findEntries(config, pluginId)
  if (entries.length === 0) {
    if (!Array.isArray(config.plugins)) config.plugins = []
    var created = { id: pluginId }
    created[key] = value
    config.plugins.push(created)
    return
  }
  for (var i = 0; i < entries.length; i++) entries[i][key] = value
}

// Deletes settings keys only: an entry may carry loader-owned keys (its id,
// bar placement options), which a reset must not touch.
function resetEntries(config, pluginId) {
  var entries = findEntries(config, pluginId)
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    for (var key in DEFAULTS) delete entry[key]
    for (var j = 0; j < LEGACY_KEYS.length; j++) delete entry[LEGACY_KEYS[j]]
  }
}

// ---------------------------------------------------------------- kinds

function isPress(kind) { return kind.slice(-6) === "-press" }
function isRelease(kind) { return kind.slice(-8) === "-release" }

// Secondary and middle both carry a crosshair; the middle one is turned 45
// degrees so the two stay distinguishable by shape rather than color (§5.2).
function hasCrosshair(kind) {
  return kind.indexOf("secondary-") === 0 || kind.indexOf("middle-") === 0
}

function crosshairRotation(kind) {
  return kind.indexOf("middle-") === 0 ? 45 : 0
}

function buttonOf(kind) {
  if (kind === "drag") return "drag"
  var cut = kind.lastIndexOf("-")
  return cut === -1 ? kind : kind.slice(0, cut)
}

// The shape this interaction should draw, or null when it is switched off.
function shapeForKind(settings, kind) {
  if (isRelease(kind) && !settings.releases) return null
  var shape = settings[buttonOf(kind)]
  return (!shape || shape === "none") ? null : shape
}

// ------------------------------------------------------------- geometry

// Stroke scales with both size and intensity (Appendix A).
function strokeFor(size, intensity) {
  return Math.max(2.0, size * 0.05 * (0.65 + 0.35 * Math.min(intensity, 1.35)))
}

// The soft glow only appears at higher intensities; lower intensities render
// as clean rings only (§5.3).
function showsGlow(intensity) {
  return intensity >= 0.70
}

// How long one pulse of `kind` lives, given the speed setting.
function lifetimeFor(kind, speed) {
  if (isRelease(kind)) return speed * 0.78
  if (kind === "drag") return Math.min(0.38, speed * 0.82)
  return speed
}

// Side of the square that holds the largest element (the glow at 1.3x size)
// plus stroke. Sublayers are centered within it.
function containerFor(kind, size, stroke) {
  if (kind === "drag") return size * 0.9
  return size * 1.5 + stroke * 2
}

// The outline of `shape` inscribed in a circle of `diameter`, as a flat list
// of points centered on (cx, cy). Every shape's vertices sit on that circle so
// the shapes share a consistent extent and the ring keeps its expand/contract
// feel.
//
// Unlike Core Graphics, Qt's y axis grows downward, so the sine term is
// negated to keep polygons point-up on screen.
function outline(shape, diameter, cx, cy) {
  var radius = diameter / 2
  var up = Math.PI / 2
  switch (shape) {
  case "square":   return polygon(4, radius, cx, cy, Math.PI / 4)
  case "diamond":  return polygon(4, radius, cx, cy, up)
  case "triangle": return polygon(3, radius, cx, cy, up)
  case "star":     return star(5, radius, radius * 0.42, cx, cy, up)
  default:         return polygon(64, radius, cx, cy, up)
  }
}

function polygon(sides, radius, cx, cy, rotation) {
  var points = []
  var step = (Math.PI * 2) / sides
  for (var i = 0; i < sides; i++) {
    var angle = rotation + i * step
    points.push(Qt.point(cx + Math.cos(angle) * radius, cy - Math.sin(angle) * radius))
  }
  return points
}

function star(tips, outerRadius, innerRadius, cx, cy, rotation) {
  var points = []
  var vertices = tips * 2
  var step = Math.PI / tips
  for (var i = 0; i < vertices; i++) {
    var radius = (i % 2 === 0) ? outerRadius : innerRadius
    var angle = rotation + i * step
    points.push(Qt.point(cx + Math.cos(angle) * radius, cy - Math.sin(angle) * radius))
  }
  return points
}

// Blends `color` toward white by `fraction` (0..1). A release is a lighter
// shade of the tint -- the quieter echo of its press (§5.2).
function lightened(color, fraction) {
  return Qt.rgba(
    color.r + (1.0 - color.r) * fraction,
    color.g + (1.0 - color.g) * fraction,
    color.b + (1.0 - color.b) * fraction,
    color.a)
}

function titleCase(text) {
  return String(text).charAt(0).toUpperCase() + String(text).slice(1)
}

// Exported for the node test suite. QML imports this file directly and never
// sees `module`, so the guard keeps both consumers happy.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    BUTTONS: BUTTONS, BUTTON_LABELS: BUTTON_LABELS,
    SHAPES: SHAPES, SHAPE_OPTIONS: SHAPE_OPTIONS, KINDS: KINDS,
    TINTS: TINTS, TINT_OPTIONS: TINT_OPTIONS, DEFAULTS: DEFAULTS,
    LEGACY_KEYS: LEGACY_KEYS,
    SIZE_MIN: SIZE_MIN, SIZE_MAX: SIZE_MAX,
    SPEED_MIN: SPEED_MIN, SPEED_MAX: SPEED_MAX,
    INTENSITY_MIN: INTENSITY_MIN, INTENSITY_MAX: INTENSITY_MAX,
    findEntries: findEntries, writeEntry: writeEntry, resetEntries: resetEntries,
    settingsFrom: settingsFrom, shapeForKind: shapeForKind, buttonOf: buttonOf,
    isPress: isPress, isRelease: isRelease,
    hasCrosshair: hasCrosshair, crosshairRotation: crosshairRotation,
    strokeFor: strokeFor, showsGlow: showsGlow,
    lifetimeFor: lifetimeFor, containerFor: containerFor,
    outline: outline, polygon: polygon, star: star,
    lightened: lightened, titleCase: titleCase
  }
}
