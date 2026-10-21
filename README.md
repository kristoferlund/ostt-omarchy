# OSTT Dictation for the Omarchy bar

A bar widget for [OSTT](https://ostt.ai) dictation in Omarchy 4.5 or later. It shows
whether OSTT is recording or transcribing, and lets you start, stop and cancel
dictation with the mouse.

| State | Icon |
| --- | --- |
| Idle | dimmed microphone |
| Recording | microphone in the bar's alert color |
| Transcribing | hourglass |
| Failed | crossed-out microphone for 15 seconds; the tooltip has the error |

Left-click starts dictation, or stops it and pastes into the focused app.
Right-click cancels a recording or a pending transcription.

The widget is only a view. Recordings run in OSTT's own background job, so the
same dictation can be started with Omarchy's keys and stopped from the bar, and
reloading the bar never abandons a recording.

## Install

OSTT must be installed and set up as the dictation backend first:

```bash
curl -fsSL https://ostt.ai/install | bash
ostt omarchy setup          # only needed for AUR installs; the installer does it
omarchy default dictation ostt
```

Then add the widget:

```bash
omarchy plugin add https://github.com/kristoferlund/omarchy-ostt.git --enable
```

## Settings

| Setting | Default | Meaning |
| --- | --- | --- |
| `hideWhenIdle` | `false` | Show the widget only while recording, transcribing, or right after an error |

## How it works

The widget runs `ostt dictate status --json --follow`, which prints a JSON line
whenever the dictation state changes, and calls `ostt dictate toggle` and
`ostt dictate cancel` for the buttons. See the
[OSTT docs](https://ostt.ai/guide/platforms/hyprland#dictation-backend) for the full interface.
