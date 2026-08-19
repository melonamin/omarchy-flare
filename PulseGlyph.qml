import QtQuick
import QtQuick.Shapes
import "FlareModel.js" as FlareModel

// Flare's mark: a ring, a center dot, and a faint outer echo -- the pulse
// itself shrunk to icon size. Drawn rather than taken from a font so there is
// no glyph coverage to depend on.
Shape {
  id: root

  property color color: "#ffffff"
  // Drives the geometry AND the item's size. Deriving `unit` from width
  // instead loops: the Shape's implicit size comes from the paths, which come
  // from the unit.
  property real size: 16

  preferredRendererType: Shape.CurveRenderer

  implicitWidth: size
  implicitHeight: size

  readonly property real unit: size
  readonly property real mid: unit / 2

  function ring(fraction) {
    var points = FlareModel.outline("circle", root.unit * fraction, root.mid, root.mid)
    points.push(points[0])
    return points
  }

  ShapePath {
    strokeColor: root.color
    strokeWidth: Math.max(1, root.unit * 0.06)
    fillColor: "transparent"
    joinStyle: ShapePath.RoundJoin
    PathPolyline { path: root.ring(0.88) }
  }

  ShapePath {
    strokeColor: root.color
    strokeWidth: Math.max(1, root.unit * 0.09)
    fillColor: "transparent"
    joinStyle: ShapePath.RoundJoin
    PathPolyline { path: root.ring(0.52) }
  }

  ShapePath {
    strokeWidth: -1
    fillColor: root.color
    PathPolyline { path: root.ring(0.18) }
  }
}
