#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import sys


DEFAULT_STRIP_PATHS = [".specify", "specs", "brainstorm"]


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


def read_strip_paths():
    if not os.path.isfile(CONFIG_FILE) or shutil.which("yq") is None:
        return list(DEFAULT_STRIP_PATHS)
    r = subprocess.run(
        ["yq", "-r", ".detach.strip_paths // [] | .[]", CONFIG_FILE],
        capture_output=True, text=True,
    )
    paths = [p for p in r.stdout.strip().split("\n") if p] if r.returncode == 0 else []
    return paths if paths else [".specify", "specs", "brainstorm"]


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


def detect_upstream_default(config_branch):
    if config_branch:
        return config_branch

    ref = git("symbolic-ref", "refs/remotes/upstream/HEAD")
    if ref:
        return ref.split("/")[-1]

    r = subprocess.run(["git", "remote", "show", "upstream"], capture_output=True, text=True)
    if r.returncode == 0:
        for line in r.stdout.split("\n"):
            if "HEAD branch:" in line:
                return line.split("HEAD branch:")[-1].strip()

    ref = git("symbolic-ref", "refs/remotes/origin/HEAD")
    if ref:
        return ref.split("/")[-1]

    r = subprocess.run(["git", "remote", "show", "origin"], capture_output=True, text=True)
    if r.returncode == 0:
        for line in r.stdout.split("\n"):
            if "HEAD branch:" in line:
                return line.split("HEAD branch:")[-1].strip()

    return "main"


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


def cmd_is_enabled():
    sys.exit(0 if os.path.isdir(".specify/extensions/spex-detach") else 1)


def cmd_clean_branch_name(args):
    branch = ""
    i = 0
    while i < len(args):
        if args[i] == "--branch":
            require_arg("--branch", len(args) - i)
            branch = args[i + 1]; i += 2
        else:
            i += 1
    if not branch:
        branch = git("branch", "--show-current")
    if not branch:
        print("ERROR: Could not determine branch name", file=sys.stderr)
        sys.exit(1)
    print("pr/{}".format(branch))


def check_gitignore():
    """Check if .gitignore includes SpecKit paths when upstream remote exists. Non-blocking advisory."""
    # Only check when an upstream remote exists (fork detection)
    remotes = git("remote")
    if not remotes or "upstream" not in remotes.split("\n"):
        return

    speckit_paths = list(DEFAULT_STRIP_PATHS)
    gitignore_content = ""
    if os.path.isfile(".gitignore"):
        with open(".gitignore", "r") as f:
            gitignore_content = f.read()

    missing = []
    for path in speckit_paths:
        # Check for the path with or without trailing slash
        found = False
        for line in gitignore_content.split("\n"):
            line = line.strip()
            if line == path or line == path + "/" or line == "/" + path or line == "/" + path + "/":
                found = True
                break
        if not found:
            missing.append(path + "/")

    if missing:
        print("WARNING: .gitignore is missing SpecKit paths (recommended for fork workflows): {}".format(
            ", ".join(missing)), file=sys.stderr)


def cmd_detach(args):
    branch = ""
    base = ""
    strip_args = []

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--branch":
            require_arg("--branch", len(args) - i)
            branch = args[i + 1]; i += 2
        elif a == "--base":
            require_arg("--base", len(args) - i)
            base = args[i + 1]; i += 2
        elif a == "--strip":
            i += 1
            while i < len(args) and not args[i].startswith("--"):
                strip_args.append(args[i]); i += 1
        else:
            i += 1

    if not branch:
        branch = git("branch", "--show-current")
    if not branch:
        json.dump({"error": "Could not determine feature branch"}, sys.stderr)
        print(file=sys.stderr)
        sys.exit(1)

    # Guard: dirty working tree
    if not git_ok("diff", "--quiet") or not git_ok("diff", "--cached", "--quiet"):
        json.dump({"error": "Working tree has uncommitted changes. Commit or stash before detaching."}, sys.stderr)
        print(file=sys.stderr)
        sys.exit(1)

    # Non-blocking .gitignore advisory (FR-008)
    check_gitignore()

    if not base:
        config_default = read_config(".upstream.default_branch", "")
        base = detect_upstream_default(config_default)

    resolved_base = base
    if git_ok("rev-parse", "--verify", "origin/{}".format(base)):
        resolved_base = "origin/{}".format(base)

    strip_paths = strip_args if strip_args else read_strip_paths()

    merge_base = git("merge-base", resolved_base, branch)
    if not merge_base:
        json.dump({"error": "Could not compute merge-base between {} and {}".format(resolved_base, branch)}, sys.stderr)
        print(file=sys.stderr)
        sys.exit(1)

    pr_branch = "pr/{}".format(branch)

    pathspec_excludes = [":(exclude){}".format(p) for p in strip_paths]
    diff_cmd = ["git", "diff", "--binary", "{}..{}".format(merge_base, branch), "--", "."] + pathspec_excludes
    r = subprocess.run(diff_cmd, capture_output=True)
    if r.returncode != 0:
        json.dump({"error": "Failed to generate diff"}, sys.stderr)
        print(file=sys.stderr)
        sys.exit(1)

    diff_output = r.stdout
    if not diff_output.strip():
        print(json.dumps({"pr_branch": pr_branch, "merge_base": merge_base, "commit": "", "files_changed": 0, "empty": True}))
        sys.exit(2)

    # Delete existing PR branch
    git("branch", "-D", pr_branch)

    original_branch = branch

    def cleanup_pr_branch():
        subprocess.run(["git", "checkout", original_branch, "--quiet"], capture_output=True)
        git("branch", "-D", pr_branch)

    try:
        r = subprocess.run(["git", "checkout", "-b", pr_branch, merge_base, "--quiet"], capture_output=True, text=True)
        if r.returncode != 0:
            cleanup_pr_branch()
            json.dump({"error": "Failed to create PR branch", "details": r.stderr.strip()}, sys.stderr)
            print(file=sys.stderr)
            sys.exit(1)

        p = subprocess.run(["git", "apply", "--index"], input=diff_output, capture_output=True)
        if p.returncode != 0:
            details = p.stderr.decode("utf-8", errors="replace").strip() if isinstance(p.stderr, bytes) else (p.stderr or "").strip()
            cleanup_pr_branch()
            json.dump({"error": "Failed to apply filtered diff", "details": details}, sys.stderr)
            print(file=sys.stderr)
            sys.exit(1)

        diff_names = git("diff", "--cached", "--name-only")
        files_changed = len([f for f in diff_names.split("\n") if f.strip()]) if diff_names else 0

        log_cmd = ["git", "log", "--format=%s", "{}..{}".format(merge_base, original_branch), "--", "."] + pathspec_excludes
        r = subprocess.run(log_cmd, capture_output=True, text=True)
        commit_subject = r.stdout.strip().split("\n")[0] if r.returncode == 0 and r.stdout.strip() else ""
        if not commit_subject:
            commit_subject = "feat: {}".format(original_branch.replace("-", " ").replace("_", " "))

        cr = subprocess.run(["git", "commit", "-m", commit_subject, "--quiet"], capture_output=True)
        if cr.returncode != 0:
            cleanup_pr_branch()
            json.dump({"error": "Failed to commit on PR branch"}, sys.stderr)
            print(file=sys.stderr)
            sys.exit(1)

        commit_sha = git("rev-parse", "HEAD")

        leaked = scan_for_leaks(strip_paths, merge_base, pr_branch)

        if leaked:
            cleanup_pr_branch()
            json.dump({
                "error": "Post-detach verification failed: SpecKit artifacts leaked to PR branch",
                "leaked_files": leaked,
                "patterns_checked": [sp.rstrip("/") + "/" for sp in strip_paths],
            }, sys.stderr)
            print(file=sys.stderr)
            sys.exit(1)

        subprocess.run(["git", "checkout", original_branch, "--quiet"], capture_output=True)

        print(json.dumps({
            "pr_branch": pr_branch,
            "merge_base": merge_base,
            "commit": commit_sha,
            "files_changed": files_changed,
            "empty": False,
            "verified": True,
        }))
    except BaseException:
        subprocess.run(["git", "checkout", original_branch, "--quiet"], capture_output=True, text=True)
        git("branch", "-D", pr_branch)
        raise


def cmd_archive(args):
    target = ""
    project = ""
    feature = ""
    auto_commit = False
    move = False
    include_brainstorm = False

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
        elif a == "--move":
            move = True; i += 1
        elif a == "--include-brainstorm":
            include_brainstorm = True; i += 1
        else:
            i += 1

    if not target:
        target = read_config(".archive.path", "")
    if not target:
        json.dump({"error": "No archive target specified. Set archive.path in spex-detach-config.yml or use --target"}, sys.stderr)
        print(file=sys.stderr)
        sys.exit(1)
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
    source_dirs_to_delete = []

    if os.path.isdir(".specify"):
        shutil.copytree(".specify", os.path.join(archive_dir, ".specify"), dirs_exist_ok=True, symlinks=True)
        files_copied += sum(len(files) for _, _, files in os.walk(".specify"))
        # Note: .specify/ deletion is deferred (not added to source_dirs_to_delete)
        # to avoid breaking post-completion hooks that reference .specify/

    spec_dir = "specs/{}".format(feature)
    if os.path.isdir(spec_dir):
        dest_specs = os.path.join(archive_dir, "specs")
        os.makedirs(dest_specs, exist_ok=True)
        shutil.copytree(spec_dir, os.path.join(dest_specs, feature), dirs_exist_ok=True, symlinks=True)
        files_copied += sum(len(files) for _, _, files in os.walk(spec_dir))
        if move:
            source_dirs_to_delete.append(spec_dir)

    if include_brainstorm and os.path.isdir("brainstorm"):
        dest_brainstorm = os.path.join(archive_dir, "brainstorm")
        shutil.copytree("brainstorm", dest_brainstorm, dirs_exist_ok=True, symlinks=True)
        files_copied += sum(len(files) for _, _, files in os.walk("brainstorm"))
        if move:
            source_dirs_to_delete.append("brainstorm")

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

    # Move semantics: delete source directories after successful archive
    source_deleted = False
    if move and committed:
        delete_warnings = []
        for src_dir in source_dirs_to_delete:
            try:
                shutil.rmtree(src_dir)
            except OSError as e:
                delete_warnings.append("{}: {}".format(src_dir, str(e)))
        source_deleted = len(delete_warnings) == 0
        if delete_warnings:
            for w in delete_warnings:
                print("WARNING: Failed to delete source directory: {}".format(w), file=sys.stderr)

    result = {"archive_path": archive_dir, "files_copied": files_copied, "committed": committed}
    if move:
        result["source_deleted"] = source_deleted
    print(json.dumps(result))


def scan_for_leaks(strip_paths, base, branch):
    """Scan git diff for leaked SpecKit artifacts. Returns list of leaked file paths.
    Raises RuntimeError if git diff fails (prevents false-clean results)."""
    patterns = build_fingerprint_patterns(strip_paths)
    r = subprocess.run(
        ["git", "diff", "--name-only", "{}..{}".format(base, branch)],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        raise RuntimeError("git diff failed for {}..{}: {}".format(base, branch, r.stderr.strip()))
    diff_files = r.stdout.strip()
    leaked = []
    if diff_files:
        for f in diff_files.split("\n"):
            f = f.strip()
            if not f:
                continue
            for pat in patterns:
                if pat.search(f):
                    leaked.append(f)
                    break
    return leaked


def build_fingerprint_patterns(strip_paths):
    """Build regex patterns from strip_paths for SpecKit fingerprint detection."""
    patterns = []
    for sp in strip_paths:
        sp_clean = sp.rstrip("/")
        patterns.append(re.compile(r"^" + re.escape(sp_clean) + r"/"))
    return patterns


def cmd_verify(args):
    branch = ""
    base = ""

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--branch":
            require_arg("--branch", len(args) - i)
            branch = args[i + 1]; i += 2
        elif a == "--base":
            require_arg("--base", len(args) - i)
            base = args[i + 1]; i += 2
        else:
            i += 1

    if not branch or not base:
        print("ERROR: --branch and --base are required for verify", file=sys.stderr)
        sys.exit(1)

    strip_paths = read_strip_paths()
    try:
        leaked = scan_for_leaks(strip_paths, base, branch)
    except RuntimeError as e:
        json.dump({"error": str(e)}, sys.stderr)
        print(file=sys.stderr)
        sys.exit(1)

    result = {
        "clean": len(leaked) == 0,
        "leaked_files": leaked,
        "patterns_checked": [sp.rstrip("/") + "/" for sp in strip_paths],
    }
    print(json.dumps(result))
    sys.exit(0 if result["clean"] else 1)


COMMANDS = {
    "detach": cmd_detach,
    "archive": cmd_archive,
    "verify": cmd_verify,
    "is-enabled": lambda a: cmd_is_enabled(),
    "clean-branch-name": cmd_clean_branch_name,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print("Usage: spex-detach.py <detach|archive|verify|is-enabled|clean-branch-name> [options]", file=sys.stderr)
        sys.exit(1)
    COMMANDS[sys.argv[1]](sys.argv[2:])
