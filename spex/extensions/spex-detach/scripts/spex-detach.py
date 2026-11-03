#!/usr/bin/env python3
import fnmatch
import itertools
import json
import os
import shutil
import subprocess
import sys


DEFAULT_EXCLUDE_PATHS = [".specify/", "specs/", "brainstorm/"]


def git(*args, check=False, cwd=None):
    r = subprocess.run(["git"] + list(args), capture_output=True, text=True, cwd=cwd)
    if check and r.returncode != 0:
        return None
    return r.stdout.strip() if r.returncode == 0 else ""


def git_ok(*args, cwd=None):
    return subprocess.run(["git"] + list(args), capture_output=True, cwd=cwd).returncode == 0


def yq_read(key, config_file):
    if not os.path.isfile(config_file):
        return None
    if shutil.which("yq") is None:
        print("WARNING: yq not found; ignoring {} (using defaults)".format(config_file), file=sys.stderr)
        return None
    r = subprocess.run(["yq", "-r", "{} // empty".format(key), config_file], capture_output=True, text=True)
    val = r.stdout.strip() if r.returncode == 0 else ""
    return val if val and val != "null" else None


CONFIG_FILE = ".specify/extensions/spex-detach/spex-detach-config.yml"


def read_config(key, default):
    val = yq_read(key, CONFIG_FILE)
    return val if val is not None else default


def read_exclude_paths(warn=False):
    """The configured exclude paths, or the defaults when the configuration
    is missing or cannot be read. With warn=True, a configuration that exists
    but cannot be read is reported on stderr, so the fallback is visible."""
    if not os.path.isfile(CONFIG_FILE):
        return list(DEFAULT_EXCLUDE_PATHS)
    if shutil.which("yq") is None:
        if warn:
            print("Stealth mode: cannot read {} (yq not found); using the default exclude paths".format(CONFIG_FILE),
                  file=sys.stderr)
        return list(DEFAULT_EXCLUDE_PATHS)
    r = subprocess.run(
        ["yq", "-r", ".exclude.paths // [] | .[]", CONFIG_FILE],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        if warn:
            print("Stealth mode: cannot read {} (invalid configuration); using the default exclude paths".format(CONFIG_FILE),
                  file=sys.stderr)
        return list(DEFAULT_EXCLUDE_PATHS)
    paths = [p for p in r.stdout.strip().split("\n") if p]
    return paths if paths else list(DEFAULT_EXCLUDE_PATHS)


def configured_entries(warn=False):
    """The configured exclude entries as enable writes them, disable removes
    them and verify checks them: whitespace stripped, empty and `#` comment
    entries dropped, duplicates removed (first one wins). Negation entries
    (`!...`) are kept; verify skips them (see verify_entries)."""
    entries = []
    for p in read_exclude_paths(warn):
        e = p.strip()
        if e and not e.startswith("#") and e not in entries:
            entries.append(e)
    return entries


def get_project_name():
    url = git("remote", "get-url", "upstream") or git("remote", "get-url", "origin")
    if url:
        for host in ["github.com", "gitlab.com"]:
            if host in url:
                part = url.split(host)[-1].lstrip(":/")
                if part.endswith(".git"):
                    part = part[:-4]
                return part
    toplevel = git("rev-parse", "--show-toplevel")
    return os.path.basename(toplevel) if toplevel else "unknown"


def validate_path_component(name, value):
    if ".." in value:
        print("ERROR: {} contains '..' path traversal".format(name), file=sys.stderr)
        sys.exit(1)
    if os.path.isabs(value):
        print("ERROR: {} is an absolute path".format(name), file=sys.stderr)
        sys.exit(1)


def require_arg(flag, remaining):
    if remaining < 2:
        print("ERROR: {} requires a value".format(flag), file=sys.stderr)
        sys.exit(1)


REGISTRY_FILE = ".specify/extensions/.registry"


def cmd_is_enabled():
    # The extension directory stays on disk when the extension is disabled,
    # so the registry flag decides.
    try:
        with open(REGISTRY_FILE, "r") as f:
            enabled = json.load(f)["extensions"]["spex-detach"]["enabled"] is True
    except (OSError, ValueError, KeyError, TypeError):
        enabled = False
    sys.exit(0 if enabled and os.path.isdir(".specify/extensions/spex-detach") else 1)


def git_common_dir_or_none():
    r = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True)
    out = r.stdout.strip() if r.returncode == 0 else ""
    return out or None


def run_enable(warn_tracked=True):
    """Write the configured exclude entries. Returns the result dict, or None
    when the current directory is not inside a git repository."""
    git_common_dir = git_common_dir_or_none()
    if not git_common_dir:
        return None

    info_dir = os.path.join(git_common_dir, "info")
    os.makedirs(info_dir, exist_ok=True)

    exclude_file = os.path.join(info_dir, "exclude")

    existing_content = ""
    if os.path.isfile(exclude_file):
        with open(exclude_file, "r") as f:
            existing_content = f.read()

    # Like git: trailing whitespace is dropped, leading whitespace belongs to
    # the pattern (` specs/` is not `specs/`).
    existing_lines = {line.rstrip() for line in existing_content.split("\n")} - {""}

    exclude_paths = configured_entries()

    to_add = [p for p in exclude_paths if p not in existing_lines]

    if to_add:
        with open(exclude_file, "a") as f:
            if existing_content and not existing_content.endswith("\n"):
                f.write("\n")
            if not any("spex-detach" in line for line in existing_lines):
                f.write("# spex-detach: spec artifacts excluded from git\n")
            for path in to_add:
                f.write(path + "\n")

    # The same tracked check verify uses (negation entries hide nothing).
    tracked_warnings = [p.rstrip("/") for p in exclude_paths
                        if not p.startswith("!") and is_tracked(p)]

    result = {
        "exclude_file": exclude_file,
        "paths_configured": exclude_paths,
        "paths_added": to_add,
        "already_present": len(exclude_paths) - len(to_add),
    }

    if tracked_warnings:
        result["tracked_warning"] = tracked_warnings
        if warn_tracked:
            print("WARNING: The following paths are already tracked by git and must be removed from history separately: {}".format(
                ", ".join(tracked_warnings)), file=sys.stderr)

    return result


def cmd_enable(args):
    result = run_enable()
    if result is None:
        print("ERROR: Not a git repository", file=sys.stderr)
        sys.exit(1)
    print(json.dumps(result))


# Files spex's own generated-file rules re-include by negation
# (`!**/.specify/spex.json`, `!**/.specify/memory/constitution.md`). They are
# probed separately when a configured entry covers them, because a probe under
# the directory alone would not notice a re-include.
REINCLUDE_FILES = [".specify/spex.json", ".specify/memory/constitution.md"]
# Not a dotfile: a generic rule such as `.*` must not satisfy the probe.
PROBE_NAME = "spex-detach-probe"
GLOB_CHARS = "*?["


def strip_anchor(entry):
    """Drop a leading `/` (anchored) and `**/` prefixes: the probe is built
    relative to the project root."""
    path = entry.lstrip("/")
    while path.startswith("**/"):
        path = path[3:]
    return path


# Upper case comes last: with core.ignorecase (macOS default), git matches
# `[!a-z]` case-insensitively, so `A` would not satisfy it there.
BRACKET_CANDIDATES = (
    "xyzq"
    + "abcdefghijklmnoprstuvw"
    + "0123456789_-+=~@%,"
    + "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    + " "
)


# Expansions that fnmatch understands. None starts with `!` (that would read
# as a negation) and none has a bare `-` (that would read as a range).
# `"-~` plus `!` is every printable ASCII character except space.
POSIX_CLASSES = {
    "alpha": "a-zA-Z", "alnum": "a-zA-Z0-9", "digit": "0-9", "lower": "a-z",
    "upper": "A-Z", "xdigit": "0-9a-fA-F", "punct": "_+=~@%,", "space": " ",
    "blank": " ", "graph": '"-~!', "print": ' "-~!',
}


def bracket_end(pattern, start):
    """Index of the `]` that closes the bracket class opening at `start`, or
    -1. A `]` right after the opening (or after `!`/`^`) is literal, and
    POSIX classes like `[:alpha:]` are skipped as a whole."""
    j = start + 1
    if j < len(pattern) and pattern[j] in "!^":
        j += 1
    if j < len(pattern) and pattern[j] == "]":
        j += 1
    while j < len(pattern):
        if pattern.startswith("[:", j):
            close = pattern.find(":]", j + 2)
            if close != -1:
                j = close + 2
                continue
        if pattern[j] == "]":
            return j
        j += 1
    return -1


def bracket_char(body):
    """A character that the bracket class `[body]` matches. Ranges, negations
    (`!` or `^`) and POSIX classes are honored. Falls back to `x` only when
    no printable ASCII character matches."""
    negate = body[:1] in ("!", "^")
    if negate:
        body = body[1:]
    for name, chars in POSIX_CLASSES.items():
        body = body.replace("[:" + name + ":]", chars)
    cls = "[" + ("!" if negate else "") + body + "]"
    # Preferred candidates first, then every other printable ASCII character
    # (for classes like `[.]` or `[]]`). `/` never matches inside a class.
    fallback = (chr(c) for c in range(0x20, 0x7F) if chr(c) != "/")
    for ch in itertools.chain(BRACKET_CANDIDATES, fallback):
        if fnmatch.fnmatchcase(ch, cls):
            return ch
    return "x"


def synthesize(pattern):
    """Turn a glob into a concrete name that matches it: `**` and `*` become
    `spex-probe`, `?` becomes `x`, a bracket class becomes one of its chars."""
    out = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == "*":
            while i < len(pattern) and pattern[i] == "*":
                i += 1
            out.append("spex-probe")
            continue
        if c == "?":
            out.append("x")
        elif c == "[":
            end = bracket_end(pattern, i)
            if end == -1:
                out.append(c)
            else:
                out.append(bracket_char(pattern[i + 1:end]))
                i = end + 1
                continue
        elif c == "\\" and i + 1 < len(pattern):
            out.append(pattern[i + 1])
            i += 2
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def classify(entry):
    if entry.endswith("/"):
        return "directory"
    if any(ch in entry for ch in GLOB_CHARS):
        return "glob"
    return "file"


def probe_for(entry):
    kind = classify(entry)
    path = strip_anchor(entry)
    if kind == "directory":
        return synthesize(path) + PROBE_NAME
    if kind == "glob":
        return synthesize(path)
    return path


def covers(entry, filename):
    """True when the configured entry hides `filename` (root-relative)."""
    kind = classify(entry)
    path = strip_anchor(entry)
    if kind == "directory":
        base = path.rstrip("/")
        if any(ch in base for ch in GLOB_CHARS):
            parts = filename.split("/")
            depth = base.count("/") + 1
            return len(parts) > depth and fnmatch.fnmatchcase("/".join(parts[:depth]), base)
        return filename.startswith(base + "/")
    if kind == "glob":
        return fnmatch.fnmatchcase(filename, path) or fnmatch.fnmatchcase(os.path.basename(filename), path)
    return filename == path


def is_ignored(probe):
    return subprocess.run(["git", "check-ignore", "-q", "--", probe], capture_output=True).returncode == 0


def is_tracked(entry):
    """True when git tracks a file the entry covers. Paths are checked
    relative to the project root, like the probes; an explicit `**/` prefix
    is checked at any depth.

    An unanchored entry such as `specs/` also matches nested directories in
    gitignore, but those are deliberately not counted: forked upstream
    projects often track nested `specs/` directories of their own, which
    would turn into a permanent warning the user cannot clear, while spex
    itself only writes its artifacts at the root paths."""
    kind = classify(entry)
    path = strip_anchor(entry)
    if kind == "directory":
        path = path.rstrip("/")
    suffix = "/**" if kind == "directory" else ""
    if entry.lstrip("/").startswith("**/"):
        return bool(git("ls-files", "--", ":(glob)**/" + path + suffix))
    if any(ch in path for ch in GLOB_CHARS) and "/" in path:
        # A glob with a slash is anchored and its `*` never crosses `/`,
        # which glob-magic pathspecs match exactly (plain ones would not).
        return bool(git("ls-files", "--", ":(glob)" + path + suffix))
    return bool(git("ls-files", "--", path))


def verify_entries(warn=False):
    """The entries verify checks: configured_entries without negations,
    which re-include instead of hide."""
    return [e for e in configured_entries(warn) if not e.startswith("!")]


def run_verify(warn=False):
    """Check every configured exclude entry with git. Changes nothing.
    Returns (result dict, exit code); the dict is None when not in a git repo."""
    if not git_common_dir_or_none():
        return None, 2

    verified = []
    visible = []
    reinclude_checked = []
    for entry in verify_entries(warn):
        probe = probe_for(entry)
        entry_ok = True
        if is_tracked(entry):
            visible.append({"entry": entry, "probe": probe, "reason": "tracked"})
            entry_ok = False
        elif not is_ignored(probe):
            visible.append({"entry": entry, "probe": probe, "reason": "not-ignored"})
            entry_ok = False
        for f in REINCLUDE_FILES:
            # Probe only while the entry still looks hidden: once it is
            # visible, the re-include file adds nothing, and listing it as
            # checked would overstate what was probed.
            if not entry_ok or not covers(entry, f):
                continue
            if f not in reinclude_checked:
                reinclude_checked.append(f)
            if not is_ignored(f):
                visible.append({"entry": entry, "probe": f, "reason": "not-ignored"})
                entry_ok = False
        if entry_ok:
            verified.append(entry)

    result = {
        "active": not visible,
        "verified": verified,
        "visible": visible,
        "reinclude_checked": reinclude_checked,
    }
    return result, (0 if not visible else 1)


def print_verify_lines(result):
    if result["active"]:
        print("Stealth mode: active (verified: {})".format(" ".join(result["verified"])), file=sys.stderr)
        return
    print("WARNING: stealth mode is NOT fully active. Still visible to git:", file=sys.stderr)
    for v in result["visible"]:
        if v["probe"] in REINCLUDE_FILES and v["reason"] == "not-ignored":
            print("  {} ({}, re-included under {})".format(v["probe"], v["reason"], v["entry"]), file=sys.stderr)
        else:
            print("  {} ({})".format(v["entry"], v["reason"]), file=sys.stderr)
    if any(v["reason"] == "tracked" for v in result["visible"]):
        print("  Tracked files cannot be hidden by excludes and must be removed from history separately.", file=sys.stderr)


def cmd_verify(args):
    if args:
        print("Usage: spex-detach.py verify", file=sys.stderr)
        sys.exit(2)
    result, code = run_verify(warn=True)
    if result is None:
        print("ERROR: Not a git repository", file=sys.stderr)
        sys.exit(2)
    print(json.dumps(result))
    print_verify_lines(result)
    sys.exit(code)


def cmd_ensure(args):
    was_enabled = False
    for a in args:
        if a == "--was-enabled":
            was_enabled = True
        else:
            print("Usage: spex-detach.py ensure [--was-enabled]", file=sys.stderr)
            sys.exit(2)
    # Outside a git repository: silent, nothing written (callers must not
    # see an ERROR line, a non-git project is simply skipped).
    if not git_common_dir_or_none():
        sys.exit(2)
    enable_result = run_enable(warn_tracked=False)
    added = enable_result["paths_added"]
    if added:
        if was_enabled:
            print("Repaired stealth mode: added {}".format(" ".join(added)), file=sys.stderr)
        else:
            print("Stealth mode: exclude entries written: {}".format(" ".join(added)), file=sys.stderr)
    verify_result, code = run_verify(warn=True)
    print(json.dumps({"enable": enable_result, "verify": verify_result}))
    print_verify_lines(verify_result)
    sys.exit(code)


def cmd_disable(args):
    git_common_dir = git_common_dir_or_none()
    if not git_common_dir:
        print("ERROR: Not a git repository", file=sys.stderr)
        sys.exit(1)

    exclude_file = os.path.join(git_common_dir, "info", "exclude")
    if not os.path.isfile(exclude_file):
        print(json.dumps({"paths_removed": [], "already_clean": True}))
        return

    with open(exclude_file, "r") as f:
        lines = f.readlines()

    exclude_paths = set(configured_entries())
    marker = "# spex-detach:"

    kept = []
    removed = []
    for line in lines:
        stripped = line.rstrip()
        if stripped in exclude_paths or stripped.startswith(marker):
            removed.append(stripped)
        else:
            kept.append(line)

    if removed:
        with open(exclude_file, "w") as f:
            f.writelines(kept)

    print(json.dumps({
        "exclude_file": exclude_file,
        "paths_removed": removed,
        "already_clean": len(removed) == 0,
    }))


def cmd_archive(args):
    target = ""
    project = ""
    feature = ""
    auto_commit = False

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--target":
            require_arg("--target", len(args) - i)
            target = args[i + 1]; i += 2
        elif a == "--project":
            require_arg("--project", len(args) - i)
            project = args[i + 1]; i += 2
        elif a == "--feature":
            require_arg("--feature", len(args) - i)
            feature = args[i + 1]; i += 2
        elif a == "--auto-commit":
            auto_commit = True; i += 1
        else:
            i += 1

    if not target:
        target = read_config(".archive.path", "")
    if not target:
        print(json.dumps({"skipped": True, "reason": "No archive path configured"}))
        sys.exit(0)
    if not os.path.isdir(target):
        json.dump({"error": "Archive target not reachable: {}".format(target)}, sys.stderr)
        print(file=sys.stderr)
        sys.exit(1)

    if not project:
        project = get_project_name()
    if not feature:
        feature = git("branch", "--show-current") or "unknown"

    validate_path_component("project", project)
    validate_path_component("feature", feature)

    archive_dir = os.path.join(target, project, feature)
    os.makedirs(archive_dir, exist_ok=True)

    files_copied = 0

    if os.path.isdir(".specify"):
        shutil.copytree(".specify", os.path.join(archive_dir, ".specify"), dirs_exist_ok=True, symlinks=True)
        files_copied += sum(len(files) for _, _, files in os.walk(".specify"))

    spec_dir = "specs/{}".format(feature)
    if os.path.isdir(spec_dir):
        dest_specs = os.path.join(archive_dir, "specs")
        os.makedirs(dest_specs, exist_ok=True)
        shutil.copytree(spec_dir, os.path.join(dest_specs, feature), dirs_exist_ok=True, symlinks=True)
        files_copied += sum(len(files) for _, _, files in os.walk(spec_dir))

    if os.path.isdir("brainstorm"):
        dest_brainstorm = os.path.join(archive_dir, "brainstorm")
        shutil.copytree("brainstorm", dest_brainstorm, dirs_exist_ok=True, symlinks=True)
        files_copied += sum(len(files) for _, _, files in os.walk("brainstorm"))

    committed = False
    should_commit = auto_commit or read_config(".archive.auto_commit", "true") == "true"
    if should_commit and git_ok("rev-parse", "--git-dir", cwd=target):
        git("add", os.path.join(project, feature), cwd=target)
        if not git_ok("diff", "--cached", "--quiet", cwd=target):
            r = subprocess.run(
                ["git", "commit", "-m", "archive: {}/{} specs\n\nAssisted-By: \U0001f916 Claude Code".format(project, feature), "--quiet"],
                capture_output=True, cwd=target,
            )
            committed = r.returncode == 0

    print(json.dumps({"archive_path": archive_dir, "files_copied": files_copied, "committed": committed}))


COMMANDS = {
    "enable": cmd_enable,
    "disable": cmd_disable,
    "archive": cmd_archive,
    "verify": cmd_verify,
    "ensure": cmd_ensure,
    "is-enabled": lambda a: cmd_is_enabled(),
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print("Usage: spex-detach.py <enable|disable|archive|is-enabled|verify|ensure> [options]", file=sys.stderr)
        sys.exit(1)
    COMMANDS[sys.argv[1]](sys.argv[2:])
