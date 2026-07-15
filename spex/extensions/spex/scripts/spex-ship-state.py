#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

STATE_FILE = os.environ.get("SHIP_STATE_FILE", ".specify/.spex-state")
STAGES = ["specify", "clarify", "review-spec", "plan", "tasks", "review-plan", "implement", "review-code"]


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
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print("Usage: spex-ship-state.py {%s}" % "|".join(COMMANDS.keys()), file=sys.stderr)
        sys.exit(2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
