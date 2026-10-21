import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The recording popup. `ostt-dictate start` summons it; from then on it
// follows `ostt-dictate status --follow` and closes itself once the dictation
// is pasted, cancelled or has failed. It never takes focus or clicks, so the
// text still lands in the app you were typing in.
Item {
  id: root

  // Read by the shell: whether the popup is showing.
  property bool opened: false
  // The window stays mapped until the fade-out has finished.
  property bool mapped: false
  property string phase: "recording"
  property var levels: []
  property int seconds: 0

  function open(payloadJson) {
    closeTimer.stop()
    if (!root.mapped) {
      root.levels = []
      root.seconds = 0
      root.phase = "recording"
    }
    root.mapped = true
    root.opened = true
  }

  function close() {
    root.opened = false
    closeTimer.restart()
  }

  function apply(line) {
    var status
    try {
      status = JSON.parse(String(line))
    } catch (e) {
      return
    }
    var state = String(status.state || "idle")
    if (state === "recording" || state === "transcribing") {
      root.phase = state
    } else if (root.opened) {
      // Idle or failed: OSTT has pasted, the user cancelled, or the error
      // went out as a notification. Nothing left to show.
      root.close()
    }
  }

  // RMS level in dBFS, as ffmpeg's astats prints it, to a bar height.
  function pushLevel(line) {
    var text = String(line)
    var mark = text.indexOf("RMS_level=")
    if (mark < 0) return
    var db = parseFloat(text.slice(mark + 10))
    if (isNaN(db)) db = -100
    var level = Math.max(0, Math.min(1, (db + 55) / 45))
    var next = root.levels.slice(-(pill.bars - 1))
    next.push(level)
    root.levels = next
  }

  Timer {
    id: closeTimer
    interval: Style.duration(220)
    onTriggered: root.mapped = false
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.phase === "recording"
    onTriggered: root.seconds += 1
  }

  Process {
    command: ["ostt-dictate", "status", "--json", "--follow"]
    running: root.mapped
    stdout: SplitParser {
      onRead: function(line) { root.apply(line) }
    }
  }

  Process {
    command: ["ostt-dictate", "levels"]
    running: root.mapped && root.phase === "recording"
    stdout: SplitParser {
      onRead: function(line) { root.pushLevel(line) }
    }
  }

  OverlayWindow {
    shown: root.mapped
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "ostt-dictation"
    // Visual only: an empty input region lets clicks through to the desktop.
    mask: Region {}

    Pill {
      id: pill
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      // Where Omarchy shows its volume and brightness OSD.
      anchors.bottomMargin: Style.space(67)
      phase: root.phase
      levels: root.levels
      seconds: root.seconds

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.94
      Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutBack } }
    }
  }
}
