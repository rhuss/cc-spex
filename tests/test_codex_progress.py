#!/usr/bin/env python3
"""Tests for spex-codex-progress.py (Codex footer and terminal title setup)."""

from __future__ import annotations

import difflib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "spex/scripts/spex-codex-progress.py"
HINT = 'To show spex progress later, run /statusline and /title in Codex and add "task progress".'
STATUS_DEFAULT = ["model-with-reasoning", "current-dir", "thread-name"]
TITLE_DEFAULT = ["activity", "thread-name", "project-name"]


class CodexProgressTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.home = self.tmp / "codex-home"
        self.home.mkdir()
        self.config = self.home / "config.toml"
        self.project = self.tmp / "project"
        self.project.mkdir()

    def tearDown(self):
        # Restore permissions so the temp dir can be removed.
        for path in (self.home, self.tmp):
            if path.exists():
                os.chmod(path, 0o755)
        self._tmp.cleanup()

    def run_tool(self, *args, codex_home=None):
        env = dict(os.environ, CODEX_HOME=str(codex_home or self.home))
        return subprocess.run(
            [sys.executable, str(TOOL), *args], env=env,
            capture_output=True, text=True, check=False,
        )

    def write(self, text: str, newline: str = "\n"):
        self.config.write_bytes(text.replace("\n", newline).encode("utf-8"))

    def read(self) -> str:
        return self.config.read_bytes().decode("utf-8")

    def lists(self) -> tuple:
        tui = tomllib.loads(self.read()).get("tui", {})
        return tui.get("status_line"), tui.get("terminal_title")

    def added_lines(self, before: str, after: str) -> list:
        """Lines removed and added between two texts (as diff lines)."""

        diff = difflib.ndiff(before.splitlines(), after.splitlines())
        return [line for line in diff if line[:2] in ("- ", "+ ")]

    def assert_only_additions(self, before: str, after: str, allowed_changed: int = 0):
        """Every original line survives unless it is one of the allowed edits."""

        removed = [l for l in self.added_lines(before, after) if l.startswith("- ")]
        self.assertLessEqual(len(removed), allowed_changed, removed)

    def assert_unsupported(self, text: str):
        self.write(text)
        before = self.read()
        result = self.run_tool("apply")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(self.read(), before)
        self.assertIn("[tui]", result.stdout)
        self.assertTrue(result.stdout.rstrip("\n").endswith(HINT))
        self.assertIn("ERROR:", result.stderr)

    # --- apply ---------------------------------------------------------------

    def test_missing_file_and_directory_are_created(self):
        home = self.tmp / "new-home" / "nested"
        result = self.run_tool("apply", codex_home=home)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"APPLIED path={home / 'config.toml'}")
        data = tomllib.loads((home / "config.toml").read_text())
        self.assertEqual(data, {"tui": {
            "status_line": [*STATUS_DEFAULT, "task-progress"],
            "terminal_title": [*TITLE_DEFAULT, "task-progress"],
        }})

    def test_file_without_tui_gets_table_appended(self):
        original = '# my settings\nmodel = "gpt-5"\n\n[profiles.fast]\nmodel = "mini"\n'
        self.write(original)
        result = self.run_tool("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        after = self.read()
        self.assertTrue(after.startswith(original))
        self.assertEqual(self.lists(), (
            [*STATUS_DEFAULT, "task-progress"], [*TITLE_DEFAULT, "task-progress"],
        ))
        self.assertEqual(tomllib.loads(after)["profiles"], {"fast": {"model": "mini"}})

    def test_single_line_array_gets_item_appended(self):
        original = (
            '# my settings\n[tui]\nstatus_line = ["model-with-reasoning", "git-branch"]\n'
            'notifications = true\n\n[other]\nkey = 1\n'
        )
        self.write(original)
        result = self.run_tool("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        after = self.read()
        self.assertIn('status_line = ["model-with-reasoning", "git-branch", "task-progress"]\n', after)
        self.assertEqual(self.lists(), (
            ["model-with-reasoning", "git-branch", "task-progress"],
            [*TITLE_DEFAULT, "task-progress"],
        ))
        self.assert_only_additions(original, after, allowed_changed=1)
        self.assertEqual(tomllib.loads(after)["tui"]["notifications"], True)
        self.assertEqual(tomllib.loads(after)["other"], {"key": 1})

    def test_multiline_array_with_trailing_comma(self):
        original = (
            '[tui]\nstatus_line = [\n  "model-with-reasoning",\n  "git-branch",\n]\n'
            'terminal_title = ["activity"]\n'
        )
        self.write(original)
        self.assertEqual(self.run_tool("apply").returncode, 0)
        after = self.read()
        self.assertIn('  "git-branch",\n  "task-progress",\n]\n', after)
        self.assert_only_additions(original, after, allowed_changed=1)
        self.assertEqual(self.lists()[0], ["model-with-reasoning", "git-branch", "task-progress"])

    def test_multiline_array_without_trailing_comma(self):
        original = '[tui]\nstatus_line = [\n    "model-with-reasoning",\n    "git-branch"  # vcs\n]\n'
        self.write(original)
        self.assertEqual(self.run_tool("apply").returncode, 0)
        after = self.read()
        self.assertIn('    "git-branch",  # vcs\n    "task-progress"\n]\n', after)
        self.assertEqual(self.lists()[0], ["model-with-reasoning", "git-branch", "task-progress"])

    def test_both_lists_configured_is_unchanged(self):
        original = (
            '[tui]\nstatus_line = ["git-branch", "task-progress"]\n'
            'terminal_title = ["task-progress"]\n'
        )
        self.write(original)
        mtime = self.config.stat().st_mtime_ns
        result = self.run_tool("apply")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), f"UNCHANGED path={self.config}")
        self.assertEqual(self.read(), original)
        self.assertEqual(self.config.stat().st_mtime_ns, mtime)
        self.assertEqual(self.run_tool("check", "--root", str(self.project)).stdout.strip(), "CONFIGURED")

    def test_only_one_list_configured(self):
        original = '[tui]\nstatus_line = ["task-progress"]\nterminal_title = ["activity"]\n'
        self.write(original)
        self.assertEqual(self.run_tool("check", "--root", str(self.project)).stdout.strip(), "ASK")
        self.assertEqual(self.run_tool("apply").returncode, 0)
        after = self.read()
        self.assertIn('status_line = ["task-progress"]\n', after)
        self.assertIn('terminal_title = ["activity", "task-progress"]\n', after)
        self.assert_only_additions(original, after, allowed_changed=1)

    def test_comments_and_unrelated_tables_preserved(self):
        original = (
            '# top comment\nmodel = "gpt-5"  # inline comment\n\n'
            '[tui]\n# footer\nstatus_line = ["git-branch"] # mine\nanimations = false\n\n'
            '# next table\n[mcp_servers.docs]\ncommand = "npx"\nargs = ["-y", "docs"]\n'
        )
        self.write(original)
        self.assertEqual(self.run_tool("apply").returncode, 0)
        after = self.read()
        changes = self.added_lines(original, after)
        self.assertEqual(changes, [
            '- status_line = ["git-branch"] # mine',
            '+ status_line = ["git-branch", "task-progress"] # mine',
            '+ terminal_title = ["activity", "thread-name", "project-name", "task-progress"]',
        ])
        # The new key goes at the end of the [tui] key block, before the blank line.
        self.assertIn('animations = false\nterminal_title = [', after)

    def test_empty_array(self):
        self.write('[tui]\nstatus_line = []\nterminal_title = [ ]\n')
        self.assertEqual(self.run_tool("apply").returncode, 0)
        self.assertEqual(self.lists(), (["task-progress"], ["task-progress"]))
        self.assertIn('status_line = ["task-progress"]\n', self.read())

    def test_file_without_trailing_newline(self):
        original = '[tui]\nstatus_line = ["git-branch"]'
        self.write(original)
        self.assertEqual(self.run_tool("apply").returncode, 0)
        after = self.read()
        self.assertFalse(after.endswith("\n"))
        self.assertEqual(self.lists(), (
            ["git-branch", "task-progress"], [*TITLE_DEFAULT, "task-progress"],
        ))

    def test_no_tui_and_no_trailing_newline(self):
        self.write('model = "gpt-5"')
        self.assertEqual(self.run_tool("apply").returncode, 0)
        self.assertTrue(self.read().startswith('model = "gpt-5"\n'))
        self.assertEqual(self.lists()[0], [*STATUS_DEFAULT, "task-progress"])

    def test_sub_table_after_tui(self):
        original = '[tui]\nstatus_line = ["git-branch"]\n\n[tui.notifications]\nenabled = true\n'
        self.write(original)
        self.assertEqual(self.run_tool("apply").returncode, 0)
        after = self.read()
        data = tomllib.loads(after)
        self.assertEqual(data["tui"]["terminal_title"], [*TITLE_DEFAULT, "task-progress"])
        self.assertEqual(data["tui"]["notifications"], {"enabled": True})
        self.assertLess(after.index("terminal_title"), after.index("[tui.notifications]"))

    def test_comment_after_closing_bracket(self):
        self.write('[tui]\nstatus_line = [\n  "git-branch",\n] # end\nterminal_title = ["a"] # t\n')
        self.assertEqual(self.run_tool("apply").returncode, 0)
        after = self.read()
        self.assertIn('  "task-progress",\n] # end\n', after)
        self.assertIn('terminal_title = ["a", "task-progress"] # t\n', after)

    def test_crlf_line_endings_preserved(self):
        self.write('# win\n[tui]\nstatus_line = ["git-branch"]\n', newline="\r\n")
        self.assertEqual(self.run_tool("apply").returncode, 0)
        raw = self.config.read_bytes()
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""))
        self.assertIn(b'status_line = ["git-branch", "task-progress"]\r\n', raw)
        self.assertIn(b"terminal_title = [", raw)

    def test_partial_tui_table_adds_missing_key(self):
        original = '[tui]\nterminal_title = ["project-name"]\n'
        self.write(original)
        self.assertEqual(self.run_tool("apply").returncode, 0)
        self.assertEqual(self.lists(), (
            [*STATUS_DEFAULT, "task-progress"], ["project-name", "task-progress"],
        ))
        self.assert_only_additions(original, self.read(), allowed_changed=1)

    def test_codex_home_is_respected(self):
        other = self.tmp / "other-home"
        other.mkdir()
        self.assertEqual(self.run_tool("apply", codex_home=other).returncode, 0)
        self.assertTrue((other / "config.toml").exists())
        self.assertFalse(self.config.exists())

    def test_file_mode_is_preserved(self):
        self.write('[tui]\nstatus_line = ["git-branch"]\n')
        os.chmod(self.config, 0o640)
        self.assertEqual(self.run_tool("apply").returncode, 0)
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o640)

    # --- unsupported forms ---------------------------------------------------

    def test_unparseable_file(self):
        self.assert_unsupported('[tui\nstatus_line = ["a"\n')

    def test_inline_table(self):
        self.assert_unsupported('tui = { status_line = ["git-branch"] }\n')

    def test_dotted_top_level_keys(self):
        self.assert_unsupported('tui.status_line = ["git-branch"]\n')

    def test_repeated_tui_table(self):
        self.assert_unsupported('[tui]\nstatus_line = ["a"]\n\n[tui]\nterminal_title = ["b"]\n')

    def test_non_array_value(self):
        self.assert_unsupported('[tui]\nstatus_line = "git-branch"\n')

    def test_non_string_items(self):
        self.assert_unsupported('[tui]\nstatus_line = [1, 2]\n')

    def test_write_failure_exits_4_with_snippet(self):
        self.write('[tui]\nstatus_line = ["git-branch"]\n')
        before = self.read()
        os.chmod(self.home, 0o555)
        try:
            result = self.run_tool("apply")
        finally:
            os.chmod(self.home, 0o755)
        if os.geteuid() == 0:
            self.skipTest("root ignores directory permissions")
        self.assertEqual(result.returncode, 4, result.stdout)
        self.assertIn("ERROR:", result.stderr)
        self.assertIn('status_line = ["git-branch", "task-progress"]', result.stdout)
        self.assertTrue(result.stdout.rstrip("\n").endswith(HINT))
        self.assertEqual(self.read(), before)

    # --- check, snippet, decline ---------------------------------------------

    def test_check_ask_without_config(self):
        self.assertEqual(self.run_tool("check", "--root", str(self.project)).stdout.strip(), "ASK")

    def test_check_declined(self):
        (self.project / ".specify").mkdir()
        (self.project / ".specify/spex.json").write_text(json.dumps({
            "schema_version": 1, "harness": "codex", "extensions": ["spex"],
            "security": "safe", "codex_progress": "declined",
        }))
        self.assertEqual(self.run_tool("check", "--root", str(self.project)).stdout.strip(), "DECLINED")

    def test_check_configured_wins_over_declined(self):
        self.test_check_declined()
        self.write('[tui]\nstatus_line = ["task-progress"]\nterminal_title = ["task-progress"]\n')
        self.assertEqual(self.run_tool("check", "--root", str(self.project)).stdout.strip(), "CONFIGURED")

    def test_snippet_uses_current_items(self):
        self.write('[tui]\nstatus_line = ["git-branch"]\n')
        result = self.run_tool("snippet")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.rstrip("\n").splitlines()[-1], HINT)
        self.assertIn('status_line = ["git-branch", "task-progress"]', result.stdout)
        self.assertIn('terminal_title = ["activity", "thread-name", "project-name", "task-progress"]', result.stdout)

    def test_snippet_falls_back_to_defaults_for_unparseable_file(self):
        self.write("this is not toml [\n")
        result = self.run_tool("snippet")
        self.assertEqual(result.returncode, 0)
        self.assertIn(
            'status_line = ["model-with-reasoning", "current-dir", "thread-name", "task-progress"]',
            result.stdout,
        )
        # The current lists are unknown: tell the user to append, not replace.
        self.assertIn('# Append "task-progress"', result.stdout)
        self.assertNotIn("[tui]\n", result.stdout)
        self.assertTrue(result.stdout.rstrip("\n").endswith(HINT))

    def test_snippet_for_existing_tui_table_has_no_header(self):
        self.write('[tui]\nnotifications = true\nstatus_line = ["git-branch"]\n')
        result = self.run_tool("snippet")
        self.assertNotIn("[tui]\n", result.stdout)
        # Applying the snippet as told (replace the key) yields valid TOML.
        keys = [line for line in result.stdout.splitlines() if " = [" in line]
        text = "[tui]\nnotifications = true\n" + "\n".join(keys) + "\n"
        tui = tomllib.loads(text)["tui"]
        self.assertEqual(tui["status_line"], ["git-branch", "task-progress"])

    def test_snippet_for_unsupported_forms_has_no_header(self):
        for text in ('tui.status_line = ["git-branch"]\n', 'tui = { status_line = ["git-branch"] }\n'):
            with self.subTest(text=text):
                self.write(text)
                result = self.run_tool("apply")
                self.assertEqual(result.returncode, 3)
                self.assertNotIn("[tui]\n", result.stdout)
                self.assertNotIn("existing [tui] table", result.stdout)
                self.assertIn('# Append "task-progress"', result.stdout)

    def test_snippet_with_only_a_tui_subtable_has_header(self):
        self.write("[tui.notifications]\nfoo = true\n")
        self.assertTrue(self.run_tool("snippet").stdout.startswith("[tui]\n"))

    def test_snippet_without_tui_table_has_header(self):
        self.write('model = "x"\n')
        result = self.run_tool("snippet")
        self.assertTrue(result.stdout.startswith("[tui]\n"), result.stdout)

    def test_symlinked_config_is_edited_through_the_link(self):
        dotfiles = self.tmp / "dotfiles"
        dotfiles.mkdir()
        target = dotfiles / "config.toml"
        target.write_text('model = "x"\n')
        self.config.symlink_to(target)
        result = self.run_tool("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.config.is_symlink())
        self.assertIn("task-progress", target.read_text())
        self.assertTrue(target.read_text().startswith('model = "x"\n'))

    def test_multiline_array_with_items_on_opening_line(self):
        self.write('[tui]\nstatus_line = ["a", "b"\n]\nterminal_title = ["task-progress"]\n')
        result = self.run_tool("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.lists()[0], ["a", "b", "task-progress"])

    def test_home_fallback_without_codex_home(self):
        home = self.tmp / "home"
        home.mkdir()
        env = {k: v for k, v in os.environ.items() if k != "CODEX_HOME"}
        env["HOME"] = str(home)
        result = subprocess.run(
            [sys.executable, str(TOOL), "apply"], env=env,
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"path={home / '.codex' / 'config.toml'}", result.stdout)
        self.assertTrue((home / ".codex" / "config.toml").is_file())

    def test_check_changes_nothing(self):
        before = sorted(p.relative_to(self.tmp) for p in self.tmp.rglob("*"))
        self.assertEqual(self.run_tool("check", "--root", str(self.project)).stdout.strip(), "ASK")
        after = sorted(p.relative_to(self.tmp) for p in self.tmp.rglob("*"))
        self.assertEqual(before, after)

    def test_check_unsupported_without_toml_parser(self):
        shadow = self.tmp / "shadow"
        shadow.mkdir()
        for name in ("tomllib", "tomli"):
            (shadow / f"{name}.py").write_text("raise ImportError('hidden for the test')\n")
        self.write('[tui]\nstatus_line = ["task-progress"]\nterminal_title = ["task-progress"]\n')
        env = dict(os.environ, CODEX_HOME=str(self.home), PYTHONPATH=str(shadow))
        result = subprocess.run(
            [sys.executable, str(TOOL), "check", "--root", str(self.project)], env=env,
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "UNSUPPORTED")
        self.assertIn("ERROR:", result.stderr)

    def test_decline_records_and_prints_hint(self):
        result = self.run_tool("decline", "--root", str(self.project))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), HINT)
        profile = json.loads((self.project / ".specify/spex.json").read_text())
        self.assertEqual(profile["codex_progress"], "declined")
        self.assertEqual(self.run_tool("check", "--root", str(self.project)).stdout.strip(), "DECLINED")

    def test_decline_failure_exits_1_and_prints_hint(self):
        (self.project / ".specify").mkdir()
        (self.project / ".specify/spex.json").write_text("{broken")
        result = self.run_tool("decline", "--root", str(self.project))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.strip(), HINT)
        self.assertIn("ERROR:", result.stderr)


if __name__ == "__main__":
    unittest.main()
