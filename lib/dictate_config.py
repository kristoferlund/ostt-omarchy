"""Reads and edits the [apps] table of dictate.toml for ostt-dictate.

    dictate_config.py apps <config>              JSON {"apps": {class: entry}, "invalid": [class]}
    dictate_config.py lookup <config> <class>    JSON entry of one app, or {} if it has none
    dictate_config.py map <config> <class> [<action> [--screenshot]]

An entry is {"action": str, "screenshot": bool}. Errors are printed as one
line on stderr with exit status 1.
"""

import json
import os
import re
import sys
import tempfile
import tomllib

EXAMPLE = '{ action = "assistant", screenshot = true }'


class ConfigError(Exception):
    pass


def load(path):
    """The parsed file, or {} if it does not exist."""
    try:
        with open(path, "rb") as f:
            document = tomllib.load(f)
    except FileNotFoundError:
        return {}
    except tomllib.TOMLDecodeError as e:
        raise ConfigError(f"{path} is not valid TOML: {e}") from e
    if not isinstance(document.get("apps", {}), dict):
        raise ConfigError(f"[apps] in {path} must be a table")
    return document


def entry(value):
    """A valid entry, or None."""
    if (isinstance(value, dict) and isinstance(value.get("action"), str)
            and isinstance(value.get("screenshot", False), bool)):
        return {"action": value["action"], "screenshot": value.get("screenshot", False)}
    return None


def apps(path):
    """Every app's entry; a malformed entry affects only its own app."""
    valid, invalid = {}, []
    for app, value in load(path).get("apps", {}).items():
        if (parsed := entry(value)) is not None:
            valid[app] = parsed
        else:
            invalid.append(app)
    return {"apps": valid, "invalid": invalid}


def lookup(path, app):
    """One app's entry, or {} if it has none."""
    value = load(path).get("apps", {}).get(app)
    if value is None:
        return {}
    if (parsed := entry(value)) is None:
        raise ConfigError(f"The entry for {app} in {path} is not valid; it must look like {EXAMPLE}")
    return parsed


def _key_of(line):
    """The key a one-line `key = value` defines, or None."""
    try:
        parsed = tomllib.loads(line)
    except tomllib.TOMLDecodeError:
        return None
    return next(iter(parsed)) if len(parsed) == 1 else None


def edit(text, app, new_entry):
    """`text` with app's line under [apps] replaced, added or removed.

    Only that line changes, so the rest of the file stays as written. The
    result must parse to the original document with just that entry changed;
    anything else (an [apps] this cannot edit line by line) is refused.
    """
    try:
        before = tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        raise ConfigError(f"not valid TOML: {e}") from e
    if not isinstance(before.get("apps", {}), dict):
        raise ConfigError("[apps] must be a table")
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()

    header = re.compile(r"\s*\[\s*apps\s*\]\s*(#.*)?")
    start = next((i for i, line in enumerate(lines) if header.fullmatch(line)), None)
    if start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append("[apps]")
        start = len(lines) - 1
    end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith("[")),
               len(lines))
    section = [line for line in lines[start + 1:end] if _key_of(line) != app]
    if new_entry:
        last_key = max((i for i, line in enumerate(section) if _key_of(line) is not None), default=-1)
        value = json.dumps(new_entry["action"], ensure_ascii=False)
        flag = "true" if new_entry["screenshot"] else "false"
        section.insert(last_key + 1,
                       f"{json.dumps(app, ensure_ascii=False)} = {{ action = {value}, screenshot = {flag} }}")
    result = newline.join(lines[:start + 1] + section + lines[end:]) + newline

    expected = dict(before)
    expected["apps"] = dict(before.get("apps", {}))
    if new_entry:
        expected["apps"][app] = new_entry
    else:
        expected["apps"].pop(app, None)
    try:
        after = tomllib.loads(result)
    except tomllib.TOMLDecodeError:
        after = None
    if after != expected:
        raise ConfigError(f"could not change {app} safely; edit [apps] by hand")
    return result


def map_app(path, app, action, screenshot):
    """Sets or clears one app's entry, replacing the file in one rename."""
    try:
        with open(path, newline="") as f:
            text = f.read()
    except FileNotFoundError:
        text = ""
    new_entry = {"action": action, "screenshot": screenshot} if action else None
    try:
        result = edit(text, app, new_entry)
    except ConfigError as e:
        raise ConfigError(f"{path}: {e}") from e
    target = os.path.realpath(path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target), prefix=".dictate.")
    try:
        with os.fdopen(fd, "w", newline="") as f:
            f.write(result)
        if os.path.exists(target):
            os.chmod(tmp, os.stat(target).st_mode & 0o777)
        os.replace(tmp, target)
    except BaseException:
        os.unlink(tmp)
        raise


def main(args):
    if args[:1] == ["map"] and len(args) >= 3 and not args[2]:
        raise ConfigError("Usage: ostt-dictate map <class> [<action> [--screenshot]]")
    match args:
        case ["apps", path]:
            print(json.dumps(apps(path)))
        case ["lookup", path, app]:
            print(json.dumps(lookup(path, app)))
        case ["map", path, app]:
            map_app(path, app, "", False)
        case ["map", path, app, action] if not action.startswith("-"):
            map_app(path, app, action, False)
        case ["map", path, app, action, "--screenshot"] if not action.startswith("-"):
            map_app(path, app, action, True)
        case ["map", *_]:
            raise ConfigError("Usage: ostt-dictate map <class> [<action> [--screenshot]]")
        case _:
            raise ConfigError("Usage: dictate_config.py apps|lookup|map ... (see its docstring)")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ConfigError, OSError) as e:
        print(e, file=sys.stderr)
        sys.exit(1)
