# OSTT dictation for Omarchy

Use [OSTT](https://ostt.ai) as the dictation backend in Omarchy 4.5 or later.
Hold Right Alt or F9 and speak; OSTT transcribes with the model you chose,
local or cloud, and pastes into the focused app.

This repo has four parts:

- `ostt-dictate` records from the default microphone without a terminal and
  hands the recording to `ostt transcribe --paste`.
- The Omarchy backend scripts, which run `ostt-dictate` from Omarchy's
  dictation keys and list OSTT in Setup > Defaults > Dictation.
- A recording popup with a live level meter and cancel and transcribe buttons.
- A bar widget that shows whether OSTT is recording or transcribing.

## Install

```bash
omarchy plugin add https://github.com/kristoferlund/ostt-omarchy.git --enable
~/.config/omarchy/plugins/ostt.dictation/install
```

Then select OSTT in Setup > Defaults > Dictation. The setup installs OSTT from
the AUR if it is missing, asks for a transcription model if none is selected,
and offers to keep a local model loaded so dictation starts instantly.

`omarchy plugin update ostt.dictation --yes` updates everything (without `--yes`, Omarchy shows the code changes and asks first). `./uninstall` in the
same folder switches dictation away from OSTT and removes the scripts; OSTT
itself stays installed.

## Keys

| Key | Action |
| --- | --- |
| Right Alt or F9 (hold) | Record while held, paste on release |
| Super + Ctrl + X | Start, or stop and paste |
| Super + Ctrl + Alt + X | Cancel without pasting |

OSTT records from the default input device; pick it in Omarchy's audio
settings. A failed transcription keeps the recording and the notification tells
you how to retry it.

## Recording popup

While you dictate, a rounded pill at the bottom of the screen shows a live
level meter between two buttons: ✕ cancels the recording, and the green ✓ stops
it and transcribes. During transcription the meter becomes a moving wave and the
✓ a spinner; the pill fades out once the text is pasted. It never takes
keyboard focus, so the text still lands in the app you were typing in.

## Context-aware dictation

In apps you choose, dictation also takes a screenshot of the window and sends
it with your words to an AI agent (Claude Code, Codex or OpenCode), so names,
terms and tone match what is on screen. Every other app keeps plain
transcription, and no screenshot is taken.

The setup offers it and adds a `screen-context` processing action to
`~/.config/ostt/ostt.toml`. List the apps in `~/.config/ostt/omarchy.toml` by
Hyprland window class (`hyprctl activewindow` shows it), each with the action
to run:

```toml
[apps]
"Slack" = "screen-context"
"thunderbird" = "my-own-action"
```

Any processing action works; it gets the screenshot through
`ostt process --attach`. If the action fails, the transcript is still in
`ostt history` and the notification shows how to retry.

## Bar widget

| State | Icon |
| --- | --- |
| Idle | dimmed microphone |
| Recording | microphone in the bar's alert color |
| Transcribing | hourglass |
| Failed | crossed-out microphone for 15 seconds; the tooltip has the error |

Left-click starts dictation, or stops it and pastes into the focused app.
Right-click cancels a recording or a pending transcription.

| Setting | Default | Meaning |
| --- | --- | --- |
| `hideWhenIdle` | `false` | Show the widget only while recording, transcribing, or right after an error |

## ostt-dictate

```
ostt-dictate start | stop | toggle | cancel
ostt-dictate status [--json] [--follow]
ostt-dictate levels
```

Each command returns at once; recording and transcription run in the
background. `status --json --follow` prints a line such as
`{"state":"recording"}` whenever the state changes. The states are `idle`,
`recording`, `transcribing` and `error`. `ostt-dictate levels` follows the
input level as ffmpeg's `RMS_level` lines in dBFS, for the popup's meter.
