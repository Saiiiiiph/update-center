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
  property string completionPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-update-center-complete"
  property string completionMarker: ""
  readonly property var barIdentity: hostWidget || root

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

  function pluginUpdateCommand() {
    return Qt.resolvedUrl("run-plugin-update.sh").toString().replace("file://", "")
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
    if (kind === "system") runInTerminal("omarchy update")
    else if (kind === "flatpak") runInTerminal("flatpak update")
    else if (kind === "plugin") {
      var pluginCommand = pluginUpdateCommand()
      if (pluginCommand) bar.run("omarchy-launch-floating-terminal-with-presentation bash " + pluginCommand)
    } else {
      var allCommand = "omarchy update && flatpak update"
      var pluginUpdates = pluginUpdateCommand()
      if (pluginUpdates) allCommand += " && " + pluginUpdates
      runInTerminal(allCommand)
    }
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
    interval: 21600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

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
            { id: "system", title: "System & AUR", action: "Update system" },
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
                width: parent.width - updateButton.width - Style.space(8)
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
            }
            Repeater {
              model: root.updates.filter(function(item) { return item.source === modelData.id })
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
