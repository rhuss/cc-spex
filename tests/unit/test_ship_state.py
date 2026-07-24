#!/usr/bin/env python3
"""Contract tests for WorkflowState v2 persistence and legacy migration.

T027 is intentionally test-first. T031 must provide the small module API named
by ``REQUIRED_API``; until then this suite reports one precise contract failure
instead of cascading AttributeErrors through every behavioral test.
"""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
STATE_TOOL = REPO_ROOT / "spex/scripts/spex-ship-state.py"
VALID_FIXTURE = REPO_ROOT / "tests/fixtures/contracts/workflow-state/valid.json"
INVALID_FIXTURE = REPO_ROOT / "tests/fixtures/contracts/workflow-state/invalid.json"
REQUIRED_API = (
    "StateError",
    "validate_workflow_state",
    "migrate_legacy_state",
    "read_workflow_state",
    "write_workflow_state",
)


def load_state_module():
    spec = importlib.util.spec_from_file_location("spex_ship_state", STATE_TOOL)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import WorkflowState implementation: {STATE_TOOL}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


STATE = load_state_module()
MISSING_API = tuple(name for name in REQUIRED_API if not hasattr(STATE, name))


def fixture(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class WorkflowStateApiContractTests(unittest.TestCase):
    def test_v2_persistence_api_is_available(self):
        self.assertFalse(
            MISSING_API,
            "T031 must implement the WorkflowState v2 API; missing: "
            + ", ".join(MISSING_API),
        )


@unittest.skipIf(MISSING_API, "T031 WorkflowState v2 API is not implemented")
class WorkflowStateV2Tests(unittest.TestCase):
    def setUp(self):
        self.valid = fixture(VALID_FIXTURE)
        self.invalid = fixture(INVALID_FIXTURE)
        self.initial = copy.deepcopy(self.valid)
        self.initial["revision"] = 1
        self.temporary = tempfile.TemporaryDirectory(prefix="spex-ship-state-")
        self.addCleanup(self.temporary.cleanup)
        self.state_path = Path(self.temporary.name) / ".specify/.spex-state"

    def next_revision(self, state: dict) -> dict:
        updated = copy.deepcopy(state)
        updated["revision"] += 1
        updated["stage"] = "review-code"
        updated["resume_point"] = {
            "stage": "review-code",
            "action": "run code review",
            "artifact": None,
        }
        updated["updated_at"] = "2026-07-24T11:00:00Z"
        return updated

    def test_v2_validation_and_serialization_round_trip(self):
        validated = STATE.validate_workflow_state(copy.deepcopy(self.valid))
        self.assertEqual(validated, self.valid)

        STATE.write_workflow_state(self.state_path, self.initial, expected_revision=0)
        loaded = STATE.read_workflow_state(self.state_path)

        self.assertEqual(loaded, self.initial)
        self.assertEqual(json.loads(self.state_path.read_text()), self.initial)
        self.assertTrue(self.state_path.read_bytes().endswith(b"\n"))

    def test_schema_validation_rejects_invalid_and_unknown_fields(self):
        with self.assertRaises(STATE.StateError):
            STATE.validate_workflow_state(copy.deepcopy(self.invalid))

        unknown = copy.deepcopy(self.valid)
        unknown["legacy_stage_index"] = 6
        with self.assertRaises(STATE.StateError):
            STATE.validate_workflow_state(unknown)

    def test_validation_rejects_nested_identity_and_resume_errors(self):
        relative_identity = copy.deepcopy(self.valid)
        relative_identity["context"]["active_worktree"] = "relative/worktree"
        with self.assertRaises(STATE.StateError):
            STATE.validate_workflow_state(relative_identity)

        incomplete_resume = copy.deepcopy(self.valid)
        del incomplete_resume["resume_point"]["action"]
        with self.assertRaises(STATE.StateError):
            STATE.validate_workflow_state(incomplete_resume)

    def test_legacy_state_migrates_once_to_v2_without_legacy_fields(self):
        legacy = {
            "mode": "ship",
            "stage": "implement",
            "stage_index": 6,
            "total_stages": 8,
            "ask": "smart",
            "started_at": "2026-07-24T09:00:00Z",
            "retries": 0,
            "status": "paused",
            "brainstorm_file": "brainstorms/047-codex.md",
            "feature_branch": self.valid["context"]["feature_branch"],
        }
        context = copy.deepcopy(self.valid["context"])

        migrated = STATE.migrate_legacy_state(
            legacy, context=context, now="2026-07-24T10:16:00Z"
        )
        STATE.validate_workflow_state(migrated)

        self.assertEqual(migrated["schema_version"], "2.0.0")
        self.assertEqual(migrated["revision"], 1)
        self.assertEqual(migrated["context"], context)
        self.assertEqual(migrated["stage"], "implement")
        self.assertEqual(migrated["status"], "paused_authority")
        self.assertEqual(migrated["created_at"], legacy["started_at"])
        self.assertEqual(migrated["updated_at"], "2026-07-24T10:16:00Z")
        self.assertEqual(migrated["resume_point"]["stage"], "implement")
        for legacy_only_field in (
            "stage_index",
            "total_stages",
            "ask",
            "retries",
            "brainstorm_file",
            "feature_branch",
        ):
            self.assertNotIn(legacy_only_field, migrated)

        self.assertEqual(
            STATE.migrate_legacy_state(
                copy.deepcopy(migrated), context=context, now="2026-07-24T12:00:00Z"
            ),
            migrated,
            "migration must be idempotent for an existing v2 state",
        )

    def test_legacy_migration_refuses_invalid_or_mismatched_identity(self):
        legacy = {
            "mode": "ship",
            "stage": "implement",
            "status": "running",
            "started_at": "2026-07-24T09:00:00Z",
            "feature_branch": "047-different-feature",
        }
        with self.assertRaises(STATE.StateError):
            STATE.migrate_legacy_state(
                legacy,
                context=copy.deepcopy(self.valid["context"]),
                now="2026-07-24T10:16:00Z",
            )

    def test_optimistic_revision_create_and_update(self):
        STATE.write_workflow_state(self.state_path, self.initial, expected_revision=0)
        updated = self.next_revision(self.initial)
        STATE.write_workflow_state(self.state_path, updated, expected_revision=1)

        self.assertEqual(STATE.read_workflow_state(self.state_path), updated)
        self.assertEqual(json.loads(self.state_path.read_text())["revision"], 2)

    def test_stale_or_skipped_revision_is_refused_without_change(self):
        STATE.write_workflow_state(self.state_path, self.initial, expected_revision=0)
        baseline = self.state_path.read_bytes()

        with self.assertRaises(STATE.StateError):
            STATE.write_workflow_state(
                self.state_path, self.next_revision(self.initial), expected_revision=0
            )
        self.assertEqual(self.state_path.read_bytes(), baseline)

        skipped = self.next_revision(self.initial)
        skipped["revision"] = 3
        with self.assertRaises(STATE.StateError):
            STATE.write_workflow_state(
                self.state_path, skipped, expected_revision=1
            )
        self.assertEqual(self.state_path.read_bytes(), baseline)

    def test_validation_failure_leaves_persisted_state_byte_identical(self):
        STATE.write_workflow_state(self.state_path, self.initial, expected_revision=0)
        baseline = self.state_path.read_bytes()
        invalid_update = self.next_revision(self.initial)
        invalid_update["completed_gates"] = ["review-plan", "review-plan"]

        with self.assertRaises(STATE.StateError):
            STATE.write_workflow_state(
                self.state_path, invalid_update, expected_revision=1
            )
        self.assertEqual(self.state_path.read_bytes(), baseline)

    def test_replace_failure_restores_prior_state_and_cleans_temporary_file(self):
        STATE.write_workflow_state(self.state_path, self.initial, expected_revision=0)
        baseline = self.state_path.read_bytes()

        with mock.patch.object(STATE.os, "replace", side_effect=OSError("injected")):
            with self.assertRaises(OSError):
                STATE.write_workflow_state(
                    self.state_path,
                    self.next_revision(self.initial),
                    expected_revision=1,
                )

        self.assertEqual(self.state_path.read_bytes(), baseline)
        self.assertEqual(list(self.state_path.parent.glob(".spex-state.*.tmp")), [])

    def test_concurrent_readers_never_observe_partial_json(self):
        STATE.write_workflow_state(self.state_path, self.initial, expected_revision=0)
        failures: list[BaseException] = []
        stop = threading.Event()

        def reader():
            while not stop.is_set():
                try:
                    STATE.validate_workflow_state(
                        json.loads(self.state_path.read_text(encoding="utf-8"))
                    )
                except BaseException as error:  # preserve assertion evidence
                    failures.append(error)
                    stop.set()

        thread = threading.Thread(target=reader)
        thread.start()
        current = copy.deepcopy(self.initial)
        try:
            for revision in range(2, 12):
                next_state = self.next_revision(current)
                next_state["revision"] = revision
                STATE.write_workflow_state(
                    self.state_path,
                    next_state,
                    expected_revision=revision - 1,
                )
                current = next_state
        finally:
            stop.set()
            thread.join(timeout=5)

        self.assertFalse(failures, failures)
        self.assertEqual(STATE.read_workflow_state(self.state_path)["revision"], 11)
        self.assertEqual(list(self.state_path.parent.glob(".spex-state.*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
