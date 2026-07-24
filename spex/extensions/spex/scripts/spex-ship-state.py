#!/usr/bin/env python3
import json
import os
import fcntl
import hashlib
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from copy import deepcopy
from datetime import datetime, timezone

STATE_FILE = os.environ.get("SHIP_STATE_FILE", ".specify/.spex-state")
STAGES = ["specify", "clarify", "review-spec", "plan", "tasks", "review-plan", "implement", "review-code"]
SCHEMA_VERSION = "2.0.0"
STATE_FIELDS = {
    "schema_version", "workflow_id", "revision", "mode", "context", "stage",
    "status", "completed_gates", "recovery", "resume_point", "diagnostics",
    "created_at", "updated_at",
}
REQUIRED_STATE_FIELDS = STATE_FIELDS - {"recovery", "diagnostics"}
CONTEXT_FIELDS = {
    "repository_root", "git_common_dir", "active_worktree", "feature_branch",
    "spec_dir", "state_file", "head_oid", "validated_at",
}
REQUIRED_CONTEXT_FIELDS = CONTEXT_FIELDS - {"head_oid"}
STATUSES = {
    "running", "recovering", "paused_authority", "failed_budget",
    "failed_nonconvergent", "failed_validation", "completed",
}
BRANCH_PATTERN = re.compile(r"^[0-9]{3}-[a-z0-9-]+$")
OID_PATTERN = re.compile(r"^[0-9a-f]{40,64}$")


class StateError(Exception):
    """An expected WorkflowState validation or persistence refusal."""


def _require(condition, message):
    if not condition:
        raise StateError(message)


def _timestamp(value, field):
    _require(isinstance(value, str), "{} must be an RFC 3339 timestamp".format(field))
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise StateError("{} must be an RFC 3339 timestamp".format(field)) from error
    _require(parsed.tzinfo is not None, "{} must include a UTC offset".format(field))


def validate_worktree_context(context):
    _require(isinstance(context, dict), "context must be an object")
    fields = set(context)
    _require(not (REQUIRED_CONTEXT_FIELDS - fields), "context is missing required fields: {}".format(
        ", ".join(sorted(REQUIRED_CONTEXT_FIELDS - fields))))
    _require(not (fields - CONTEXT_FIELDS), "context contains unknown fields: {}".format(
        ", ".join(sorted(fields - CONTEXT_FIELDS))))
    for field in ("repository_root", "git_common_dir", "active_worktree", "spec_dir", "state_file"):
        _require(isinstance(context[field], str) and Path(context[field]).is_absolute(),
                 "context.{} must be an absolute path".format(field))
    _require(isinstance(context["feature_branch"], str) and BRANCH_PATTERN.fullmatch(context["feature_branch"]),
             "context.feature_branch is invalid")
    if "head_oid" in context:
        _require(isinstance(context["head_oid"], str) and OID_PATTERN.fullmatch(context["head_oid"]),
                 "context.head_oid is invalid")
    _timestamp(context["validated_at"], "context.validated_at")
    return context


def _validate_resume(value):
    _require(isinstance(value, dict), "resume_point must be an object")
    allowed = {"stage", "action", "artifact"}
    _require({"stage", "action"} <= set(value), "resume_point requires stage and action")
    _require(not (set(value) - allowed), "resume_point contains unknown fields")
    _require(isinstance(value["stage"], str), "resume_point.stage must be a string")
    _require(isinstance(value["action"], str), "resume_point.action must be a string")
    _require("artifact" not in value or value["artifact"] is None or isinstance(value["artifact"], str),
             "resume_point.artifact must be a string or null")


def _validate_recovery(value):
    if value is None:
        return
    _require(isinstance(value, dict), "recovery must be an object or null")
    required = {
        "episode_id", "objective", "origin_stage", "finding_fingerprint",
        "max_attempts", "max_elapsed_seconds", "started_at", "deadline",
        "attempts", "affected_artifacts", "affected_gates", "outcome",
    }
    _require(required <= set(value), "recovery is missing required fields")
    _require(not (set(value) - required), "recovery contains unknown fields")
    _require(isinstance(value["objective"], str) and value["objective"], "recovery.objective is required")
    for field in ("max_attempts", "max_elapsed_seconds"):
        _require(isinstance(value[field], int) and not isinstance(value[field], bool) and value[field] >= 1,
                 "recovery.{} must be a positive integer".format(field))
    _timestamp(value["started_at"], "recovery.started_at")
    _timestamp(value["deadline"], "recovery.deadline")
    _require(isinstance(value["attempts"], list), "recovery.attempts must be an array")
    _require(isinstance(value["affected_artifacts"], list), "recovery.affected_artifacts must be an array")
    _require(isinstance(value["affected_gates"], list), "recovery.affected_gates must be an array")
    _require(value["outcome"] in {"running", "accepted", "budget_exhausted", "nonconvergent", "authority_required", "failed"},
             "recovery.outcome is invalid")
    attempt_fields = {"number", "remedy_fingerprint", "input_hashes", "result_fingerprint", "evidence", "started_at", "finished_at", "outcome"}
    for attempt in value["attempts"]:
        _require(isinstance(attempt, dict), "recovery attempt must be an object")
        _require({"number", "remedy_fingerprint", "started_at", "outcome"} <= set(attempt),
                 "recovery attempt is missing required fields")
        _require(not (set(attempt) - attempt_fields), "recovery attempt contains unknown fields")
        _require(isinstance(attempt["number"], int) and not isinstance(attempt["number"], bool) and attempt["number"] >= 1,
                 "recovery attempt number is invalid")
        _timestamp(attempt["started_at"], "recovery.attempt.started_at")
        if attempt.get("finished_at") is not None:
            _timestamp(attempt["finished_at"], "recovery.attempt.finished_at")
        _require(attempt["outcome"] in {"running", "accepted", "rejected", "failed"},
                 "recovery attempt outcome is invalid")


def validate_workflow_state(state):
    _require(isinstance(state, dict), "workflow state must be an object")
    fields = set(state)
    missing = REQUIRED_STATE_FIELDS - fields
    extra = fields - STATE_FIELDS
    _require(not missing, "workflow state is missing required fields: {}".format(", ".join(sorted(missing))))
    _require(not extra, "workflow state contains unknown fields: {}".format(", ".join(sorted(extra))))
    _require(state["schema_version"] == SCHEMA_VERSION, "schema_version must be {}".format(SCHEMA_VERSION))
    _require(isinstance(state["workflow_id"], str) and len(state["workflow_id"]) >= 8,
             "workflow_id must contain at least eight characters")
    revision = state["revision"]
    _require(isinstance(revision, int) and not isinstance(revision, bool) and revision >= 1,
             "revision must be a positive integer")
    _require(state["mode"] in {"flow", "ship", "watch"}, "mode is invalid")
    validate_worktree_context(state["context"])
    _require(isinstance(state["stage"], str) and state["stage"], "stage must be nonempty")
    _require(state["status"] in STATUSES, "status is invalid")
    gates = state["completed_gates"]
    _require(isinstance(gates, list) and all(isinstance(item, str) for item in gates),
             "completed_gates must be an array of strings")
    _require(len(gates) == len(set(gates)), "completed_gates must be unique")
    _validate_recovery(state.get("recovery"))
    _validate_resume(state["resume_point"])
    if "diagnostics" in state:
        _require(isinstance(state["diagnostics"], list) and all(isinstance(item, dict) for item in state["diagnostics"]),
                 "diagnostics must be an array of objects")
    _timestamp(state["created_at"], "created_at")
    _timestamp(state["updated_at"], "updated_at")
    return state


def migrate_legacy_state(state, *, context, now=None):
    if isinstance(state, dict) and state.get("schema_version") == SCHEMA_VERSION:
        return validate_workflow_state(state)
    _require(isinstance(state, dict), "legacy workflow state must be an object")
    validate_worktree_context(context)
    legacy_branch = state.get("feature_branch")
    _require(not legacy_branch or legacy_branch == context["feature_branch"],
             "legacy feature branch does not match worktree context")
    stage = state.get("stage")
    _require(isinstance(stage, str) and stage, "legacy stage is required")
    created = state.get("started_at") or now or now_iso()
    updated = now or now_iso()
    status = {"paused": "paused_authority", "failed": "failed_validation", "done": "completed"}.get(
        state.get("status"), state.get("status", "running"))
    if status not in STATUSES:
        status = "failed_validation"
    legacy_identity = "{}\0{}".format(context["feature_branch"], created).encode("utf-8")
    migrated = {
        "schema_version": SCHEMA_VERSION,
        "workflow_id": "legacy-{}".format(hashlib.sha256(legacy_identity).hexdigest()[:16]),
        "revision": 1,
        "mode": state.get("mode", "ship") if state.get("mode", "ship") in {"flow", "ship", "watch"} else "ship",
        "context": deepcopy(context),
        "stage": stage,
        "status": status,
        "completed_gates": [],
        "recovery": None,
        "resume_point": {"stage": stage, "action": "resume migrated workflow", "artifact": state.get("brainstorm_file")},
        "diagnostics": [{"kind": "legacy_migration", "source_schema": state.get("schema_version", "legacy")}],
        "created_at": created,
        "updated_at": updated,
    }
    return validate_workflow_state(migrated)


def read_workflow_state(path):
    destination = Path(path)
    try:
        with destination.open(encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise StateError("cannot read workflow state {}: {}".format(destination, error)) from error
    return validate_workflow_state(state)


def write_workflow_state(path, state, *, expected_revision):
    destination = Path(path)
    validate_workflow_state(state)
    directory = destination.parent
    directory.mkdir(parents=True, exist_ok=True)
    directory_fd = os.open(directory, os.O_RDONLY)
    temporary = None
    try:
        fcntl.flock(directory_fd, fcntl.LOCK_EX)
        if destination.is_file():
            current_revision = read_workflow_state(destination)["revision"]
        else:
            current_revision = 0
        _require(current_revision == expected_revision,
                 "state revision conflict: expected {}, found {}".format(expected_revision, current_revision))
        _require(state["revision"] == current_revision + 1,
                 "workflow state revision must be exactly one greater than persisted revision")
        descriptor, raw_path = tempfile.mkstemp(dir=directory, prefix=".spex-state.", suffix=".tmp")
        temporary = Path(raw_path)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                json.dump(state, handle, indent=2, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
            temporary = None
            os.fsync(directory_fd)
        except Exception:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
            raise
    finally:
        fcntl.flock(directory_fd, fcntl.LOCK_UN)
        os.close(directory_fd)


def _git_result(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


def _git_value(cwd, *args):
    result = _git_result(cwd, *args)
    if result.returncode != 0:
        raise StateError("git {} failed: {}".format(" ".join(args), result.stderr.strip()))
    return result.stdout.strip()


def _registered_worktrees(cwd):
    output = _git_value(cwd, "worktree", "list", "--porcelain")
    worktrees = {}
    current = None
    for line in output.splitlines():
        if line.startswith("worktree "):
            current = str(Path(line[9:]).resolve())
            worktrees[current] = {"branch": None, "head": None}
        elif current and line.startswith("branch refs/heads/"):
            worktrees[current]["branch"] = line[len("branch refs/heads/"):]
        elif current and line.startswith("HEAD "):
            worktrees[current]["head"] = line[5:]
    return worktrees


def _repository_identity(cwd):
    top = Path(_git_value(cwd, "rev-parse", "--show-toplevel")).resolve()
    common_raw = Path(_git_value(cwd, "rev-parse", "--git-common-dir"))
    common = common_raw.resolve() if common_raw.is_absolute() else (top / common_raw).resolve()
    repository = common.parent if common.name == ".git" else top
    return repository, common, _registered_worktrees(cwd)


def validate_feature_context(context, *, candidate_path, cwd=None):
    validate_worktree_context(context)
    cwd = Path(cwd or os.getcwd()).resolve()
    candidate = Path(candidate_path).resolve()
    reasons = []
    try:
        repository, common, worktrees = _repository_identity(cwd)
    except StateError as error:
        return [str(error)]
    active = str(Path(context["active_worktree"]).resolve())
    registration = worktrees.get(active)
    if registration is None:
        reasons.append("active worktree is not registered or no longer exists: {}".format(active))
    else:
        if registration["branch"] != context["feature_branch"]:
            reasons.append("branch mismatch for {}: recorded {}, registered {}".format(
                active, context["feature_branch"], registration["branch"]))
        if context.get("head_oid") and registration["head"] != context["head_oid"]:
            reasons.append("HEAD mismatch for worktree {}".format(active))
    if Path(context["repository_root"]).resolve() != repository:
        reasons.append("repository root mismatch: recorded {}, actual {}".format(context["repository_root"], repository))
    if Path(context["git_common_dir"]).resolve() != common:
        reasons.append("git common directory mismatch: recorded {}, actual {}".format(context["git_common_dir"], common))
    spec = Path(context["spec_dir"])
    if not spec.is_dir() or not (spec / "spec.md").is_file():
        reasons.append("spec directory is missing or invalid: {}".format(spec))
    else:
        try:
            spec.resolve().relative_to(Path(active))
        except ValueError:
            reasons.append("spec directory is outside active worktree: {}".format(spec))
    recorded_state = Path(context["state_file"]).resolve()
    if recorded_state != candidate:
        reasons.append("state file path mismatch: candidate {}, recorded {}".format(candidate, recorded_state))
    expected_state = Path(active) / ".specify/.spex-state"
    if recorded_state != expected_state.resolve():
        reasons.append("state file is outside active worktree authority: {}".format(recorded_state))
    return reasons


def resolve_workflow_state(cwd=None):
    cwd = Path(cwd or os.getcwd()).resolve()
    repository, _common, worktrees = _repository_identity(cwd)
    candidate_paths = {repository / ".specify/.spex-state"}
    candidate_paths.update(Path(path) / ".specify/.spex-state" for path in worktrees)
    env_path = os.environ.get("SHIP_STATE_FILE")
    if env_path:
        candidate_paths.add(Path(env_path))
    valid = []
    diagnostics = []
    for path in sorted((item.resolve() for item in candidate_paths), key=str):
        if not path.is_file():
            continue
        try:
            state = read_workflow_state(path)
            reasons = validate_feature_context(state["context"], candidate_path=path, cwd=cwd)
        except StateError as error:
            state = None
            reasons = [str(error)]
        if reasons:
            diagnostics.append({"candidate": str(path), "accepted": False, "reasons": reasons})
        else:
            valid.append((path, state))
    if len(valid) != 1:
        reason = "no valid workflow state candidate" if not valid else "multiple valid workflow state candidates"
        diagnostics.append({"accepted": False, "reasons": [reason], "candidate_count": len(valid)})
        raise ResolutionError(reason, diagnostics)
    state = deepcopy(valid[0][1])
    state["diagnostics"] = diagnostics
    return validate_workflow_state(state)


class ResolutionError(StateError):
    def __init__(self, message, diagnostics):
        super().__init__(message)
        self.diagnostics = diagnostics


def stage_index(name):
    try:
        return STAGES.index(name)
    except ValueError:
        print("ERROR: Invalid stage '{}'".format(name), file=sys.stderr)
        sys.exit(1)


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git(*args):
    r = subprocess.run(["git"] + list(args), capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def read_state():
    with open(STATE_FILE) as f:
        return json.load(f)


def write_json(path, data):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except Exception:
        os.unlink(tmp)
        raise


def write_state(stage, index, status, ask, started, brainstorm):
    write_json(STATE_FILE, {
        "mode": "ship",
        "stage": stage,
        "stage_index": index,
        "total_stages": len(STAGES),
        "ask": ask,
        "started_at": started,
        "retries": 0,
        "status": status,
        "brainstorm_file": brainstorm,
        "feature_branch": git("branch", "--show-current") or "unknown",
    })


def update_state(fn):
    data = read_state()
    fn(data)
    write_json(STATE_FILE, data)


def find_spec_dir(brainstorm):
    if brainstorm:
        base = os.path.splitext(os.path.basename(brainstorm))[0]
        for candidate in ["specs/{}".format(base), "specs/{}".format(base.rsplit("-", 1)[0])]:
            if os.path.isdir(candidate):
                return candidate
    if os.path.isdir("specs"):
        entries = sorted(
            [os.path.join("specs", d) for d in os.listdir("specs") if os.path.isdir(os.path.join("specs", d))],
            key=lambda p: os.path.getmtime(p),
            reverse=True,
        )
        if entries:
            return entries[0]
    return None


def verify_stage_artifacts(stage_idx, brainstorm):
    spec_dir = find_spec_dir(brainstorm)
    checks = {
        0: ("spec.md", "specify", "a specification"),
        3: ("plan.md", "plan", "an implementation plan"),
        4: ("tasks.md", "tasks", "a task breakdown"),
    }
    if stage_idx in checks:
        fname, stage_name, desc = checks[stage_idx]
        if not spec_dir or not os.path.isfile(os.path.join(spec_dir, fname)):
            return "ARTIFACT_MISSING: {} not found. Stage '{}' did not produce {}.".format(fname, stage_name, desc)
    return None


def do_create(args):
    brainstorm = ""
    ask = "smart"
    start_stage = "specify"
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--ask":
            i += 1
            ask = args[i] if i < len(args) else "smart"
        elif a == "--start-from":
            i += 1
            start_stage = args[i] if i < len(args) else "specify"
        elif a.startswith("-"):
            print("ERROR: Unknown flag '{}'".format(a), file=sys.stderr)
            sys.exit(2)
        else:
            brainstorm = a
        i += 1
    if not brainstorm:
        print("ERROR: Brainstorm file required", file=sys.stderr)
        sys.exit(2)
    idx = stage_index(start_stage)
    write_state(start_stage, idx, "running", ask, now_iso(), brainstorm)
    print("CREATED stage={} index={} ask={}".format(start_stage, idx, ask))


def do_advance():
    if not os.path.isfile(STATE_FILE):
        print("PIPELINE_COMPLETE")
        return
    data = read_state()
    current_index = data["stage_index"]
    ask = data.get("ask", "smart")
    started = data["started_at"]
    brainstorm = data["brainstorm_file"]

    err = verify_stage_artifacts(current_index, brainstorm)
    if err:
        print(err)
        sys.exit(1)

    next_index = current_index + 1
    if next_index >= len(STAGES):
        write_state("done", next_index, "completed", ask, started, brainstorm)
        print("PIPELINE_COMPLETE")
        return
    next_stage = STAGES[next_index]
    write_state(next_stage, next_index, "running", ask, started, brainstorm)
    print("ADVANCED stage={} index={}".format(next_stage, next_index))


def do_status():
    if not os.path.isfile(STATE_FILE):
        print("NO_PIPELINE")
        return
    data = read_state()
    print(json.dumps({k: data.get(k) for k in ["mode", "stage", "stage_index", "status", "ask"]}))


def do_pause():
    if not os.path.isfile(STATE_FILE):
        print("ERROR: No state file found", file=sys.stderr)
        sys.exit(1)
    update_state(lambda d: d.update(status="paused"))
    print("PAUSED")


def do_fail():
    if not os.path.isfile(STATE_FILE):
        print("ERROR: No state file found", file=sys.stderr)
        sys.exit(1)
    update_state(lambda d: d.update(status="failed"))
    print("FAILED")


def do_cleanup():
    if os.path.isfile(STATE_FILE):
        os.remove(STATE_FILE)
    print("CLEANUP_DONE")


def do_watch_start(args):
    pr_number = ""
    pr_url = ""
    timeout_minutes = 30
    poll_interval = 60
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--pr-number":
            i += 1; pr_number = args[i] if i < len(args) else ""
        elif a == "--pr-url":
            i += 1; pr_url = args[i] if i < len(args) else ""
        elif a == "--timeout":
            i += 1; timeout_minutes = int(args[i]) if i < len(args) else 30
        elif a == "--interval":
            i += 1; poll_interval = int(args[i]) if i < len(args) else 60
        else:
            print("ERROR: Unknown flag '{}'".format(a), file=sys.stderr)
            sys.exit(2)
        i += 1
    if not pr_number:
        print("ERROR: --pr-number is required", file=sys.stderr)
        sys.exit(2)
    write_json(STATE_FILE, {
        "mode": "watch",
        "pr_number": int(pr_number),
        "pr_url": pr_url,
        "watch_started_at": now_iso(),
        "watch_timeout_minutes": timeout_minutes,
        "watch_poll_interval_seconds": poll_interval,
        "last_ci_status": "pending",
        "last_ci_check_at": None,
        "ci_fix_attempts": 0,
        "last_triage_at": None,
        "triage_count": 0,
        "feature_branch": git("branch", "--show-current") or "unknown",
    })
    print("WATCH_STARTED pr={} timeout={}m interval={}s".format(pr_number, timeout_minutes, poll_interval))


def do_watch_update(args):
    if not os.path.isfile(STATE_FILE):
        print("ERROR: No state file found", file=sys.stderr)
        sys.exit(1)
    data = read_state()
    i = 0
    while i + 1 < len(args):
        key, value = args[i], args[i + 1]
        i += 2
        if value == "null":
            data[key] = None
        else:
            try:
                data[key] = int(value)
            except ValueError:
                data[key] = value
    write_json(STATE_FILE, data)
    print("WATCH_UPDATED")


def do_watch_cleanup():
    if os.path.isfile(STATE_FILE):
        os.remove(STATE_FILE)
    print("WATCH_COMPLETE")


def do_checkpoint_record(args):
    checkpoint = ""
    findings = 0
    fixed = 0
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--checkpoint":
            i += 1; checkpoint = args[i] if i < len(args) else ""
        elif a == "--findings":
            i += 1; findings = int(args[i]) if i < len(args) else 0
        elif a == "--fixed":
            i += 1; fixed = int(args[i]) if i < len(args) else 0
        else:
            print("ERROR: Unknown flag '{}'".format(a), file=sys.stderr)
            sys.exit(2)
        i += 1
    if checkpoint not in ("1", "2"):
        print("ERROR: --checkpoint must be 1 or 2", file=sys.stderr)
        sys.exit(2)

    ts = now_iso()
    if not os.path.isfile(STATE_FILE):
        os.makedirs(os.path.dirname(STATE_FILE) or ".", exist_ok=True)
        write_json(STATE_FILE, {
            "checkpoint_{}_findings".format(checkpoint): findings,
            "checkpoint_{}_fixed".format(checkpoint): fixed,
            "checkpoint_{}_at".format(checkpoint): ts,
        })
    else:
        data = read_state()
        data["checkpoint_{}_findings".format(checkpoint)] = findings
        data["checkpoint_{}_fixed".format(checkpoint)] = fixed
        data["checkpoint_{}_at".format(checkpoint)] = ts
        write_json(STATE_FILE, data)
    print("CHECKPOINT_RECORDED checkpoint={} findings={} fixed={}".format(checkpoint, findings, fixed))


def _option(args, name, *, required=False):
    if name not in args:
        if required:
            raise StateError("{} is required".format(name))
        return None
    index = args.index(name)
    if index + 1 >= len(args):
        raise StateError("{} requires a value".format(name))
    return args[index + 1]


def emit_json(value):
    json.dump(value, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def do_resolve(args):
    if "--help" in args:
        print("Usage: spex-ship-state.py resolve")
        return
    _require(not args, "resolve does not accept arguments")
    emit_json(resolve_workflow_state())


def do_validate(args):
    if "--help" in args:
        print("Usage: spex-ship-state.py validate --identity-file <path>")
        return
    identity_path = _option(args, "--identity-file", required=True)
    try:
        with open(identity_path, encoding="utf-8") as handle:
            identity = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise StateError("cannot read identity file {}: {}".format(identity_path, error)) from error
    candidate = identity.get("state_file", "") if isinstance(identity, dict) else ""
    reasons = validate_feature_context(identity, candidate_path=candidate)
    _require(not reasons, "; ".join(reasons))
    emit_json(identity)


def do_resume(args):
    if "--help" in args:
        print("Usage: spex-ship-state.py resume --expected-revision <revision>")
        return
    raw_revision = _option(args, "--expected-revision", required=True)
    try:
        expected_revision = int(raw_revision)
    except (TypeError, ValueError) as error:
        raise StateError("--expected-revision must be an integer") from error
    state = resolve_workflow_state()
    _require(state["revision"] == expected_revision,
             "state revision conflict: expected {}, found {}".format(expected_revision, state["revision"]))
    _require(state["status"] == "paused_authority", "only paused_authority state can be resumed")
    state["revision"] += 1
    state["status"] = "running"
    state["updated_at"] = now_iso()
    state["diagnostics"] = []
    destination = Path(state["context"]["state_file"])
    write_workflow_state(destination, state, expected_revision=expected_revision)
    emit_json(state)


COMMANDS = {
    "create": lambda a: do_create(a),
    "advance": lambda a: do_advance(),
    "status": lambda a: do_status(),
    "pause": lambda a: do_pause(),
    "fail": lambda a: do_fail(),
    "cleanup": lambda a: do_cleanup(),
    "checkpoint-record": lambda a: do_checkpoint_record(a),
    "watch-start": lambda a: do_watch_start(a),
    "watch-update": lambda a: do_watch_update(a),
    "watch-cleanup": lambda a: do_watch_cleanup(),
    "resolve": do_resolve,
    "validate": do_validate,
    "resume": do_resume,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print("Usage: spex-ship-state.py {%s}" % "|".join(COMMANDS.keys()), file=sys.stderr)
        sys.exit(2)
    try:
        COMMANDS[sys.argv[1]](sys.argv[2:])
    except ResolutionError as error:
        emit_json({"status": "failed_validation", "diagnostics": error.diagnostics})
        print("ERROR: {}".format(error), file=sys.stderr)
        sys.exit(1)
    except StateError as error:
        emit_json({"status": "failed_validation", "diagnostics": [{"reasons": [str(error)]}]})
        print("ERROR: {}".format(error), file=sys.stderr)
        sys.exit(1)
