#!/usr/bin/env python3
"""Contract tests for the team-owned Spex setup declaration."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "spex/scripts/spex-setup-profile.py"
FIXTURES = ROOT / "tests/fixtures/setup-profile"


class SetupProfileTests(unittest.TestCase):
    def run_tool(self, *args: str, cwd: Path, input_value=None, success=True):
        payload = None if input_value is None else json.dumps(input_value)
        result = subprocess.run(
            ["python3", str(TOOL), *args], cwd=cwd, input=payload,
            capture_output=True, text=True, check=False,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        return result.stderr

    def test_defaults_are_recommended_and_safe(self):
        with tempfile.TemporaryDirectory() as raw:
            resolved = self.run_tool("resolve", "--root", raw, cwd=Path(raw))
        self.assertEqual(resolved["harness"], "auto")
        self.assertEqual(resolved["security"], "safe")
        self.assertEqual(
            resolved["extensions"],
            ["spex", "spex-gates", "spex-worktrees", "spex-deep-review"],
        )

    def test_stored_intent_is_reused_and_explicit_values_win(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            stored = json.loads((FIXTURES / "valid.json").read_text())
            self.run_tool("persist", "--root", raw, cwd=root, input_value=stored)
            reused = self.run_tool("resolve", "--root", raw, cwd=root)
            overridden = self.run_tool(
                "resolve", "--root", raw, "--harness", "claude",
                "--extensions", "spex,spex-collab", "--security", "yolo", cwd=root,
            )
        self.assertEqual(reused, stored)
        self.assertEqual(overridden["harness"], "claude")
        self.assertEqual(overridden["security"], "yolo")
        self.assertEqual(overridden["extensions"], ["spex", "spex-gates", "spex-collab"])

    def test_validation_rejects_unknowns_and_normalizes_dependencies(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            normalized = self.run_tool(
                "resolve", "--root", raw, "--extensions", "spex-teams,spex", cwd=root
            )
            error = self.run_tool(
                "validate", "--root", raw, cwd=root,
                input_value=json.loads((FIXTURES / "invalid.json").read_text()), success=False,
            )
        self.assertEqual(normalized["extensions"], ["spex", "spex-gates", "spex-teams"])
        self.assertIn("harness", error)

    def test_failure_is_byte_identical_and_persistence_is_atomic(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            valid = json.loads((FIXTURES / "valid.json").read_text())
            self.run_tool("persist", "--root", raw, cwd=root, input_value=valid)
            path = root / ".specify/spex.json"
            before = hashlib.sha256(path.read_bytes()).digest()
            self.run_tool(
                "persist", "--root", raw, cwd=root,
                input_value={**valid, "security": "unsafe"}, success=False,
            )
            after = hashlib.sha256(path.read_bytes()).digest()
            temporary = list(path.parent.glob(".spex.*.tmp"))
        self.assertEqual(before, after)
        self.assertEqual(temporary, [])

    def test_legacy_permission_names_migrate(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            safe = self.run_tool(
                "resolve", "--root", raw, "--legacy-permissions", "none", cwd=root
            )
            autonomous = self.run_tool(
                "resolve", "--root", raw, "--legacy-permissions", "standard", cwd=root
            )
        self.assertEqual(safe["security"], "safe")
        self.assertEqual(autonomous["security"], "autonomous")

    def resolve_extensions(self, *args: str) -> list[str]:
        with tempfile.TemporaryDirectory() as raw:
            return self.run_tool("resolve", "--root", raw, *args, cwd=Path(raw))["extensions"]

    def test_mode_recommended(self):
        self.assertEqual(
            self.resolve_extensions("--mode", "recommended"),
            ["spex", "spex-gates", "spex-worktrees", "spex-deep-review"],
        )

    def test_mode_all_excludes_detach(self):
        self.assertEqual(
            self.resolve_extensions("--mode", "all"),
            ["spex", "spex-gates", "spex-worktrees", "spex-deep-review",
             "spex-teams", "spex-collab"],
        )

    def test_interactive_reply_all_equals_all_mode(self):
        self.assertEqual(
            self.resolve_extensions("--mode", "interactive", "--reply", "all"),
            self.resolve_extensions("--mode", "all"),
        )
        self.assertEqual(
            self.resolve_extensions("--mode", "interactive", "--reply", '"all"'),
            self.resolve_extensions("--mode", "all"),
        )

    def test_interactive_empty_reply_equals_recommended(self):
        recommended = self.resolve_extensions("--mode", "recommended")
        self.assertEqual(
            self.resolve_extensions("--mode", "interactive", "--reply", ""), recommended
        )
        self.assertEqual(self.resolve_extensions("--mode", "interactive"), recommended)
        self.assertEqual(
            self.resolve_extensions("--mode", "interactive", "--reply", "  "), recommended
        )

    def test_interactive_list_adds_gates_and_keeps_detach(self):
        self.assertEqual(
            self.resolve_extensions(
                "--mode", "interactive", "--reply", "spex-teams,spex-detach"
            ),
            ["spex", "spex-gates", "spex-teams", "spex-detach"],
        )

    def test_extensions_spex_only(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            stored = json.loads((FIXTURES / "valid.json").read_text())
            self.run_tool("persist", "--root", raw, cwd=root, input_value=stored)
            resolved = self.run_tool(
                "resolve", "--root", raw, "--extensions", "spex", cwd=root
            )
        self.assertEqual(resolved["extensions"], ["spex"])

    def test_mode_rejects_unknown_reply_and_mixed_inputs(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            unknown = self.run_tool(
                "resolve", "--root", raw, "--mode", "interactive",
                "--reply", "spex-bogus", cwd=root, success=False,
            )
            mixed = self.run_tool(
                "resolve", "--root", raw, "--mode", "all",
                "--extensions", "spex-gates", cwd=root, success=False,
            )
        self.assertIn("unknown extension", unknown)
        self.assertIn("mutually exclusive", mixed)


class MigrateDetachTests(unittest.TestCase):
    """Legacy `all` declarations listed spex-detach while it stayed disabled."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        (self.root / ".specify/extensions").mkdir(parents=True)
        self.snapshot = self.root / ".specify/extensions/.registry.before"

    def tearDown(self):
        self.directory.cleanup()

    def declare(self, extensions: list[str]) -> None:
        value = {
            "schema_version": 1, "harness": "claude",
            "extensions": extensions, "security": "safe",
        }
        (self.root / ".specify/spex.json").write_text(json.dumps(value))

    def snapshot_with(self, entries: dict) -> None:
        self.snapshot.write_text(json.dumps({"schema_version": "1.0", "extensions": entries}))

    def migrate(self, before: Path | None = None):
        return subprocess.run(
            ["python3", str(TOOL), "migrate-detach", "--root", str(self.root),
             "--before", str(before or self.snapshot)],
            cwd=self.root, capture_output=True, text=True, check=False,
        )

    def declared(self) -> list[str]:
        return json.loads((self.root / ".specify/spex.json").read_text())["extensions"]

    def test_disabled_detach_is_removed_and_reported(self):
        self.declare(["spex", "spex-gates", "spex-detach"])
        self.snapshot_with({"spex": {"enabled": True}, "spex-detach": {"enabled": False}})
        result = self.migrate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.declared(), ["spex", "spex-gates"])
        self.assertIn("Migrated: removed spex-detach from .specify/spex.json", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(list((self.root / ".specify").glob(".spex.*.tmp")), [])

    def test_enabled_detach_is_kept(self):
        self.declare(["spex", "spex-detach"])
        self.snapshot_with({"spex-detach": {"enabled": True}})
        before = (self.root / ".specify/spex.json").read_bytes()
        result = self.migrate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / ".specify/spex.json").read_bytes(), before)
        self.assertEqual(result.stderr, "")

    def test_declaration_without_detach_is_unchanged(self):
        self.declare(["spex", "spex-gates"])
        self.snapshot_with({"spex-detach": {"enabled": False}})
        before = (self.root / ".specify/spex.json").read_bytes()
        result = self.migrate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / ".specify/spex.json").read_bytes(), before)
        self.assertEqual(result.stderr, "")

    def test_snapshot_without_detach_entry_is_unchanged(self):
        self.declare(["spex", "spex-detach"])
        self.snapshot_with({"spex": {"enabled": True}})
        result = self.migrate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.declared(), ["spex", "spex-detach"])
        self.assertEqual(result.stderr, "")

    def test_missing_snapshot_file_is_unchanged(self):
        self.declare(["spex", "spex-detach"])
        result = self.migrate(self.root / "missing.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.declared(), ["spex", "spex-detach"])
        self.assertEqual(result.stderr, "")

    def test_invalid_declaration_exits_1(self):
        (self.root / ".specify/spex.json").write_text('{"schema_version": 1}')
        self.snapshot_with({"spex-detach": {"enabled": False}})
        result = self.migrate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("ERROR", result.stderr)

    def test_invalid_root_is_a_usage_error(self):
        result = subprocess.run(
            ["python3", str(TOOL), "migrate-detach", "--root", "relative/path",
             "--before", str(self.snapshot)],
            cwd=self.root, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 2)

    def test_missing_before_argument_is_a_usage_error(self):
        result = subprocess.run(
            ["python3", str(TOOL), "migrate-detach", "--root", str(self.root)],
            cwd=self.root, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 2)


SETUP = ROOT / "spex/setup.yml"
SPEX = ROOT / "spex"


def step_ids() -> list[str]:
    result = subprocess.run(
        ["yq", "-r", ".steps[].id", str(SETUP)],
        capture_output=True, text=True, check=True,
    )
    return result.stdout.split()


def step_run(step_id: str) -> str:
    result = subprocess.run(
        ["yq", "-r", f'.steps[] | select(.id == "{step_id}") | .run', str(SETUP)],
        capture_output=True, text=True, check=True,
    )
    return result.stdout


@unittest.skipUnless(shutil.which("yq") and shutil.which("jq"), "yq and jq are required")
class SetupWorkflowGlueTests(unittest.TestCase):
    """Run the setup.yml shell blocks that resolve the selection and security.

    The workflow engine substitutes `{{ ... }}` textually before /bin/sh runs
    the block, so the rendering below does the same.
    """

    def render(self, step_id: str, values: dict[str, str]) -> str:
        script = step_run(step_id)
        for expression, value in values.items():
            self.assertIn(expression, script)
            script = script.replace(expression, value)
        self.assertNotIn("{{", script, "unrendered expression")
        return script

    def run_block(self, script: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as raw:
            return subprocess.run(
                ["/bin/sh", "-c", script], cwd=raw,
                capture_output=True, text=True, check=False,
            )

    def selected_extensions(self, mode: str) -> subprocess.CompletedProcess:
        return self.run_block(self.render("selected-extensions", {
            "{{ steps.extension-mode.output.stdout }}": mode,
            "{{ steps.validate-source.output.stdout }}": str(SPEX),
        }))

    def test_no_prompt_step_and_no_prompt_output_in_shell(self):
        prompts = subprocess.run(
            ["yq", "-r", '.. | select(type == "!!map" and .type == "prompt") | .id', str(SETUP)],
            capture_output=True, text=True, check=True,
        ).stdout.split()
        self.assertEqual(prompts, [], "prompt replies are discarded by spec-kit")
        for step in step_ids():
            self.assertNotIn("prompt.output", step_run(step), step)

    def test_modes_resolve_without_trailing_newline(self):
        cases = {
            "recommended": "spex,spex-gates,spex-worktrees,spex-deep-review",
            "all": "spex,spex-gates,spex-worktrees,spex-deep-review,spex-teams,spex-collab",
            "spex-gates,spex-worktrees": "spex,spex-gates,spex-worktrees",
            "spex-teams,spex-detach": "spex,spex-gates,spex-teams,spex-detach",
        }
        for mode, expected in cases.items():
            with self.subTest(mode=mode):
                result = self.selected_extensions(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)

    def test_interactive_falls_back_to_recommended_and_says_so(self):
        result = self.selected_extensions("interactive")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "spex,spex-gates,spex-worktrees,spex-deep-review")
        self.assertIn("NOTE: the interactive reply cannot be read back", result.stderr)

    def test_unknown_name_fails_the_step_and_is_named(self):
        result = self.selected_extensions("spex-gates,spex-worktree")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("spex-worktree", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_security_modes(self):
        for mode, expected in {"safe": "safe", "autonomous": "autonomous", "yolo": "yolo"}.items():
            with self.subTest(mode=mode):
                result = self.run_block(self.render("selected-security", {
                    "{{ steps.security-mode.output.stdout }}": mode,
                }))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)
        result = self.run_block(self.render("selected-security", {
            "{{ steps.security-mode.output.stdout }}": "interactive",
        }))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "safe")
        self.assertIn("NOTE: the interactive reply cannot be read back", result.stderr)
        result = self.run_block(self.render("selected-security", {
            "{{ steps.security-mode.output.stdout }}": "bogus",
        }))
        self.assertNotEqual(result.returncode, 0)

    def test_inputs_are_resolved_before_anything_is_reinstalled(self):
        ids = step_ids()
        first_install = ids.index("install-ext-spex")
        first_change = min(ids.index(s) for s in (
            "migrate-commands", "init-project", "snapshot-before-install", "install-ext-spex"))
        for step in ("selected-extensions", "selected-security"):
            self.assertLess(ids.index(step), first_change, step)
        self.assertLess(first_install, ids.index("apply-extensions"))
        self.assertLess(ids.index("apply-extensions"), ids.index("persist-request"))


class InitSkillDeclarationTests(unittest.TestCase):
    """The resolve, apply, persist sequence of the init skill (FR-022)."""

    def resolve_persist(self, root: Path, *args: str) -> dict:
        resolved = subprocess.run(
            ["python3", str(TOOL), "resolve", "--root", str(root), *args],
            capture_output=True, text=True, check=True,
        ).stdout
        subprocess.run(
            ["python3", str(TOOL), "persist", "--root", str(root)],
            input=resolved, capture_output=True, text=True, check=True,
        )
        return json.loads((root / ".specify/spex.json").read_text())

    def test_create_then_update(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            created = self.resolve_persist(
                root, "--extensions", "spex,spex-teams",
                "--legacy-permissions", "standard", "--harness", "claude",
            )
            self.assertEqual(created["harness"], "claude")
            self.assertEqual(created["security"], "autonomous")
            self.assertEqual(created["extensions"], ["spex", "spex-gates", "spex-teams"])
            data = dict(created, harness="codex")
            (root / ".specify/spex.json").write_text(json.dumps(data))
            updated = self.resolve_persist(
                root, "--extensions", "spex", "--legacy-permissions", "yolo",
            )
            self.assertEqual(updated["harness"], "codex")
            self.assertEqual(updated["security"], "yolo")
            self.assertEqual(updated["extensions"], ["spex"])
            self.assertEqual(
                self.resolve_persist(root, "--extensions", "spex",
                                     "--legacy-permissions", "none")["security"],
                "safe",
            )


class CodexProgressFieldTests(unittest.TestCase):
    """The optional codex_progress field (FR-024) survives every setup run."""

    def run_tool(self, *args: str, root: Path, input_value=None):
        payload = None if input_value is None else json.dumps(input_value)
        return subprocess.run(
            ["python3", str(TOOL), *args, "--root", str(root)], cwd=root, input=payload,
            capture_output=True, text=True, check=False,
        )

    def declaration(self, **extra) -> dict:
        return {**json.loads((FIXTURES / "valid.json").read_text()), **extra}

    def test_validate_accepts_declined(self):
        with tempfile.TemporaryDirectory() as raw:
            result = self.run_tool("validate", root=Path(raw),
                                   input_value=self.declaration(codex_progress="declined"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["codex_progress"], "declined")

    def test_validate_rejects_other_values(self):
        # Unhashable values (list, object) must give the validation error too,
        # not a traceback.
        for value in ("accepted", "", True, None, [], ["declined"], {"a": 1}):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as raw:
                result = self.run_tool("validate", root=Path(raw),
                                       input_value=self.declaration(codex_progress=value))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR: codex_progress", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_validate_rejects_unhashable_harness_and_security(self):
        for field in ("harness", "security"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as raw:
                result = self.run_tool("validate", root=Path(raw),
                                       input_value=self.declaration(**{field: []}))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"ERROR: {field}", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_validate_omits_field_when_absent(self):
        with tempfile.TemporaryDirectory() as raw:
            result = self.run_tool("validate", root=Path(raw), input_value=self.declaration())
        self.assertNotIn("codex_progress", json.loads(result.stdout))

    def test_resolve_and_persist_keep_the_decline(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            stored = self.declaration(codex_progress="declined")
            persisted = self.run_tool("persist", root=root, input_value=stored)
            self.assertEqual(persisted.returncode, 0, persisted.stderr)
            self.assertEqual(json.loads((root / ".specify/spex.json").read_text()), stored)
            # A refresh with explicit inputs (as setup.yml runs it) keeps the field.
            resolved = subprocess.run(
                ["python3", str(TOOL), "resolve", "--root", raw, "--harness", "codex",
                 "--extensions", "spex,spex-gates", "--security", "safe"],
                capture_output=True, text=True, check=True,
            ).stdout
            self.assertEqual(json.loads(resolved)["codex_progress"], "declined")
            again = subprocess.run(
                ["python3", str(TOOL), "persist", "--root", raw],
                input=resolved, capture_output=True, text=True, check=True,
            )
            self.assertEqual(json.loads(again.stdout)["codex_progress"], "declined")
            self.assertEqual(
                json.loads((root / ".specify/spex.json").read_text())["codex_progress"], "declined"
            )

    def test_decline_updates_an_existing_profile(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.run_tool("persist", root=root, input_value=self.declaration())
            result = self.run_tool("decline-codex-progress", root=root)
            self.assertEqual(result.returncode, 0, result.stderr)
            stored = json.loads((root / ".specify/spex.json").read_text())
        self.assertEqual(stored, self.declaration(codex_progress="declined"))

    def test_decline_creates_a_default_profile(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            result = self.run_tool("decline-codex-progress", root=root)
            self.assertEqual(result.returncode, 0, result.stderr)
            stored = json.loads((root / ".specify/spex.json").read_text())
        self.assertEqual(stored["codex_progress"], "declined")
        self.assertEqual(stored["harness"], "auto")
        self.assertEqual(stored["security"], "safe")

    def test_decline_with_invalid_profile_fails(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            (root / ".specify").mkdir()
            (root / ".specify/spex.json").write_text("{broken")
            result = self.run_tool("decline-codex-progress", root=root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR:", result.stderr)


if __name__ == "__main__":
    unittest.main()
