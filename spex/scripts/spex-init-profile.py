#!/usr/bin/env python3
"""Create, validate, and atomically persist Spex InitializationProfiles."""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import Any


SCHEMA_VERSION = "1.0.0"
PROFILE_RELATIVE_PATH = Path(".specify/spex-profile.yml")
HARNESSES = {"claude", "codex", "opencode"}
SECURITY_LEVELS = {"safe": 0, "autonomous": 1, "yolo": 2}
EXTENSION_PATTERN = re.compile(r"^spex(?:-[a-z0-9-]+)?$")
REQUIRED_FIELDS = {
    "schema_version",
    "active_harness",
    "enabled_extensions",
    "requested_security",
    "effective_security",
    "capabilities",
    "config_revision",
    "updated_at",
}
EXTENSION_DEPENDENCIES = {
    "spex-deep-review": {"spex-gates"},
    "spex-teams": {"spex-gates"},
    "spex-collab": {"spex-gates"},
}


class ProfileError(Exception):
    """Expected profile or command failure."""


def fail(message: str) -> None:
    raise ProfileError(message)


def resolve_root(raw_root: str) -> Path:
    root = Path(raw_root)
    if not root.is_absolute():
        fail("--root must be an absolute directory")
    if not root.is_dir():
        fail(f"repository root is not an existing directory: {root}")
    return root.resolve()


def profile_path(root: Path) -> Path:
    return root / PROFILE_RELATIVE_PATH


def read_json_stream() -> dict[str, Any]:
    try:
        value = json.load(sys.stdin)
    except json.JSONDecodeError as error:
        fail(f"stdin is not valid JSON: {error.msg}")
    if not isinstance(value, dict):
        fail("profile input must be a JSON object")
    return value


def read_profile(root: Path, *, required: bool = True) -> dict[str, Any] | None:
    path = profile_path(root)
    if not path.is_file():
        if required:
            fail(f"initialization profile does not exist: {path}")
        return None
    try:
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read initialization profile {path}: {error}")
    if not isinstance(value, dict):
        fail(f"initialization profile must contain a JSON object: {path}")
    validate_profile(value)
    return value


def validate_timestamp(value: Any) -> None:
    if not isinstance(value, str):
        fail("updated_at must be an RFC 3339 timestamp")
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError:
        fail("updated_at must be an RFC 3339 timestamp")
    if parsed.tzinfo is None:
        fail("updated_at must include a UTC offset")


def validate_extensions(value: Any) -> None:
    if not isinstance(value, list) or not value:
        fail("enabled_extensions must be a nonempty array")
    if any(not isinstance(item, str) or not EXTENSION_PATTERN.fullmatch(item) for item in value):
        fail("enabled_extensions contains an invalid extension identifier")
    if len(set(value)) != len(value):
        fail("enabled_extensions must not contain duplicates")
    enabled = set(value)
    if "spex" not in enabled:
        fail("enabled_extensions must include spex")
    for extension, dependencies in EXTENSION_DEPENDENCIES.items():
        missing = dependencies - enabled
        if extension in enabled and missing:
            fail(f"{extension} requires: {', '.join(sorted(missing))}")


def validate_profile(profile: dict[str, Any]) -> dict[str, Any]:
    fields = set(profile)
    missing = REQUIRED_FIELDS - fields
    extra = fields - REQUIRED_FIELDS
    if missing:
        fail(f"profile is missing required fields: {', '.join(sorted(missing))}")
    if extra:
        fail(f"profile contains unknown fields: {', '.join(sorted(extra))}")
    if profile["schema_version"] != SCHEMA_VERSION:
        fail(f"schema_version must be {SCHEMA_VERSION}")
    if profile["active_harness"] not in HARNESSES:
        fail("active_harness must be claude, codex, or opencode")
    validate_extensions(profile["enabled_extensions"])

    requested = profile["requested_security"]
    effective = profile["effective_security"]
    if requested not in SECURITY_LEVELS or effective not in SECURITY_LEVELS:
        fail("requested_security and effective_security must be safe, autonomous, or yolo")
    if SECURITY_LEVELS[effective] > SECURITY_LEVELS[requested]:
        fail("effective_security cannot be less safe than requested_security")
    if not isinstance(profile["capabilities"], dict):
        fail("capabilities must be an object")
    revision = profile["config_revision"]
    if isinstance(revision, bool) or not isinstance(revision, int) or revision < 1:
        fail("config_revision must be an integer greater than zero")
    validate_timestamp(profile["updated_at"])
    return profile


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def emit(profile: dict[str, Any]) -> None:
    json.dump(profile, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def command_load(args: argparse.Namespace) -> None:
    root = resolve_root(args.root)
    profile = read_profile(root)
    if profile is None:  # read_profile(required=True) cannot return None.
        fail("initialization profile is absent")
    emit(profile)


def parse_capabilities(raw: str) -> dict[str, Any]:
    try:
        capabilities = json.loads(raw)
    except json.JSONDecodeError as error:
        fail(f"--capabilities-json is not valid JSON: {error.msg}")
    if not isinstance(capabilities, dict):
        fail("--capabilities-json must contain an object")
    return capabilities


def command_propose(args: argparse.Namespace) -> None:
    root = resolve_root(args.root)
    current = read_profile(root, required=False)
    revision = 1 if current is None else current["config_revision"] + 1
    profile = {
        "schema_version": SCHEMA_VERSION,
        "active_harness": args.harness,
        "enabled_extensions": sorted(set(args.extension)),
        "requested_security": args.requested_security,
        "effective_security": args.effective_security,
        "capabilities": parse_capabilities(args.capabilities_json),
        "config_revision": revision,
        "updated_at": utc_now(),
    }
    emit(validate_profile(profile))


def command_validate(args: argparse.Namespace) -> None:
    resolve_root(args.root)
    emit(validate_profile(read_json_stream()))


def write_atomic(root: Path, profile: dict[str, Any], expected_revision: int) -> None:
    destination = profile_path(root)
    directory = destination.parent
    directory.mkdir(mode=0o755, parents=True, exist_ok=True)
    directory_fd = os.open(directory, os.O_RDONLY)
    temporary_path: Path | None = None
    try:
        fcntl.flock(directory_fd, fcntl.LOCK_EX)
        current = read_profile(root, required=False)
        current_revision = 0 if current is None else current["config_revision"]
        if current_revision != expected_revision:
            fail(
                f"config revision conflict: expected {expected_revision}, "
                f"found {current_revision}"
            )
        if profile["config_revision"] != current_revision + 1:
            fail(
                "profile config_revision must be exactly one greater than "
                "the persisted revision"
            )

        file_descriptor, raw_path = tempfile.mkstemp(
            dir=directory, prefix=".spex-profile.", suffix=".tmp"
        )
        temporary_path = Path(raw_path)
        try:
            with os.fdopen(file_descriptor, "w", encoding="utf-8") as handle:
                json.dump(profile, handle, indent=2, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary_path, 0o600)
            os.replace(temporary_path, destination)
            temporary_path = None
            os.fsync(directory_fd)
        except Exception:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)
            raise
    finally:
        fcntl.flock(directory_fd, fcntl.LOCK_UN)
        os.close(directory_fd)


def command_persist(args: argparse.Namespace) -> None:
    root = resolve_root(args.root)
    profile = validate_profile(read_json_stream())
    if profile["requested_security"] != profile["effective_security"]:
        if args.fallback_confirmation != "accept":
            fail("a safer effective security fallback requires explicit acceptance")
    write_atomic(root, profile, args.expected_revision)
    emit(profile)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    load = subparsers.add_parser("load", help="load the persisted profile")
    load.add_argument("--root", required=True)
    load.set_defaults(handler=command_load)

    propose = subparsers.add_parser("propose", help="create the next profile revision")
    propose.add_argument("--root", required=True)
    propose.add_argument("--harness", required=True, choices=sorted(HARNESSES))
    propose.add_argument("--extension", action="append", required=True)
    propose.add_argument("--requested-security", required=True, choices=SECURITY_LEVELS)
    propose.add_argument("--effective-security", required=True, choices=SECURITY_LEVELS)
    propose.add_argument("--capabilities-json", default="{}")
    propose.set_defaults(handler=command_propose)

    validate = subparsers.add_parser("validate", help="validate a profile from stdin")
    validate.add_argument("--root", required=True)
    validate.set_defaults(handler=command_validate)

    persist = subparsers.add_parser("persist", help="persist a profile from stdin")
    persist.add_argument("--root", required=True)
    persist.add_argument("--expected-revision", required=True, type=int)
    persist.add_argument(
        "--fallback-confirmation", choices=("accept", "decline"), default="decline"
    )
    persist.set_defaults(handler=command_persist)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if getattr(args, "expected_revision", 0) < 0:
        fail("--expected-revision must not be negative")
    args.handler(args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProfileError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
