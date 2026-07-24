#!/usr/bin/env python3
"""Present one durable Spex progress event on Codex-native surfaces or transcript."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


KINDS = {"normal", "delegated", "recovery", "pause", "complete"}
NATIVE_OPERATIONS = {
    "normal": "update_task_progress",
    "delegated": "update_delegated_task",
    "recovery": "update_recovery_task",
    "pause": "pause_task_progress",
    "complete": "complete_task_progress",
}


class PresentationError(Exception):
    """Invalid or inconsistent presenter input."""


def read_object(path: Path, label: str) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as stream:
            value = json.load(stream)
    except (OSError, json.JSONDecodeError) as exc:
        raise PresentationError(f"cannot read {label} {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise PresentationError(f"{label} must contain one JSON object")
    return value


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PresentationError(message)


def validate_event(event: dict[str, Any]) -> dict[str, Any]:
    required = {
        "schema_version", "workflow_id", "sequence", "timestamp", "stage",
        "kind", "status", "message",
    }
    missing = sorted(required - set(event))
    require(not missing, f"progress event is missing required fields: {', '.join(missing)}")
    require(event["schema_version"] == "1.0.0", "unsupported progress event schema")
    require(isinstance(event["workflow_id"], str) and bool(event["workflow_id"]),
            "progress event workflow_id must be nonempty")
    require(isinstance(event["sequence"], int) and not isinstance(event["sequence"], bool)
            and event["sequence"] >= 1, "progress event sequence must be positive")
    require(isinstance(event["stage"], str) and bool(event["stage"].strip()),
            "progress event stage must be nonempty")
    require(event["kind"] in KINDS, "progress event kind is invalid")
    require(isinstance(event["status"], str) and bool(event["status"].strip()),
            "progress event status must be nonempty")
    require(isinstance(event["message"], str) and bool(event["message"].strip()),
            "progress event message must be nonempty")
    return event


def concise(value: object) -> str:
    return " ".join(str(value).split())


def event_transcript(event: dict[str, Any]) -> str:
    suffix = []
    if event.get("objective"):
        suffix.append(f"objective={concise(event['objective'])}")
    if event.get("attempt") is not None:
        suffix.append(f"attempt {event['attempt']}")
    details = f" ({', '.join(suffix)})" if suffix else ""
    return (
        f"[{event['sequence']}] {event['stage']} "
        f"{event['kind']}/{event['status']}: {concise(event['message'])}{details}"
    )


def reconcile(
    event: dict[str, Any], state: dict[str, Any] | None,
    visible_sequence: int | None, visible_stage: str | None,
) -> dict[str, Any] | None:
    if state is None:
        if visible_sequence is None and visible_stage is None:
            return None
        stale_event = visible_sequence is not None and event["sequence"] <= visible_sequence
        return {
            "stale": stale_event,
            "visible_sequence": visible_sequence,
            "visible_stage": visible_stage,
            "authoritative_sequence": event["sequence"],
            "authoritative_stage": event["stage"],
            "event_order": "stale" if stale_event else "next",
        }

    require(state.get("schema_version") == "2.0.0", "unsupported workflow state schema")
    require(state.get("workflow_id") == event["workflow_id"],
            "progress event and workflow state IDs differ")
    revision = state.get("revision")
    stage = state.get("stage")
    require(isinstance(revision, int) and not isinstance(revision, bool) and revision >= 1,
            "workflow state revision must be positive")
    require(isinstance(stage, str) and bool(stage.strip()), "workflow state stage must be nonempty")
    stale = ((visible_sequence is not None and visible_sequence != revision) or
             (visible_stage is not None and visible_stage != stage))
    return {
        "stale": stale,
        "visible_sequence": visible_sequence,
        "visible_stage": visible_stage,
        "authoritative_sequence": revision,
        "authoritative_stage": stage,
        "event_order": (
            "stale" if event["sequence"] < revision
            else "ahead" if event["sequence"] > revision
            else "current"
        ),
    }


def present(args: argparse.Namespace) -> dict[str, Any]:
    event = validate_event(read_object(args.event, "progress event"))
    state = read_object(args.state, "workflow state") if args.state else None
    reconciliation = reconcile(
        event, state, args.visible_sequence, args.visible_stage,
    )
    transcript = event_transcript(event)
    if reconciliation and reconciliation["stale"] and state is not None:
        transcript = (
            f"{transcript}; visible progress is stale; resume from durable "
            f"{reconciliation['authoritative_stage']} at revision "
            f"{reconciliation['authoritative_sequence']}"
        )

    native = None
    degradation = None
    if args.native == "available":
        native = {
            "operation": NATIVE_OPERATIONS[event["kind"]],
            "workflow_id": event["workflow_id"],
            "sequence": event["sequence"],
            "stage": event["stage"],
            "kind": event["kind"],
            "status": event["status"],
            "message": concise(event["message"]),
        }
    else:
        degradation = {
            "reason": "Codex native task progress is unavailable",
            "fallback": "ordered transcript progress",
        }
    return {
        "workflow_id": event["workflow_id"],
        "sequence": event["sequence"],
        "native": native,
        "transcript": transcript,
        "degradation": degradation,
        "reconciliation": reconciliation,
    }


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(
        description="Present one Spex ProgressEvent using Codex task progress or transcript fallback."
    )
    command.add_argument("--event", required=True, type=Path, help="one ProgressEvent JSON object")
    command.add_argument("--state", type=Path, help="durable WorkflowState used only for reconciliation")
    command.add_argument("--visible-sequence", type=int, help="last sequence visible before restart")
    command.add_argument("--visible-stage", help="last stage visible before restart")
    command.add_argument(
        "--native", required=True, choices=("available", "unavailable"),
        help="whether the caller exposes Codex native task progress",
    )
    return command


def main() -> int:
    args = parser().parse_args()
    try:
        result = present(args)
    except PresentationError as exc:
        print(json.dumps({"status": "failed_validation", "error": str(exc)}, sort_keys=True))
        return 1
    json.dump(result, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
