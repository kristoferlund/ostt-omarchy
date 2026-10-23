import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Dictation status for OSTT. The widget is only a client: the recording runs
// in the background under `ostt-dictate`, so closing or reloading the bar never
// abandons a recording. Status comes from `ostt-dictate status --follow`,
// which prints a JSON line whenever the state changes.
//
// Right-click while idle opens a card listing the apps on the visible
// workspaces (and any already set up), each with a dropdown choosing the
// processing action for context-aware dictation in that app.
Panel {
  id: root
  moduleName: "ostt.dictation"

  // idle | recording | transcribing | error, or "" while OSTT is unavailable.
  property string phase: ""
  property string errorText: ""
  // An error is shown prominently for a while, then the widget calms down;
  // the next dictation clears it.
  property bool errorFresh: false
  readonly property bool hideWhenIdle: setting("hideWhenIdle", false)

  readonly property bool busy: phase === "recording" || phase === "transcribing"

  // From `ostt-dictate apps`: [{ class, title, action }] and [{ id, name }].
  property var apps: []
  property var actionOptions: [{ value: "", label: "None" }]
  property string appsError: ""

  visible: phase !== "" && !(hideWhenIdle && !busy && !errorFresh)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function apply(line) {
    var status
    try {
      status = JSON.parse(String(line))
    } catch (e) {
      return
    }
    var previous = root.phase
    root.phase = String(status.state || "idle")
    root.errorText = String(status.error || "")
    if (root.phase === "error" && previous !== "error" && previous !== "") {
      root.errorFresh = true
      errorTimer.restart()
    } else if (root.phase !== "error") {
      root.errorFresh = false
    }
  }

  function run(action) {
    if (root.bar) root.bar.run("ostt-dictate " + action)
  }

  function loadApps(text) {
    var data
    try {
      data = JSON.parse(String(text))
    } catch (e) {
      root.appsError = "Could not list apps."
      return
    }
    var options = [{ value: "", label: "None" }]
    var actions = data.actions || []
    for (var i = 0; i < actions.length; i++)
      options.push({ value: String(actions[i].id), label: String(actions[i].name || actions[i].id) })
    root.actionOptions = options
    root.apps = data.apps || []
    root.appsError = String(data.error || "")
  }

  function setAction(appClass, action) {
    mapProc.command = action === ""
      ? ["ostt-dictate", "map", appClass]
      : ["ostt-dictate", "map", appClass, action]
    mapProc.running = true
  }

  onOpenedChanged: if (opened) appsProc.running = true

  Process {
    id: follower
    command: ["ostt-dictate", "status", "--json", "--follow"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.apply(line) }
    }
    onExited: function() {
      // ostt-dictate missing, or replaced by an update: hide and try again shortly.
      root.phase = ""
      restartTimer.restart()
    }
  }

  Process {
    id: appsProc
    command: ["ostt-dictate", "apps"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadApps(text) }
  }

  Process {
    id: mapProc
    stderr: StdioCollector { id: mapErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.appsError = String(mapErr.text || "Could not save the change.").trim()
      appsProc.running = true
    }
  }

  Timer {
    id: restartTimer
    interval: 5000
    onTriggered: follower.running = true
  }

  Timer {
    id: errorTimer
    interval: 15000
    onTriggered: root.errorFresh = false
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      if (root.phase === "transcribing") return "󰔟"
      if (root.phase === "error" && root.errorFresh) return "󰍭"
      return "󰍬"
    }
    active: root.phase === "recording" || (root.phase === "error" && root.errorFresh)
    dimmed: root.phase === "idle" || (root.phase === "error" && !root.errorFresh)
    tooltipText: {
      if (root.phase === "recording") return "OSTT is recording. Click to paste, right-click to cancel."
      if (root.phase === "transcribing") return "OSTT is transcribing. Right-click to cancel."
      if (root.phase === "error") return "OSTT dictation failed:\n" + root.errorText
      return "OSTT dictation. Click to start, right-click to choose apps with screen context."
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.busy) root.run("cancel")
        else root.toggle()
      } else if (b === Qt.LeftButton) {
        // Toggle refuses new work while transcribing; nothing to do then.
        if (root.phase !== "transcribing") root.run("toggle")
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: {
        for (var i = 0; i < rows.count; i++) {
          var row = rows.itemAt(i)
          if (row && row.dropdownOpen) return true
        }
        return false
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "SCREEN CONTEXT PER APP"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.appsError !== "" ? root.appsError
            : "Dictation in an app with an action sends a screenshot of its window with your words to that action."
          color: root.bar.foreground
          opacity: root.appsError !== "" ? 1 : 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          id: rows
          model: root.apps

          Item {
            id: row
            required property var modelData
            readonly property bool dropdownOpen: dropdown.popupOpen
            width: column.width
            implicitHeight: Math.max(labels.implicitHeight, dropdown.implicitHeight)

            Column {
              id: labels
              anchors.left: parent.left
              anchors.right: dropdown.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: String(row.modelData["class"])
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.modelData.title ? String(row.modelData.title) : "Not on a visible workspace"
                color: root.bar.foreground
                opacity: 0.6
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Dropdown {
              id: dropdown
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              showLabel: false
              fontFamily: root.bar.fontFamily
              options: root.actionOptions
              value: String(row.modelData.action || "")
              onChanged: function(v) { root.setAction(String(row.modelData["class"]), v) }
            }
          }
        }
      }
    }
  }
}
