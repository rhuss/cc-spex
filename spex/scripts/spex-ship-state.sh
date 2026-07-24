#!/bin/sh
# Stable WorkflowState CLI. State semantics remain owned by the Python helper;
# this wrapper selects an interpreter and exposes transactional transfer.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
STATE_AUTHORITY="$SCRIPT_DIR/spex-ship-state.py"
PYTHON=""
for candidate in python3 py python; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PYTHON="$candidate"
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo "ERROR: No Python interpreter found (tried python3, py, python)" >&2
  exit 1
fi

if [ "${1:-}" = "create" ] && [ "${2:-}" = "--help" ]; then
  echo "Usage: spex-ship-state.sh create --identity-file <identity.json> [--mode <flow|ship|watch>] [--stage <stage>] [--workflow-id <id>]"
  echo "       spex-ship-state.sh create <brainstorm> [legacy options]"
  exit 0
fi

if [ "${1:-}" = "create" ] && printf '%s\n' "$*" | grep -q -- '--identity-file'; then
  shift
  exec "$PYTHON" - "$STATE_AUTHORITY" "$@" <<'PY'
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import uuid


def emit(value):
    json.dump(value, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


authority_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("spex_ship_state_authority", authority_path)
if spec is None or spec.loader is None:
    print("ERROR: cannot load WorkflowState authority", file=sys.stderr)
    raise SystemExit(1)
authority = importlib.util.module_from_spec(spec)
spec.loader.exec_module(authority)

try:
    allowed = {"--identity-file", "--mode", "--stage", "--workflow-id"}
    values = {"--mode": "ship", "--stage": "specify"}
    arguments = sys.argv[2:]
    index = 0
    while index < len(arguments):
        option = arguments[index]
        authority._require(option in allowed, "unknown create option: {}".format(option))
        authority._require(index + 1 < len(arguments), "{} requires a value".format(option))
        values[option] = arguments[index + 1]
        index += 2
    authority._require("--identity-file" in values, "--identity-file is required")
    identity_path = Path(values["--identity-file"]).resolve()
    try:
        identity = json.loads(identity_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise authority.StateError("cannot read identity file {}: {}".format(identity_path, error)) from error
    reasons = authority.validate_feature_context(
        identity, candidate_path=identity.get("state_file", ""), cwd=Path.cwd()
    )
    authority._require(not reasons, "; ".join(reasons))
    now = authority.now_iso()
    stage = values["--stage"]
    state = {
        "schema_version": authority.SCHEMA_VERSION,
        "workflow_id": values.get("--workflow-id", "workflow-{}".format(uuid.uuid4().hex)),
        "revision": 1,
        "mode": values["--mode"],
        "context": identity,
        "stage": stage,
        "status": "running",
        "completed_gates": [],
        "recovery": None,
        "resume_point": {"stage": stage, "action": "continue", "artifact": None},
        "diagnostics": [],
        "created_at": now,
        "updated_at": now,
    }
    authority.write_workflow_state(Path(identity["state_file"]), state, expected_revision=0)
    emit(state)
except authority.StateError as error:
    emit({"status": "failed_validation", "diagnostics": [{"reasons": [str(error)]}]})
    print("ERROR: {}".format(error), file=sys.stderr)
    raise SystemExit(1)
PY
fi

case "${1:-}" in
  recovery-start|recovery-record|recovery-complete)
    RECOVERY_COMMAND="$1"
    shift
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
      case "$RECOVERY_COMMAND" in
        recovery-start)
          echo "Usage: spex-ship-state.sh recovery-start --expected-revision <n> --objective <text> --origin-stage <stage> --finding <text> [--affected-artifact <path>] [--affected-gate <gate>]"
          ;;
        recovery-record)
          echo "Usage: spex-ship-state.sh recovery-record --expected-revision <n> --remedy <text> [--input-hash <path=digest>] --result <text> --evidence <text> --outcome <running|accepted|rejected|failed>"
          ;;
        recovery-complete)
          echo "Usage: spex-ship-state.sh recovery-complete --expected-revision <n> --outcome <accepted|budget_exhausted|nonconvergent|authority_required|failed> [--rewind-stage <stage>|--resume-stage <stage>] --resume-action <text> [--resume-artifact <path>] [--residual-risk <text>]"
          ;;
      esac
      exit 0
    fi
    exec "$PYTHON" - "$STATE_AUTHORITY" "$RECOVERY_COMMAND" "$@" <<'PY'
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys


def emit(value):
    json.dump(value, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


authority_path = Path(sys.argv[1])
command = sys.argv[2]
arguments = sys.argv[3:]
spec = importlib.util.spec_from_file_location("spex_ship_state_authority", authority_path)
if spec is None or spec.loader is None:
    print("ERROR: cannot load WorkflowState authority", file=sys.stderr)
    raise SystemExit(1)
authority = importlib.util.module_from_spec(spec)
spec.loader.exec_module(authority)


def parse_options(raw):
    repeatable = {"--affected-artifact", "--affected-gate", "--input-hash", "--evidence"}
    values = {name: [] for name in repeatable}
    index = 0
    while index < len(raw):
        option = raw[index]
        authority._require(option.startswith("--"), "unexpected argument: {}".format(option))
        authority._require(index + 1 < len(raw), "{} requires a value".format(option))
        value = raw[index + 1]
        if option in repeatable:
            values[option].append(value)
        else:
            authority._require(option not in values, "{} may be specified only once".format(option))
            values[option] = value
        index += 2
    return values


def required(options, name):
    value = options.get(name)
    authority._require(value not in (None, "", []), "{} is required".format(name))
    return value


try:
    options = parse_options(arguments)
    expected_revision = int(required(options, "--expected-revision"))
    state = authority.resolve_workflow_state()
    authority._require(
        state["revision"] == expected_revision,
        "state revision conflict: expected {}, found {}".format(expected_revision, state["revision"]),
    )
    destination = Path(state["context"]["state_file"])
    now = authority.now_iso()

    if command == "recovery-start":
        origin_stage = required(options, "--origin-stage")
        authority._require(state["stage"] == origin_stage, "origin stage does not match WorkflowState")
        kwargs = {}
        if "--max-attempts" in options:
            kwargs["max_attempts"] = int(options["--max-attempts"])
        if "--max-elapsed-seconds" in options:
            kwargs["max_elapsed_seconds"] = int(options["--max-elapsed-seconds"])
        updated = authority.recovery_start(
            state,
            objective=required(options, "--objective"),
            finding_fingerprint=authority.fingerprint_finding(required(options, "--finding")),
            affected_artifacts=options["--affected-artifact"],
            affected_gates=options["--affected-gate"],
            now=now,
            **kwargs
        )
    elif command == "recovery-record":
        input_hashes = {}
        for item in options["--input-hash"]:
            authority._require("=" in item, "--input-hash must be path=digest")
            path, digest = item.split("=", 1)
            authority._require(path and digest and path not in input_hashes, "invalid or duplicate input hash")
            input_hashes[path] = digest
        updated = authority.recovery_record(
            state,
            remedy_fingerprint=authority.fingerprint_remedy(required(options, "--remedy")),
            input_hashes=input_hashes,
            result_fingerprint=authority.fingerprint_result(required(options, "--result")),
            evidence=options["--evidence"],
            started_at=now,
            finished_at=now,
            outcome=required(options, "--outcome"),
        )
    else:
        outcome = required(options, "--outcome")
        updated = authority.recovery_complete(state, outcome=outcome, now=now)
        resume_stage = options.get("--rewind-stage") or options.get("--resume-stage")
        if resume_stage:
            updated["stage"] = resume_stage
            updated["resume_point"] = {
                "stage": resume_stage,
                "action": required(options, "--resume-action"),
                "artifact": options.get("--resume-artifact"),
            }
        if outcome == "accepted":
            invalidated = set(updated["recovery"]["affected_gates"])
            rewind_stage = options.get("--rewind-stage")
            stage_rank = {
                "specify": 0, "clarify": 1, "review-spec": 2, "plan": 3,
                "tasks": 4, "review-plan": 5, "implement": 6, "review-code": 7,
            }
            gate_rank = {"review-spec": 2, "review-plan": 5, "review-code": 7}
            if rewind_stage in stage_rank:
                invalidated.update(
                    gate for gate, rank in gate_rank.items()
                    if rank >= stage_rank[rewind_stage]
                )
            updated["completed_gates"] = [
                gate for gate in updated["completed_gates"] if gate not in invalidated
            ]
        if outcome == "authority_required":
            attempts = updated["recovery"]["attempts"]
            updated.setdefault("diagnostics", []).append({
                "kind": "authority_boundary",
                "episode_id": updated["recovery"]["episode_id"],
                "objective": updated["recovery"]["objective"],
                "evidence": [evidence for item in attempts for evidence in item.get("evidence", [])],
                "residual_risk": options.get("--residual-risk", ""),
                "affected_artifacts": updated["recovery"]["affected_artifacts"],
                "resume_point": updated["resume_point"],
            })
        if outcome in {"budget_exhausted", "nonconvergent", "failed"}:
            attempts = updated["recovery"]["attempts"]
            updated.setdefault("diagnostics", []).append({
                "kind": "terminal_recovery_report",
                "episode_id": updated["recovery"]["episode_id"],
                "attempted_actions": [item["remedy_fingerprint"] for item in attempts],
                "evidence": [evidence for item in attempts for evidence in item.get("evidence", [])],
                "residual_risk": options.get("--residual-risk", ""),
                "affected_artifacts": updated["recovery"]["affected_artifacts"],
                "affected_gates": updated["recovery"]["affected_gates"],
                "resume_point": updated["resume_point"],
            })
        authority.validate_workflow_state(updated)

    authority.write_workflow_state(destination, updated, expected_revision=expected_revision)
    emit(updated)
except (authority.StateError, ValueError) as error:
    emit({"status": "failed_validation", "diagnostics": [{"reasons": [str(error)]}]})
    print("ERROR: {}".format(error), file=sys.stderr)
    raise SystemExit(1)
PY
    ;;
esac

if [ "${1:-}" != "transfer" ]; then
  exec "$PYTHON" "$STATE_AUTHORITY" "$@"
fi

shift
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: spex-ship-state.sh transfer --source <state> --destination <state> --identity-file <identity.json> --transfer-id <id>"
  exit 0
fi

exec "$PYTHON" - "$STATE_AUTHORITY" "$@" <<'PY'
from __future__ import annotations

import copy
import importlib.util
import json
import os
from pathlib import Path
import sys


def emit(value):
    json.dump(value, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def refuse(message, *, diagnostics=None):
    emit({
        "status": "failed_validation",
        "diagnostics": diagnostics or [{"reasons": [message]}],
    })
    print("ERROR: {}".format(message), file=sys.stderr)
    raise SystemExit(1)


def options(arguments):
    values = {}
    index = 0
    while index < len(arguments):
        option = arguments[index]
        if option not in {"--source", "--destination", "--identity-file", "--transfer-id"}:
            refuse("unknown transfer option: {}".format(option))
        if index + 1 >= len(arguments):
            refuse("{} requires a value".format(option))
        values[option] = arguments[index + 1]
        index += 2
    missing = [name for name in ("--source", "--destination", "--identity-file", "--transfer-id") if not values.get(name)]
    if missing:
        refuse("missing transfer options: {}".format(", ".join(missing)))
    return values


authority_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("spex_ship_state_authority", authority_path)
if spec is None or spec.loader is None:
    refuse("cannot load WorkflowState authority: {}".format(authority_path))
authority = importlib.util.module_from_spec(spec)
spec.loader.exec_module(authority)

try:
    arguments = options(sys.argv[2:])
    source = Path(arguments["--source"]).resolve()
    destination = Path(arguments["--destination"]).resolve()
    identity_path = Path(arguments["--identity-file"]).resolve()
    transfer_id = arguments["--transfer-id"]
    if source == destination:
        refuse("transfer source and destination must differ")

    try:
        identity = json.loads(identity_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        refuse("cannot read transfer identity {}: {}".format(identity_path, error))
    authority.validate_worktree_context(identity)
    reasons = authority.validate_feature_context(
        identity, candidate_path=destination, cwd=Path.cwd()
    )
    if reasons:
        refuse("transfer identity is invalid", diagnostics=[{
            "identity_file": str(identity_path), "reasons": reasons
        }])

    existing = None
    if destination.is_file():
        existing = authority.read_workflow_state(destination)
        transfer_diagnostics = [
            item for item in existing.get("diagnostics", [])
            if isinstance(item, dict) and "transfer_id" in item
        ]
        if len(transfer_diagnostics) != 1:
            refuse("destination has no unambiguous transfer diagnostic")
        if transfer_diagnostics[0]["transfer_id"] != transfer_id:
            refuse("destination belongs to a different transfer")

    if source.is_file():
        source_state = authority.read_workflow_state(source)
        if source_state["context"] != identity:
            refuse("source WorkflowState identity does not match transfer identity")
    elif existing is not None:
        source_state = None
    else:
        refuse("transfer source does not exist: {}".format(source))

    phase = "prepared_main"
    if os.environ.get("SPEX_TRANSFER_FAIL_AFTER") == phase:
        refuse("injected transfer failure after {}".format(phase))

    if existing is None:
        candidate = copy.deepcopy(source_state)
        candidate["revision"] += 1
        candidate["context"] = copy.deepcopy(identity)
        candidate["diagnostics"] = [{
            "transfer_id": transfer_id,
            "phase": "candidate_written",
            "authoritative": False,
        }]
        candidate["updated_at"] = authority.now_iso()
        authority.validate_workflow_state(candidate)
        authority.write_json(str(destination), candidate)
        existing = candidate
    phase = "candidate_written"
    if os.environ.get("SPEX_TRANSFER_FAIL_AFTER") == phase:
        refuse("injected transfer failure after {}".format(phase))

    candidate = authority.read_workflow_state(destination)
    reasons = authority.validate_feature_context(
        candidate["context"], candidate_path=destination, cwd=Path.cwd()
    )
    if reasons:
        refuse("transferred candidate failed validation", diagnostics=[{
            "candidate": str(destination), "reasons": reasons
        }])
    phase = "candidate_validated"
    if os.environ.get("SPEX_TRANSFER_FAIL_AFTER") == phase:
        refuse("injected transfer failure after {}".format(phase))

    diagnostic = next(
        item for item in candidate["diagnostics"] if item.get("transfer_id") == transfer_id
    )
    if not diagnostic.get("authoritative"):
        candidate["revision"] += 1
        diagnostic["phase"] = "committed_worktree"
        diagnostic["authoritative"] = True
        candidate["updated_at"] = authority.now_iso()
        authority.validate_workflow_state(candidate)
        authority.write_json(str(destination), candidate)
    phase = "committed_worktree"
    if os.environ.get("SPEX_TRANSFER_FAIL_AFTER") == phase:
        refuse("injected transfer failure after {}".format(phase))

    if source.exists():
        source.unlink()
    phase = "main_removed"
    if os.environ.get("SPEX_TRANSFER_FAIL_AFTER") == phase:
        refuse("injected transfer failure after {}".format(phase))

    emit({
        "transfer_id": transfer_id,
        "phase": phase,
        "source": str(source),
        "destination": str(destination),
        "state": authority.read_workflow_state(destination),
    })
except authority.StateError as error:
    refuse(str(error))
PY
