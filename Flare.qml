import QtQuick
import Quickshell

// Flare's renderer: one click-through overlay per display, drawing whatever
// the service tells it to. All state lives in Service.qml.
Item {
  id: root

  // Injected by the omarchy-shell panel loader.
  property var shell: null
  property var manifest: null
  property var service: null

  readonly property var appearance: service ? service.appearance : ({})

  Connections {
    target: root.service
    function onPulseRequested(kind, x, y, shape) {
      for (var i = 0; i < overlays.instances.length; i++) {
        overlays.instances[i].spawn(kind, x, y, shape)
      }
    }
  }

  Variants {
    id: overlays
    model: Quickshell.screens

    Overlay {
      appearance: root.appearance
    }
  }
}
