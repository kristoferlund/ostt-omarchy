import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// The recording pill: cancel on the left, a live level meter, and a green
// check on the right that stops recording and transcribes. While OSTT
// transcribes, the meter becomes a travelling wave and the check a spinner.
// Popup.qml feeds it and runs the actions; this file only draws.
Item {
  id: pill

  // recording | transcribing
  property string phase: "recording"
  // Input levels from 0 to 1, oldest first; the newest bar is on the right.
  property var levels: []

  signal cancelClicked()
  signal confirmClicked()

  readonly property bool recording: phase === "recording"
  readonly property int bars: 24
  readonly property int pillHeight: Style.space(48)
  readonly property int button: Style.space(34)
  readonly property int inset: Math.round((pillHeight - button) / 2)
  readonly property int gap: Style.space(14)
  readonly property int barWidth: Math.max(2, Style.space(3))
  readonly property int barGap: Math.max(2, Style.space(3))
  readonly property int meterHeight: Style.space(26)
  readonly property color green: "#22c55e"

  implicitWidth: card.width
  implicitHeight: card.height

  // Drives the transcribing wave and spinner.
  property real wavePhase: 0
  NumberAnimation on wavePhase {
    running: !pill.recording && pill.visible
    from: 0
    to: 1
    duration: 1400
    loops: Animation.Infinite
  }

  function levelAt(index) {
    if (!recording) {
      var x = 2 * Math.PI * (wavePhase - index / bars)
      return 0.15 + 0.3 * (0.5 + 0.5 * Math.sin(x))
    }
    // Pad on the left until there is enough history to fill the meter.
    var offset = bars - levels.length
    return index < offset ? 0 : levels[index - offset]
  }

  // A soft shadow, drawn as rings that grow fainter outward.
  Repeater {
    model: 6
    Rectangle {
      required property int index
      readonly property int spread: Style.space(2) * (index + 1)
      x: card.x - spread
      y: card.y - spread + Style.space(3)
      width: card.width + 2 * spread
      height: card.height + 2 * spread
      radius: height / 2
      color: Qt.rgba(0, 0, 0, 0.07 - index * 0.01)
    }
  }

  Rectangle {
    id: card
    width: pill.inset + pill.button + pill.gap + meter.width + pill.gap + pill.button + pill.inset
    height: pill.pillHeight
    radius: height / 2
    color: Util.alpha(Commons.Color.background, 0.94)
    border.width: 1
    border.color: Util.alpha(Commons.Color.foreground, 0.08)

    // Cancel: discard the recording, or the pending transcription.
    Rectangle {
      id: cancel
      x: pill.inset
      anchors.verticalCenter: parent.verticalCenter
      width: pill.button
      height: width
      radius: width / 2
      color: Util.alpha(Commons.Color.foreground, cancelArea.containsMouse ? 0.2 : 0.1)
      scale: cancelArea.pressed ? 0.92 : 1
      Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      Behavior on scale { NumberAnimation { duration: Style.duration(90) } }

      Repeater {
        model: [45, -45]
        Rectangle {
          required property var modelData
          anchors.centerIn: parent
          width: Math.round(cancel.width * 0.42)
          height: Math.max(2, Style.space(2))
          radius: height / 2
          rotation: modelData
          color: Commons.Color.foreground
          antialiasing: true
        }
      }

      MouseArea {
        id: cancelArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.cancelClicked()
      }
    }

    Row {
      id: meter
      x: cancel.x + cancel.width + pill.gap
      anchors.verticalCenter: parent.verticalCenter
      height: pill.meterHeight
      spacing: pill.barGap

      Repeater {
        model: pill.bars

        Rectangle {
          required property int index
          readonly property real level: Math.max(0, Math.min(1, pill.levelAt(index)))

          y: Math.round((pill.meterHeight - height) / 2)
          width: pill.barWidth
          height: Math.max(pill.barWidth, Math.round(pill.meterHeight * level))
          radius: width / 2
          color: Commons.Color.foreground
          // Older bars fade a little, so the meter reads left to right.
          opacity: pill.recording ? 0.35 + 0.65 * (index + 1) / pill.bars : 0.6

          Behavior on height {
            enabled: pill.recording
            NumberAnimation { duration: Style.duration(80); easing.type: Easing.OutQuad }
          }
        }
      }
    }

    // Confirm: stop recording and transcribe. A spinner while transcribing.
    Rectangle {
      id: confirm
      x: meter.x + meter.width + pill.gap
      anchors.verticalCenter: parent.verticalCenter
      width: pill.button
      height: width
      radius: width / 2
      color: pill.recording
        ? Qt.lighter(pill.green, confirmArea.containsMouse ? 1.12 : 1)
        : Util.alpha(Commons.Color.foreground, 0.1)
      scale: confirmArea.pressed ? 0.92 : 1
      Behavior on color { ColorAnimation { duration: Style.duration(160) } }
      Behavior on scale { NumberAnimation { duration: Style.duration(90) } }

      Shape {
        anchors.fill: parent
        visible: pill.recording
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "white"
          strokeWidth: Math.max(2, Style.space(2.5))
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin
          startX: confirm.width * 0.3; startY: confirm.height * 0.52
          PathLine { x: confirm.width * 0.44; y: confirm.height * 0.66 }
          PathLine { x: confirm.width * 0.71; y: confirm.height * 0.37 }
        }
      }

      Shape {
        anchors.fill: parent
        visible: !pill.recording
        rotation: pill.wavePhase * 720
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: Commons.Color.foreground
          strokeWidth: Math.max(2, Style.space(2.5))
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          PathAngleArc {
            centerX: confirm.width / 2; centerY: confirm.height / 2
            radiusX: confirm.width * 0.26; radiusY: radiusX
            startAngle: 0; sweepAngle: 270
          }
        }
      }

      MouseArea {
        id: confirmArea
        anchors.fill: parent
        enabled: pill.recording
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.confirmClicked()
      }
    }
  }
}
