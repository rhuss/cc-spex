#!/usr/bin/env python3
"""Test-first safety contract for bounded Codex subagent assignments."""

from __future__ import annotations

import json
from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
FEATURE = REPO_ROOT / "specs/047-codex-plugin-support"
SCHEMA_PATH = FEATURE / "contracts/subagent-assignment.schema.json"
VALID_PATH = REPO_ROOT / "tests/fixtures/contracts/subagent-assignment/valid.json"
INVALID_PATH = REPO_ROOT / "tests/fixtures/contracts/subagent-assignment/invalid.json"
TEAMS_COMMANDS = REPO_ROOT / "spex/extensions/spex-teams/commands"
ORCHESTRATE_PATH = TEAMS_COMMANDS / "speckit.spex-teams.orchestrate.md"
IMPLEMENT_PATH = TEAMS_COMMANDS / "speckit.spex-teams.implement.md"
RESEARCH_PATH = TEAMS_COMMANDS / "speckit.spex-teams.research.md"


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"{path} must contain a JSON object")
    return value


def contract_errors(value: dict, schema: dict) -> list[str]:
    """Validate the deliberately small SubagentAssignment schema vocabulary."""
    errors: list[str] = []
    properties = schema["properties"]
    for name in schema["required"]:
        if name not in value:
            errors.append(f"missing {name}")
    if schema.get("additionalProperties") is False:
        errors.extend(f"unknown {name}" for name in value.keys() - properties.keys())
    for name, rule in properties.items():
        if name not in value:
            continue
        item = value[name]
        if "const" in rule and item != rule["const"]:
            errors.append(f"{name} const")
        if "enum" in rule and item not in rule["enum"]:
            errors.append(f"{name} enum")
        if rule.get("type") == "string":
            if not isinstance(item, str):
                errors.append(f"{name} type")
            elif len(item) < rule.get("minLength", 0):
                errors.append(f"{name} length")
            elif "pattern" in rule and re.search(rule["pattern"], item) is None:
                errors.append(f"{name} pattern")
        if rule.get("type") == "array":
            if not isinstance(item, list):
                errors.append(f"{name} type")
            else:
                if len(item) < rule.get("minItems", 0):
                    errors.append(f"{name} length")
                if rule.get("items", {}).get("type") == "string" and not all(
                    isinstance(entry, str) for entry in item
                ):
                    errors.append(f"{name} items")
        if rule.get("type") == "boolean" and not isinstance(item, bool):
            errors.append(f"{name} type")
    if value.get("kind") == "write" and "isolated_worktree" not in value:
        errors.append("missing isolated_worktree")
    return errors


def normalized(path: Path) -> str:
    return " ".join(path.read_text(encoding="utf-8").lower().split())


class AssignmentSchemaTests(unittest.TestCase):
    def setUp(self):
        self.schema = load_json(SCHEMA_PATH)
        self.valid = load_json(VALID_PATH)
        self.invalid = load_json(INVALID_PATH)

    def test_assignment_schema_and_fixtures_enforce_the_bounded_contract(self):
        self.assertEqual(contract_errors(self.valid, self.schema), [])
        errors = contract_errors(self.invalid, self.schema)
        self.assertTrue(errors, "invalid assignment fixture unexpectedly satisfies the schema")
        for field in ("assignment_id", "workdir", "objective", "security_profile",
                      "required_evidence"):
            self.assertTrue(
                any(error.startswith(field) for error in errors),
                f"invalid fixture must exercise {field} validation; got {errors}",
            )

    def test_write_assignments_require_isolation_and_evidence(self):
        no_isolation = dict(self.valid)
        no_isolation.pop("isolated_worktree")
        self.assertIn("missing isolated_worktree", contract_errors(no_isolation, self.schema))

        no_evidence = dict(self.valid, required_evidence=[])
        self.assertIn("required_evidence length", contract_errors(no_evidence, self.schema))


class AssignmentGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.orchestration = normalized(ORCHESTRATE_PATH)
        cls.research = normalized(RESEARCH_PATH)

    def test_assignments_include_only_bounded_context_and_explicit_scope(self):
        for field in ("assignment_id", "objective", "spec_context", "task_ids",
                      "dependencies", "allowed_files", "required_evidence"):
            self.assertIn(
                field, self.orchestration,
                f"T057 must generate the SubagentAssignment `{field}` field",
            )
        self.assertRegex(
            self.orchestration,
            r"(?:only|minimum|bounded|relevant).{0,100}(?:spec context|spec_context|context)",
            "T057 must prohibit sending unrelated repository/spec context",
        )

    def test_assignments_inherit_security_without_escalation(self):
        self.assertIn("security_profile", self.orchestration)
        self.assertRegex(
            self.orchestration,
            r"(?:inherit|same as).{0,100}(?:effective|parent).{0,100}(?:security|profile)|"
            r"(?:effective|parent).{0,100}(?:security|profile).{0,100}(?:inherit|same as)",
            "T057 must inherit the effective parent security profile",
        )
        self.assertRegex(
            self.orchestration, r"(?:must not|never|no).{0,80}(?:escalat|broader|weaker)",
            "assignment guidance must explicitly prohibit security escalation",
        )

    def test_every_assignment_has_an_explicit_absolute_workdir(self):
        self.assertIn("workdir", self.orchestration)
        self.assertRegex(
            self.orchestration, r"(?:workdir.{0,80}absolute|absolute.{0,80}workdir)",
            "T057 must place an absolute workdir in every assignment",
        )
        self.assertRegex(
            self.research, r"(?:shared|same).{0,80}(?:read view|workdir)",
            "read-only research assignments may explicitly share a read view",
        )

    def test_concurrent_writers_are_isolated_and_return_reviewable_evidence(self):
        self.assertIn("isolated_worktree", self.orchestration)
        self.assertRegex(
            self.orchestration,
            r"(?:writer|write assignment).{0,100}(?:isolated worktree|isolated_worktree)",
            "concurrent write assignments must use isolated worktrees",
        )
        self.assertRegex(
            self.orchestration,
            r"required_evidence.{0,160}(?:changed.file|test|check|contract)",
            "writer assignments must request concrete review evidence",
        )


class IndependenceAnalysisTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.implementation = normalized(IMPLEMENT_PATH)

    def test_dependency_edges_block_parallel_dispatch(self):
        self.assertRegex(
            self.implementation,
            r"dependenc(?:y|ies).{0,140}(?:block|independent|parallel|dispatch)",
            "T058 must analyze dependency edges before dispatch",
        )

    def test_overlapping_files_and_shared_contracts_are_conflicts(self):
        self.assertRegex(
            self.implementation,
            r"(?:allowed_files|file).{0,120}(?:overlap|conflict)",
            "T058 must reject overlapping allowed-file scopes",
        )
        self.assertRegex(
            self.implementation,
            r"(?:contract|schema|shared interface).{0,120}(?:overlap|conflict|consumer)",
            "T058 must treat shared contract producer/consumer work as a conflict",
        )

    def test_parallel_dispatch_requires_two_or_more_independent_groups(self):
        self.assertRegex(self.implementation, r"2\+ independent")
        self.assertRegex(
            self.implementation,
            r"(?:fewer than|<) ?2.{0,100}(?:sequential|fall back)",
            "zero or one independent group must use sequential fallback",
        )


if __name__ == "__main__":
    unittest.main()
