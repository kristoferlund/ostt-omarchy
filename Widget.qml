import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Dictation status for OSTT. The widget is only a client: the recording runs
// in the background under `ostt-dictate`, so closing or reloading the bar never
// abandons a recording. Status comes from `ostt-dictate status --follow`,
// which prints a JSON line whenever the state changes.
//
// Right-click while idle opens a card listing the apps on the visible
// workspaces (and any already set up) with their current settings. Each row's
// cog opens a popup choosing the processing action for dictation in that app
// and whether to attach a screenshot of its window.
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

  // From `ostt-dictate apps`: [{ class, name, title, action, screenshot }]
  // and [{ id, name }].
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

  function setApp(appClass, action, screenshot) {
    var command = ["ostt-dictate", "map", appClass]
    if (action !== "") command.push(action)
    if (action !== "" && screenshot) command.push("--screenshot")
    mapProc.command = command
    mapProc.running = true
  }

  function actionLabel(action) {
    for (var i = 0; i < root.actionOptions.length; i++)
      if (root.actionOptions[i].value === action) return root.actionOptions[i].label
    return action
  }

  function appByClass(appClass) {
    for (var i = 0; i < root.apps.length; i++)
      if (String(root.apps[i]["class"]) === appClass) return root.apps[i]
    return null
  }

  onOpenedChanged: {
    if (opened) appsProc.running = true
    else settings.close()
  }

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
      return "OSTT dictation. Click to start, right-click to choose actions per app."
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
    // The settings popup draws inside the card, so the card grows to fit it.
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, settings.opened ? settings.implicitHeight : 0))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: settings.opened
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "DICTATION PER APP"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.appsError !== "" ? root.appsError
            : "Dictation in an app with an action sends your words to that action, and a screenshot of the app's window if you allow it."
          color: root.bar.foreground
          opacity: root.appsError !== "" ? 1 : 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.apps

          // App name and class | current settings | cog.
          Item {
            id: row
            required property var modelData
            readonly property string appClass: String(row.modelData["class"])
            readonly property string action: String(row.modelData.action || "")
            width: column.width
            implicitHeight: Math.max(app.implicitHeight, summary.implicitHeight, cog.implicitHeight)

            Column {
              id: app
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Math.round(parent.width * 0.45)
              spacing: Style.space(2)

              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: String(row.modelData.name || row.appClass)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.appClass
                color: root.bar.foreground
                opacity: 0.6
                font.family: "monospace"
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              id: summary
              anchors.left: app.right
              anchors.leftMargin: Style.space(10)
              anchors.right: cog.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.action !== "" ? root.actionLabel(row.action) : "Plain dictation"
                color: root.bar.foreground
                opacity: row.action !== "" ? 1 : 0.6
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                visible: row.action !== ""
                text: row.modelData.screenshot === true ? "With screenshot" : "No screenshot"
                color: root.bar.foreground
                opacity: 0.6
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Button {
              id: cog
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒓"
              tooltipText: "Settings for " + String(row.modelData.name || row.appClass)
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: settings.show(row.appClass, row.mapToItem(keyCatcher, 0, 0).y)
            }
          }
        }
      }

      // One app's settings, over the card next to its row.
      Popup {
        id: settings
        property string appClass: ""
        property real rowY: 0
        readonly property var app: root.appByClass(settings.appClass)
        readonly property string action: settings.app ? String(settings.app.action || "") : ""
        readonly property bool screenshot: settings.app ? settings.app.screenshot === true : false
        readonly property var borderSpec: Border.localOrSurfaceSpec("popups", "border", Commons.Color.popups.border, Commons.Color.popups.border, Style.normalBorderWidth)

        function show(appClass, y) {
          settings.appClass = appClass
          settings.rowY = y
          settings.open()
        }

        x: 0
        y: Math.max(0, Math.min(settings.rowY, keyCatcher.height - settings.height))
        width: keyCatcher.width
        padding: Style.space(12)
        focus: true

        background: BorderSurface {
          color: Commons.Color.popups.background
          borderSpec: settings.borderSpec
          radius: Style.cornerRadius
        }

        contentItem: Column {
          spacing: Style.space(8)
          Keys.onEscapePressed: settings.close()

          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: settings.app ? String(settings.app.name || settings.appClass) : settings.appClass
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: settings.appClass
            color: root.bar.foreground
            opacity: 0.6
            font.family: "monospace"
            font.pixelSize: Style.font.caption
          }

          Text {
            topPadding: Style.space(4)
            textFormat: Text.PlainText
            text: "ACTION"
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Repeater {
            model: root.actionOptions
            Button {
              required property var modelData
              width: parent.width
              leftAlign: true
              text: modelData.value === "" ? "None, plain dictation" : String(modelData.label)
              selected: modelData.value === settings.action
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: if (!mapProc.running) root.setApp(settings.appClass, String(modelData.value), settings.screenshot)
            }
          }

          // Only an app with an action can send a screenshot.
          Toggle {
            width: parent.width
            enabled: settings.action !== ""
            opacity: enabled ? 1 : 0.4
            label: "Send a screenshot"
            description: "Of the app's window when dictation starts, to the action"
            checked: settings.screenshot
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            titleSize: Style.font.bodySmall
            onClicked: if (enabled && !mapProc.running) root.setApp(settings.appClass, settings.action, !settings.screenshot)
          }
        }
      }
    }
  }
}
