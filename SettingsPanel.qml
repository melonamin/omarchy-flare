import QtQuick
import qs.Commons
import qs.Ui
import "FlareModel.js" as FlareModel

// Bar button plus the settings popup. Left click opens the panel, right click
// toggles highlighting outright -- the same split the audio widget uses.
Panel {
  id: root
  moduleName: "melonamin.flare"
  ipcTarget: "melonamin.flare"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("melonamin.flare")
    : null

  readonly property var config: service ? service.settings : FlareModel.DEFAULTS
  readonly property bool on: service ? service.active : false
  readonly property color ink: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function put(key, value) {
    if (service) service.write(key, value)
  }

  // Dropdown renders its labels with Text.AutoText, so a little markup gets a
  // swatch into both the trigger and the popup rows without touching the
  // shared component.
  readonly property var tintOptions: {
    var out = []
    for (var i = 0; i < FlareModel.TINT_OPTIONS.length; i++) {
      var name = FlareModel.TINT_OPTIONS[i]
      var named = FlareModel.TINTS[name]
      var swatch = named ? named : String(Color.accent)
      var text = name === "auto" ? "Theme accent" : FlareModel.titleCase(name)
      out.push({
        value: name,
        label: '<font color="' + swatch + '">&#9679;</font>&#160;&#160;' + text
      })
    }
    return out
  }

  // ------------------------------------------------------------ bar button

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.on
      ? "Click highlighting on — right-click to turn off"
      : "Click highlighting off — right-click to turn on"
    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.service) root.service.toggle() }
      else root.toggle()
    }

    iconComponent: Component {
      PulseGlyph {
        size: Style.bar.iconCanvas
        opacity: root.on ? 1.0 : 0.45
        color: root.ink
      }
    }
  }

  // -------------------------------------------------------- popup content

  // Label on the left, live readout on the right, slider underneath.
  component SliderRow: Column {
    id: sliderRow
    property string label: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 0.01
    property string suffix: ""
    property int decimals: 0
    // Speed reads backwards from its slider: right means faster, so the knob
    // sits at `span - duration` while the readout still shows the duration.
    property real span: 0
    signal moved(real value)

    readonly property real live: slider.dragging ? slider.liveValue : value
    readonly property real readout: span > 0 ? span - live : live

    width: parent ? parent.width : 0
    spacing: Style.spacing.labelGap

    Item {
      width: parent.width
      height: nameText.implicitHeight

      Text {
        id: nameText
        anchors.left: parent.left
        text: sliderRow.label
        color: Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        text: sliderRow.readout.toFixed(sliderRow.decimals) + sliderRow.suffix
        color: Color.popups.text
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    PanelSlider {
      id: slider
      bar: root.bar
      width: parent.width
      value: sliderRow.value
      minimum: sliderRow.minimum
      maximum: sliderRow.maximum
      step: sliderRow.step
      onMoved: function(v) { sliderRow.moved(v) }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    // No cap: the panel sizes to its content so nothing scrolls. It is still
    // clamped to the screen by fittedContentHeight.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.spacing.sm

        PanelHero {
          width: parent.width
          title: "Flare"
          meta: root.on ? "Highlighting on" : "Paused"
          foreground: Color.popups.text
          fontFamily: root.fontFamily
          iconOpacity: root.on ? 1.0 : 0.5

          iconComponent: Component {
            PulseGlyph {
              size: Style.font.display
              color: Color.popups.text
            }
          }

          trailingControl: Component {
            Row {
              spacing: Style.spacing.sm

              Button {
                iconText: "\uF0E2"
                tooltipText: "Reset to defaults"
                foreground: Color.popups.text
                fontFamily: root.fontFamily
                iconSize: Style.font.subtitle * 1.5
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: if (root.service) root.service.reset()
              }

              ToggleSwitch {
                checked: root.on
                foreground: Color.popups.text
                accent: Color.accent
                anchors.verticalCenter: parent.verticalCenter
                onToggled: if (root.service) root.service.toggle()
              }
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: Color.popups.text }

        PanelSectionHeader {
          width: parent.width
          text: "SHAPE PER BUTTON"
          foreground: Color.popups.text
          fontFamily: root.fontFamily
        }

        ShapeMatrix {
          width: parent.width
          config: root.config
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.fontFamily
          onPicked: function(button, shape) { root.put(button, shape) }
        }

        PanelSeparator { width: parent.width; foreground: Color.popups.text }

        PanelSectionHeader {
          width: parent.width
          text: "APPEARANCE"
          foreground: Color.popups.text
          fontFamily: root.fontFamily
        }

        SliderRow {
          label: "Size"
          suffix: " px"
          value: root.config.size
          minimum: FlareModel.SIZE_MIN
          maximum: FlareModel.SIZE_MAX
          step: 2
          onMoved: function(v) { root.put("size", Math.round(v)) }
        }

        // Inverted so dragging right speeds the pulse up while the readout
        // still shows the honest duration.
        SliderRow {
          label: "Speed"
          suffix: " s"
          decimals: 2
          span: FlareModel.SPEED_MIN + FlareModel.SPEED_MAX
          value: span - root.config.speed
          minimum: FlareModel.SPEED_MIN
          maximum: FlareModel.SPEED_MAX
          step: 0.02
          onMoved: function(v) { root.put("speed", Math.round((span - v) * 100) / 100) }
        }

        SliderRow {
          label: "Intensity"
          decimals: 2
          value: root.config.intensity
          minimum: FlareModel.INTENSITY_MIN
          maximum: FlareModel.INTENSITY_MAX
          step: 0.05
          onMoved: function(v) { root.put("intensity", Math.round(v * 100) / 100) }
        }

        Dropdown {
          width: parent.width
          label: "Color"
          fontFamily: root.fontFamily
          options: root.tintOptions
          value: root.config.tint
          onChanged: function(v) { root.put("tint", v) }
        }

      }
    }
  }
}
