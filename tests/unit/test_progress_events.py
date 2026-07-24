#!/usr/bin/env python3
"""Test-first contract for ordered semantic ProgressEvent emission."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
STATE_TOOL = REPO_ROOT / "spex/scripts/spex-ship-state.py"
STATE_FIXTURE = REPO_ROOT / "tests/fixtures/contracts/workflow-state/valid.json"
VALID_EVENT = REPO_ROOT / "tests/fixtures/contracts/progress-event/valid.json"
INVALID_EVENT = REPO_ROOT / "tests/fixtures/contracts/progress-event/invalid.json"
REQUIRED_API = (
    "validate_progress_event",
    "emit_progress_event",
    "read_progress_events",
    "progress_transcript",
)


def load_state_module():
    spec = importlib.util.spec_from_file_location("spex_progress_state", STATE_TOOL)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import WorkflowState authority: {STATE_TOOL}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


STATE = load_state_module()
MISSING_API = tuple(name for name in REQUIRED_API if not hasattr(STATE, name))


class ProgressApiContractTests(unittest.TestCase):
    def test_progress_event_api_is_available(self):
        self.assertFalse(
            MISSING_API,
            "T050 must implement the ProgressEvent API; missing: "
            + ", ".join(MISSING_API),
        )


@unittest.skipIf(MISSING_API, "T050 ProgressEvent API is not implemented")
class ProgressEventTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="spex-progress-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.state_path = root / ".specify/.spex-state"
        self.events_path = root / ".specify/.spex-progress.jsonl"
        fixture = json.loads(STATE_FIXTURE.read_text(encoding="utf-8"))
        self.workflow = copy.deepcopy(fixture)
        self.workflow.update(
            revision=1,
            stage="implement",
            status="running",
            recovery=None,
            resume_point={
                "stage": "implement",
                "action": "continue implementation",
                "artifact": "tasks.md",
            },
        )
        STATE.write_workflow_state(self.state_path, self.workflow, expected_revision=0)

    def emit(self, **overrides):
        arguments = {
            "kind": "normal",
            "status": "updated",
            "message": "Implementation is progressing",
            "timestamp": "2026-07-24T10:16:00Z",
        }
        arguments.update(overrides)
        return STATE.emit_progress_event(self.state_path, self.events_path, **arguments)

    def test_schema_accepts_fixture_and_rejects_invalid_or_extra_fields(self):
        valid = json.loads(VALID_EVENT.read_text(encoding="utf-8"))
        invalid = json.loads(INVALID_EVENT.read_text(encoding="utf-8"))
        self.assertEqual(STATE.validate_progress_event(copy.deepcopy(valid)), valid)
        with self.assertRaises(STATE.StateError):
            STATE.validate_progress_event(invalid)
        extra = copy.deepcopy(valid)
        extra["presentation_hint"] = "spinner"
        with self.assertRaises(STATE.StateError):
            STATE.validate_progress_event(extra)

    def test_first_event_derives_authority_and_sequence_from_persisted_state(self):
        baseline = self.state_path.read_bytes()
        event = self.emit(status="started", message="Implementation started")

        self.assertEqual(event["schema_version"], "1.0.0")
        self.assertEqual(event["workflow_id"], self.workflow["workflow_id"])
        self.assertEqual(event["stage"], "implement")
        self.assertEqual(event["sequence"], 1)
        self.assertEqual(self.state_path.read_bytes(), baseline)
        self.assertEqual(STATE.read_progress_events(self.events_path), [event])

    def test_ordered_transition_kinds_statuses_recovery_pause_and_completion(self):
        transitions = (
            {"kind": "normal", "status": "started", "message": "Stage started"},
            {"kind": "delegated", "status": "updated", "message": "Reviewer is running"},
            {
                "kind": "recovery",
                "status": "updated",
                "message": "Running recovery attempt 1 of 3",
                "objective": "Resolve a feasibility finding",
                "attempt": 1,
            },
            {"kind": "pause", "status": "paused", "message": "Product authority required"},
            {"kind": "complete", "status": "succeeded", "message": "Workflow completed"},
        )
        emitted = [
            self.emit(timestamp=f"2026-07-24T10:16:0{index}Z", **transition)
            for index, transition in enumerate(transitions, start=1)
        ]

        self.assertEqual([event["sequence"] for event in emitted], [1, 2, 3, 4, 5])
        self.assertEqual([event["kind"] for event in emitted],
                         ["normal", "delegated", "recovery", "pause", "complete"])
        self.assertEqual(emitted[2]["attempt"], 1)
        self.assertEqual(emitted[2]["objective"], "Resolve a feasibility finding")
        self.assertEqual(STATE.read_progress_events(self.events_path), emitted)

    def test_pause_and_complete_require_semantically_terminal_statuses(self):
        with self.assertRaises(STATE.StateError):
            self.emit(kind="pause", status="started", message="Invalid pause")
        with self.assertRaises(STATE.StateError):
            self.emit(kind="complete", status="updated", message="Invalid completion")
        self.assertFalse(self.events_path.exists())

    def test_sequence_remains_monotonic_after_module_restart(self):
        first = self.emit(status="started", message="Stage started")
        restarted = load_state_module()
        second = restarted.emit_progress_event(
            self.state_path,
            self.events_path,
            kind="delegated",
            status="updated",
            message="Delegated review returned",
            timestamp="2026-07-24T10:17:00Z",
        )
        self.assertEqual((first["sequence"], second["sequence"]), (1, 2))

    def test_concurrent_emission_allocates_unique_ordered_sequences(self):
        results = []
        failures = []
        lock = threading.Lock()

        def worker(number):
            try:
                event = self.emit(
                    kind="delegated",
                    message=f"Delegated update {number}",
                    timestamp="2026-07-24T10:18:00Z",
                )
                with lock:
                    results.append(event)
            except BaseException as error:
                with lock:
                    failures.append(error)

        threads = [threading.Thread(target=worker, args=(number,)) for number in range(20)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=5)

        self.assertFalse(failures, failures)
        persisted = STATE.read_progress_events(self.events_path)
        self.assertEqual([event["sequence"] for event in persisted], list(range(1, 21)))
        self.assertEqual(sorted(event["sequence"] for event in results), list(range(1, 21)))

    def test_missing_or_invalid_workflow_state_refuses_without_event_append(self):
        missing_state = self.state_path.parent / "missing-state"
        with self.assertRaises(STATE.StateError):
            STATE.emit_progress_event(
                missing_state,
                self.events_path,
                kind="normal",
                status="updated",
                message="Must not emit",
                timestamp="2026-07-24T10:16:00Z",
            )
        self.assertFalse(self.events_path.exists())

        self.state_path.write_text('{"status":"stale"}\n', encoding="utf-8")
        with self.assertRaises(STATE.StateError):
            self.emit(message="Must still not emit")
        self.assertFalse(self.events_path.exists())

    def test_corrupt_or_wrong_workflow_event_log_fails_closed(self):
        self.events_path.parent.mkdir(parents=True, exist_ok=True)
        self.events_path.write_text("not-json\n", encoding="utf-8")
        baseline = self.events_path.read_bytes()
        with self.assertRaises(STATE.StateError):
            self.emit()
        self.assertEqual(self.events_path.read_bytes(), baseline)

        existing = json.loads(VALID_EVENT.read_text(encoding="utf-8"))
        existing["sequence"] = 1
        existing["workflow_id"] = "different-workflow"
        self.events_path.write_text(json.dumps(existing) + "\n", encoding="utf-8")
        baseline = self.events_path.read_bytes()
        with self.assertRaises(STATE.StateError):
            self.emit()
        self.assertEqual(self.events_path.read_bytes(), baseline)

    def test_transcript_fallback_is_concise_ordered_and_semantically_complete(self):
        events = [
            self.emit(status="started", message="Implementation started"),
            self.emit(
                kind="recovery",
                status="updated",
                message="Running recovery attempt 1 of 3",
                objective="Resolve feasibility",
                attempt=1,
                timestamp="2026-07-24T10:17:00Z",
            ),
        ]
        transcript = [STATE.progress_transcript(event) for event in events]

        self.assertIn("1", transcript[0])
        self.assertIn("implement", transcript[0])
        self.assertIn("started", transcript[0])
        self.assertIn("Implementation started", transcript[0])
        self.assertIn("2", transcript[1])
        self.assertIn("recovery", transcript[1])
        self.assertIn("attempt 1", transcript[1].lower())
        self.assertTrue(all("\n" not in line for line in transcript))


if __name__ == "__main__":
    unittest.main()
