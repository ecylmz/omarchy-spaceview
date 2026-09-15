import QtQuick
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
  property bool capturing: true
  // { x, y, width, height } of the workspace's monitor in logical pixels.
  property var monitorBounds: null

  readonly property var toplevelModel: workspace ? workspace.toplevels : []
  readonly property int windowCount: workspace ? workspace.toplevels.values.length : 0
  readonly property bool occupied: windowCount > 0
  readonly property real monitorAspect: monitorBounds && monitorBounds.height > 0
    ? monitorBounds.width / monitorBounds.height : 1.55

  // Where each window sits, as fractions of the monitor. Falls back to an even
  // grid when Hyprland has no geometry for a window (e.g. it just mapped).
  readonly property var layoutRects: {
    var windows = root.workspace ? root.workspace.toplevels.values : []
    var bounds = root.monitorBounds
    var usable = bounds && bounds.width > 0 && bounds.height > 0
    var rects = []

    var resolved = 0

    for (var i = 0; i < windows.length; i++) {
      var ipc = usable && windows[i] ? windows[i].lastIpcObject : null
      if (ipc && root.behindItsGroup(ipc, windows)) {
        rects.push(null)
        continue
      }
      if (!ipc || !ipc.at || !ipc.size || ipc.size[0] <= 0 || ipc.size[1] <= 0) {
        // Hyprland announces a window before its geometry is queried. Hold
        // that one tile back rather than dropping the whole card to a grid.
        rects.push(null)
        continue
      }
      resolved += 1
      rects.push({
        x: (ipc.at[0] - bounds.x) / bounds.width,
        y: (ipc.at[1] - bounds.y) / bounds.height,
        width: ipc.size[0] / bounds.width,
        height: ipc.size[1] / bounds.height,
        floating: ipc.floating === true
      })
    }

    if (resolved > 0) return rects

    var columns = windows.length === 2 ? 2 : Math.max(1, Math.ceil(Math.sqrt(windows.length)))
    var rows = Math.max(1, Math.ceil(windows.length / columns))
    var fallback = []
    for (var j = 0; j < windows.length; j++) {
      fallback.push({
        x: (j % columns) / columns,
        y: Math.floor(j / columns) / rows,
        width: 1 / columns,
        height: 1 / rows,
        floating: false
      })
    }
    return fallback
  }

  // Hyprland reports every member of a tabbed group at the same geometry, so
  // drawing all of them stacks the group into a single smear. Only the tab on
  // top is worth a tile.
  //
  // ponytail: focus history is the one field in the client IPC that tells
  // group members apart — neither `hidden` nor the `grouped` order does.
  // Swap it for an active-member field if Hyprland ever exposes one.
  function behindItsGroup(ipc, windows) {
    var group = ipc.grouped
    if (!group || group.length < 2) return false

    var order = Number(ipc.focusHistoryID)
    if (!isFinite(order)) return false

    for (var i = 0; i < windows.length; i++) {
      var other = windows[i] ? windows[i].lastIpcObject : null
      if (!other || other.address === ipc.address) continue
      if (group.indexOf(other.address) === -1) continue
      if (Number(other.focusHistoryID) < order) return true
    }
    return false
  }

  readonly property real headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int draggedSourceWorkspaceId: draggedToplevel && draggedToplevel.workspace
    ? Number(draggedToplevel.workspace.id) : -1
  readonly property bool dragActive: draggedToplevel !== null
    && String(draggedToplevel.address || "") !== ""
    && workspaceId > 0 && workspaceId <= 10
  readonly property bool foreignDrag: dragActive && draggedSourceWorkspaceId !== workspaceId
  readonly property bool validDropTarget: dragActive && (foreignDrag || windowCount > 1)
  readonly property bool dropHovered: foreignDrag && dropArea.containsDrag
    && root.dropTargetPreview === null
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

    var local = stage.mapFromItem(root, cardX, cardY)
    var tile = stage.childAt(local.x, local.y)
    if (!tile || tile.width <= 0 || tile.height <= 0) {
      root.dropTargetPreview = null
      root.dropTargetDirection = ""
      return
    }

    var dragged = root.draggedToplevel ? String(root.draggedToplevel.address || "") : ""
    if (tile.toplevel && dragged !== "" && String(tile.toplevel.address || "") === dragged) {
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
    : (foreignDrag
      ? Border.withWidth(Border.controlSpec("hover-cursor", Color.menu.text, Color.accent), root.accentBorderWidth)
      : normalBorderSpec)
  clip: true
  opacity: focused || keyboardSelected || dragActive ? 1 : 0.74

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
      : (root.foreignDrag || root.keyboardSelected
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
        textFormat: Text.PlainText
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
    textFormat: Text.PlainText
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

    // The stage keeps the monitor's aspect ratio, so a tall split reads as a
    // tall split instead of being stretched to the card.
    Item {
      id: stage
      width: Math.min(parent.width, parent.height * root.monitorAspect)
      height: width / root.monitorAspect
      anchors.centerIn: parent

      readonly property real inset: Math.max(1, Style.space(2)) / 2

      Repeater {
        model: root.toplevelModel

        WindowPreview {
          id: previewItem
          required property var modelData
          required property int index

          readonly property var rect: root.layoutRects[index] || null

          visible: rect !== null
          x: rect ? rect.x * stage.width + stage.inset : 0
          y: rect ? rect.y * stage.height + stage.inset : 0
          width: rect ? Math.max(1, rect.width * stage.width - stage.inset * 2) : 1
          height: rect ? Math.max(1, rect.height * stage.height - stage.inset * 2) : 1
          z: rect && rect.floating ? 2 : 1

          toplevel: modelData
          capturing: root.capturing
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
    textFormat: Text.PlainText
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
    keys: ["ecylmz.spaceview-window"]
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

      if (target && target.toplevel && direction !== "") {
        drop.acceptProposedAction()
        root.windowDroppedNextTo(drop.source.toplevel, target.toplevel, direction)
      } else if (root.foreignDrag) {
        drop.acceptProposedAction()
        root.windowDropped(drop.source.toplevel)
      } else {
        drop.accepted = false
      }
    }
  }
}
