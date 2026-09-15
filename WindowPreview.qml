import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// One window tile inside a workspace card: a live Wayland capture of the
// toplevel with a title strip underneath. Falls back to the app icon when
// the compositor has no frame to hand us (e.g. a freshly mapped window).
BorderSurface {
  id: root

  required property var toplevel

  readonly property var waylandToplevel: toplevel ? toplevel.wayland : null
  readonly property string address: toplevel ? String(toplevel.address || "") : ""
  readonly property bool activatable: waylandToplevel !== null || address !== ""
  readonly property bool dragging: dragProxy.dragSessionActive
  readonly property string appId: waylandToplevel ? String(waylandToplevel.appId || "") : ""
  readonly property string title: toplevel ? String(toplevel.title || appId || "Window") : "Window"
  readonly property var desktopEntry: {
    if (!appId) return null
    return DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId)
  }
  readonly property string iconSource: {
    if (!desktopEntry || !desktopEntry.icon) return ""
    return Quickshell.iconPath(desktopEntry.icon, true)
  }
  readonly property real titleHeight: Math.min(height * 0.3,
    Math.max(Style.space(28), Style.font.bodySmall + Style.spacing.controlPaddingY * 2))

  // "l", "r", "u" or "d" while a dragged window would land on that side of
  // this one; empty when this tile is not the drop target.
  property string dropDirection: ""

  readonly property point dragScenePosition: previewDrag.active
    ? previewDrag.centroid.scenePosition : Qt.point(0, 0)

  // The capture is a single frame, so it has to be retaken whenever the
  // compositor resizes the window under it — otherwise a re-tiled window
  // keeps the shape it had when the overview opened.
  readonly property var ipcObject: toplevel ? toplevel.lastIpcObject : null
  property var capturedSize: null

  // A tile is reused when its window closes or when the drag ghost changes
  // hands, so forget the captured size or a same-sized successor keeps the
  // previous window's frame.
  onToplevelChanged: {
    capturedSize = null
    if (toplevel) recaptureTimer.restart()
  }

  onIpcObjectChanged: {
    var size = ipcObject && ipcObject.size ? ipcObject.size : null
    if (!size) return
    if (capturedSize && capturedSize[0] === size[0] && capturedSize[1] === size[1]) return
    capturedSize = size
    recaptureTimer.restart()
  }

  // Give the client a moment to draw at its new size before recapturing.
  Timer {
    id: recaptureTimer
    interval: 180
    onTriggered: preview.captureFrame()
  }

  signal activated()
  signal dragStarted(var toplevel)
  signal dragFinished(var toplevel)
  signal dragMoved(point scenePosition)

  onDragScenePositionChanged: if (previewDrag.active) root.dragMoved(dragScenePosition)

  radius: Style.cornerRadius
  color: previewHover.hovered || dragging
    ? Style.hoverFillFor(Color.menu.text, Color.accent)
    : Util.alpha(Color.background, 0.52)
  borderSpec: previewHover.hovered
    ? Border.controlSpec("hover-cursor", Color.menu.text, Color.accent)
    : Border.flat(Util.alpha(Color.menu.border, 0.32), Math.max(1, Style.normalBorderWidth))
  clip: true
  opacity: dragging ? 0.58 : 1

  Behavior on color { ColorAnimation { duration: 60 } }
  Behavior on opacity { NumberAnimation { duration: 60 } }

  Item {
    id: imageArea
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true

    ScreencopyView {
      id: preview
      anchors.centerIn: parent
      captureSource: root.waylandToplevel
      live: false
      paintCursor: false
      width: {
        if (!hasContent || sourceSize.width <= 0 || sourceSize.height <= 0) return parent.width
        return Math.min(parent.width, parent.height * sourceSize.width / sourceSize.height)
      }
      height: {
        if (!hasContent || sourceSize.width <= 0 || sourceSize.height <= 0) return parent.height
        return Math.min(parent.height, parent.width * sourceSize.height / sourceSize.width)
      }
      visible: hasContent
    }

    Image {
      visible: !preview.hasContent && source !== ""
      anchors.centerIn: parent
      width: Math.min(parent.width, parent.height) * 0.34
      height: width
      source: root.iconSource
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      opacity: 0.72
    }
  }

  Rectangle {
    id: dropZone
    visible: root.dropDirection !== ""
    z: 10
    color: Style.selectedFillFor(Color.menu.text, Color.accent)
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Color.accent

    readonly property bool horizontal: root.dropDirection === "l" || root.dropDirection === "r"
    width: horizontal ? parent.width / 2 : parent.width
    height: horizontal ? parent.height : parent.height / 2
    x: root.dropDirection === "r" ? parent.width / 2 : 0
    y: root.dropDirection === "d" ? parent.height / 2 : 0

    Behavior on x { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
    Behavior on y { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
    Behavior on width { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
    Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
  }

  Rectangle {
    id: titleBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: root.titleHeight
    color: Util.alpha(Color.menu.background, 0.92)

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.md
      anchors.rightMargin: Style.spacing.md
      spacing: Style.spacing.sm

      Image {
        id: appIcon
        visible: source !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? Style.font.icon : 0
        height: width
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - (appIcon.visible ? appIcon.width + parent.spacing : 0)
        text: root.title
        textFormat: Text.PlainText
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  HoverHandler {
    id: previewHover
    cursorShape: root.dragging ? Qt.ClosedHandCursor
      : (root.activatable ? Qt.PointingHandCursor : Qt.ArrowCursor)
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    enabled: root.activatable
    onTapped: root.activated()
  }

  // Dragging a tile onto another workspace card moves the window there.
  DragHandler {
    id: previewDrag
    acceptedButtons: Qt.LeftButton
    enabled: root.address !== ""
    target: null
    dragThreshold: Style.space(6)

    onActiveChanged: {
      if (active) {
        dragProxy.dragSessionActive = true
        root.dragStarted(root.toplevel)
      } else if (dragProxy.dragSessionActive) {
        dragProxy.Drag.drop()
        dragProxy.dragSessionActive = false
        root.dragFinished(root.toplevel)
      }
    }
  }

  Item {
    id: dragProxy
    property bool dragSessionActive: false
    property real lastX: 0
    property real lastY: 0

    x: previewDrag.active ? previewDrag.centroid.position.x : lastX
    y: previewDrag.active ? previewDrag.centroid.position.y : lastY
    width: 1
    height: 1
    onXChanged: if (previewDrag.active) lastX = x
    onYChanged: if (previewDrag.active) lastY = y
    Drag.active: dragSessionActive
    Drag.source: root
    Drag.keys: ["ecylmz.spaceview-window"]
    Drag.supportedActions: Qt.MoveAction
    Drag.proposedAction: Qt.MoveAction
  }
}
