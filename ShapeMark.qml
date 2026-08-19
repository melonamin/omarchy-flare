import QtQuick
import QtQuick.Shapes
import "FlareModel.js" as FlareModel

// A single shape drawn as an outline, at icon scale. Uses the same geometry
// the pulses do, so the picker shows the actual outline rather than a glyph
// that happens to look like it -- and it cannot fall foul of font coverage
// the way the "star" token does.
Shape {
  id: root

  property string shape: "circle"
  property color color: "#ffffff"
  property real size: 18

  preferredRendererType: Shape.CurveRenderer
  antialiasing: true

  // Explicit, not implicit: a Shape derives its implicit size from the bounds
  // of its paths, so leaving it implicit makes the box hug the ink and the
  // mark lands off-centre in whatever cell holds it.
  width: size
  height: size

  readonly property real mid: size / 2

  // Fraction of the box the outline spans. Close to the edge so the mark stays
  // legible once the cells get small.
  readonly property real span: size * 0.86

  // "none" is a dash: an open two-point path rather than a closed outline.
  function marks() {
    if (shape === "none") {
      var arm = span * 0.36
      return [Qt.point(mid - arm, mid), Qt.point(mid + arm, mid)]
    }
    var points = FlareModel.outline(shape, span, mid, mid)
    points.push(points[0])
    return points
  }

  ShapePath {
    strokeColor: root.color
    strokeWidth: Math.max(1.25, root.size * 0.075)
    fillColor: "transparent"
    joinStyle: ShapePath.RoundJoin
    capStyle: ShapePath.RoundCap
    PathPolyline { path: root.marks() }
  }
}
