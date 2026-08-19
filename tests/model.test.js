const test = require("node:test")
const assert = require("node:assert")

// The model builds Qt values; QML supplies Qt, node does not.
global.Qt = {
  point: (x, y) => ({ x: x, y: y }),
  rgba: (r, g, b, a) => ({ r: r, g: g, b: b, a: a })
}
const M = require("../FlareModel.js")

test("defaults tell the three buttons apart on sight", () => {
  assert.equal(M.DEFAULTS.primary, "circle")
  assert.equal(M.DEFAULTS.secondary, "square")
  assert.equal(M.DEFAULTS.middle, "diamond")
  assert.equal(M.DEFAULTS.drag, "circle")
  // The release echo doubles every click; off unless asked for.
  assert.equal(M.DEFAULTS.releases, false)
})

test("an absent or junk entry falls back to the defaults", () => {
  for (const entry of [null, undefined, "nonsense", 42, []]) {
    const s = M.settingsFrom(entry)
    assert.equal(s.size, 64)
    assert.equal(s.primary, "circle")
  }
})

// `omarchy bar set` writes strings unless --json is passed. This is the bug
// that made every value silently revert to its default.
test("numeric strings from `omarchy bar set` are honoured", () => {
  assert.equal(M.settingsFrom({ size: "120" }).size, 120)
  assert.equal(M.settingsFrom({ speed: "0.9" }).speed, 0.9)
  assert.equal(M.settingsFrom({ intensity: "1.25" }).intensity, 1.25)
})

test("boolean strings are honoured, and \"false\" is not truthy", () => {
  assert.equal(M.settingsFrom({ enabled: "false" }).enabled, false)
  assert.equal(M.settingsFrom({ enabled: "true" }).enabled, true)
  assert.equal(M.settingsFrom({ releases: "true" }).releases, true)
  assert.equal(M.settingsFrom({ enabled: false }).enabled, false)
})

test("out-of-range numbers clamp instead of drawing nonsense", () => {
  assert.equal(M.settingsFrom({ size: 9999 }).size, M.SIZE_MAX)
  assert.equal(M.settingsFrom({ size: -5 }).size, M.SIZE_MIN)
  assert.equal(M.settingsFrom({ speed: 99 }).speed, M.SPEED_MAX)
})

test("the pre-numeric preset names still parse", () => {
  assert.equal(M.settingsFrom({ size: "large" }).size, 88)
  assert.equal(M.settingsFrom({ speed: "snappy" }).speed, 0.28)
  assert.equal(M.settingsFrom({ intensity: "beacon" }).intensity, 1.35)
  // ...as does the single global `shape` key that predates per-button shapes.
  const s = M.settingsFrom({ shape: "star" })
  assert.equal(s.primary, "star")
  assert.equal(s.middle, "star")
})

test("a per-button shape overrides the legacy global one", () => {
  const s = M.settingsFrom({ shape: "star", middle: "triangle" })
  assert.equal(s.primary, "star")
  assert.equal(s.middle, "triangle")
})

test("\"none\" switches a button off; releases follow their own flag", () => {
  const off = M.settingsFrom({ secondary: "none" })
  assert.equal(M.shapeForKind(off, "secondary-press"), null)
  assert.equal(M.shapeForKind(off, "primary-press"), "circle")

  const echoes = M.settingsFrom({ releases: true })
  assert.equal(M.shapeForKind(echoes, "primary-release"), "circle")
  const quiet = M.settingsFrom({ releases: false })
  assert.equal(M.shapeForKind(quiet, "primary-release"), null)
})

test("every interaction maps to a button", () => {
  assert.equal(M.buttonOf("primary-press"), "primary")
  assert.equal(M.buttonOf("secondary-release"), "secondary")
  assert.equal(M.buttonOf("middle-press"), "middle")
  assert.equal(M.buttonOf("drag"), "drag")
  for (const kind of M.KINDS) {
    assert.ok(M.BUTTONS.includes(M.buttonOf(kind)), kind)
  }
})

test("press and release are told apart, and drag is neither", () => {
  assert.ok(M.isPress("middle-press") && !M.isRelease("middle-press"))
  assert.ok(M.isRelease("primary-release") && !M.isPress("primary-release"))
  assert.ok(!M.isPress("drag") && !M.isRelease("drag"))
})

test("secondary and middle stay distinguishable by shape, not colour", () => {
  assert.ok(M.hasCrosshair("secondary-press") && M.hasCrosshair("middle-press"))
  assert.ok(!M.hasCrosshair("primary-press") && !M.hasCrosshair("drag"))
  // A "+" for secondary, the same arms turned into an "x" for middle.
  assert.equal(M.crosshairRotation("secondary-press"), 0)
  assert.equal(M.crosshairRotation("middle-press"), 45)
})

test("a release is shorter than its press, and a drag dot is capped", () => {
  assert.ok(M.lifetimeFor("primary-release", 1.0) < M.lifetimeFor("primary-press", 1.0))
  assert.ok(M.lifetimeFor("drag", 1.0) <= 0.38)
})

test("stroke stays visible at the smallest size and never hits zero", () => {
  for (const size of [M.SIZE_MIN, 64, M.SIZE_MAX]) {
    for (const intensity of [M.INTENSITY_MIN, 1.0, M.INTENSITY_MAX]) {
      assert.ok(M.strokeFor(size, intensity) >= 2, `${size}/${intensity}`)
    }
  }
})

test("the container holds the widest element a pulse can draw", () => {
  const size = 120, stroke = M.strokeFor(size, 1.0)
  // The glow peaks at 1.3x the pulse size and has to fit.
  assert.ok(M.containerFor("primary-press", size, stroke) >= size * 1.3)
})

test("every shape is a closed outline inscribed in its diameter", () => {
  for (const shape of M.SHAPES) {
    const pts = M.outline(shape, 100, 50, 50)
    assert.ok(pts.length >= 3, shape)
    for (const p of pts) {
      const r = Math.hypot(p.x - 50, p.y - 50)
      assert.ok(r <= 50.001, `${shape} vertex escapes the circle: ${r}`)
    }
    // A star's valleys sit inside; every other shape rides the circle.
    const outer = pts.filter(p => Math.abs(Math.hypot(p.x - 50, p.y - 50) - 50) < 0.001)
    assert.ok(outer.length >= 3, `${shape} has too few vertices on the circle`)
  }
})

test("polygons point up rather than sideways", () => {
  // Qt's y axis grows downward, so the top vertex is the smallest y.
  const tri = M.outline("triangle", 100, 50, 50)
  const top = tri.reduce((a, b) => (a.y <= b.y ? a : b))
  assert.ok(Math.abs(top.x - 50) < 0.001, "apex should sit on the centre line")
})

test("lightening moves toward white and keeps alpha", () => {
  const c = M.lightened({ r: 0.2, g: 0.4, b: 0.6, a: 1 }, 0.5)
  assert.ok(c.r > 0.2 && c.g > 0.4 && c.b > 0.6)
  assert.equal(c.a, 1)
})

test("every tint option resolves, and auto defers to the theme", () => {
  for (const name of M.TINT_OPTIONS) {
    assert.ok(name in M.TINTS, name)
  }
  assert.equal(M.TINTS.auto, null)
  assert.equal(M.settingsFrom({ tint: "purple" }).tint, "purple")
  assert.equal(M.settingsFrom({ tint: "chartreuse" }).tint, "auto")
})
