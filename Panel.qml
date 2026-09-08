import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.saiiiiiph.update-center"
  ipcTarget: "io.github.saiiiiiph.update-center"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var updates: []
  property bool checking: false
  property var expandedSections: ({})
  readonly property int compactRowLimit: 3
  property string completionPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-update-center-complete"
  property string completionMarker: ""
  readonly property var barIdentity: hostWidget || root
  readonly property string checkSchedule: String(setting("checkSchedule", "Every 6 hours"))
  readonly property int checkIntervalMs: {
    if (checkSchedule === "Every 30 minutes") return 30 * 60 * 1000
    if (checkSchedule === "Every 2 hours") return 2 * 60 * 60 * 1000
    if (checkSchedule === "Every 12 hours") return 12 * 60 * 60 * 1000
    if (checkSchedule === "Every 6 hours") return 6 * 60 * 60 * 1000
    return 0 // At startup only
  }

  function open() {
    root.controller.show()
    root.refresh()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (checkProcess.running) return
    checking = true
    checkProcess.running = true
  }

  function parseUpdates(raw) {
    var parsed = []
    var lines = String(raw || "").trim().split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue
      var fields = lines[i].split("\t")
      if (fields.length < 3) continue
      parsed.push({ source: fields[0], name: fields[1], detail: fields.slice(2).join("\t") })
    }
    updates = parsed
    if (hostWidget) hostWidget.updates = parsed
  }

  function count(source) {
    var total = 0
    for (var i = 0; i < updates.length; i++) if (updates[i].source === source) total++
    return total
  }

  function sectionRows(source) {
    return updates.filter(function(item) { return item.source === source })
  }

  function visibleSectionRows(source) {
    var rows = sectionRows(source)
    return sectionExpanded(source) ? rows : rows.slice(0, compactRowLimit)
  }

  function sectionExpanded(source) {
    return expandedSections[source] === true
  }

  function toggleSection(source) {
    var next = ({})
    for (var key in expandedSections) next[key] = expandedSections[key]
    next[source] = !sectionExpanded(source)
    expandedSections = next
  }

  function pendingPluginIds() {
    var ids = []
    for (var i = 0; i < updates.length; i++) {
      var item = updates[i]
      // Plugin ids come from directory names, but retain a strict allow-list
      // before interpolating one into a terminal command.
      if (item.source === "plugin" && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(item.name))
        ids.push(item.name)
    }
    return ids
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function runInTerminal(command) {
    // Kept behind && so a failed or cancelled update never masquerades as a
    // success at the bottom of the terminal. The marker is watched below, so
    // the bar is refreshed immediately after a successful update finishes.
    var completedCommand = command
      + " && date +%s%N > " + shellQuote(completionPath)
      + " && printf '\\n\\033[1;32m✓ Mise à jour OK.\\033[0m\\n'"
    bar.run("omarchy-launch-floating-terminal-with-presentation bash -lc " + shellQuote(completedCommand))
  }

  FileView {
    path: root.completionPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var marker = String(text() || "").trim()
      if (marker !== "" && marker !== root.completionMarker) {
        root.completionMarker = marker
        root.refresh()
      }
    }
  }

  function launch(kind) {
    if (!bar) return
    if (kind === "system" || kind === "aur") runInTerminal("omarchy update")
    else if (kind === "flatpak") runInTerminal("flatpak update")
    else if (kind === "plugin") runInTerminal("omarchy plugin update")
    else runInTerminal("omarchy update && flatpak update && omarchy plugin update")
  }

  Process {
    id: checkProcess
    command: ["bash", Qt.resolvedUrl("check-updates.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseUpdates(text)
    }
    onExited: function() { root.checking = false }
  }

  Timer {
    interval: root.checkIntervalMs > 0 ? root.checkIntervalMs : 60000
    running: root.checkIntervalMs > 0
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: Qt.callLater(root.refresh)

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(410))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(520))

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            width: parent.width - refreshButton.width - Style.space(10)
            text: root.checking ? "Checking updates…" : (root.updates.length ? root.updates.length + " updates available" : "Everything is up to date")
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          Button {
            id: refreshButton
            text: "Refresh"
            foreground: root.barForeground
            bordered: true
            onClicked: root.refresh()
          }
        }

        Text {
          width: parent.width
          visible: root.updates.length > 0
          text: "Nothing is installed automatically. Updates always open in a terminal."
          wrapMode: Text.WordWrap
          color: Qt.darker(root.barForeground, 1.35)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: [
            { id: "system", title: "System", action: "Update system" },
            { id: "aur", title: "AUR", action: "Update AUR" },
            { id: "flatpak", title: "Flatpak", action: "Update Flatpak" },
            { id: "plugin", title: "Omarchy plugins", action: "Update plugins" }
          ]
          delegate: Column {
            required property var modelData
            width: content.width
            spacing: Style.space(6)
            visible: root.count(modelData.id) > 0
            PanelSeparator { foreground: root.barForeground }
            Row {
              width: parent.width
              spacing: Style.space(8)
              Text {
                width: parent.width - updateButton.width - detailsButton.width - Style.space(16)
                text: modelData.title + " · " + root.count(modelData.id)
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Button {
                id: updateButton
                text: modelData.action
                foreground: root.barForeground
                bordered: true
                onClicked: root.launch(modelData.id)
              }
              Button {
                id: detailsButton
                visible: root.count(modelData.id) > root.compactRowLimit
                text: root.sectionExpanded(modelData.id)
                  ? "Less"
                  : "Show all (" + root.count(modelData.id) + ")"
                foreground: root.barForeground
                bordered: true
                onClicked: root.toggleSection(modelData.id)
              }
            }
            Repeater {
              model: root.visibleSectionRows(modelData.id)
              delegate: Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(10)
                Text {
                  width: parent.width * 0.54
                  text: modelData.name
                  elide: Text.ElideRight
                  color: root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width * 0.42
                  text: modelData.detail
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignRight
                  color: Qt.darker(root.barForeground, 1.35)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }

        Item { visible: root.updates.length === 0; width: 1; height: Style.space(4) }
        Button {
          visible: root.updates.length > 0
          text: "Update everything"
          foreground: root.barForeground
          bordered: true
          onClicked: root.launch("all")
        }
      }
    }
  }
}
