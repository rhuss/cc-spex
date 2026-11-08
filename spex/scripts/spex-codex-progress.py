#!/usr/bin/env python3
"""Add Codex's task-progress item to the footer and the terminal title.

Edits only `[tui].status_line` and `[tui].terminal_title` in the user's Codex
configuration ($CODEX_HOME/config.toml, else ~/.codex/config.toml). The edit
is line based, so comments and formatting survive, and the result is parsed
again with tomllib to prove that nothing but those two lists changed.

Subcommands:
  check --root DIR    CONFIGURED, DECLINED, ASK, or UNSUPPORTED when no TOML
                      parser is available (Python < 3.11 without tomli); exit 0
  apply               APPLIED path=P or UNCHANGED path=P (exit 0); exit 3 for
                      an unparseable or unsupported file, exit 4 when the
                      write fails; both print the manual snippet on stdout
  snippet             TOML lines to add (without a [tui] header when the file
                      already has that table), followed by the hint line
  decline --root DIR  record the decline in .specify/spex.json, print the hint
"""

from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

ITEM = "task-progress"
KEYS = ("status_line", "terminal_title")
# Codex defaults used when a key is unset (Codex CLI 0.164.0):
# DEFAULT_STATUS_LINE_ITEMS in codex-rs/tui/src/chatwidget.rs and
# DEFAULT_TERMINAL_TITLE_ITEMS in codex-rs/tui/src/chatwidget/status_surfaces.rs.
DEFAULTS = {
    "status_line": ["model-with-reasoning", "current-dir", "thread-name"],
    "terminal_title": ["activity", "thread-name", "project-name"],
}
HINT = 'To show spex progress later, run /statusline and /title in Codex and add "task progress".'
EXIT_UNSUPPORTED = 3
EXIT_WRITE = 4

TUI_NAME = r"""(?:tui|"tui"|'tui')"""
TUI_HEADER = re.compile(r"^\s*\[\s*" + TUI_NAME + r"\s*\]\s*(?:#.*)?$")
TUI_TOP_LEVEL_KEY = re.compile(r"^\s*" + TUI_NAME + r"\s*[.=]")


class Unsupported(Exception):
    """The configuration cannot be edited safely (parse error or unsupported form)."""


class NoParser(Unsupported):
    """No TOML parser is available (Python < 3.11 and no tomli)."""


def config_path() -> Path:
    """Return the Codex configuration path ($CODEX_HOME wins over ~/.codex)."""

    home = os.environ.get("CODEX_HOME")
    if home:
        return Path(home) / "config.toml"
    return Path.home() / ".codex" / "config.toml"


def parse(text: str) -> dict:
    """Parse TOML with tomllib; any failure is Unsupported."""

    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib
        except ImportError as error:
            raise NoParser(
                "Python 3.11 or newer (or the tomli package) is required to read TOML"
            ) from error
    try:
        return tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise Unsupported(f"cannot parse the configuration: {error}") from error


def current_lists(data: dict) -> dict:
    """Return {key: list or None} for the two keys; reject non-string arrays."""

    tui = data.get("tui", {})
    if not isinstance(tui, dict):
        raise Unsupported("tui is not a table")
    result = {}
    for key in KEYS:
        value = tui.get(key)
        if value is not None and (
            not isinstance(value, list) or not all(isinstance(item, str) for item in value)
        ):
            raise Unsupported(f"tui.{key} is not an array of strings")
        result[key] = value
    return result


def target_lists(lists: dict) -> dict:
    """Lists after the change: existing items plus ITEM, or defaults plus ITEM."""

    result = {}
    for key in KEYS:
        items = list(lists[key]) if lists[key] is not None else list(DEFAULTS[key])
        if ITEM not in items:
            items.append(ITEM)
        result[key] = items
    return result


def toml_array(items: list) -> str:
    """Render a list of strings as a single-line TOML array."""

    return "[" + ", ".join(json.dumps(item, ensure_ascii=False) for item in items) + "]"


# --- Line model -------------------------------------------------------------

def split_lines(text: str) -> list:
    """Split into [content, eol] pairs; eol is "\\r\\n", "\\n" or "" (last line)."""

    lines = []
    for piece in re.findall(r"[^\n]*\n|[^\n]+$", text):
        if piece.endswith("\r\n"):
            lines.append([piece[:-2], "\r\n"])
        elif piece.endswith("\n"):
            lines.append([piece[:-1], "\n"])
        else:
            lines.append([piece, ""])
    return lines


def join_lines(lines: list) -> str:
    return "".join(content + eol for content, eol in lines)


def insert_line(lines: list, index: int, content: str, eol: str) -> None:
    """Insert a line, keeping the file's final-newline state."""

    if index == len(lines) and lines and lines[-1][1] == "":
        lines[-1][1] = eol
        lines.append([content, ""])
    else:
        lines.insert(index, [content, eol])


class Scanner:
    """Track strings, comments and bracket depth across lines."""

    def __init__(self) -> None:
        self.depth = 0
        self.string = None
        self.comment_at = None

    def feed(self, s: str, start: int = 0, stop_at_depth: int | None = None):
        """Advance over s[start:]; return the column of a closing bracket that
        brings depth to stop_at_depth, or None."""

        j = start
        self.comment_at = None
        while j < len(s):
            c = s[j]
            if self.string is None:
                if s.startswith('"""', j) or s.startswith("'''", j):
                    self.string = s[j:j + 3]
                    j += 3
                    continue
                if c in "\"'":
                    self.string = c
                elif c == "#":
                    self.comment_at = j
                    break
                elif c in "[{":
                    self.depth += 1
                elif c in "]}":
                    self.depth -= 1
                    if stop_at_depth is not None and self.depth == stop_at_depth:
                        return j
            elif self.string in ('"', '"""') and c == "\\":
                j += 2
                continue
            elif len(self.string) == 3 and s.startswith(self.string, j):
                self.string = None
                j += 3
                continue
            elif len(self.string) == 1 and c == self.string:
                self.string = None
            j += 1
        if self.string in ('"', "'"):
            # Single-line strings end at the line break (invalid TOML otherwise).
            self.string = None
        return None


def statement_starts(lines: list) -> list:
    """Indices of lines that start a new statement (depth 0, not in a string)."""

    scanner = Scanner()
    starts = []
    for index, (content, _eol) in enumerate(lines):
        if scanner.depth == 0 and scanner.string is None:
            starts.append(index)
        scanner.feed(content)
    return starts


def find_close(lines: list, line: int, col: int) -> tuple:
    """Return (line, col) of the bracket closing the array opened at (line, col)."""

    scanner = Scanner()
    scanner.depth = 0
    start = col
    for index in range(line, len(lines)):
        found = scanner.feed(lines[index][0], start, stop_at_depth=0)
        if found is not None:
            return index, found
        start = 0
    raise Unsupported("unterminated array")


def code_end(content: str) -> int:
    """Column where the code part of a line ends (before a trailing comment)."""

    scanner = Scanner()
    scanner.feed(content)
    end = len(content) if scanner.comment_at is None else scanner.comment_at
    return len(content[:end].rstrip())


# --- Edit -------------------------------------------------------------------

def append_to_array(lines: list, key_line: int, open_col: int, eol: str) -> None:
    """Append ITEM to the array whose '[' is at (key_line, open_col)."""

    close_line, close_col = find_close(lines, key_line, open_col)
    content = lines[close_line][0]
    before = content[:close_col]
    stripped = before.rstrip()
    if close_line == key_line or stripped.strip():
        # Closing bracket shares its line with the opening bracket or an item.
        if stripped.endswith("["):
            new = stripped + json.dumps(ITEM) + content[close_col:]
        elif stripped.endswith(","):
            new = stripped + " " + json.dumps(ITEM) + before[len(stripped):] + content[close_col:]
        else:
            new = stripped + ", " + json.dumps(ITEM) + before[len(stripped):] + content[close_col:]
        lines[close_line][0] = new
        return
    # Multi-line array with the closing bracket on its own line.
    last = None
    for index in range(close_line - 1, key_line, -1):
        text = lines[index][0]
        if code_end(text) > 0:
            last = index
            break
    if last is None:
        indent = re.match(r"\s*", content).group(0) + "    "
        key_text = lines[key_line][0]
        key_end = code_end(key_text)
        if key_end > open_col + 1:
            # Items sit on the opening line, the bracket closes on its own line.
            if not key_text[:key_end].endswith(","):
                lines[key_line][0] = key_text[:key_end] + "," + key_text[key_end:]
            insert_line(lines, close_line, indent + json.dumps(ITEM), eol)
            return
        # Empty multi-line array: indent one level deeper than the bracket.
        insert_line(lines, close_line, indent + json.dumps(ITEM) + ",", eol)
        return
    text = lines[last][0]
    indent = re.match(r"\s*", text).group(0)
    end = code_end(text)
    if text[:end].endswith(","):
        insert_line(lines, close_line, indent + json.dumps(ITEM) + ",", eol)
    else:
        lines[last][0] = text[:end] + "," + text[end:]
        insert_line(lines, close_line, indent + json.dumps(ITEM), eol)


def plan_edit(text: str) -> tuple:
    """Return (new_text, changed). Raises Unsupported when editing is unsafe."""

    data = parse(text)
    lists = current_lists(data)
    targets = target_lists(lists)
    if all(lists[key] is not None and ITEM in lists[key] for key in KEYS):
        return text, False

    lines = split_lines(text)
    eol = "\r\n" if "\r\n" in text else "\n"
    starts = statement_starts(lines)
    headers = [i for i in starts if lines[i][0].lstrip().startswith("[")]
    first_header = headers[0] if headers else len(lines)
    if any(TUI_TOP_LEVEL_KEY.match(lines[i][0]) for i in starts if i < first_header):
        raise Unsupported("tui keys are defined outside a [tui] table (inline table or dotted keys)")
    tui_headers = [i for i in headers if TUI_HEADER.match(lines[i][0])]
    if len(tui_headers) > 1:
        raise Unsupported("the [tui] table is defined more than once")

    if not tui_headers:
        if any(lists[key] is not None for key in KEYS):
            raise Unsupported("tui keys are defined outside a [tui] table")
        if lines and lines[-1][1] == "":
            lines[-1][1] = eol
        if lines:
            lines.append(["", eol])
        lines.append(["[tui]", eol])
        for key in KEYS:
            lines.append([f"{key} = {toml_array(targets[key])}", eol])
    else:
        header = tui_headers[0]
        following = [i for i in headers if i > header]
        region_end = following[0] if following else len(lines)
        region_starts = [i for i in starts if header < i < region_end]
        located = {}
        for key in KEYS:
            pattern = re.compile(r"^\s*(?:%s|\"%s\"|'%s')\s*=\s*\[" % (key, key, key))
            matches = [i for i in region_starts if pattern.match(lines[i][0])]
            if len(matches) > 1:
                raise Unsupported(f"tui.{key} is defined more than once")
            if lists[key] is not None and not matches:
                raise Unsupported(f"tui.{key} is not written as an array in the [tui] table")
            if matches:
                located[key] = matches[0]
        # Append to existing arrays first (bottom-up keeps indices valid),
        # then add missing keys after the last statement of the table.
        for key in sorted(located, key=located.get, reverse=True):
            if ITEM in lists[key]:
                continue
            index = located[key]
            match = re.match(r"^\s*(?:%s|\"%s\"|'%s')\s*=\s*\[" % (key, key, key), lines[index][0])
            append_to_array(lines, index, match.end() - 1, eol)
        missing = [key for key in KEYS if key not in located]
        if missing:
            # Recompute the table end: appending may have added lines.
            starts = statement_starts(lines)
            headers = [i for i in starts if lines[i][0].lstrip().startswith("[")]
            following = [i for i in headers if i > header]
            region_end = following[0] if following else len(lines)
            insert_at = header + 1
            for index in range(region_end - 1, header, -1):
                if code_end(lines[index][0]) > 0:
                    insert_at = index + 1
                    break
            for offset, key in enumerate(missing):
                insert_line(lines, insert_at + offset, f"{key} = {toml_array(targets[key])}", eol)

    new_text = join_lines(lines)
    expected = copy.deepcopy(data)
    tui = expected.setdefault("tui", {})
    for key in KEYS:
        tui[key] = targets[key]
    try:
        verified = parse(new_text) == expected
    except Unsupported:
        verified = False
    if not verified:
        raise Unsupported("the edited configuration did not verify; it was left unchanged")
    return new_text, True


# --- Commands ---------------------------------------------------------------

def read_config(path: Path) -> str:
    if not path.exists():
        return ""
    with path.open(encoding="utf-8", newline="") as stream:
        return stream.read()


def snippet_text(path: Path) -> str:
    """Manual lines that are safe to paste into the current file."""

    try:
        text = read_config(path)
        data = parse(text)
        lists = current_lists(data)
    except (Unsupported, OSError, UnicodeDecodeError):
        text, data = "", None
        lists = {key: None for key in KEYS}
    lines = [content for content, _eol in split_lines(text)]
    has_header = any(TUI_HEADER.match(line) for line in lines)
    top_level_tui = any(TUI_TOP_LEVEL_KEY.match(line) for line in lines)
    targets = target_lists(lists)
    keys = [f"{key} = {toml_array(targets[key])}" for key in KEYS]
    if data is None or top_level_tui:
        # Current lists unknown, or tui keys written outside a [tui] table
        # (inline table, dotted keys): never suggest a [tui] header or
        # replacing the lists with defaults.
        body = [
            f'# Append "{ITEM}" to [tui].status_line and [tui].terminal_title.',
            "# Only when a key is missing from your [tui] table, add it as:",
        ] + keys
    elif has_header:
        body = ["# Set these keys in your existing [tui] table (replace a key that is already there):"] + keys
    else:
        body = ["[tui]"] + keys
    return "\n".join(body) + "\n\n" + HINT


def declined(root: Path) -> bool:
    try:
        with (root / ".specify" / "spex.json").open(encoding="utf-8") as stream:
            profile = json.load(stream)
    except (OSError, ValueError):
        return False
    return isinstance(profile, dict) and profile.get("codex_progress") == "declined"


def cmd_check(root: Path) -> int:
    try:
        lists = current_lists(parse(read_config(real_path(config_path()))))
        configured = all(lists[key] is not None and ITEM in lists[key] for key in KEYS)
    except NoParser as error:
        print(f"ERROR: {error}", file=sys.stderr)
        print("UNSUPPORTED")
        return 0
    except (Unsupported, OSError, UnicodeDecodeError):
        configured = False
    if configured:
        print("CONFIGURED")
    elif declined(root):
        print("DECLINED")
    else:
        print("ASK")
    return 0


def real_path(path: Path) -> Path:
    """Follow symlinks so a linked config (dotfile managers) is edited in place."""

    return Path(os.path.realpath(path))


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else None
    descriptor, raw = tempfile.mkstemp(dir=path.parent, prefix=".config.", suffix=".tmp")
    temporary = Path(raw)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        if mode is not None:
            os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def cmd_apply() -> int:
    path = config_path()
    target = real_path(path)
    try:
        text = read_config(target)
        new_text, changed = plan_edit(text)
    except (Unsupported, UnicodeDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        print(snippet_text(path))
        return EXIT_UNSUPPORTED
    except OSError as error:
        print(f"ERROR: cannot read {path}: {error}", file=sys.stderr)
        print(snippet_text(path))
        return EXIT_WRITE
    if not changed:
        print(f"UNCHANGED path={path}")
        return 0
    try:
        write_atomic(target, new_text)
    except OSError as error:
        print(f"ERROR: cannot write {path}: {error}", file=sys.stderr)
        print(snippet_text(path))
        return EXIT_WRITE
    print(f"APPLIED path={path}")
    return 0


def cmd_decline(root: Path) -> int:
    tool = Path(__file__).resolve().parent / "spex-setup-profile.py"
    result = subprocess.run(
        [sys.executable, str(tool), "decline-codex-progress", "--root", str(root)],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or "could not record the decline"
        print(message if message.startswith("ERROR:") else f"ERROR: {message}", file=sys.stderr)
        print(HINT)
        return 1
    print(HINT)
    return 0


def main(argv: list) -> int:
    usage = "Usage: spex-codex-progress.py {check --root DIR|apply|snippet|decline --root DIR}"
    if not argv or argv[0] not in ("check", "apply", "snippet", "decline"):
        print(usage, file=sys.stderr)
        return 2
    command, rest = argv[0], argv[1:]
    if command in ("check", "decline"):
        if len(rest) != 2 or rest[0] != "--root" or not rest[1]:
            print(usage, file=sys.stderr)
            return 2
        root = Path(rest[1]).resolve()
        return cmd_check(root) if command == "check" else cmd_decline(root)
    if rest:
        print(usage, file=sys.stderr)
        return 2
    if command == "apply":
        return cmd_apply()
    print(snippet_text(config_path()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
