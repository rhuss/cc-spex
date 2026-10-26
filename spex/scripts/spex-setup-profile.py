#!/usr/bin/env python3
"""Resolve and atomically persist the team-owned Spex setup declaration."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import tempfile
from typing import Any


PROFILE = Path(".specify/spex.json")
HARNESSES = {"auto", "claude", "codex", "opencode"}
EXTENSIONS = {
    "spex", "spex-gates", "spex-worktrees", "spex-deep-review",
    "spex-teams", "spex-collab", "spex-detach",
}
DEPENDENCIES = {
    "spex-deep-review": {"spex-gates"},
    "spex-teams": {"spex-gates"},
    "spex-collab": {"spex-gates"},
}
SECURITY = {"safe", "autonomous", "yolo"}
DEFAULT = {
    "schema_version": 1,
    "harness": "auto",
    "extensions": ["spex", "spex-gates", "spex-worktrees", "spex-deep-review"],
    "security": "safe",
}
LEGACY_SECURITY = {"none": "safe", "standard": "autonomous", "yolo": "yolo"}
FIELDS = set(DEFAULT)
# Optional fields: kept by validate/resolve/persist only when present.
# codex_progress records a declined Codex footer/title setup question.
OPTIONAL = {"codex_progress": {"declined"}}
# Optional extensions per selection mode. `all` leaves out spex-detach, which
# is opt-in and enabled only when named explicitly.
MODES = {
    "recommended": ["spex-gates", "spex-worktrees", "spex-deep-review"],
    "all": [
        "spex-gates", "spex-worktrees", "spex-deep-review",
        "spex-teams", "spex-collab",
    ],
}
MIGRATED_DETACH = (
    "Migrated: removed spex-detach from .specify/spex.json "
    "(it was disabled; select it explicitly to enable it)"
)


class ProfileError(Exception):
    """Report invalid or inaccessible setup profile data."""

    pass


def fail(message: str) -> None:
    """Raise a setup-profile validation error."""

    raise ProfileError(message)


def root_path(raw: str) -> Path:
    """Return a validated absolute project root."""

    root = Path(raw)
    if not root.is_absolute() or not root.is_dir():
        fail("--root must be an existing absolute directory")
    return root.resolve()


def normalize_extensions(value: Any) -> list[str]:
    """Validate extensions, add dependencies, and return canonical order."""

    if not isinstance(value, list) or not value:
        fail("extensions must be a nonempty array")
    if any(not isinstance(item, str) for item in value):
        fail("extensions contains an unknown extension")
    unknown = [item for item in value if item not in EXTENSIONS]
    if unknown:
        fail(f"extensions contains an unknown extension: {', '.join(unknown)}")
    enabled = set(value)
    if "spex" not in enabled:
        fail("extensions must include spex")
    for extension, required in DEPENDENCIES.items():
        if extension in enabled:
            enabled.update(required)
    order = [*DEFAULT["extensions"], "spex-teams", "spex-collab", "spex-detach"]
    return [extension for extension in order if extension in enabled]


def validate(value: Any) -> dict[str, Any]:
    """Validate and canonicalize a complete setup declaration."""

    if not isinstance(value, dict):
        fail("configuration must be a JSON object")
    missing = FIELDS - set(value)
    extra = set(value) - FIELDS - set(OPTIONAL)
    if missing:
        fail(f"configuration is missing: {', '.join(sorted(missing))}")
    if extra:
        fail(f"configuration contains unknown fields: {', '.join(sorted(extra))}")
    if value["schema_version"] != 1:
        fail("schema_version must be 1")
    if not isinstance(value["harness"], str) or value["harness"] not in HARNESSES:
        fail("harness must be auto, claude, codex, or opencode")
    if not isinstance(value["security"], str) or value["security"] not in SECURITY:
        fail("security must be safe, autonomous, or yolo")
    for field, allowed in OPTIONAL.items():
        if field in value and (not isinstance(value[field], str) or value[field] not in allowed):
            fail(f"{field} must be {', '.join(sorted(allowed))}")
    result = {
        "schema_version": 1,
        "harness": value["harness"],
        "extensions": normalize_extensions(value["extensions"]),
        "security": value["security"],
    }
    for field in OPTIONAL:
        if field in value:
            result[field] = value[field]
    return result


def read_json(stream) -> dict[str, Any]:
    """Read a JSON object from a text stream with a stable error message."""

    try:
        return json.load(stream)
    except json.JSONDecodeError as error:
        fail(f"invalid JSON: {error.msg}")


def load(root: Path) -> dict[str, Any] | None:
    """Load a stored declaration, or return None when it is absent."""

    path = root / PROFILE
    if not path.exists():
        return None
    try:
        with path.open(encoding="utf-8") as stream:
            return validate(read_json(stream))
    except OSError as error:
        fail(f"cannot read {path}: {error}")


def emit(value: dict[str, Any]) -> None:
    """Write a canonical declaration to standard output."""

    json.dump(value, sys.stdout, indent=2)
    sys.stdout.write("\n")


def parse_extension_argument(raw: str) -> list[str]:
    """Parse a comma-separated workflow extension input."""

    return [item.strip() for item in raw.split(",") if item.strip()]


def mode_extensions(mode: str, reply: str) -> list[str]:
    """Map a selection mode (and an interactive reply) to optional extensions."""

    if mode != "interactive":
        return list(MODES[mode])
    # Agents often quote names or wrap them in backticks; names never contain
    # quotes or whitespace, so both act as separators like commas.
    answer = reply
    for quote in ('"', "'", "`"):
        answer = answer.replace(quote, " ")
    names = answer.replace(",", " ").split()
    if not names:
        return list(MODES["recommended"])
    if len(names) == 1 and names[0].lower() == "all":
        return list(MODES["all"])
    return names


def resolve(args: argparse.Namespace) -> None:
    """Resolve explicit inputs over stored values and defaults."""

    if args.mode and args.extensions:
        fail("--mode and --extensions are mutually exclusive")
    if args.reply and args.mode != "interactive":
        fail("--reply requires --mode interactive")
    root = root_path(args.root)
    stored = load(root) or DEFAULT
    security = args.security
    if not security and args.legacy_permissions:
        security = LEGACY_SECURITY[args.legacy_permissions]
    if args.mode:
        extensions = ["spex", *mode_extensions(args.mode, args.reply)]
    elif args.extensions:
        extensions = ["spex", *parse_extension_argument(args.extensions)]
    else:
        extensions = stored["extensions"]
    candidate = {
        "schema_version": 1,
        "harness": args.harness or stored["harness"],
        "extensions": extensions,
        "security": security or stored["security"],
    }
    for field in OPTIONAL:
        if field in stored:
            candidate[field] = stored[field]
    emit(validate(candidate))


def write_atomic(root: Path, value: dict[str, Any]) -> None:
    """Atomically write a validated declaration below the project root."""

    destination = root / PROFILE
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, raw_temporary = tempfile.mkstemp(
        dir=destination.parent, prefix=".spex.", suffix=".tmp"
    )
    temporary = Path(raw_temporary)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def persist(args: argparse.Namespace) -> None:
    """Atomically persist a validated declaration below the project root."""

    root = root_path(args.root)
    value = validate(read_json(sys.stdin))
    write_atomic(root, value)
    emit(value)


def snapshot_disabled(path: Path, extension: str) -> bool:
    """Return True when a registry snapshot shows the extension disabled."""

    try:
        with path.open(encoding="utf-8") as stream:
            registry = json.load(stream)
    except (OSError, json.JSONDecodeError):
        return False
    if not isinstance(registry, dict):
        return False
    entries = registry.get("extensions")
    if not isinstance(entries, dict):
        return False
    entry = entries.get(extension)
    return isinstance(entry, dict) and entry.get("enabled") is False


def migrate_detach(args: argparse.Namespace) -> None:
    """Drop spex-detach from a legacy declaration when it was left disabled.

    Earlier `all` runs listed spex-detach in the declaration while leaving the
    extension disabled. Applying such a declaration would switch stealth mode
    on, so the entry is removed instead and the removal is reported.
    """

    try:
        root = root_path(args.root)
    except ProfileError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2) from error
    stored = load(root)
    if stored is None or "spex-detach" not in stored["extensions"]:
        return
    if not snapshot_disabled(Path(args.before), "spex-detach"):
        return
    migrated = {
        **stored,
        "extensions": [e for e in stored["extensions"] if e != "spex-detach"],
    }
    write_atomic(root, validate(migrated))
    print(MIGRATED_DETACH, file=sys.stderr)


def decline_codex_progress(args: argparse.Namespace) -> None:
    """Record that the Codex footer/title setup question was declined."""

    root = root_path(args.root)
    stored = load(root) or DEFAULT
    value = validate({**stored, "codex_progress": "declined"})
    write_atomic(root, value)
    emit(value)


def validate_command(args: argparse.Namespace) -> None:
    """Validate a declaration received on standard input."""

    root_path(args.root)
    emit(validate(read_json(sys.stdin)))


def parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""

    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(required=True)
    resolve_parser = commands.add_parser("resolve")
    resolve_parser.add_argument("--root", required=True)
    resolve_parser.add_argument("--harness", choices=sorted(HARNESSES), default="")
    resolve_parser.add_argument("--extensions", default="")
    resolve_parser.add_argument(
        "--mode", choices=["recommended", "all", "interactive"], default=""
    )
    resolve_parser.add_argument("--reply", default="")
    resolve_parser.add_argument("--security", choices=sorted(SECURITY), default="")
    resolve_parser.add_argument(
        "--legacy-permissions", choices=sorted(LEGACY_SECURITY), default=""
    )
    resolve_parser.set_defaults(handler=resolve)
    persist_parser = commands.add_parser("persist")
    persist_parser.add_argument("--root", required=True)
    persist_parser.set_defaults(handler=persist)
    validate_parser = commands.add_parser("validate")
    validate_parser.add_argument("--root", required=True)
    validate_parser.set_defaults(handler=validate_command)
    migrate_parser = commands.add_parser("migrate-detach")
    migrate_parser.add_argument("--root", required=True)
    migrate_parser.add_argument("--before", required=True)
    migrate_parser.set_defaults(handler=migrate_detach)
    decline_parser = commands.add_parser("decline-codex-progress")
    decline_parser.add_argument("--root", required=True)
    decline_parser.set_defaults(handler=decline_codex_progress)
    return result


def main() -> int:
    """Run the requested setup-profile operation."""

    args = parser().parse_args()
    args.handler(args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProfileError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error
