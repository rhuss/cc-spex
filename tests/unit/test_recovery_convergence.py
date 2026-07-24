#!/usr/bin/env python3
"""Test-first contract for deterministic recovery convergence detection."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
STATE_TOOL = REPO_ROOT / "spex/scripts/spex-ship-state.py"
REQUIRED_API = (
    "fingerprint_finding",
    "fingerprint_remedy",
    "fingerprint_artifact_inputs",
    "fingerprint_result",
    "recovery_refusal_reason",
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


def attempt(number: int, remedy: str, inputs: dict[str, str], result: str) -> dict:
    return {
        "number": number,
        "remedy_fingerprint": remedy,
        "input_hashes": inputs,
        "result_fingerprint": result,
        "started_at": f"2026-07-24T10:0{number}:00Z",
        "finished_at": f"2026-07-24T10:0{number}:30Z",
        "outcome": "rejected",
    }


def episode(*attempts: dict) -> dict:
    return {
        "finding_fingerprint": STATE.fingerprint_finding(
            "The implementation cannot satisfy the offline requirement"
        ),
        "attempts": list(attempts),
    }


class RecoveryConvergenceApiContractTests(unittest.TestCase):
    def test_convergence_api_is_available(self):
        self.assertFalse(
            MISSING_API,
            "T043 must implement the recovery convergence API; missing: "
            + ", ".join(MISSING_API),
        )


@unittest.skipIf(MISSING_API, "T043 recovery convergence API is not implemented")
class RecoveryConvergenceTests(unittest.TestCase):
    def test_finding_and_remedy_fingerprints_normalize_equivalent_text(self):
        finding_a = "  API\u00a0access is IMPOSSIBLE\n while offline. "
        finding_b = "api access is impossible while offline."
        remedy_a = "Cache the response, then\tuse the cached value."
        remedy_b = "  cache the response, THEN use the cached value.  "

        self.assertEqual(
            STATE.fingerprint_finding(finding_a),
            STATE.fingerprint_finding(finding_b),
        )
        self.assertEqual(
            STATE.fingerprint_remedy(remedy_a),
            STATE.fingerprint_remedy(remedy_b),
        )
        self.assertNotEqual(
            STATE.fingerprint_remedy(remedy_a),
            STATE.fingerprint_remedy("Remove offline support."),
        )

    def test_artifact_and_result_fingerprints_are_canonical(self):
        inputs_a = {"spec.md": "sha256:aaa", "plan.md": "sha256:bbb"}
        inputs_b = {"plan.md": "sha256:bbb", "spec.md": "sha256:aaa"}
        result_a = {"status": "FAILED", "evidence": ["one", "two"]}
        result_b = {"evidence": ["one", "two"], "status": "FAILED"}

        self.assertEqual(
            STATE.fingerprint_artifact_inputs(inputs_a),
            STATE.fingerprint_artifact_inputs(inputs_b),
        )
        self.assertEqual(
            STATE.fingerprint_result(result_a), STATE.fingerprint_result(result_b)
        )
        self.assertNotEqual(
            STATE.fingerprint_artifact_inputs(inputs_a),
            STATE.fingerprint_artifact_inputs(
                {"spec.md": "sha256:changed", "plan.md": "sha256:bbb"}
            ),
        )

    def test_repeated_finding_and_equivalent_remedy_are_refused(self):
        remedy = STATE.fingerprint_remedy("Introduce a local response cache")
        inputs = {"spec.md": "sha256:aaa"}
        result = STATE.fingerprint_result("cache does not cover first use")
        current = episode(attempt(1, remedy, inputs, result))

        self.assertEqual(
            STATE.recovery_refusal_reason(
                current, finding_fingerprint=current["finding_fingerprint"]
            ),
            "repeated_finding",
        )
        self.assertEqual(
            STATE.recovery_refusal_reason(
                current,
                remedy_fingerprint=STATE.fingerprint_remedy(
                    "  INTRODUCE a local response cache "
                ),
            ),
            "equivalent_remedy",
        )

    def test_a_b_a_oscillation_is_refused_before_attempt_is_appended(self):
        inputs = {"spec.md": "sha256:aaa"}
        result_a = STATE.fingerprint_result({"strategy": "local", "viable": False})
        result_b = STATE.fingerprint_result({"strategy": "remote", "viable": False})
        current = episode(
            attempt(1, STATE.fingerprint_remedy("Use local data"), inputs, result_a),
            attempt(2, STATE.fingerprint_remedy("Use remote data"), inputs, result_b),
        )

        before = json.dumps(current, sort_keys=True)
        reason = STATE.recovery_refusal_reason(
            current, result_fingerprint=result_a
        )

        self.assertEqual(reason, "oscillation")
        self.assertEqual(json.dumps(current, sort_keys=True), before)
        self.assertEqual(len(current["attempts"]), 2)

    def test_changed_artifact_inputs_do_not_false_match(self):
        first = {"spec.md": "sha256:aaa", "plan.md": "sha256:bbb"}
        changed = {"spec.md": "sha256:ccc", "plan.md": "sha256:bbb"}
        current = episode(
            attempt(
                1,
                STATE.fingerprint_remedy("Reconcile the plan"),
                first,
                STATE.fingerprint_result("still inconsistent"),
            )
        )

        self.assertIsNone(
            STATE.recovery_refusal_reason(
                current,
                artifact_input_fingerprint=STATE.fingerprint_artifact_inputs(
                    changed
                ),
            )
        )

    def test_restart_replay_produces_the_same_fingerprints_and_refusal(self):
        remedy = STATE.fingerprint_remedy("Use local data")
        inputs = {"spec.md": "sha256:aaa"}
        result_a = STATE.fingerprint_result({"strategy": "local"})
        result_b = STATE.fingerprint_result({"strategy": "remote"})
        persisted = json.loads(
            json.dumps(
                episode(
                    attempt(1, remedy, inputs, result_a),
                    attempt(2, STATE.fingerprint_remedy("Use remote data"), inputs, result_b),
                )
            )
        )
        restarted = load_state_module()

        self.assertEqual(restarted.fingerprint_remedy(" USE local data "), remedy)
        self.assertEqual(
            restarted.recovery_refusal_reason(
                persisted, result_fingerprint=restarted.fingerprint_result({"strategy": "local"})
            ),
            "oscillation",
        )


if __name__ == "__main__":
    unittest.main()
