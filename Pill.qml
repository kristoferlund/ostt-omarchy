import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The recording pill: a pulsing dot, a live level meter and the elapsed time.
// While OSTT transcribes, the dot turns to the accent color and the meter
// becomes a travelling wave. Popup.qml feeds it; this file only draws.
BorderSurface {
  id: pill

  // recording | transcribing
  property string phase: "recording"
  // Input levels from 0 to 1, oldest first; the newest bar is on the right.
  property var levels: []
  property int seconds: 0

  readonly property bool recording: phase === "recording"
  readonly property int bars: 28
  readonly property int padX: Style.space(16)
  readonly property int padY: Style.space(11)
  readonly property int gap: Style.space(12)
  readonly property int barWidth: Math.max(2, Style.space(3))
  readonly property int barGap: Math.max(1, Style.space(2))
  readonly property int meterHeight: Style.space(24)
  readonly property int dotSize: Style.space(10)

  // Drives the transcribing wave.
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
      return 0.18 + 0.32 * (0.5 + 0.5 * Math.sin(x))
    }
    // Pad on the left until there is enough history to fill the meter.
    var offset = bars - levels.length
    return index < offset ? 0 : levels[index - offset]
  }

  function clock(total) {
    var minutes = Math.floor(total / 60)
    var rest = total % 60
    return minutes + ":" + (rest < 10 ? "0" : "") + rest
  }

  width: borderLeft + padX + content.width + padX + borderRight
  height: borderTop + padY + meterHeight + padY + borderBottom
  color: Util.alpha(Commons.Color.popups.background, 0.97)
  borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
  radius: Style.cornerRadius

  TextMetrics {
    id: clockMetrics
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Style.font.title
    // Wide enough for any time under an hour, so the pill never resizes.
    text: "00:00"
  }

  Row {
    id: content
    x: pill.borderLeft + pill.padX
    y: pill.borderTop + pill.padY
    height: pill.meterHeight
    spacing: pill.gap

    Item {
      width: pill.dotSize
      height: parent.height

      Rectangle {
        id: dot
        anchors.centerIn: parent
        width: pill.dotSize
        height: width
        radius: width / 2
        color: pill.recording ? Commons.Color.urgent : Commons.Color.accent
        Behavior on color { ColorAnimation { duration: Style.duration(200) } }

        SequentialAnimation on opacity {
          running: pill.recording && pill.visible
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 0.35; duration: 750; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 750; easing.type: Easing.InOutSine }
        }
      }
    }

    Row {
      height: parent.height
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
          color: pill.recording ? Commons.Color.popups.text : Commons.Color.accent
          // Older bars fade a little, so the meter reads left to right.
          opacity: pill.recording ? 0.45 + 0.55 * (index + 1) / pill.bars : 0.9

          Behavior on height {
            enabled: pill.recording
            NumberAnimation { duration: Style.duration(80); easing.type: Easing.OutQuad }
          }
        }
      }
    }

    Text {
      width: Math.ceil(clockMetrics.advanceWidth)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: pill.clock(pill.seconds)
      font: clockMetrics.font
      color: Commons.Color.popups.text
      opacity: pill.recording ? 1 : 0.55
      Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }
    }
  }
}
