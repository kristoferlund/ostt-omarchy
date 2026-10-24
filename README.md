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
omarchy plugin add https://github.com/kristoferlund/ostt-omarchy-dictate.git --enable
~/.config/omarchy/plugins/ostt.dictation/install
```

Then select OSTT in Setup > Defaults > Dictation. The setup installs OSTT from
the AUR if it is missing, asks for a transcription model if none is selected,
and offers to keep a local model loaded so dictation starts instantly.

`omarchy plugin update ostt.dictation --yes` updates everything (without `--yes`, Omarchy shows the code changes and asks first). `./uninstall` in the
same folder switches dictation away from OSTT and removes the scripts; OSTT
itself stays installed, and so do `~/.config/ostt/dictate.toml` and the
`assistant` and `clean` actions in `ostt.toml`.

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

In apps you choose, dictation sends your words to a processing action, and if
you allow it, a screenshot of the window too. An AI agent you already use
tidies up your words and carries out spoken instructions such as
"finish this sentence as a haiku" or "reply saying I can't make it"; with the
screenshot it also matches names and terms on screen. Every other app keeps
plain transcription. No screenshot is taken unless you turn it on for that
app.

The setup offers it and adds two processing actions to
`~/.config/ostt/ostt.toml`, using the agent and model you pick; edit their
prompts there:

- **Writing assistant** (`assistant`) tidies up your words and carries out
  spoken instructions. With the screenshot on, it also matches names, terms
  and tone on screen.
- **Text cleanup** (`clean`) only fixes misheard words, punctuation and
  filler.

If you already have an action with one of those ids, the setup leaves it as
it is. To choose the apps,
right-click the bar widget: it lists the apps on the visible workspaces, and
any already set up, with their current settings. Click a row to expand it and
choose one of your processing actions, and whether to send a screenshot. The
choice applies to every window of that app. It is
saved in `~/.config/ostt/dictate.toml` by Hyprland window class, which you can
also edit by hand (`screenshot` defaults to `false`):

```toml
[apps]
"Slack" = { action = "assistant", screenshot = true }
"thunderbird" = { action = "my-own-action" }
```

The setup offers the agents OSTT knows how to run with their tools switched
off, so text on screen can't make them run commands or touch files: Claude
Code, Codex, OpenCode, Gemini CLI, Pi, Oh My Pi and Hermes (`ostt agent list`
shows which are installed). Hermes takes no screenshots, so dictation in an
app with the screenshot on fails with it. A bash action gets the screenshot's
path in `$OSTT_ATTACHMENT`. If something is wrong
with an app's entry, or the screenshot fails, that dictation falls back to
plain transcription and a notification says why.

The agent takes a few seconds, and the text is pasted into whichever window is
focused when it finishes. Super + Ctrl + Alt + X cancels a dictation that is
taking too long.

The screenshot is a capture of the window's area of the screen, so anything on
top of it, such as a notification, is included. It is kept in
`$XDG_RUNTIME_DIR/ostt-dictate` (readable only by you) until the dictation
finishes, and after a failure until the next dictation, so the retry command
in the notification works.

## Bar widget

| State | Icon |
| --- | --- |
| Idle | dimmed microphone |
| Recording | microphone in the bar's alert color |
| Transcribing | hourglass |
| Failed | crossed-out microphone for 15 seconds; the tooltip has the error |

Left-click starts dictation, or stops it and pastes into the focused app.
Right-click cancels a recording or a pending transcription; otherwise it opens
the list of apps with their processing action and screenshot setting.

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
