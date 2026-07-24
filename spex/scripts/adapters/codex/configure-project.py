#!/usr/bin/env python3
"""Probe Codex capabilities and atomically configure a trusted project.

The adapter deliberately does not approximate Spex Autonomous with Codex's
broader workspace-write preset. If the requested policy cannot be expressed,
it returns a safer proposal and requires the caller to confirm it explicitly.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path
from typing import Any


BEGIN_MARKER = "# >>> spex managed Codex security >>>"
END_MARKER = "# <<< spex managed Codex security <<<"
CONTROLLED_KEYS = {"approval_policy", "sandbox_mode", "sandbox_workspace_write"}


class ConfigurationError(Exception):
    """A refusal that must leave project configuration unchanged."""


def absolute_root(value: str) -> Path:
    root = Path(value)
    if not root.is_absolute():
        raise argparse.ArgumentTypeError("--root must be an absolute path")
    try:
        resolved = root.resolve(strict=True)
    except OSError as exc:
        raise argparse.ArgumentTypeError(f"project root is unavailable: {exc}") from exc
    if not resolved.is_dir():
        raise argparse.ArgumentTypeError("--root must name a directory")
    return resolved


def run_codex_probe() -> dict[str, Any]:
    executable = shutil.which("codex")
    if not executable:
        return {
            "codex_available": False,
            "codex_version": None,
            "project_config": False,
            "workspace_write": False,
            "on_request_approval": False,
            "autonomous_allowlist": False,
        }

    version = None
    help_text = ""
    try:
        result = subprocess.run(
            [executable, "--version"], capture_output=True, text=True, timeout=5, check=False
        )
        version = (result.stdout or result.stderr).strip() or None
        result = subprocess.run(
            [executable, "--help"], capture_output=True, text=True, timeout=5, check=False
        )
        help_text = f"{result.stdout}\n{result.stderr}".lower()
    except (OSError, subprocess.TimeoutExpired):
        pass

    has_sandbox = "sandbox" in help_text
    has_approval = "approval" in help_text
    return {
        "codex_available": True,
        "codex_version": version,
        "project_config": has_sandbox and has_approval,
        "workspace_write": "workspace-write" in help_text or has_sandbox,
        "on_request_approval": "on-request" in help_text or has_approval,
        # Codex's workspace preset is broader than Spex Autonomous. No current
        # config-only primitive proves the required enumerated-operation set.
        "autonomous_allowlist": False,
    }


def parse_capability_override(raw: str | None) -> dict[str, Any] | None:
    if raw is None:
        return None
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigurationError(f"invalid --capabilities-json: {exc}") from exc
    if not isinstance(value, dict):
        raise ConfigurationError("--capabilities-json must contain a JSON object")
    defaults = run_codex_probe()
    defaults.update(value)
    return defaults


def capabilities(raw_override: str | None) -> dict[str, Any]:
    return parse_capability_override(raw_override) or run_codex_probe()


def strip_managed_block(content: str) -> tuple[str, bool]:
    begin_count = content.count(BEGIN_MARKER)
    end_count = content.count(END_MARKER)
    if begin_count != end_count or begin_count > 1:
        raise ConfigurationError("malformed Spex-managed block in .codex/config.toml")
    if begin_count == 0:
        return content, False
    pattern = re.compile(
        rf"(?:^|\n){re.escape(BEGIN_MARKER)}\n.*?\n{re.escape(END_MARKER)}(?:\n|$)",
        re.DOTALL,
    )
    stripped, count = pattern.subn("\n", content)
    if count != 1:
        raise ConfigurationError("could not isolate Spex-managed configuration")
    return stripped.strip("\n") + ("\n" if stripped.strip("\n") else ""), True


def parse_unmanaged_toml(content: str) -> dict[str, Any]:
    if not content.strip():
        return {}
    try:
        parsed = tomllib.loads(content)
    except tomllib.TOMLDecodeError as exc:
        raise ConfigurationError(f"existing .codex/config.toml is invalid: {exc}") from exc
    conflicts = sorted(CONTROLLED_KEYS.intersection(parsed))
    if conflicts:
        joined = ", ".join(conflicts)
        raise ConfigurationError(
            f"refusing to replace user-owned Codex security settings: {joined}"
        )
    return parsed


def yolo_block() -> str:
    return "\n".join(
        [
            BEGIN_MARKER,
            '# Effective Spex security: "yolo" (non-destructive workspace operations).',
            '# Requests beyond the workspace and network boundary still require approval.',
            'approval_policy = "on-request"',
            'sandbox_mode = "workspace-write"',
            "",
            "[sandbox_workspace_write]",
            "network_access = false",
            END_MARKER,
            "",
        ]
    )


def desired_content(existing: str, effective: str) -> str:
    unmanaged, had_managed_block = strip_managed_block(existing)
    if effective == "safe":
        if not had_managed_block:
            return existing
        parse_unmanaged_toml(unmanaged)
        return unmanaged
    if effective == "yolo":
        parse_unmanaged_toml(unmanaged)
        separator = "" if not unmanaged else "\n"
        # Root-level security keys must precede any user-owned TOML tables;
        # TOML has no syntax for returning to the root after a table header.
        return f"{yolo_block()}{separator}{unmanaged}"
    raise ConfigurationError(f"unsupported effective security level: {effective}")


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    previous_mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
        ) as stream:
            temporary = stream.name
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, previous_mode)
        os.replace(temporary, path)
        temporary = None
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)


def supported_yolo(observed: dict[str, Any]) -> bool:
    return all(
        observed.get(key) is True
        for key in ("project_config", "workspace_write", "on_request_approval")
    )


def proposal(requested: str, observed: dict[str, Any]) -> tuple[str, str | None]:
    if requested == "safe":
        return "safe", None
    if requested == "autonomous":
        if observed.get("autonomous_allowlist") is True:
            # Reserved until Codex exposes a config-only primitive matching the
            # enumerated Spex operation set. Never broaden it to YOLO here.
            return "safe", "Autonomous mapping is not implemented safely by this adapter"
        return "safe", "Codex project config cannot express Spex's enumerated Autonomous allowlist"
    if requested == "yolo" and supported_yolo(observed):
        return "yolo", None
    return "safe", "Codex does not expose the bounded workspace-write capabilities required for YOLO"


def emit(payload: dict[str, Any]) -> None:
    json.dump(payload, sys.stdout, sort_keys=True, separators=(",", ":"))
    sys.stdout.write("\n")


def configure(args: argparse.Namespace) -> int:
    observed = capabilities(args.capabilities_json)
    effective, fallback_reason = proposal(args.security, observed)
    config_path = args.root / ".codex" / "config.toml"
    existing = config_path.read_text(encoding="utf-8") if config_path.exists() else ""

    if fallback_reason and args.confirm_fallback != effective:
        emit(
            {
                "status": "confirmation_required",
                "requested_security": args.security,
                "proposed_security": effective,
                "reason": fallback_reason,
                "config_changed": False,
                "capabilities": observed,
            }
        )
        return 3

    updated = desired_content(existing, effective)
    changed = updated != existing
    if changed:
        atomic_write(config_path, updated)
    emit(
        {
            "status": "configured",
            "requested_security": args.security,
            "effective_security": effective,
            "fallback_confirmed": fallback_reason is not None,
            "reason": fallback_reason,
            "config_changed": changed,
            "config_path": str(config_path),
            "trusted_project_required": True,
            "capabilities": observed,
        }
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    probe_parser = subparsers.add_parser("probe", help="report observed Codex capabilities")
    probe_parser.add_argument("--root", required=True, type=absolute_root)
    probe_parser.add_argument("--capabilities-json")

    configure_parser = subparsers.add_parser(
        "configure", help="atomically apply a confirmed project security mapping"
    )
    configure_parser.add_argument("--root", required=True, type=absolute_root)
    configure_parser.add_argument(
        "--security", required=True, choices=("safe", "autonomous", "yolo")
    )
    configure_parser.add_argument(
        "--confirm-fallback", choices=("safe", "autonomous", "yolo")
    )
    configure_parser.add_argument("--capabilities-json")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        if args.command == "probe":
            emit(
                {
                    "status": "probed",
                    "root": str(args.root),
                    "trusted_project_required": True,
                    "capabilities": capabilities(args.capabilities_json),
                }
            )
            return 0
        return configure(args)
    except (ConfigurationError, OSError) as exc:
        emit({"status": "refused", "error": str(exc), "config_changed": False})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
