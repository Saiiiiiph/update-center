import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.saiiiiiph.update-center"

  property var updates: []
  property var anchorItem: null
  property var hostWidget: root
  readonly property int updateCount: updates.length
  readonly property bool initialCheckFinished: panelLoader.item ? panelLoader.item.hasCompletedFirstCheck === true : false
  readonly property bool checking: !initialCheckFinished || (panelLoader.item ? panelLoader.item.checking : false)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item) panelLoader.item.refresh()
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.refresh)
    }
  }

  IpcHandler {
    target: "io.github.saiiiiiph.update-center"
    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A package is clearer than a sync-arrow here: this widget gathers
    // updates from several package sources, rather than merely refreshing.
    text: root.checking ? "󰑐" : "󰏗"
    // This is an interactive plugin entry, not a passive status dot: keep
    // the normal icon slot so it carries the same visual weight as peers.
    slotSize: Style.bar.iconSlot
    fontSize: Style.bar.iconFont
    active: root.updateCount > 0
    tooltipText: root.checking ? "Checking for updates…" : (root.updateCount > 0 ? root.updateCount + " updates available" : "Everything is up to date")
    onPressed: function(button) {
      if (button === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Text {
      visible: root.updateCount > 0 && !root.vertical
      anchors.left: parent.right
      anchors.leftMargin: -Style.space(7)
      anchors.top: parent.top
      text: root.updateCount > 99 ? "99+" : String(root.updateCount)
      color: root.bar ? root.bar.foreground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption * 0.72
      font.bold: true
    }
  }
}
