-- ostt-omarchy:managed - linked by ostt-omarchy's install script. Delete this
-- line to keep your own edits; the script then leaves the file alone.
--
-- Omarchy loads this file while OSTT is the selected dictation backend.
-- Omarchy owns the recording keys (Right Alt / F9 hold, Super + Ctrl + X
-- toggle); this adds a key to discard a recording instead of pasting it.
o.bind("SUPER + CTRL + ALT + X", "Cancel dictation", "ostt-dictate cancel")
