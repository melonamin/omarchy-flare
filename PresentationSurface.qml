import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Presentation mode. Unlike the pulse overlay, this surface *accepts* input:
// it covers the screen, so clicks land here and reach nothing underneath. The
// highlights themselves still come from the compositor binds, which fire
// whether or not a client consumes the click.
//
// It exists only while presenting. Flipping input or visibility on a live
// layer-shell surface does not reliably take effect, so the whole surface is
// created on entry and destroyed on exit.
PanelWindow {
  id: win

  required property var modelData
  property string shortcutLabel: ""
  // Only one screen should carry the badge, or a multi-monitor setup shows it
  // several times.
  property bool primary: false

  signal exitRequested()

  screen: modelData

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"

  WlrLayershell.namespace: "flare-presenting"
  WlrLayershell.layer: WlrLayer.Overlay
  // Exclusive so Escape reaches us even though nothing here is focusable.
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  // Deliberately no `mask`: an empty input region is what makes the pulse
  // overlay click-through, and here we want the opposite.

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    // Accepting the press is the entire point: it stops here.
    onPressed: function(event) { event.accepted = true }
    onWheel: function(event) { event.accepted = true }
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: win.exitRequested()
  }

  // The way out has to be visible: every click is being swallowed, including
  // on the bar and on this plugin's own widget.
  BorderSurface {
    visible: win.primary
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Style.space(48)

    width: badge.implicitWidth + Style.space(28)
    height: badge.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: Util.alpha(Color.popups.background, 0.94)
    borderSpec: Border.surfaceSpec("popups", "border", Color.accent, Style.normalBorderWidth)

    Row {
      id: badge
      anchors.centerIn: parent
      spacing: Style.spacing.sm

      Rectangle {
        width: Style.space(8); height: Style.space(8)
        radius: width / 2
        color: Color.accent
        anchors.verticalCenter: parent.verticalCenter
        // A slow pulse, so the badge reads as "a mode is running".
        SequentialAnimation on opacity {
          loops: Animation.Infinite
          NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Presenting — clicks won't reach your apps"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: win.shortcutLabel !== ""
          ? "Esc or " + win.shortcutLabel + " to exit"
          : "Esc to exit"
        color: Qt.darker(Color.popups.text, 1.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
