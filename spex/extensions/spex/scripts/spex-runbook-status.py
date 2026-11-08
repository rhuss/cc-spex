#!/usr/bin/env python3
"""spex-runbook-status.py - Runbook status, freshness, and scratch location.

Subcommands: fingerprint, locate, init, step, steps, mode, reset, show, list, not-testable.
Frontmatter and the human status line are written only by this script
(Constitution VII). Stdlib only (no PyYAML). JSON goes to stdout; diagnostics
to stderr.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import date

STATE_FILE = os.environ.get("SHIP_STATE_FILE", ".specify/.spex-state")

FM_ORDER = [
    "runbook_version", "feature", "status", "mode", "steps_total",
    "step_results", "drafted_at", "drafted_fingerprint", "tested_at",
    "tested_fingerprint", "updated",
]
# Optional keys are written only when non-empty, so runbooks that never use
# them stay byte-identical. stale_reason is set by `reset` (FR-030).
OPTIONAL_KEYS = ["stale_reason"]
REQUIRED_KEYS = ["status", "mode", "steps_total", "step_results"]
RESULTS = ("passed", "failed", "skipped", "pending")


def run(args, env=None, cwd=None):
    r = subprocess.run(args, capture_output=True, text=True, env=env, cwd=cwd)
    return r.returncode, r.stdout


def is_git():
    return run(["git", "rev-parse", "--git-dir"])[0] == 0


def short_head():
    rc, out = run(["git", "rev-parse", "--short", "HEAD"])
    return out.strip() if rc == 0 else ""


def today():
    return date.today().strftime("%Y-%m-%d")


# ─── Fingerprint (research R1) ───

def _plain_index():
    """Path of the real index when seeding from it cannot change the result,
    else None. Seeding is only safe when every entry is a plain cached entry
    (no assume-unchanged, skip-worktree/sparse, or unmerged flags) and no
    tracked file matches an ignore rule: an empty index never picks those
    up, a seeded `git add -A` would keep them. Submodule gitlinks are also
    excluded (an uninitialized one survives a seeded add but not an empty one).
    The listings run from the top level, since `ls-files` only covers cwd."""
    rc, top = run(["git", "rev-parse", "--show-toplevel"])
    top = top.strip()
    if rc != 0 or not top:
        return None
    rc, real = run(["git", "rev-parse", "--git-path", "index"], cwd=top)
    real = real.strip()
    if rc != 0 or not real:
        return None
    real = os.path.join(top, real)
    if not os.path.isfile(real):
        return None
    rc, out = run(["git", "ls-files", "-v", "-s"], cwd=top)
    if rc != 0:
        return None
    for line in out.splitlines():
        if not line.startswith("H ") or line.startswith("H 160000 "):
            return None
    rc, out = run(["git", "ls-files", "-ci", "--exclude-standard"], cwd=top)
    if rc != 0 or out.strip():
        return None
    return real


def code_tree():
    """Write the working tree (tracked + untracked, honoring .gitignore) to a
    temporary index and return its tree SHA. None when not a git repo."""
    if not is_git():
        return None
    tmp = tempfile.mkdtemp()
    idx = os.path.join(tmp, "index")
    env = dict(os.environ)
    env["GIT_INDEX_FILE"] = idx
    try:
        # Seed the temporary index from the real one so `git add -A` can reuse
        # its stat cache instead of re-hashing every file (this runs on every
        # commit via the pre-commit verification reminder). Only a plain index
        # is used (see _plain_index), so the tree SHA equals the one built
        # from an empty index; otherwise, or on any problem, start from empty.
        seeded = False
        real = _plain_index()
        if real:
            try:
                shutil.copyfile(real, idx)
                seeded = True
            except OSError:
                seeded = False
        if run(["git", "add", "-A"], env=env)[0] != 0:
            if not seeded:
                return None
            try:
                os.remove(idx)
            except OSError:
                pass
            if run(["git", "add", "-A"], env=env)[0] != 0:
                return None
        rc, out = run(["git", "write-tree"], env=env)
        return out.strip() if rc == 0 else None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _excluded(path):
    return path.startswith("specs/") or path.startswith("brainstorm/")


def fingerprint():
    tree = code_tree()
    if tree is None:
        return None
    rc, out = run(["git", "ls-tree", "--full-tree", "-r", tree])
    if rc != 0:
        return None
    entries = []
    for line in out.splitlines():
        if "\t" not in line:
            continue
        meta, path = line.split("\t", 1)
        if _excluded(path):
            continue
        parts = meta.split()
        if len(parts) >= 3:
            entries.append(parts[2] + " " + path)
    entries.sort()
    return hashlib.sha256("\n".join(entries).encode("utf-8")).hexdigest()


def changed_files(ref_commit):
    if not ref_commit:
        return [], None
    if run(["git", "cat-file", "-e", ref_commit + "^{commit}"])[0] != 0:
        return [], ("commit {} no longer exists (history rewritten); "
                    "file list unavailable".format(ref_commit))
    tree = code_tree()
    if tree is None:
        return [], None
    rc, out = run(["git", "diff", "--name-only", ref_commit, tree])
    if rc != 0:
        return [], None
    files = [p for p in out.splitlines() if p and not _excluded(p)]
    return files, None


# ─── Frontmatter ───

def split_frontmatter(text):
    """Return (status, fm_dict_or_None, body) where status is
    'none', 'ok', or 'invalid'."""
    if not text.startswith("---"):
        return "none", None, text
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.DOTALL)
    if not m:
        return "none", None, text
    fm_text, body = m.group(1), m.group(2)
    fm = {}
    for line in fm_text.splitlines():
        if not line.strip():
            continue
        mm = re.match(r"^([A-Za-z0-9_]+):\s?(.*)$", line)
        if not mm:
            return "invalid", None, body
        fm[mm.group(1)] = mm.group(2)
    return "ok", fm, body


def parse_runbook(path):
    """Return ('ok', fm, body) or ('unreadable', None, None)."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    status, fm, body = split_frontmatter(text)
    if status != "ok":
        return "unreadable", None, None
    if not all(k in fm for k in REQUIRED_KEYS):
        return "unreadable", None, None
    try:
        int(fm["steps_total"])
    except (ValueError, TypeError):
        return "unreadable", None, None
    return "ok", fm, body


def serialize_frontmatter(fm):
    lines = ["---"]
    for k in FM_ORDER:
        v = fm.get(k, "")
        lines.append("{}:".format(k) if v == "" else "{}: {}".format(k, v))
    for k in OPTIONAL_KEYS:
        v = fm.get(k, "")
        if v != "":
            lines.append("{}: {}".format(k, v))
    lines.append("---")
    return "\n".join(lines) + "\n"


def results_of(fm):
    raw = fm.get("step_results", "")
    return raw.split(",") if raw else []


def derive_status(results, presented):
    if all(r == "pending" for r in results) and not presented:
        return "drafted"
    if any(r == "failed" for r in results):
        return "failed"
    if any(r == "pending" for r in results):
        return "in_progress"
    return "passed"


def status_line_text(fm):
    results = results_of(fm)
    total = len(results)
    counts = {k: results.count(k) for k in RESULTS}
    done = total - counts["pending"]
    parts = ["{} {}".format(counts[k], k) for k in ("passed", "failed", "skipped") if counts[k]]
    seg = "{} of {} steps".format(done, total)
    if parts:
        seg += " (" + ", ".join(parts) + ")"
    pieces = ["**Status:** {}".format(fm.get("status", "")), seg,
              "Mode: {}".format(fm.get("mode", ""))]
    if fm.get("tested_at"):
        pieces.append("Tested at {}".format(fm["tested_at"]))
    elif fm.get("drafted_at"):
        pieces.append("Drafted at {}".format(fm["drafted_at"]))
    if fm.get("updated"):
        pieces.append(fm["updated"])
    if fm.get("status") == "stale" and fm.get("stale_reason"):
        pieces.append("Reset: {}; step results below predate it".format(fm["stale_reason"]))
    return "> " + " · ".join(pieces)


def set_status_line(body, line_text):
    block = "<!-- runbook-status -->\n{}\n<!-- /runbook-status -->".format(line_text)
    body = re.sub(r"<!-- runbook-status -->.*?<!-- /runbook-status -->\n?", "",
                  body, flags=re.DOTALL)
    lines = body.split("\n")
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if not inserted and line.startswith("# "):
            out.append("")
            out.append(block)
            inserted = True
    if not inserted:
        out = [block, ""] + out
    return "\n".join(out).strip("\n") + "\n"


def write_runbook(path, fm, body):
    body2 = set_status_line(body, status_line_text(fm))
    content = serialize_frontmatter(fm) + "\n" + body2.lstrip("\n")
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# ─── Locate ───

def do_locate(args):
    create = "--create" in args
    pos = [a for a in args if a != "--create"]
    if len(pos) != 1:
        sys.stderr.write("usage: locate <spec-dir> [--create]\n")
        sys.exit(2)
    spec_dir = pos[0].rstrip("/")
    scratch = os.path.join(spec_dir, ".walkthrough")
    runbook = os.path.join(spec_dir, "RUNBOOK.md")
    detach, relocated = detach_relocation(spec_dir, runbook)
    if relocated:
        runbook = os.path.join(scratch, "RUNBOOK.md")
    if create:
        os.makedirs(scratch, exist_ok=True)
        gi = os.path.join(scratch, ".gitignore")
        if not os.path.isfile(gi):
            with open(gi, "w", encoding="utf-8") as f:
                f.write("*\n")
    print(json.dumps({"runbook": runbook, "scratch": scratch,
                      "detach": detach, "relocated": relocated}))


def detach_relocation(spec_dir, normal_runbook):
    """Return (detach_enabled, relocated) per research R4.

    Detach is read via spex-detach.sh is-enabled (exit 0 = enabled; missing
    script = disabled). When detach is on, relocate to the self-ignoring scratch
    folder only if the normal path is not already git-ignored."""
    detach_script = ".specify/extensions/spex-detach/scripts/spex-detach.sh"
    if not os.path.isfile(detach_script):
        return False, False
    if run(["sh", detach_script, "is-enabled"])[0] != 0:
        return False, False
    ignored = run(["git", "check-ignore", normal_runbook])[0] == 0
    return True, (not ignored)


# ─── Resolve ───

def resolve_runbook(arg):
    arg = arg.rstrip("/")
    if arg.endswith(".md"):
        return arg
    for cand in (os.path.join(arg, "RUNBOOK.md"),
                 os.path.join(arg, ".walkthrough", "RUNBOOK.md")):
        if os.path.isfile(cand):
            return cand
    return os.path.join(arg, "RUNBOOK.md")


# ─── init / step / steps / mode ───

def do_init(args):
    runbook = None
    feature = None
    mode = None
    steps = None
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--feature":
            i += 1; feature = args[i] if i < len(args) else None
        elif a == "--mode":
            i += 1; mode = args[i] if i < len(args) else None
        elif a == "--steps":
            i += 1; steps = args[i] if i < len(args) else None
        elif runbook is None:
            runbook = a
        i += 1
    if not runbook or not feature or mode not in ("light", "full") or steps is None:
        sys.stderr.write("usage: init <runbook> --feature <name> --mode light|full --steps <n>\n")
        sys.exit(2)
    try:
        n = int(steps)
    except ValueError:
        sys.stderr.write("init: --steps must be an integer\n")
        sys.exit(2)
    if not os.path.isfile(runbook):
        sys.stderr.write("init: runbook file not found: {}\n".format(runbook))
        sys.exit(1)
    with open(runbook, encoding="utf-8") as f:
        text = f.read()
    _, _, body = split_frontmatter(text)
    fm = {
        "runbook_version": 1,
        "feature": feature,
        "status": "drafted",
        "mode": mode,
        "steps_total": n,
        "step_results": ",".join(["pending"] * n),
        "drafted_at": short_head(),
        "drafted_fingerprint": fingerprint() or "",
        "tested_at": "",
        "tested_fingerprint": "",
        "updated": today(),
    }
    write_runbook(runbook, fm, body)


def _load_or_die(runbook, code):
    if not os.path.isfile(runbook):
        sys.stderr.write("runbook file not found: {}\n".format(runbook))
        sys.exit(code)
    kind, fm, body = parse_runbook(runbook)
    if kind != "ok":
        sys.stderr.write("runbook frontmatter is unreadable: {}\n".format(runbook))
        sys.exit(code)
    return fm, body


def do_step(args):
    if len(args) < 3:
        sys.stderr.write("usage: step <runbook> <n> passed|failed|skipped|pending\n")
        sys.exit(2)
    runbook, n_str, result = args[0], args[1], args[2]
    if result not in RESULTS:
        sys.stderr.write("step: result must be one of {}\n".format("|".join(RESULTS)))
        sys.exit(2)
    try:
        n = int(n_str)
    except ValueError:
        sys.stderr.write("step: step number must be an integer\n")
        sys.exit(2)
    fm, body = _load_or_die(runbook, 1)
    results = results_of(fm)
    if n < 1 or n > len(results):
        sys.stderr.write("step: step {} out of range 1..{}\n".format(n, len(results)))
        sys.exit(1)
    results[n - 1] = result
    fm["step_results"] = ",".join(results)
    fm["tested_at"] = short_head()
    fm["tested_fingerprint"] = fingerprint() or ""
    fm["updated"] = today()
    fm["status"] = derive_status(results, presented=True)
    fm.pop("stale_reason", None)
    write_runbook(runbook, fm, body)
    print(json.dumps(build_show(runbook, use_git=True)))


def do_steps(args):
    if len(args) < 2:
        sys.stderr.write("usage: steps <runbook> <n>\n")
        sys.exit(2)
    runbook, n_str = args[0], args[1]
    try:
        n = int(n_str)
    except ValueError:
        sys.stderr.write("steps: <n> must be an integer\n")
        sys.exit(2)
    fm, body = _load_or_die(runbook, 2)
    results = results_of(fm)
    if n > len(results):
        results += ["pending"] * (n - len(results))
    else:
        results = results[:n]
    fm["step_results"] = ",".join(results)
    fm["steps_total"] = n
    fm["updated"] = today()
    presented = bool(fm.get("tested_at"))
    if fm.get("status") == "stale" and all(r == "pending" for r in results):
        fm["status"] = "stale"  # a refreshed step count does not clear a reset
    else:
        fm["status"] = derive_status(results, presented=presented)
    write_runbook(runbook, fm, body)


def do_reset(args):
    """Mark a runbook stale after a requirement-changing spec amendment (FR-030).

    Every step goes back to pending and the test stamps are cleared, so earlier
    results no longer count; the draft stamps, mode, and step count are kept.
    A missing runbook is a no-op (exit 0)."""
    reason = ""
    pos = []
    i = 0
    while i < len(args):
        if args[i] == "--reason":
            i += 1
            reason = args[i] if i < len(args) else ""
        else:
            pos.append(args[i])
        i += 1
    if len(pos) != 1:
        sys.stderr.write("usage: reset <spec-dir|runbook> [--reason <text>]\n")
        sys.exit(2)
    runbook = resolve_runbook(pos[0])
    if not os.path.isfile(runbook):
        print(json.dumps({"reset": False, "why": "no-runbook", "path": runbook}))
        return
    fm, body = _load_or_die(runbook, 1)
    reason = " ".join(reason.split()) or "spec amended"
    n = int(fm["steps_total"])
    fm["step_results"] = ",".join(["pending"] * n)
    fm["status"] = "stale"
    fm["stale_reason"] = reason
    fm["tested_at"] = ""
    fm["tested_fingerprint"] = ""
    fm["updated"] = today()
    write_runbook(runbook, fm, body)
    print(json.dumps(build_show(runbook, use_git=False)))


def do_mode(args):
    if len(args) < 2 or args[1] not in ("light", "full"):
        sys.stderr.write("usage: mode <runbook> light|full\n")
        sys.exit(2)
    runbook, target = args[0], args[1]
    fm, body = _load_or_die(runbook, 2)
    current = fm.get("mode")
    results = results_of(fm)
    if current == "full" and target == "light" and any(r != "pending" for r in results):
        sys.stderr.write("mode: cannot downgrade to light after a step has a result\n")
        sys.exit(1)
    fm["mode"] = target
    fm["updated"] = today()
    write_runbook(runbook, fm, body)


# ─── show / list / not-testable ───

def build_show(arg, use_git):
    runbook = resolve_runbook(arg)
    base = {
        "exists": False, "path": runbook, "readable": None, "status": None,
        "mode": None, "steps": None, "drafted_at": None, "tested_at": None,
        "current": None, "changed_since_draft": None, "changed_files": [],
        "changed_files_note": None, "not_testable": False, "stale_reason": None,
    }
    if not os.path.isfile(runbook):
        spec_dir = os.path.dirname(os.path.dirname(runbook)) if runbook.endswith(
            os.path.join(".walkthrough", "RUNBOOK.md")) else os.path.dirname(runbook)
        base["not_testable"] = not_testable_recorded(spec_dir) if use_git else False
        if base["not_testable"]:
            base["status"] = "not_testable"
        return base
    kind, fm, _ = parse_runbook(runbook)
    if kind != "ok":
        base["exists"] = True
        base["readable"] = False
        base["status"] = "unreadable"
        return base
    results = results_of(fm)
    total = int(fm["steps_total"])
    steps = {"total": total}
    for k in ("passed", "failed", "skipped", "pending"):
        steps[k] = results.count(k)
    drafted_at = fm.get("drafted_at") or None
    tested_at = fm.get("tested_at") or None
    result = {
        "exists": True, "path": runbook, "readable": True,
        "status": fm["status"], "mode": fm["mode"], "steps": steps,
        "drafted_at": drafted_at, "tested_at": tested_at,
        "current": None, "changed_since_draft": None, "changed_files": [],
        "changed_files_note": None, "not_testable": False,
        "stale_reason": fm.get("stale_reason") or None,
    }
    if use_git:
        fp = fingerprint()
        if fp is not None:
            drafted_fp = fm.get("drafted_fingerprint") or ""
            tested_fp = fm.get("tested_fingerprint") or ""
            ref_fp = tested_fp or drafted_fp
            result["current"] = (fp == ref_fp) if ref_fp else None
            result["changed_since_draft"] = (fp != drafted_fp) if drafted_fp else None
            if result["current"] is False:
                files, note = changed_files(tested_at or drafted_at)
                result["changed_files"] = files
                result["changed_files_note"] = note
    return result


def do_show(args):
    use_git = "--no-git" not in args
    pos = [a for a in args if a != "--no-git"]
    if len(pos) != 1:
        sys.stderr.write("usage: show <spec-dir|runbook> [--no-git]\n")
        sys.exit(2)
    print(json.dumps(build_show(pos[0], use_git)))


def do_list(args):
    root = args[0] if args else "specs"
    out = []
    if os.path.isdir(root):
        for name in sorted(os.listdir(root)):
            spec_dir = os.path.join(root, name)
            if not os.path.isdir(spec_dir):
                continue
            runbook = resolve_runbook(spec_dir)
            if os.path.isfile(runbook):
                out.append(build_show(spec_dir, use_git=True))
    print(json.dumps(out))


def not_testable_recorded(spec_dir):
    if not os.path.isfile(STATE_FILE):
        return False
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            state = json.load(f)
    except (ValueError, OSError):
        return False
    recorded = state.get("walkthrough_not_testable_fingerprint")
    if not recorded:
        return False
    return recorded == fingerprint()


def do_not_testable(args):
    if len(args) != 1:
        sys.stderr.write("usage: not-testable <spec-dir>\n")
        sys.exit(2)
    if not os.path.isfile(STATE_FILE):
        return
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            state = json.load(f)
    except (ValueError, OSError):
        return
    state["walkthrough_not_testable_fingerprint"] = fingerprint() or ""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(STATE_FILE) or ".")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
        f.write("\n")
    os.replace(tmp, STATE_FILE)


def do_fingerprint(args):
    fp = fingerprint()
    if fp is None:
        sys.stderr.write("fingerprint: not a git repository\n")
        sys.exit(1)
    print(fp)


COMMANDS = {
    "fingerprint": do_fingerprint,
    "locate": do_locate,
    "init": do_init,
    "step": do_step,
    "steps": do_steps,
    "mode": do_mode,
    "reset": do_reset,
    "show": do_show,
    "list": do_list,
    "not-testable": do_not_testable,
}

def _exit_on_sigterm(signum, frame):
    # Turn SIGTERM into SystemExit so `finally` blocks remove temp dirs
    # (the pre-commit hook sends SIGTERM to the group on timeout).
    sys.exit(143)


if __name__ == "__main__":
    try:
        import signal
        signal.signal(signal.SIGTERM, _exit_on_sigterm)
    except (ImportError, AttributeError, ValueError):
        pass
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.stderr.write("Usage: spex-runbook-status.py {%s}\n" % "|".join(COMMANDS))
        sys.exit(2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
