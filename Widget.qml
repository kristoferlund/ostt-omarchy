import QtQuick
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
// workspaces (and any already set up) with their current settings. Clicking a
// row expands it in place, as the network panel does, to choose the
// processing action for dictation in that app and whether to attach a
// screenshot of its window.
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

  // From `ostt-dictate apps`: [{ class, name, icon, title, action,
  // screenshot }] and [{ id, name }].
  property var apps: []
  property var actionOptions: [{ value: "", label: "None" }]
  property string appsError: ""
  // The class of the one expanded row; kept across reloads after a change.
  property string expandedClass: ""

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

  function iconSource(icon) {
    if (icon === "") return ""
    if (icon.charAt(0) === "/") return "file://" + icon
    return Quickshell.iconPath(icon, true)
  }

  onOpenedChanged: {
    if (opened) appsProc.running = true
    else root.expandedClass = ""
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.expandedClass !== "") root.expandedClass = ""
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(4)

        PanelSectionHeader {
          text: "DICTATION PER APP"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Text {
          width: parent.width
          bottomPadding: Style.space(6)
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.appsError !== "" ? root.appsError
            : root.apps.length === 0 ? "No apps are open on the visible workspaces."
            : "Choose what happens to dictation in each app. Other apps get plain dictation."
          color: root.appsError !== "" ? root.bar.urgent : root.bar.foreground
          opacity: root.appsError !== "" ? 1 : 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.apps
          delegate: AppRow {}
        }
      }
    }
  }

  // One app: icon, name and class, and its current setting. Expands in place
  // to the action pills and the screenshot switch.
  component AppRow: CursorSurface {
    id: row
    required property var modelData
    readonly property string appClass: String(modelData["class"])
    readonly property string appName: String(modelData.name || appClass)
    readonly property string action: String(modelData.action || "")
    readonly property bool screenshot: modelData.screenshot === true
    readonly property bool expanded: root.expandedClass === appClass

    width: column.width
    implicitHeight: header.height + (expanded ? settingsBody.implicitHeight : 0)
    hasCursor: headerMouse.containsMouse && !expanded
    current: expanded
    foreground: root.bar.foreground
    currentFill: Style.normalFillFor(root.bar.foreground, Commons.Color.accent)
    clip: true

    MouseArea {
      id: headerMouse
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: header.height
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.expandedClass = row.expanded ? "" : row.appClass
    }

    Item {
      id: header
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      height: Math.max(appIcon.height, names.implicitHeight) + Style.spacing.rowPaddingX

      Image {
        id: appIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(22)
        height: width
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        source: root.iconSource(String(row.modelData.icon || ""))
        visible: status === Image.Ready
      }
      Text {
        anchors.centerIn: appIcon
        visible: !appIcon.visible
        textFormat: Text.PlainText
        text: "󰣆"
        color: root.bar.foreground
        opacity: 0.6
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
      }

      Column {
        id: names
        anchors.left: appIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: summary.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: row.appName
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          visible: row.appName !== row.appClass
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: row.appClass
          color: root.bar.foreground
          opacity: 0.5
          font.family: "monospace"
          font.pixelSize: Style.font.caption
        }
      }

      // Current setting at a glance: the action, with a camera when a
      // screenshot goes along.
      Row {
        id: summary
        anchors.right: chevron.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: row.action !== "" && row.screenshot
          textFormat: Text.PlainText
          text: "󰄀"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, header.width * 0.5)
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: row.action !== "" ? root.actionLabel(row.action) : "Plain dictation"
          color: root.bar.foreground
          opacity: row.action !== "" ? 0.9 : 0.5
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.expanded ? "󰅀" : "󰅂"
        color: root.bar.foreground
        opacity: 0.6
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Column {
      id: settingsBody
      visible: row.expanded
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: header.bottom
      // Lined up with the app name, past the icon.
      anchors.leftMargin: Style.space(10) + appIcon.width + Style.space(4)
      anchors.rightMargin: Style.space(10)
      topPadding: Style.space(2)
      bottomPadding: Style.space(12)
      spacing: Style.space(10)

      Column {
        width: parent.width
        spacing: Style.space(4)

        PanelSectionHeader {
          leftPadding: Style.space(6)
          text: "ACTION"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Repeater {
          model: root.actionOptions

          // One choice; the current one carries a check mark.
          CursorSurface {
            id: option
            required property var modelData
            readonly property string value: String(modelData.value)
            readonly property bool chosen: value === row.action
            width: parent.width
            implicitHeight: optionLabel.implicitHeight + Style.space(12)
            hasCursor: optionMouse.containsMouse
            foreground: root.bar.foreground

            Text {
              id: optionLabel
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.right: check.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: option.value === "" ? "None, plain dictation" : String(option.modelData.label)
              color: root.bar.foreground
              opacity: option.chosen ? 1 : 0.75
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              id: check
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              visible: option.chosen
              textFormat: Text.PlainText
              text: "󰄬"
              color: Commons.Color.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: optionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (!mapProc.running && !option.chosen) root.setApp(row.appClass, option.value, row.screenshot)
            }
          }
        }
      }

      // Only an app with an action can send a screenshot.
      Item {
        x: Style.space(6)
        width: parent.width - x
        implicitHeight: Math.max(shotText.implicitHeight, shotSwitch.implicitHeight)
        enabled: row.action !== ""
        opacity: enabled ? 1 : 0.4

        Column {
          id: shotText
          anchors.left: parent.left
          anchors.right: shotSwitch.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Send a screenshot"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: "The action sees the window as it is when dictation starts."
            color: root.bar.foreground
            opacity: 0.5
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        ToggleSwitch {
          id: shotSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: row.screenshot
          busy: mapProc.running
          foreground: root.bar.foreground
          onToggled: root.setApp(row.appClass, row.action, !row.screenshot)
        }
      }
    }
  }
}
