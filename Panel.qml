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
  property var knownUpdateKeys: ({})
  property bool hasCompletedFirstCheck: false
  property var lastCheckedAt: null
  property var lastUpdatedAt: null
  readonly property int compactRowLimit: 3
  property string completionPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-update-center-complete"
  property string completionMarker: ""
  property string stateDirectory: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy-update-center"
  property string lastUpdatePath: stateDirectory + "/last-update"
  readonly property var barIdentity: hostWidget || root
  readonly property string checkSchedule: String(setting("checkSchedule", "Every 6 hours"))
  readonly property var offerShutdownActionValue: setting("offerShutdownAction", true)
  readonly property bool offerShutdownAction: offerShutdownActionValue === true || String(offerShutdownActionValue) === "true"
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
    var nextKeys = ({})
    var newlyAvailable = 0
    var lines = String(raw || "").trim().split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue
      var fields = lines[i].split("\t")
      if (fields.length < 3) continue
      var item = { source: fields[0], name: fields[1], detail: fields.slice(2).join("\t") }
      var key = item.source + "\t" + item.name
      nextKeys[key] = true
      if (hasCompletedFirstCheck && !knownUpdateKeys[key]) newlyAvailable++
      parsed.push(item)
    }
    updates = parsed
    knownUpdateKeys = nextKeys
    lastCheckedAt = new Date()
    hasCompletedFirstCheck = true
    if (hostWidget) hostWidget.updates = parsed
    if (newlyAvailable > 0) notifyNewUpdates(newlyAvailable)
  }

  function notifyNewUpdates(count) {
    if (!bar) return
    var message = count === 1
      ? "1 new update is available."
      : count + " new updates are available."
    bar.run("notify-send " + shellQuote("Update Center") + " " + shellQuote(message))
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (hostWidget && "settings" in hostWidget) hostWidget.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setCheckSchedule(schedule) {
    if (schedule === checkSchedule) return
    persistSettings({ checkSchedule: schedule })
    refresh()
  }

  function count(source) {
    var total = 0
    for (var i = 0; i < updates.length; i++) if (updates[i].source === source) total++
    return total
  }

  function displayName(item) {
    if (item.source === "plugin" && item.name === root.moduleName) return "Update Center"
    return item.name
  }

  function sectionRows(source) {
    return updates.filter(function(item) { return item.source === source })
  }

  function visibleSectionRows(source) {
    var rows = sectionRows(source)
    // System update lists are often long. Keep that section to its heading
    // until the user explicitly asks for the package names.
    if (source === "system" && !sectionExpanded(source)) return []
    // Flatpak and plugin updates stay compact as soon as there is more than
    // one row, while a single update remains immediately visible.
    if ((source === "flatpak" || source === "plugin")
        && rows.length > 1 && !sectionExpanded(source)) return []
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
      + " && mkdir -p " + shellQuote(stateDirectory)
      + " && date +%s%N | tee " + shellQuote(completionPath) + " > " + shellQuote(lastUpdatePath)
      + " && printf '\\n\\033[1;32m✓ Update complete.\\033[0m\\n'"
    // The Omarchy terminal wrapper rebuilds its command from its arguments.
    // Pass the complete script as one argument: an inner `bash -lc` would
    // otherwise receive only `omarchy` and silently skip the `update` action.
    bar.run("omarchy-launch-floating-terminal-with-presentation " + shellQuote(completedCommand))
  }

  // Flatpak is optional in Omarchy. Treat a missing executable as a skipped
  // update, while still propagating a real `flatpak update` failure.
  function flatpakUpdateCommand() {
    return "{ ! command -v flatpak >/dev/null 2>&1 || flatpak update; }"
  }

  function updateChain() {
    return "omarchy update && " + flatpakUpdateCommand() + " && omarchy plugin update --yes"
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

  FileView {
    path: root.lastUpdatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var timestamp = Number(String(text() || "").trim())
      root.lastUpdatedAt = isNaN(timestamp) || timestamp <= 0 ? null : new Date(timestamp / 1000000)
    }
  }

  function launch(kind) {
    if (!bar) return
    if (kind === "system" || kind === "aur") runInTerminal("omarchy update")
    else if (kind === "flatpak") runInTerminal(flatpakUpdateCommand())
    else if (kind === "plugin") runInTerminal("omarchy plugin update --yes")
    else runInTerminal(updateChain())
  }

  function updateThenShutdown() {
    if (!bar) return
    var command = updateChain()
      + " && mkdir -p " + shellQuote(stateDirectory)
      + " && date +%s%N > " + shellQuote(lastUpdatePath)
      + " && omarchy system shutdown"
    bar.run("omarchy-launch-floating-terminal-with-presentation " + shellQuote(command))
  }

  function shutdownAnyway() {
    if (!bar) return
    bar.run("omarchy-system-shutdown")
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

  // A shell can appear before Wi-Fi or package mirrors are ready. This is a
  // one-off boot retry, not an additional recurring schedule.
  Timer {
    interval: 30000
    running: true
    repeat: false
    onTriggered: if (root.updates.length === 0) root.refresh()
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
          Column {
            width: parent.width - refreshButton.width - Style.space(10)
            spacing: Style.space(2)
            Text {
              width: parent.width
              text: (root.checking || !root.hasCompletedFirstCheck)
                ? "Checking updates…"
                : (root.updates.length ? root.updates.length + " updates available" : "Everything is up to date")
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              width: parent.width
              text: root.lastCheckedAt
                ? "Last check: " + Qt.formatDateTime(root.lastCheckedAt, "ddd d MMM · HH:mm")
                : "Not checked yet"
              color: Qt.darker(root.barForeground, 1.35)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              text: root.lastUpdatedAt
                ? "Last update: " + Qt.formatDateTime(root.lastUpdatedAt, "ddd d MMM · HH:mm")
                : "Last update: never"
              color: Qt.darker(root.barForeground, 1.35)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
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

        Column {
          visible: root.updates.length > 0 && root.offerShutdownAction
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { foreground: root.barForeground }

          Text {
            width: parent.width
            text: "Updates are waiting"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Button {
            width: parent.width
            text: "Update everything"
            foreground: root.barForeground
            bordered: true
            onClicked: root.launch("all")
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Update & shut down"
              foreground: root.barForeground
              bordered: true
              onClicked: root.updateThenShutdown()
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Shut down anyway"
              foreground: root.barForeground
              bordered: true
              onClicked: root.shutdownAnyway()
            }
          }
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
                visible: modelData.id === "system"
                  ? root.count(modelData.id) > 0
                  : ((modelData.id === "flatpak" || modelData.id === "plugin")
                     ? root.count(modelData.id) > 1
                     : root.count(modelData.id) > root.compactRowLimit)
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
                  text: root.displayName(modelData)
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

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSeparator { foreground: root.barForeground }

          Text {
            text: "Check for updates"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: [
                { value: "At startup only", label: "Startup" },
                { value: "Every 30 minutes", label: "30 min" },
                { value: "Every 2 hours", label: "2 hours" },
                { value: "Every 6 hours", label: "6 hours" },
                { value: "Every 12 hours", label: "12 hours" }
              ]
              delegate: Button {
                required property var modelData
                text: root.checkSchedule === modelData.value ? "✓ " + modelData.label : modelData.label
                foreground: root.barForeground
                bordered: true
                onClicked: root.setCheckSchedule(modelData.value)
              }
            }
          }
        }

      }
    }
  }
}
