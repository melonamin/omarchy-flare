import QtQuick
import QtQuick.Shapes
import "FlareModel.js" as FlareModel

// One self-animating pulse. Every element fades out over `lifetime` on a
// single eased `phase` driver, mirroring the CAAnimationGroup the macOS build
// puts on each layer (§5.2).
Item {
  id: root

  property string kind: "primary-press"
  property real pulseSize: 64
  property real intensity: 1.0
  property real duration: 0.48
  property string shape: "circle"
  property color tint: "#ffffff"

  signal finished()

  readonly property real stroke: FlareModel.strokeFor(pulseSize, intensity)
  readonly property real lifetime: FlareModel.lifetimeFor(kind, duration)
  readonly property real baseAlpha: Math.min(1.0, intensity)

  // A release is a lighter shade of the tint, and a quieter one (§5.2).
  readonly property color ink: FlareModel.isRelease(kind)
    ? FlareModel.lightened(tint, 0.4)
    : tint
  readonly property real elementAlpha: FlareModel.isRelease(kind)
    ? baseAlpha * 0.7
    : baseAlpha

  readonly property real side: FlareModel.containerFor(kind, pulseSize, stroke)
  readonly property real mid: side / 2

  readonly property bool crosshaired: FlareModel.hasCrosshair(kind)
  readonly property bool release: FlareModel.isRelease(kind)

  width: side
  height: side

  // 0 -> 1 over the pulse's lifetime. Drives geometry, scale, and fade
  // together, so every element shares one ease-out curve.
  property real phase: 0

  function lerp(from, to) { return from + (to - from) * phase }

  // Closed outline of `shape` at `diameter`, centered in the container.
  function ringPath(diameter) {
    var points = FlareModel.outline(shape, diameter, mid, mid)
    points.push(points[0])
    return points
  }

  function ink4(alpha) { return Qt.rgba(ink.r, ink.g, ink.b, alpha) }

  NumberAnimation on phase {
    from: 0
    to: 1
    duration: Math.round(root.lifetime * 1000)
    easing.type: Easing.OutQuad
    running: true
    onFinished: root.finished()
  }

  // ------------------------------------------------------------------ glow
  // Only at higher intensities; lower intensities render clean rings only.
  Shape {
    anchors.fill: parent
    visible: FlareModel.showsGlow(root.intensity) && FlareModel.isPress(root.kind)
    preferredRendererType: Shape.CurveRenderer
    opacity: 1 - root.phase
    scale: root.lerp(0.4, 1.0)

    ShapePath {
      strokeWidth: -1
      fillGradient: RadialGradient {
        centerX: root.mid
        centerY: root.mid
        centerRadius: root.pulseSize * 1.3 / 2
        focalX: root.mid
        focalY: root.mid
        GradientStop { position: 0.0; color: root.ink4(root.baseAlpha * 0.55) }
        GradientStop { position: 1.0; color: root.ink4(0) }
      }
      PathPolyline { path: root.ringPath(root.pulseSize * 1.3) }
    }
  }

  // ------------------------------------------------------------------ ring
  // Press expands 0.35x -> 1.0x; release contracts 0.82x -> 0.40x.
  Shape {
    id: ring
    anchors.fill: parent
    visible: root.kind !== "drag"
    preferredRendererType: Shape.CurveRenderer
    opacity: 1 - root.phase

    readonly property real diameter: root.release
      ? root.lerp(root.pulseSize * 0.82, root.pulseSize * 0.40)
      : root.lerp(root.pulseSize * 0.35, root.pulseSize)

    ShapePath {
      strokeColor: root.ink4(root.elementAlpha)
      strokeWidth: root.release ? root.stroke * 0.85 : root.stroke
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: root.ringPath(ring.diameter) }
    }
  }

  // ------------------------------------------------------------------- dot
  // Primary press gets a center dot; drag is a small dot on its own.
  Shape {
    anchors.fill: parent
    visible: root.kind === "primary-press" || root.kind === "drag"
    preferredRendererType: Shape.CurveRenderer
    opacity: 1 - root.phase
    scale: root.kind === "drag" ? root.lerp(0.8, 1.15) : root.lerp(1.0, 1.35)

    ShapePath {
      strokeWidth: -1
      fillColor: root.ink4(root.elementAlpha)
      joinStyle: ShapePath.RoundJoin
      PathPolyline {
        path: root.ringPath(root.kind === "drag" ? root.pulseSize * 0.30 : root.pulseSize * 0.17)
      }
    }
  }

  // ------------------------------------------------------------- crosshair
  // Secondary clicks add a "+" of four arms around a small central gap.
  Shape {
    id: cross
    anchors.fill: parent
    visible: root.crosshaired
    // A middle click turns the "+" into an "x" so it never reads as a
    // secondary click.
    rotation: FlareModel.crosshairRotation(root.kind)
    preferredRendererType: Shape.CurveRenderer
    opacity: 1 - root.phase
    scale: root.release ? root.lerp(1.0, 0.4) : root.lerp(0.6, 1.0)

    readonly property real arm: root.release
      ? root.pulseSize * 0.28 * 0.82
      : root.pulseSize * 0.28
    readonly property real gap: arm * 0.3
    readonly property real armStroke: root.release ? root.stroke * 0.7 : root.stroke * 0.8
    readonly property color armColor: root.ink4(root.elementAlpha)

    ShapePath {
      strokeColor: cross.armColor; strokeWidth: cross.armStroke
      capStyle: ShapePath.RoundCap; fillColor: "transparent"
      startX: root.mid; startY: root.mid + cross.gap
      PathLine { x: root.mid; y: root.mid + cross.arm }
    }
    ShapePath {
      strokeColor: cross.armColor; strokeWidth: cross.armStroke
      capStyle: ShapePath.RoundCap; fillColor: "transparent"
      startX: root.mid; startY: root.mid - cross.gap
      PathLine { x: root.mid; y: root.mid - cross.arm }
    }
    ShapePath {
      strokeColor: cross.armColor; strokeWidth: cross.armStroke
      capStyle: ShapePath.RoundCap; fillColor: "transparent"
      startX: root.mid + cross.gap; startY: root.mid
      PathLine { x: root.mid + cross.arm; y: root.mid }
    }
    ShapePath {
      strokeColor: cross.armColor; strokeWidth: cross.armStroke
      capStyle: ShapePath.RoundCap; fillColor: "transparent"
      startX: root.mid - cross.gap; startY: root.mid
      PathLine { x: root.mid - cross.arm; y: root.mid }
    }
  }
}
