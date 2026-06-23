# Data Model: Smoke Test V2

**Date**: 2026-06-23

## Entities

### Scenario Evidence (returned by subagent)

A structured text block per scenario in the subagent's return payload.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| scenario_number | integer | yes | Position in the scenario list (1-based) |
| total_scenarios | integer | yes | Total number of scenarios |
| user_story | string | yes | Title of the parent user story |
| type | enum | yes | One of: automated, manual, skip |
| given | string | yes | Precondition text from spec |
| when | string | yes | Action text from spec |
| then | string | yes | Expected outcome text from spec |
| why_it_matters | string | yes | One-sentence explanation of what risk this catches |
| command | string | conditional | Exact command run (automated type only) |
| output | string | conditional | Full command output (automated type only) |
| observation | string | conditional | Subagent's factual observation (automated type only) |
| instructions | string | conditional | Step-by-step human instructions (manual type only) |
| skip_reason | string | conditional | Why it cannot be exercised (skip type only) |
| manual_test_instructions | string | conditional | How to test later (skip type only) |

### Scenario Verdict (recorded during review)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| scenario_number | integer | yes | Matches evidence scenario_number |
| verdict | enum | yes | One of: pass, fail, skip |
| notes | string | no | Reviewer's notes (reason for fail/skip, observations) |
| retry_result | string | no | Result after fix+retry (if applicable) |

### SMOKE-TEST.md Report

A markdown file combining evidence and verdicts. One section per scenario with the structure defined in the plan's report format.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| feature_name | string | yes | From spec title |
| date | date | yes | Run date |
| spec_path | string | yes | Relative path to spec.md |
| summary | string | yes | "N passed, M skipped, K failed (out of TOTAL)" |
| scenarios | list | yes | List of scenario entries (evidence + verdict) |
