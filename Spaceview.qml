import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Fullscreen workspace overview. Summoned over shell IPC:
//   omarchy-shell shell toggle ecylmz.spaceview
//
// Hyprland is configured in Lua here, so every dispatch goes through the
// hl.dsp.* form; the classic "workspace 3" syntax is a Lua syntax error.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  property var draggedToplevel: null
  // Windows take a detour through this hidden workspace when they are
  // repositioned inside the workspace they already live on.
  readonly property string parkingWorkspace: "special:spaceview-move"
  readonly property var layoutEvents: [
    "openwindow", "closewindow", "movewindow", "movewindowv2",
    "workspace", "workspacev2", "createworkspace", "createworkspacev2",
    "destroyworkspace", "destroyworkspacev2", "moveworkspace", "moveworkspacev2",
    "changefloatingmode", "fullscreen", "togglegroup", "moveintogroup", "moveoutofgroup"
  ]
  property var pendingReposition: null
  // What the user asked for while a reposition was still in flight, so
  // finishing that move does not drag them back to where they started.
  property int requestedWorkspaceId: -1
  property string requestedWindowAddress: ""
  property point dragScenePosition: Qt.point(0, 0)
  property int selectedCardIndex: -1

  readonly property var workspaceModel: root.workspaceIds()
  readonly property int workspaceCount: workspaceModel.length
  readonly property int nextWorkspaceId: root.nextWorkspaceAfter(workspaceModel)
  readonly property var overviewCardModel: {
    var ids = workspaceModel.slice()
    if (nextWorkspaceId > 0) ids.push(nextWorkspaceId)
    return ids
  }
  readonly property int cardCount: overviewCardModel.length
  readonly property var defaultMonitorBounds: root.monitorBoundsFor(-1)
  readonly property real cardAspectRatio: defaultMonitorBounds && defaultMonitorBounds.height > 0
    ? defaultMonitorBounds.width / defaultMonitorBounds.height : 1.55
  readonly property real outerMargin: Math.max(Style.gapsOut, Style.spacing.panelPadding)
  readonly property real gridSpacing: Style.spacing.lg
  readonly property real availableWidth: Math.max(1, panel.width - outerMargin * 2)
  readonly property real availableHeight: Math.max(1, panel.height - outerMargin * 2)
  readonly property int columns: Math.max(1, Math.min(cardCount,
    Math.ceil(Math.sqrt(cardCount * availableWidth / availableHeight / cardAspectRatio))))
  readonly property int rows: Math.max(1, Math.ceil(cardCount / columns))
  readonly property real cardWidth: Math.max(1, Math.min(
    Style.space(520),
    (availableWidth - gridSpacing * (columns - 1)) / columns,
    ((availableHeight - gridSpacing * (rows - 1)) / rows) * cardAspectRatio))
  readonly property real cardHeight: Math.max(1, cardWidth / cardAspectRatio)

  // Logical bounds of the monitor a workspace lives on, used to scale window
  // geometry into each card. Falls back to the focused monitor.
  function monitorBoundsFor(workspaceId) {
    var workspace = root.workspaceById(workspaceId)
    var wanted = workspace && workspace.lastIpcObject
      ? String(workspace.lastIpcObject.monitor || "") : ""
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    var found = null

    for (var i = 0; i < monitors.length; i++) {
      var ipc = monitors[i] ? monitors[i].lastIpcObject : null
      if (ipc && wanted && String(ipc.name || "") === wanted) { found = ipc; break }
    }

    if (!found && Hyprland.focusedMonitor) found = Hyprland.focusedMonitor.lastIpcObject
    if (!found || !found.width || !found.height) return null

    var scale = found.scale > 0 ? found.scale : 1
    return {
      x: found.x || 0,
      y: found.y || 0,
      width: found.width / scale,
      height: found.height / scale
    }
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  // Always show 1..5 so the grid has a stable shape, plus anything else live.
  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function nextWorkspaceAfter(ids) {
    if (!ids || ids.length === 0) return -1
    var next = ids[ids.length - 1] + 1
    return next <= 10 ? next : -1
  }

  function cardIndexAfterMove(index, dx, dy, count, columnCount) {
    if (count <= 0) return -1
    var current = Math.max(0, Math.min(index, count - 1))
    var cols = Math.max(1, columnCount)
    var row = Math.floor(current / cols)
    var column = current % cols

    if (dx < 0) return Math.max(row * cols, current - 1)
    if (dx > 0) return Math.min(Math.min(row * cols + cols - 1, count - 1), current + 1)

    var targetRow = Math.max(0, Math.min(Math.ceil(count / cols) - 1, row + dy))
    return Math.min(targetRow * cols + column, count - 1)
  }

  function initialSelectedCardIndex() {
    var focused = Hyprland.focusedWorkspace
    if (focused) {
      var index = root.workspaceModel.indexOf(focused.id)
      if (index >= 0) return index
    }
    return root.cardCount > 0 ? 0 : -1
  }

  function moveCardSelection(dx, dy) {
    root.selectedCardIndex = root.cardIndexAfterMove(
      root.selectedCardIndex, dx, dy, root.cardCount, root.columns)
  }

  function activateSelectedCard() {
    var index = root.selectedCardIndex
    if (index < 0 || index >= root.cardCount) return
    if (root.nextWorkspaceId > 0 && index === root.workspaceCount)
      root.activateWorkspace(root.nextWorkspaceId)
    else
      root.activateWorkspace(root.overviewCardModel[index])
  }

  function normalizedAddress(toplevel) {
    var address = String((toplevel && toplevel.address) || "").trim()
    if (!address.match(/^(0x)?[0-9a-fA-F]+$/)) return ""
    return address.indexOf("0x") === 0 ? address : "0x" + address
  }

  function sourceWorkspaceId(toplevel) {
    return toplevel && toplevel.workspace ? Number(toplevel.workspace.id) : -1
  }

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var screens = Quickshell.screens || []
    if (monitor) {
      for (var i = 0; i < screens.length; i++) {
        if (screens[i] && screens[i].name === monitor.name) return screens[i]
      }
    }
    return screens.length > 0 ? screens[0] : null
  }

  // Hyprland re-tiles asynchronously, so poll its geometry a few times after
  // a move instead of reading stale positions once.
  function refreshSoon() {
    settleTimer.ticks = 0
    settleTimer.restart()
  }

  // Safety net for a reposition that was cut short in an earlier session.
  function rescueParkedWindows() {
    var all = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var fallbackId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1

    for (var i = 0; i < all.length; i++) {
      var ipc = all[i] ? all[i].lastIpcObject : null
      var name = ipc && ipc.workspace ? String(ipc.workspace.name || "") : ""
      if (name !== root.parkingWorkspace) continue

      var address = root.normalizedAddress(all[i])
      if (address)
        Hyprland.dispatch("hl.dsp.window.move({ workspace = \"" + fallbackId
          + "\", window = \"address:" + address + "\", follow = false })")
    }
  }

  function open(payloadJson) {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    rescueTimer.restart()
    root.targetScreen = root.focusedScreen()
    root.draggedToplevel = null
    root.requestedWorkspaceId = -1
    root.requestedWindowAddress = ""
    root.selectedCardIndex = root.initialSelectedCardIndex()
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    // Finish a parked reposition rather than stranding the window on the
    // hidden workspace when the overview is dismissed mid-move.
    root.flushPendingReposition()

    root.draggedToplevel = null
    root.selectedCardIndex = -1
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ecylmz.spaceview")
  }

  function activateWorkspace(workspaceId) {
    if (workspaceId <= 0 || workspaceId > 10) return
    root.requestedWorkspaceId = workspaceId
    Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + workspaceId + "\" })")
    Qt.callLater(root.dismiss)
  }

  function activateWindow(toplevel) {
    var address = root.normalizedAddress(toplevel)
    if (address) {
      root.requestedWindowAddress = address
      Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + address + "\" })")
    }
    else if (toplevel && toplevel.wayland)
      toplevel.wayland.activate()
    else
      return
    Qt.callLater(root.dismiss)
  }

  function moveWindowToWorkspace(toplevel, workspaceId) {
    var address = root.normalizedAddress(toplevel)
    var sourceId = root.sourceWorkspaceId(toplevel)
    if (!address || workspaceId <= 0 || workspaceId > 10 || sourceId === workspaceId) return false

    root.draggedToplevel = null
    Hyprland.dispatch("hl.dsp.window.move({ workspace = \"" + workspaceId
      + "\", window = \"address:" + address + "\", follow = false })")
    return true
  }

  // dwindle opens a window next to the workspace's focused window, and
  // `preselect` picks the side, so focus the drop target first.
  function placeWindow(address, targetAddress, direction, workspaceId, restoreId) {
    Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + targetAddress + "\" })")
    Hyprland.dispatch("hl.dsp.layout(\"preselect " + direction + "\")")
    Hyprland.dispatch("hl.dsp.window.move({ workspace = \"" + workspaceId
      + "\", window = \"address:" + address + "\", follow = false })")

    // Focusing the drop target moved us to its workspace. Go back — unless the
    // user has since asked for somewhere else, which outranks the restore.
    if (root.requestedWindowAddress !== "")
      Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + root.requestedWindowAddress + "\" })")
    else if (root.requestedWorkspaceId > 0) {
      if (root.requestedWorkspaceId !== workspaceId)
        Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + root.requestedWorkspaceId + "\" })")
    } else if (restoreId > 0 && restoreId !== workspaceId) {
      Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + restoreId + "\" })")
    }

    root.refreshSoon()
  }

  function moveWindowNextTo(toplevel, workspaceId, target, direction) {
    var address = root.normalizedAddress(toplevel)
    var targetAddress = root.normalizedAddress(target)
    if (!address || !targetAddress || address === targetAddress) return false
    if (workspaceId <= 0 || workspaceId > 10) return false

    var restoreId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    root.draggedToplevel = null
    root.placeWindow(address, targetAddress, direction, workspaceId, restoreId)
    return true
  }

  // Hyprland ignores a move to the workspace a window is already on, so a
  // reposition parks the window on a hidden special workspace first and then
  // brings it back next to the drop target.
  function repositionWindow(toplevel, workspaceId, target, direction) {
    var address = root.normalizedAddress(toplevel)
    var targetAddress = root.normalizedAddress(target)
    if (!address || !targetAddress || address === targetAddress) return false
    if (workspaceId <= 0 || workspaceId > 10) return false

    // A window is already parked; bring it home before parking another one,
    // or it would be stranded on the hidden workspace.
    root.flushPendingReposition()

    root.draggedToplevel = null
    root.pendingReposition = {
      address: address,
      targetAddress: targetAddress,
      direction: direction,
      workspaceId: workspaceId,
      restoreId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    }

    Hyprland.dispatch("hl.dsp.window.move({ workspace = \"" + root.parkingWorkspace
      + "\", window = \"address:" + address + "\", follow = false })")
    repositionTimer.restart()
    return true
  }

  function flushPendingReposition() {
    if (!root.pendingReposition) return
    repositionTimer.stop()
    var job = root.pendingReposition
    root.pendingReposition = null
    root.placeWindow(job.address, job.targetAddress, job.direction, job.workspaceId, job.restoreId)
  }

  function beginWindowDrag(toplevel) {
    if (root.normalizedAddress(toplevel)) root.draggedToplevel = toplevel
  }

  function endWindowDrag(toplevel) {
    if (root.draggedToplevel === toplevel) root.draggedToplevel = null
  }

  PanelWindow {
    id: panel

    screen: root.targetScreen
    visible: root.opened && root.targetScreen !== null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "spaceview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The theme's menu scrim is tuned for small panels; a fullscreen grid needs
    // a deeper veil, so the theme tint is kept and backed with its background.
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.6)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: dragGhost
      z: 100
      visible: root.draggedToplevel !== null
      width: Math.max(Style.space(180), panel.width * 0.16)
      height: width / 1.5
      x: root.dragScenePosition.x - width / 2
      y: root.dragScenePosition.y - height / 2
      opacity: root.draggedToplevel !== null ? 0.92 : 0
      scale: root.draggedToplevel !== null ? 1 : 0.9
      enabled: false

      Behavior on x { NumberAnimation { duration: 45; easing.type: Easing.OutQuad } }
      Behavior on y { NumberAnimation { duration: 45; easing.type: Easing.OutQuad } }
      Behavior on opacity { NumberAnimation { duration: 110 } }
      Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

      WindowPreview {
        anchors.fill: parent
        toplevel: root.draggedToplevel
        capturing: root.draggedToplevel !== null
        enabled: false
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCardSelection(dx, dy) }
      onActivateRequested: root.activateSelectedCard()
      onCloseRequested: root.dismiss()
      onTextKey: function(text) {
        // 1..9 and 0 jump straight to that workspace.
        if (text >= "1" && text <= "9") root.activateWorkspace(Number(text))
        else if (text === "0") root.activateWorkspace(10)
      }

      Grid {
        id: workspaceGrid
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        columns: root.columns
        spacing: root.gridSpacing

        Repeater {
          model: root.overviewCardModel

          WorkspaceCard {
            required property int modelData
            required property int index

            readonly property bool isAddCard: root.nextWorkspaceId > 0
              && index === root.workspaceCount

            width: root.cardWidth
            height: root.cardHeight
            workspaceId: modelData
            workspace: isAddCard ? null : root.workspaceById(modelData)
            monitorBounds: isAddCard ? null : root.monitorBoundsFor(modelData)
            addWorkspace: isAddCard
            capturing: root.opened
            draggedToplevel: root.draggedToplevel
            keyboardSelected: index === root.selectedCardIndex
            focused: !isAddCard && Hyprland.focusedWorkspace !== null
              && Hyprland.focusedWorkspace.id === modelData
            onWorkspaceActivated: root.activateWorkspace(modelData)
            onWindowActivated: function(toplevel) { root.activateWindow(toplevel) }
            onWindowDragStarted: function(toplevel) { root.beginWindowDrag(toplevel) }
            onWindowDragMoved: function(scenePosition) { root.dragScenePosition = scenePosition }
            onWindowDroppedNextTo: function(toplevel, target, direction) {
              if (root.sourceWorkspaceId(toplevel) === modelData)
                root.repositionWindow(toplevel, modelData, target, direction)
              else
                root.moveWindowNextTo(toplevel, modelData, target, direction)
            }
            onWindowDragFinished: function(toplevel) { root.endWindowDrag(toplevel) }
            onWindowDropped: function(toplevel) { root.moveWindowToWorkspace(toplevel, modelData) }
          }
        }
      }
    }
  }

  // Anything that moves, opens or closes a window invalidates the miniature,
  // whoever caused it. Title and focus events are deliberately absent: they
  // fire constantly and would keep the settle timer restarting forever.
  Connections {
    target: Hyprland
    enabled: root.opened

    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "").toLowerCase()
      if (root.layoutEvents.indexOf(name) !== -1) root.refreshSoon()
    }
  }

  Timer {
    id: rescueTimer
    interval: 220
    onTriggered: root.rescueParkedWindows()
  }

  Timer {
    id: repositionTimer
    interval: 140
    onTriggered: root.flushPendingReposition()
  }

  Timer {
    id: settleTimer
    interval: 120
    repeat: true
    property int ticks: 0
    onTriggered: {
      Hyprland.refreshToplevels()
      Hyprland.refreshWorkspaces()
      ticks += 1
      if (ticks >= 3) {
        stop()
        ticks = 0
      }
    }
  }

  Connections {
    target: root.draggedToplevel
    ignoreUnknownSignals: true
    function onDestroyed() { root.draggedToplevel = null }
  }

  onCardCountChanged: {
    if (root.selectedCardIndex >= root.cardCount)
      root.selectedCardIndex = root.cardCount - 1
  }
}
