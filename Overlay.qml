import QtQuick
import Quickshell
import Quickshell.Wayland

// One click-through layer-shell surface per display. Visual only: the input
// region stays empty so pulses never intercept a click, and the surface is
// only mapped while something is actually animating.
PanelWindow {
  id: win

  required property var modelData
  property var appearance: ({})

  screen: modelData

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"

  WlrLayershell.namespace: "flare-overlay"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  // Visual-only surface: an empty layer-shell input region keeps every click
  // reaching the window underneath.
  mask: Region {}

  // Stay unmapped while idle so an always-on fullscreen overlay never blocks
  // the compositor from handing a fullscreen client direct scanout.
  property int liveCount: 0
  visible: liveCount > 0

  // Spawn a pulse for a click at global layout coordinates, if it lands
  // anywhere on this screen's slice of the layout.
  function spawn(kind, globalX, globalY, shape) {
    var localX = globalX - modelData.x
    var localY = globalY - modelData.y
    var reach = appearance.reach || 0
    if (localX < -reach || localY < -reach) return
    if (localX > modelData.width + reach || localY > modelData.height + reach) return

    var pulse = pulseComponent.createObject(field, {
      kind: kind,
      pulseSize: appearance.size,
      intensity: appearance.intensity,
      duration: appearance.duration,
      shape: shape,
      tint: appearance.tint
    })
    if (!pulse) {
      console.warn("flare: failed to create pulse for " + kind)
      return
    }

    pulse.x = localX - pulse.side / 2
    pulse.y = localY - pulse.side / 2
    win.liveCount++
  }

  Item {
    id: field
    anchors.fill: parent
  }

  Component {
    id: pulseComponent

    Pulse {
      onFinished: {
        win.liveCount--
        destroy()
      }
    }
  }
}
