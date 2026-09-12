import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// One workspace in the grid: a labelled card holding a tile per window.
// Doubles as a drop target so windows can be dragged between workspaces.
BorderSurface {
  id: root

  required property int workspaceId
  property var workspace: null
  property bool focused: false
  property bool addWorkspace: false
  property bool keyboardSelected: false
  property var draggedToplevel: null

  readonly property var toplevelModel: workspace ? workspace.toplevels : []
  readonly property int windowCount: workspace ? workspace.toplevels.values.length : 0
  readonly property bool occupied: windowCount > 0
  readonly property int previewColumns: windowCount === 2 ? 2 : Math.max(1, Math.ceil(Math.sqrt(windowCount)))
  readonly property int previewRows: Math.max(1, Math.ceil(windowCount / previewColumns))
  readonly property real headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property real previewSpacing: Style.spacing.sm
  readonly property int draggedSourceWorkspaceId: draggedToplevel && draggedToplevel.workspace
    ? Number(draggedToplevel.workspace.id) : -1
  readonly property bool validDropTarget: draggedToplevel !== null
    && String(draggedToplevel.address || "") !== ""
    && workspaceId > 0 && workspaceId <= 10
    && draggedSourceWorkspaceId !== workspaceId
  readonly property bool dropHovered: validDropTarget && dropArea.containsDrag
  readonly property real accentBorderWidth: Math.max(Style.space(2), Style.focusBorderWidth)
  readonly property var normalBorderSpec: focused
    ? Border.flat(Color.accent, root.accentBorderWidth)
    : (keyboardSelected
      ? Border.withWidth(Border.controlSpec("hover-cursor", Color.menu.text, Color.accent), Math.max(1, Style.hoverBorderWidth))
      : (occupied
        ? Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.normalBorderWidth))
        : Border.flat(Util.alpha(Color.menu.border, 0.35), Math.max(1, Style.normalBorderWidth))))

  property var dropTargetPreview: null
  property string dropTargetDirection: ""

  // Which tile is under the pointer, and which side of it the window would
  // take. Grid children are WindowPreview items laid out inside previewArea.
  function updateDropTarget(cardX, cardY) {
    if (!validDropTarget) {
      root.dropTargetPreview = null
      root.dropTargetDirection = ""
      return
    }

    var local = previewArea.mapFromItem(root, cardX, cardY)
    var tile = previewGrid.childAt(local.x, local.y)
    if (!tile || tile.width <= 0 || tile.height <= 0) {
      root.dropTargetPreview = null
      root.dropTargetDirection = ""
      return
    }

    var dx = (local.x - tile.x) / tile.width - 0.5
    var dy = (local.y - tile.y) / tile.height - 0.5
    root.dropTargetPreview = tile
    root.dropTargetDirection = Math.abs(dx) >= Math.abs(dy)
      ? (dx < 0 ? "l" : "r")
      : (dy < 0 ? "u" : "d")
  }

  function clearDropTarget() {
    root.dropTargetPreview = null
    root.dropTargetDirection = ""
  }

  signal workspaceActivated()
  signal windowActivated(var toplevel)
  signal windowDragStarted(var toplevel)
  signal windowDragFinished(var toplevel)
  signal windowDropped(var toplevel)
  signal windowDroppedNextTo(var toplevel, var target, string direction)
  signal windowDragMoved(point scenePosition)

  radius: Style.cornerRadius
  color: focused
    ? Color.menu.background
    : (occupied ? Util.alpha(Color.menu.background, 0.82) : Util.alpha(Color.menu.background, 0.62))
  borderSpec: dropHovered
    ? Border.withWidth(Border.controlSpec("focus", Color.menu.text, Color.accent), Math.max(Style.space(2), Style.focusBorderWidth))
    : (validDropTarget
      ? Border.withWidth(Border.controlSpec("hover-cursor", Color.menu.text, Color.accent), root.accentBorderWidth)
      : normalBorderSpec)
  clip: true
  opacity: focused || keyboardSelected || dropHovered ? 1 : 0.74

  Behavior on opacity { NumberAnimation { duration: 90 } }

  MouseArea {
    anchors.fill: parent
    z: 1
    cursorShape: Qt.PointingHandCursor
    onClicked: root.workspaceActivated()
  }

  Rectangle {
    anchors.fill: parent
    z: 2
    color: root.dropHovered
      ? Style.selectedFillFor(Color.menu.text, Color.accent)
      : (root.validDropTarget || root.keyboardSelected
        ? Style.hoverFillFor(Color.menu.text, Color.accent)
        : (root.focused ? Util.alpha(Color.accent, 0.07) : "transparent"))

    Behavior on color { ColorAnimation { duration: 60 } }
  }

  Item {
    id: header
    visible: !root.addWorkspace
    z: 3
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.md
    anchors.rightMargin: Style.spacing.md
    height: root.headerHeight

    Row {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      spacing: Style.spacing.sm

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.focused
        width: visible ? Style.space(8) : 0
        height: width
        radius: width / 2
        color: Color.accent
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.workspaceId === 10 ? "Workspace 0" : "Workspace " + root.workspaceId
        color: root.focused ? Color.accent : Color.menu.text
        opacity: root.focused ? 1 : (root.occupied ? 0.82 : 0.5)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.title
        font.bold: root.focused
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  Text {
    visible: !root.occupied && !root.addWorkspace
    anchors.centerIn: previewArea
    text: "Empty"
    color: Color.menu.text
    opacity: 0.42
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }

  Item {
    id: previewArea
    visible: !root.addWorkspace
    z: 5
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.md

    Grid {
      id: previewGrid
      anchors.fill: parent
      columns: root.previewColumns
      spacing: root.previewSpacing

      Repeater {
        model: root.toplevelModel

        WindowPreview {
          id: previewItem
          required property var modelData

          width: Math.max(1, (previewArea.width - root.previewSpacing * (root.previewColumns - 1)) / root.previewColumns)
          height: Math.max(1, (previewArea.height - root.previewSpacing * (root.previewRows - 1)) / root.previewRows)
          toplevel: modelData
          dropDirection: root.dropTargetPreview === previewItem ? root.dropTargetDirection : ""
          onActivated: root.windowActivated(modelData)
          onDragStarted: root.windowDragStarted(modelData)
          onDragFinished: root.windowDragFinished(modelData)
          onDragMoved: function(scenePosition) { root.windowDragMoved(scenePosition) }
        }
      }
    }
  }

  Text {
    visible: root.addWorkspace
    anchors.centerIn: parent
    z: 3
    text: "+"
    color: Color.menu.text
    opacity: root.dropHovered ? 1 : 0.58
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.displayLarge
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  DropArea {
    id: dropArea
    anchors.fill: parent
    z: 20
    keys: ["omarchy-window"]
    enabled: root.validDropTarget

    onPositionChanged: function(drag) { root.updateDropTarget(drag.x, drag.y) }
    onEntered: function(drag) { root.updateDropTarget(drag.x, drag.y) }
    onExited: root.clearDropTarget()

    onDropped: function(drop) {
      var target = root.dropTargetPreview
      var direction = root.dropTargetDirection
      root.clearDropTarget()

      if (!root.validDropTarget || !drop.source || !drop.source.toplevel) {
        drop.accepted = false
        return
      }
      drop.acceptProposedAction()

      if (target && target.toplevel && direction !== "")
        root.windowDroppedNextTo(drop.source.toplevel, target.toplevel, direction)
      else
        root.windowDropped(drop.source.toplevel)
    }
  }
}
