import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "FlareModel.js" as FlareModel

// Prototype: one square cell per mouse button instead of four labeled
// dropdowns. Each cell shows its current outline and opens a strip of the
// six choices when clicked, so it behaves like a dropdown that speaks in
// shapes rather than words.
Item {
  id: root

  property var config: ({})
  property color foreground: Color.popups.text
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal picked(string button, string shape)

  readonly property real cellSize: Style.space(32)
  readonly property real optionSize: Style.space(28)
  readonly property real optionGap: Style.spacing.hairline * 2
  readonly property real stripPadding: Style.spacing.hairline * 2
  readonly property var buttons: FlareModel.BUTTONS

  // Width of the open strip, computed rather than measured so the edge clamp
  // below can run before the popup has ever been shown.
  readonly property real stripWidth:
    FlareModel.SHAPE_OPTIONS.length * optionSize
    + (FlareModel.SHAPE_OPTIONS.length - 1) * optionGap
    + stripPadding * 2

  // Hoisted off the Row so each cell can work out where it sits, and from
  // that whether its strip would hang off the panel.
  readonly property real rowSpacing: buttons.length > 1
    ? Math.max(Style.spacing.xs,
        (width - buttons.length * cellSize) / (buttons.length - 1))
    : 0

  // Plus a little breathing room: the cells fill their box exactly, so without
  // it the bottom border sits right on the next section's separator.
  implicitHeight: cellColumnHeight + Style.spacing.xs
  readonly property real cellColumnHeight:
    captionMetrics.height + Style.spacing.labelGap + cellSize

  TextMetrics {
    id: captionMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "Middle"
  }

  Row {
    anchors.fill: parent
    // Spread the four cells evenly across the panel rather than bunching them
    // at the left edge.
    spacing: root.rowSpacing

    Repeater {
      model: root.buttons

      delegate: Column {
        id: group
        required property var modelData
        required property int index
        readonly property string button: String(modelData)
        readonly property real originX: index * (root.cellSize + root.rowSpacing)
        readonly property string shape: root.config[button] || "circle"

        spacing: Style.spacing.labelGap

        // The caption is wider than its cell ("Middle" does not fit in 32px),
        // so it is centred inside a cell-width box and allowed to spill into
        // the gaps. Sizing the box to the cell keeps the Row layout honest.
        Item {
          width: root.cellSize
          height: caption.implicitHeight

          Text {
            id: caption
            anchors.centerIn: parent
            text: FlareModel.BUTTON_LABELS[group.button] || group.button
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        BorderSurface {
          id: cell
          width: root.cellSize
          height: root.cellSize
          radius: Style.cornerRadius

          readonly property bool hot: cellHover.hovered || strip.opened

          color: Style.controlFill(strip.opened, hot, root.foreground, root.accent)
          borderSpec: Border.controlSpec(
            strip.opened ? "focus" : (hot ? "hover-cursor" : "normal"),
            root.foreground, root.accent)

          HoverHandler { id: cellHover }

          ShapeMark {
            anchors.centerIn: parent
            shape: group.shape
            size: Math.round(root.cellSize * 0.52)
            color: group.shape === "none"
              ? Qt.darker(root.foreground, 1.7)
              : root.foreground
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: strip.opened ? strip.close() : strip.open()
          }

          // The choices, as a horizontal strip of outlines.
          Popup {
            id: strip
            y: cell.height + Style.spacing.xxs
            // Centred under the cell, then pulled back inside the panel so the
            // last cell's strip does not run off the screen edge.
            x: {
              var centered = (cell.width - root.stripWidth) / 2
              var lowest = -group.originX
              var highest = root.width - root.stripWidth - group.originX
              return Math.round(Math.max(lowest, Math.min(centered, highest)))
            }
            width: root.stripWidth
            padding: root.stripPadding
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

            background: BorderSurface {
              color: Color.popups.background
              borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
              radius: Style.cornerRadius
            }

            contentItem: Row {
              spacing: root.optionGap

              Repeater {
                model: FlareModel.SHAPE_OPTIONS

                delegate: BorderSurface {
                  id: option
                  required property var modelData
                  readonly property string shape: String(modelData)
                  readonly property bool selected: group.shape === shape

                  width: root.optionSize
                  height: root.optionSize
                  radius: Style.cornerRadius

                  color: selected
                    ? Style.selectedFillFor(root.foreground, root.accent)
                    : Style.controlFill(false, optionHover.hovered, root.foreground, root.accent)
                  borderSpec: Border.controlSpec(
                    selected ? "focus" : (optionHover.hovered ? "hover-cursor" : "normal"),
                    root.foreground, root.accent)

                  HoverHandler { id: optionHover }

                  ShapeMark {
                    anchors.centerIn: parent
                    shape: option.shape
                    size: Math.round(root.optionSize * 0.52)
                    color: option.selected ? root.accent : Qt.darker(root.foreground, 1.25)
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.picked(group.button, option.shape)
                      strip.close()
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
