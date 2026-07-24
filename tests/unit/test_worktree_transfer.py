#!/usr/bin/env python3
"""Contract tests for WorktreeIdentity and transactional state transfer."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
STATE_TOOL = REPO_ROOT / "spex" / "scripts" / "spex-ship-state.sh"
TRANSFER_PHASES = (
    "prepared_main",
    "candidate_written",
    "candidate_validated",
    "committed_worktree",
    "main_removed",
)


def command(*args: str, cwd: Path | None = None) -> str:
    result = subprocess.run(
        args, cwd=cwd, text=True, capture_output=True, check=False
    )
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} failed: {result.stderr}")
    return result.stdout.strip()


def state_tool_supports_transfer() -> bool:
    if not STATE_TOOL.is_file():
        return False
    result = subprocess.run(
        [str(STATE_TOOL), "transfer", "--help"],
        text=True,
        capture_output=True,
        check=False,
    )
    combined = f"{result.stdout}\n{result.stderr}".lower()
    return "--source" in combined and "--destination" in combined


class TransferFixture:
    def __init__(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="spex-transfer-test-")
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repository"
        self.worktree = self.root / "worktree"
        command("git", "init", "-q", str(self.repository))
        command("git", "config", "user.name", "Spex Test", cwd=self.repository)
        command("git", "config", "user.email", "spex@example.invalid", cwd=self.repository)
        command("git", "commit", "--allow-empty", "-q", "-m", "initial", cwd=self.repository)
        command(
            "git",
            "worktree",
            "add",
            "-q",
            "-b",
            "047-transfer-test",
            str(self.worktree),
            cwd=self.repository,
        )
        self.spec_dir = self.worktree / "specs" / "047-transfer-test"
        self.spec_dir.mkdir(parents=True)
        (self.spec_dir / "spec.md").write_text("# Transfer test\n", encoding="utf-8")
        self.source = self.repository / ".specify" / ".spex-state"
        self.destination = self.worktree / ".specify" / ".spex-state"
        self.source.parent.mkdir(parents=True)
        self.destination.parent.mkdir(parents=True)
        self.identity_file = self.root / "identity.json"
        self.identity = self.make_identity()
        self.identity_file.write_text(json.dumps(self.identity), encoding="utf-8")
        self.initial_state = self.make_state()
        self.source.write_text(json.dumps(self.initial_state), encoding="utf-8")

    def close(self) -> None:
        self.temporary.cleanup()

    def make_identity(self) -> dict[str, object]:
        common_dir_raw = command(
            "git", "rev-parse", "--git-common-dir", cwd=self.worktree
        )
        common_dir = Path(common_dir_raw)
        if not common_dir.is_absolute():
            common_dir = self.worktree / common_dir
        return {
            "repository_root": str(self.repository.resolve()),
            "git_common_dir": str(common_dir.resolve()),
            "active_worktree": str(self.worktree.resolve()),
            "feature_branch": "047-transfer-test",
            "spec_dir": str(self.spec_dir.resolve()),
            "state_file": str(self.destination.resolve()),
            "head_oid": command("git", "rev-parse", "HEAD", cwd=self.worktree),
            "validated_at": "2026-07-24T12:00:00Z",
        }

    def make_state(self) -> dict[str, object]:
        return {
            "schema_version": "2.0.0",
            "workflow_id": "workflow-transfer-047",
            "revision": 1,
            "mode": "ship",
            "context": self.identity,
            "stage": "specify",
            "status": "running",
            "completed_gates": [],
            "resume_point": {"stage": "specify", "action": "continue"},
            "diagnostics": [],
            "created_at": "2026-07-24T12:00:00Z",
            "updated_at": "2026-07-24T12:00:00Z",
        }

    def run_tool(
        self, *arguments: str, fail_after: str | None = None
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        if fail_after is not None:
            environment["SPEX_TRANSFER_FAIL_AFTER"] = fail_after
        return subprocess.run(
            [str(STATE_TOOL), *arguments],
            cwd=self.repository,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def transfer(self, transfer_id: str, fail_after: str | None = None):
        return self.run_tool(
            "transfer",
            "--source",
            str(self.source),
            "--destination",
            str(self.destination),
            "--identity-file",
            str(self.identity_file),
            "--transfer-id",
            transfer_id,
            fail_after=fail_after,
        )


@unittest.skipUnless(STATE_TOOL.exists(), "state helper is absent")
class WorktreeTransferTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = TransferFixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def test_validates_registered_worktree_identity(self) -> None:
        result = self.fixture.run_tool(
            "validate", "--identity-file", str(self.fixture.identity_file)
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), self.fixture.identity)

    def test_rejects_identity_that_does_not_match_registered_worktree(self) -> None:
        invalid = dict(self.fixture.identity)
        invalid["feature_branch"] = "047-wrong-branch"
        self.fixture.identity_file.write_text(json.dumps(invalid), encoding="utf-8")
        before = self.fixture.source.read_bytes()

        result = self.fixture.run_tool(
            "validate", "--identity-file", str(self.fixture.identity_file)
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.fixture.source.read_bytes(), before)
        self.assertFalse(self.fixture.destination.exists())

    def test_source_is_retained_after_failure_at_every_nonterminal_phase(self) -> None:
        for phase in TRANSFER_PHASES[:-1]:
            with self.subTest(phase=phase):
                fixture = TransferFixture()
                self.addCleanup(fixture.close)
                source_before = fixture.source.read_bytes()

                result = fixture.transfer(f"transfer-{phase}", fail_after=phase)

                self.assertNotEqual(result.returncode, 0, phase)
                self.assertTrue(fixture.source.exists(), phase)
                self.assertEqual(fixture.source.read_bytes(), source_before, phase)
                if phase in ("prepared_main", "candidate_written", "candidate_validated"):
                    if fixture.destination.exists():
                        destination = json.loads(fixture.destination.read_text())
                        self.assertFalse(self.authoritative(destination), phase)

    def test_success_removes_source_only_after_verified_commit(self) -> None:
        result = self.fixture.transfer("transfer-success")

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["phase"], "main_removed")
        self.assertFalse(self.fixture.source.exists())
        self.assertTrue(self.fixture.destination.exists())
        destination = json.loads(self.fixture.destination.read_text())
        self.assertEqual(destination["context"], self.fixture.identity)
        self.assertTrue(self.authoritative(destination))

    def test_fault_after_terminal_transition_leaves_complete_destination(self) -> None:
        result = self.fixture.transfer("transfer-terminal", fail_after="main_removed")

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.fixture.source.exists())
        self.assertTrue(self.fixture.destination.exists())
        self.assertTrue(self.authoritative(json.loads(self.fixture.destination.read_text())))

    def test_crash_with_competing_copies_resumes_same_transfer(self) -> None:
        first = self.fixture.transfer(
            "transfer-resume", fail_after="candidate_validated"
        )
        self.assertNotEqual(first.returncode, 0)
        self.assertTrue(self.fixture.source.exists())
        self.assertTrue(self.fixture.destination.exists())

        resumed = self.fixture.transfer("transfer-resume")

        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertFalse(self.fixture.source.exists())
        destination = json.loads(self.fixture.destination.read_text())
        self.assertTrue(self.authoritative(destination))
        self.assertEqual(self.transfer_id(destination), "transfer-resume")

    def test_competing_copy_from_different_transfer_is_preserved_and_refused(self) -> None:
        first = self.fixture.transfer(
            "transfer-original", fail_after="candidate_written"
        )
        self.assertNotEqual(first.returncode, 0)
        source_before = self.fixture.source.read_bytes()
        destination_before = self.fixture.destination.read_bytes()

        conflict = self.fixture.transfer("transfer-conflict")

        self.assertNotEqual(conflict.returncode, 0)
        self.assertEqual(self.fixture.source.read_bytes(), source_before)
        self.assertEqual(self.fixture.destination.read_bytes(), destination_before)

    @staticmethod
    def transfer_diagnostic(state: dict[str, object]) -> dict[str, object]:
        diagnostics = state.get("diagnostics", [])
        matches = [
            item
            for item in diagnostics
            if isinstance(item, dict) and "transfer_id" in item
        ]
        if len(matches) != 1:
            raise AssertionError(f"expected one transfer diagnostic, got {matches!r}")
        return matches[0]

    @classmethod
    def authoritative(cls, state: dict[str, object]) -> bool:
        return cls.transfer_diagnostic(state).get("authoritative") is True

    @classmethod
    def transfer_id(cls, state: dict[str, object]) -> object:
        return cls.transfer_diagnostic(state).get("transfer_id")


if __name__ == "__main__":
    if not state_tool_supports_transfer():
        print(
            "FAIL: WorkflowState v2 transfer interface is not implemented; "
            "T028 is test-first and requires T031/T033 transfer --source/--destination support.",
            file=sys.stderr,
        )
        raise SystemExit(1)
    unittest.main()
