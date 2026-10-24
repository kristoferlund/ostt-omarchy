"""Tests for lib/dictate_config.py. Run with: python3 -m unittest discover tests"""

import os
import sys
import tempfile
import tomllib
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
import dictate_config as dc  # noqa: E402

ENTRY = {"action": "assistant", "screenshot": True}


class Edit(unittest.TestCase):
    """dictate.toml is the user's file: an edit changes one app and keeps
    everything else as written, or refuses."""

    def test_keeps_comments_and_other_sections(self):
        text = '# mine\n[apps] # apps\n"foot" = { action = "clean" }\n\n[other]\nk = 1\n'
        result = dc.edit(text, "Slack", ENTRY)
        self.assertEqual(
            result,
            '# mine\n[apps] # apps\n"foot" = { action = "clean" }\n'
            '"Slack" = { action = "assistant", screenshot = true }\n\n[other]\nk = 1\n',
        )

    def test_replaces_and_removes_an_entry(self):
        text = '[apps]\n"Slack" = { action = "clean" }\n'
        self.assertIn('"Slack" = { action = "assistant", screenshot = true }', dc.edit(text, "Slack", ENTRY))
        self.assertEqual(dc.edit(text, "Slack", None), "[apps]\n")

    def test_keeps_crlf_line_endings(self):
        result = dc.edit('[apps]\r\n"a" = { action = "x" }\r\n', "b", ENTRY)
        self.assertEqual(result.count("\r\n"), 3)
        self.assertNotIn("\n", result.replace("\r\n", ""))

    def test_leaves_keys_with_toml_only_escapes_alone(self):
        text = '[apps]\n"K\\U0001F600" = { action = "x" }\n'
        result = dc.edit(text, "Slack", ENTRY)
        self.assertTrue(result.startswith(text))

    def test_creates_the_table_in_an_empty_file(self):
        self.assertEqual(
            dc.edit("", "Slack", ENTRY),
            '[apps]\n"Slack" = { action = "assistant", screenshot = true }\n',
        )

    def test_refuses_an_edit_that_would_change_anything_else(self):
        # The line looks like Slack's entry but belongs to a multi-line string.
        text = '[apps]\nnote = """\n"Slack" = "x"\n"""\n"Slack" = { action = "clean" }\n'
        with self.assertRaises(dc.ConfigError):
            dc.edit(text, "Slack", None)

    def test_refuses_invalid_toml(self):
        with self.assertRaises(dc.ConfigError):
            dc.edit("[apps\n", "Slack", ENTRY)


class Read(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "dictate.toml")

    def tearDown(self):
        self.dir.cleanup()

    def write(self, text):
        with open(self.path, "w") as f:
            f.write(text)

    def test_a_malformed_entry_affects_only_its_app(self):
        self.write('[apps]\nSlack = { action = "assistant", screenshot = true }\nOld = "assistant"\n')
        self.assertEqual(dc.apps(self.path), {"apps": {"Slack": ENTRY}, "invalid": ["Old"]})
        self.assertEqual(dc.lookup(self.path, "Slack"), ENTRY)
        self.assertEqual(dc.lookup(self.path, "Firefox"), {})
        with self.assertRaisesRegex(dc.ConfigError, "Old"):
            dc.lookup(self.path, "Old")

    def test_a_missing_file_has_no_apps(self):
        self.assertEqual(dc.apps(self.path), {"apps": {}, "invalid": []})

    def test_screenshot_defaults_to_off(self):
        self.write('[apps]\nfoot = { action = "clean" }\n')
        self.assertEqual(dc.lookup(self.path, "foot"), {"action": "clean", "screenshot": False})

    def test_map_writes_atomically_and_keeps_the_mode(self):
        self.write('[apps]\n')
        os.chmod(self.path, 0o640)
        dc.map_app(self.path, "Slack", "assistant", True)
        with open(self.path, "rb") as f:
            self.assertEqual(tomllib.load(f)["apps"]["Slack"], ENTRY)
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o640)
        self.assertEqual(os.listdir(self.dir.name), ["dictate.toml"])

    def test_map_refuses_an_option_as_the_action(self):
        with self.assertRaises(dc.ConfigError):
            dc.main(["map", self.path, "Slack", "--screenshot"])


if __name__ == "__main__":
    unittest.main()
