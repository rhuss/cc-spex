#!/usr/bin/env python3
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


def read_exclude_paths():
    if not os.path.isfile(CONFIG_FILE) or shutil.which("yq") is None:
        return list(DEFAULT_EXCLUDE_PATHS)
    r = subprocess.run(
        ["yq", "-r", ".exclude.paths // [] | .[]", CONFIG_FILE],
        capture_output=True, text=True,
    )
    paths = [p for p in r.stdout.strip().split("\n") if p] if r.returncode == 0 else []
    return paths if paths else list(DEFAULT_EXCLUDE_PATHS)


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


def cmd_is_enabled():
    sys.exit(0 if os.path.isdir(".specify/extensions/spex-detach") else 1)


def cmd_enable(args):
    git_common_dir = git("rev-parse", "--git-common-dir")
    if not git_common_dir:
        print("ERROR: Not a git repository", file=sys.stderr)
        sys.exit(1)

    info_dir = os.path.join(git_common_dir, "info")
    os.makedirs(info_dir, exist_ok=True)

    exclude_file = os.path.join(info_dir, "exclude")

    existing_content = ""
    if os.path.isfile(exclude_file):
        with open(exclude_file, "r") as f:
            existing_content = f.read()

    existing_lines = set(existing_content.strip().split("\n")) if existing_content.strip() else set()

    exclude_paths = read_exclude_paths()

    to_add = [p for p in exclude_paths if p not in existing_lines]

    if to_add:
        with open(exclude_file, "a") as f:
            if existing_content and not existing_content.endswith("\n"):
                f.write("\n")
            if not any("spex-detach" in line for line in existing_lines):
                f.write("# spex-detach: spec artifacts excluded from git\n")
            for path in to_add:
                f.write(path + "\n")

    tracked_warnings = []
    for path in exclude_paths:
        clean_path = path.rstrip("/")
        ls_output = git("ls-files", clean_path)
        if ls_output:
            tracked_warnings.append(clean_path)

    result = {
        "exclude_file": exclude_file,
        "paths_configured": exclude_paths,
        "paths_added": to_add,
        "already_present": len(exclude_paths) - len(to_add),
    }

    if tracked_warnings:
        result["tracked_warning"] = tracked_warnings
        print("WARNING: The following paths are already tracked by git and must be removed from history separately: {}".format(
            ", ".join(tracked_warnings)), file=sys.stderr)

    print(json.dumps(result))


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
    "archive": cmd_archive,
    "is-enabled": lambda a: cmd_is_enabled(),
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print("Usage: spex-detach.py <enable|archive|is-enabled> [options]", file=sys.stderr)
        sys.exit(1)
    COMMANDS[sys.argv[1]](sys.argv[2:])
