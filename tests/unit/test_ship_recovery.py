#!/usr/bin/env python3
"""Test-first contract for durable, bounded WorkflowState recovery episodes."""

from __future__ import annotations

import copy
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
STATE_TOOL = REPO_ROOT / "spex/scripts/spex-ship-state.py"
VALID_FIXTURE = REPO_ROOT / "tests/fixtures/contracts/workflow-state/valid.json"
REQUIRED_API = (
    "recovery_start",
    "recovery_record",
    "recovery_complete",
)


def load_state_module():
    spec = importlib.util.spec_from_file_location("spex_ship_recovery", STATE_TOOL)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import WorkflowState authority: {STATE_TOOL}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


STATE = load_state_module()
MISSING_API = tuple(name for name in REQUIRED_API if not hasattr(STATE, name))


class RecoveryApiContractTests(unittest.TestCase):
    def test_recovery_transition_api_is_available(self):
        self.assertFalse(
            MISSING_API,
            "T042 must implement the RecoveryEpisode API; missing: "
            + ", ".join(MISSING_API),
        )


@unittest.skipIf(MISSING_API, "T042 RecoveryEpisode API is not implemented")
class RecoveryEpisodeTests(unittest.TestCase):
    START = "2026-07-24T10:15:30Z"

    def setUp(self):
        fixture = json.loads(VALID_FIXTURE.read_text(encoding="utf-8"))
        self.base = copy.deepcopy(fixture)
        self.base.update(
            revision=1,
            stage="implement",
            status="running",
            recovery=None,
            resume_point={
                "stage": "implement",
                "action": "continue implementation",
                "artifact": "tasks.md",
            },
            updated_at=self.START,
        )
        self.temporary = tempfile.TemporaryDirectory(prefix="spex-recovery-")
        self.addCleanup(self.temporary.cleanup)
        self.state_path = Path(self.temporary.name) / ".specify/.spex-state"

    def start(self, state=None, **overrides):
        arguments = {
            "objective": "Resolve a materialization feasibility finding",
            "finding_fingerprint": "sha256:finding-001",
            "affected_artifacts": ["plan.md", "tasks.md"],
            "affected_gates": ["review-plan"],
            "now": self.START,
        }
        arguments.update(overrides)
        return STATE.recovery_start(copy.deepcopy(state or self.base), **arguments)

    def attempt(self, state, number=1, **overrides):
        arguments = {
            "remedy_fingerprint": f"sha256:remedy-{number:03d}",
            "input_hashes": {"plan.md": f"sha256:plan-{number:03d}"},
            "result_fingerprint": f"sha256:result-{number:03d}",
            "evidence": [f"focused test evidence for attempt {number}"],
            "started_at": f"2026-07-24T10:{15 + number:02d}:00Z",
            "finished_at": f"2026-07-24T10:{15 + number:02d}:30Z",
            "outcome": "rejected",
        }
        arguments.update(overrides)
        return STATE.recovery_record(copy.deepcopy(state), **arguments)

    def assert_utc(self, value):
        self.assertTrue(value.endswith("Z"), value)
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
        self.assertEqual(parsed.utcoffset(), timezone.utc.utcoffset(parsed))

    def test_start_uses_finite_three_attempt_1800_second_defaults(self):
        recovering = self.start()

        self.assertEqual(recovering["revision"], 2)
        self.assertEqual(recovering["status"], "recovering")
        self.assertEqual(recovering["recovery"]["max_attempts"], 3)
        self.assertEqual(recovering["recovery"]["max_elapsed_seconds"], 1800)
        self.assertEqual(recovering["recovery"]["attempts"], [])
        self.assertEqual(recovering["recovery"]["origin_stage"], "implement")
        self.assertEqual(recovering["recovery"]["outcome"], "running")
        self.assert_utc(recovering["recovery"]["started_at"])
        self.assert_utc(recovering["recovery"]["deadline"])
        started = datetime.fromisoformat(recovering["recovery"]["started_at"].replace("Z", "+00:00"))
        deadline = datetime.fromisoformat(recovering["recovery"]["deadline"].replace("Z", "+00:00"))
        self.assertEqual((deadline - started).total_seconds(), 1800)
        STATE.validate_workflow_state(recovering)

    def test_non_utc_input_is_normalized_to_utc(self):
        recovering = self.start(now="2026-07-24T12:15:30+02:00")
        self.assertEqual(recovering["recovery"]["started_at"], self.START)
        self.assertEqual(recovering["recovery"]["deadline"], "2026-07-24T10:45:30Z")

    def test_nonfinite_or_nonpositive_budgets_are_refused(self):
        for field, value in (
            ("max_attempts", 0),
            ("max_attempts", None),
            ("max_elapsed_seconds", 0),
            ("max_elapsed_seconds", float("inf")),
        ):
            with self.subTest(field=field, value=value):
                with self.assertRaises(STATE.StateError):
                    self.start(**{field: value})

    def test_attempt_persists_fingerprints_hashes_evidence_and_timestamps(self):
        attempted = self.attempt(self.start())
        attempt = attempted["recovery"]["attempts"][0]

        self.assertEqual(attempt["number"], 1)
        self.assertEqual(attempt["remedy_fingerprint"], "sha256:remedy-001")
        self.assertEqual(attempt["input_hashes"], {"plan.md": "sha256:plan-001"})
        self.assertEqual(attempt["result_fingerprint"], "sha256:result-001")
        self.assertEqual(attempt["evidence"], ["focused test evidence for attempt 1"])
        self.assertEqual(attempt["outcome"], "rejected")
        self.assert_utc(attempt["started_at"])
        self.assert_utc(attempt["finished_at"])
        self.assertEqual(attempted["revision"], 3)
        STATE.validate_workflow_state(attempted)

    def test_missing_attempt_evidence_is_refused_without_mutating_input(self):
        recovering = self.start()
        baseline = copy.deepcopy(recovering)
        with self.assertRaises(STATE.StateError):
            self.attempt(recovering, evidence=[])
        self.assertEqual(recovering, baseline)

    def test_restart_preserves_deadline_budget_and_attempt_evidence(self):
        STATE.write_workflow_state(self.state_path, self.base, expected_revision=0)
        recovering = self.start()
        STATE.write_workflow_state(self.state_path, recovering, expected_revision=1)

        restarted = STATE.read_workflow_state(self.state_path)
        attempted = self.attempt(restarted)
        STATE.write_workflow_state(self.state_path, attempted, expected_revision=2)
        reloaded = STATE.read_workflow_state(self.state_path)

        self.assertEqual(reloaded["recovery"]["deadline"], "2026-07-24T10:45:30Z")
        self.assertEqual(reloaded["recovery"]["max_attempts"], 3)
        self.assertEqual(reloaded["recovery"]["attempts"][0]["evidence"],
                         ["focused test evidence for attempt 1"])

    def test_stale_recovery_cas_is_refused_byte_identically(self):
        STATE.write_workflow_state(self.state_path, self.base, expected_revision=0)
        recovering = self.start()
        STATE.write_workflow_state(self.state_path, recovering, expected_revision=1)
        baseline = self.state_path.read_bytes()

        attempted = self.attempt(recovering)
        with self.assertRaises(STATE.StateError):
            STATE.write_workflow_state(self.state_path, attempted, expected_revision=1)
        self.assertEqual(self.state_path.read_bytes(), baseline)

    def test_elapsed_deadline_transitions_to_failed_budget_without_new_attempt(self):
        recovering = self.start(max_elapsed_seconds=60)
        expired = self.attempt(
            recovering,
            started_at="2026-07-24T10:16:31Z",
            finished_at="2026-07-24T10:16:40Z",
        )

        self.assertEqual(expired["status"], "failed_budget")
        self.assertEqual(expired["recovery"]["outcome"], "budget_exhausted")
        self.assertEqual(expired["recovery"]["attempts"], [])
        self.assertEqual(expired["revision"], 3)

    def test_attempt_limit_transitions_to_failed_budget(self):
        state = self.start()
        for number in range(1, 4):
            state = self.attempt(state, number=number)

        terminal = STATE.recovery_complete(
            copy.deepcopy(state), outcome="budget_exhausted", now="2026-07-24T10:20:00Z"
        )
        self.assertEqual(terminal["status"], "failed_budget")
        self.assertEqual(terminal["recovery"]["outcome"], "budget_exhausted")
        self.assertEqual(len(terminal["recovery"]["attempts"]), 3)
        with self.assertRaises(STATE.StateError):
            self.attempt(terminal, number=4)

    def test_accepted_and_nonconvergent_terminal_transitions(self):
        attempted = self.attempt(self.start(), outcome="accepted")
        accepted = STATE.recovery_complete(
            copy.deepcopy(attempted), outcome="accepted", now="2026-07-24T10:17:00Z"
        )
        self.assertEqual(accepted["status"], "running")
        self.assertEqual(accepted["recovery"]["outcome"], "accepted")
        self.assertEqual(accepted["resume_point"]["stage"], "implement")
        self.assertIn("resume", accepted["resume_point"]["action"].lower())

        nonconvergent = STATE.recovery_complete(
            self.attempt(self.start()),
            outcome="nonconvergent",
            now="2026-07-24T10:17:00Z",
        )
        self.assertEqual(nonconvergent["status"], "failed_nonconvergent")
        self.assertEqual(nonconvergent["recovery"]["outcome"], "nonconvergent")
        self.assertIsNotNone(nonconvergent["resume_point"])


if __name__ == "__main__":
    unittest.main()
