#!/usr/bin/env python3
"""Test-first contract for deterministic WorkflowState candidate resolution."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
STATE_CLI = REPO_ROOT / "spex" / "scripts" / "spex-ship-state.sh"
FEATURE_BRANCH = "047-resolver-fixture"
TIMESTAMP = "2026-07-24T12:00:00Z"


class StateResolverTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="spex-state-resolver-")
        self.root = Path(self.tempdir.name)
        self.repository = self.root / "repository"
        self.worktree = self.root / "feature-worktree"

        self.git("init", "-q", "-b", "main", str(self.repository), cwd=self.root)
        self.git("config", "user.name", "Spex Test", cwd=self.repository)
        self.git("config", "user.email", "spex-test@example.invalid", cwd=self.repository)
        (self.repository / "README.md").write_text("resolver fixture\n", encoding="utf-8")
        self.git("add", "README.md", cwd=self.repository)
        self.git("commit", "-q", "-m", "initial", cwd=self.repository)
        self.git(
            "worktree",
            "add",
            "-q",
            "-b",
            FEATURE_BRANCH,
            str(self.worktree),
            cwd=self.repository,
        )
        self.make_spec(self.worktree)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def git(self, *args: str, cwd: Path) -> str:
        result = subprocess.run(
            ["git", *args], cwd=cwd, text=True, capture_output=True, check=False
        )
        if result.returncode != 0:
            self.fail(f"fixture git command failed: {' '.join(args)}\n{result.stderr}")
        return result.stdout.strip()

    def make_spec(self, checkout: Path) -> Path:
        spec_dir = checkout / "specs" / FEATURE_BRANCH
        spec_dir.mkdir(parents=True, exist_ok=True)
        (spec_dir / "spec.md").write_text("# Resolver fixture\n", encoding="utf-8")
        return spec_dir

    def state_path(self, checkout: Path) -> Path:
        return checkout / ".specify" / ".spex-state"

    def state_for(
        self,
        *,
        active_worktree: Path | None = None,
        feature_branch: str = FEATURE_BRANCH,
        spec_dir: Path | None = None,
        state_file: Path | None = None,
        stage: str = "plan",
    ) -> dict:
        active = (active_worktree or self.worktree).resolve()
        spec = (spec_dir or (active / "specs" / FEATURE_BRANCH)).resolve()
        state = (state_file or self.state_path(active)).resolve()
        head_oid = self.git("rev-parse", "HEAD", cwd=self.worktree)
        return {
            "schema_version": "2.0.0",
            "workflow_id": "resolver-fixture-001",
            "revision": 3,
            "mode": "ship",
            "context": {
                "repository_root": str(self.repository.resolve()),
                "git_common_dir": str((self.repository / ".git").resolve()),
                "active_worktree": str(active),
                "feature_branch": feature_branch,
                "spec_dir": str(spec),
                "state_file": str(state),
                "head_oid": head_oid,
                "validated_at": TIMESTAMP,
            },
            "stage": stage,
            "status": "running",
            "completed_gates": ["review-spec"],
            "recovery": None,
            "resume_point": {"stage": stage, "action": "continue", "artifact": None},
            "diagnostics": [],
            "created_at": TIMESTAMP,
            "updated_at": TIMESTAMP,
        }

    def write_state(self, path: Path, state: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")

    def run_resolve(self, cwd: Path) -> tuple[subprocess.CompletedProcess[str], dict]:
        env = os.environ.copy()
        env.pop("SHIP_STATE_FILE", None)
        result = subprocess.run(
            [str(STATE_CLI), "resolve"],
            cwd=cwd,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            self.fail(
                "resolve must emit one JSON diagnostic/result object; "
                f"exit={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
        return result, payload

    def assert_refusal(self, cwd: Path, *evidence: str) -> dict:
        result, payload = self.run_resolve(cwd)
        self.assertNotEqual(result.returncode, 0, "invalid identity must fail closed")
        self.assertEqual(payload.get("status"), "failed_validation")
        self.assertIsInstance(payload.get("diagnostics"), list)
        self.assertTrue(payload["diagnostics"], "refusal must preserve diagnostics")
        rendered = json.dumps(payload, sort_keys=True).lower()
        for item in evidence:
            self.assertIn(item.lower(), rendered)
        return payload

    def without_timestamps(self, value):
        if isinstance(value, dict):
            return {
                key: self.without_timestamps(item)
                for key, item in value.items()
                if not key.endswith("_at")
            }
        if isinstance(value, list):
            return [self.without_timestamps(item) for item in value]
        return value

    def install_competing_states(self) -> tuple[Path, Path]:
        main_state = self.state_path(self.repository)
        feature_state = self.state_path(self.worktree)
        wrong_main = self.state_for(
            feature_branch="047-wrong-branch", state_file=main_state
        )
        self.write_state(main_state, wrong_main)
        self.write_state(feature_state, self.state_for(state_file=feature_state))
        return main_state, feature_state

    def test_competing_states_select_worktree_candidate_from_main(self) -> None:
        main_state, feature_state = self.install_competing_states()

        result, payload = self.run_resolve(self.repository)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload["context"]["active_worktree"], str(self.worktree.resolve()))
        self.assertEqual(payload["context"]["state_file"], str(feature_state.resolve()))
        evidence = json.dumps(payload.get("diagnostics", []), sort_keys=True)
        self.assertIn(str(main_state.resolve()), evidence)
        self.assertIn("branch", evidence.lower())

    def test_main_and_worktree_invocations_resolve_same_authority(self) -> None:
        _, feature_state = self.install_competing_states()

        main_result, main_payload = self.run_resolve(self.repository)
        worktree_result, worktree_payload = self.run_resolve(self.worktree)

        self.assertEqual(main_result.returncode, 0, main_result.stderr)
        self.assertEqual(worktree_result.returncode, 0, worktree_result.stderr)
        self.assertEqual(main_payload["workflow_id"], worktree_payload["workflow_id"])
        self.assertEqual(main_payload["revision"], worktree_payload["revision"])
        self.assertEqual(
            main_payload["context"]["state_file"], str(feature_state.resolve())
        )
        self.assertEqual(main_payload["context"], worktree_payload["context"])

    def test_moved_worktree_is_refused_with_old_path_evidence(self) -> None:
        main_state = self.state_path(self.repository)
        feature_state = self.state_path(self.worktree)
        state = self.state_for(state_file=feature_state)
        self.write_state(main_state, state)
        self.write_state(feature_state, state)
        old_path = self.worktree.resolve()
        moved_path = self.root / "moved-feature-worktree"
        self.git("worktree", "move", str(self.worktree), str(moved_path), cwd=self.repository)
        self.worktree = moved_path

        self.assert_refusal(self.repository, str(old_path), "worktree")

    def test_deleted_worktree_is_refused_without_recreating_state(self) -> None:
        main_state = self.state_path(self.repository)
        feature_state = self.state_path(self.worktree)
        state = self.state_for(state_file=feature_state)
        self.write_state(main_state, state)
        self.write_state(feature_state, state)
        deleted_path = self.worktree.resolve()
        self.git("worktree", "remove", "--force", str(self.worktree), cwd=self.repository)

        self.assert_refusal(self.repository, str(deleted_path), "worktree")
        self.assertFalse(deleted_path.exists(), "resolver must not recreate a deleted worktree")

    def test_invalid_spec_and_branch_mismatch_refuse_deterministically(self) -> None:
        main_state = self.state_path(self.repository)
        missing_spec = self.worktree / "specs" / "047-missing-spec"
        invalid = self.state_for(
            feature_branch="047-wrong-branch",
            spec_dir=missing_spec,
            state_file=main_state,
        )
        self.write_state(main_state, invalid)

        first_payload = self.assert_refusal(
            self.repository, str(main_state.resolve()), str(missing_spec), "branch", "spec"
        )
        second_payload = self.assert_refusal(
            self.repository, str(main_state.resolve()), str(missing_spec), "branch", "spec"
        )
        self.assertEqual(
            self.without_timestamps(first_payload),
            self.without_timestamps(second_payload),
            "refusal diagnostics must be deterministic apart from observation timestamps",
        )
        self.assertEqual(json.loads(main_state.read_text()), invalid, "resolver must not mutate candidates")


if __name__ == "__main__":
    unittest.main(verbosity=2)
