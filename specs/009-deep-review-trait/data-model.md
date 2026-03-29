# Data Model: Deep-Review Trait

**Feature**: 009-deep-review-trait
**Date**: 2026-03-28

## Entities

### ReviewAgent

A specialized sub-agent with a focused review perspective.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Agent identifier: `correctness`, `architecture`, `security`, `production-readiness`, `test-quality` |
| display_name | string | Human-readable name for progress reporting (e.g., "Correctness", "Architecture & Idioms") |
| scope | string[] | List of focus areas the agent IS responsible for |
| anti_scope | string[] | List of focus areas the agent IS NOT responsible for |
| prompt_template | string | Full prompt text including role gate, anti-sycophancy, checklist, output format |

**Cardinality**: Exactly 5 internal agents (fixed, not user-configurable). CodeRabbit and Copilot are external tools, not modeled as ReviewAgents.

### Finding

A code quality issue identified by a review agent.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | string | `FINDING-{N}` per agent | Unique within an agent's report |
| severity | enum | `Critical`, `Important`, `Minor` | Impact classification |
| confidence | int | 0-100 | Agent's certainty. Report threshold: >= 70 (>= 50 for Critical) |
| file | string | Relative path | File containing the issue |
| line_start | int | >= 1 | First line of the issue |
| line_end | int | >= line_start | Last line of the issue |
| category | enum | `correctness`, `architecture`, `security`, `production-readiness`, `test-quality`, `external` | Maps to source agent focus area |
| description | string | Non-empty | What is wrong |
| rationale | string | Non-empty | Why it matters |
| fix | string | Non-empty | How to fix it |
| source_agent | string | Agent name | Which agent reported this |
| also_reported_by | string[] | Agent names | Other agents that found the same issue (post-dedup) |
| resolution | enum | `fixed`, `remaining`, `not-applicable` | Status after fix loop |
| round_found | int | 1-3 | Which review round discovered this |
| round_resolved | int | null or 1-3 | Which round fixed it (null if remaining) |

### ReviewRound

One complete cycle of agent review + fix.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| number | int | 1-3 | Round sequence number |
| findings_count | int | >= 0 | Total findings in this round |
| critical_count | int | >= 0 | Critical findings in this round |
| important_count | int | >= 0 | Important findings in this round |
| minor_count | int | >= 0 | Minor findings in this round |
| files_reviewed | string[] | Relative paths | Files reviewed in this round |
| files_fixed | string[] | Relative paths | Files modified by fixes in this round |
| agents_completed | int | 0-7 | Agents that returned results (5 internal + optional CodeRabbit + optional Copilot) |
| agents_failed | string[] | Agent names | Agents that failed/timed out |

### ReviewSession

The top-level entity for one complete review execution.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| date | string | ISO-8601 | When the review started |
| branch | string | Git branch name | Branch being reviewed |
| spec_path | string | null or path | Path to spec (null if no spec) |
| stage1_score | float | null or 0-100 | Spec compliance score (null if Stage 1 skipped) |
| stage1_passed | bool | | Whether Stage 1 passed (true if skipped) |
| rounds | ReviewRound[] | 1-3 items | All review rounds executed |
| gate_outcome | enum | `pass`, `fail`, `advisory_pass`, `advisory_fail` | Final gate result |
| invocation_context | enum | `superpowers`, `manual` | How review-code was triggered |
| hint_text | string | null or text | User-provided focus hint |
| total_findings | int | >= 0 | All findings across all rounds |
| fixed_count | int | >= 0 | Findings resolved by fix loop |
| remaining_count | int | >= 0 | Findings still open |

## State Transitions

### ReviewSession Lifecycle

```
[not started]
     │
     ▼
[Stage 1: Spec Compliance]
     │
     ├─ score < 95% ──► [BLOCKED] (report score, list issues, stop)
     ├─ score >= 95% ──► [Stage 2]
     └─ no spec ───────► [Stage 2] (skip Stage 1)
     │
     ▼
[Stage 2: Multi-Perspective Review]
     │
     ├─ dispatch agents (parallel or sequential)
     ├─ collect findings
     ├─ merge + deduplicate
     │
     ▼
[Gate Check]
     │
     ├─ no Critical/Important ──► gate_outcome = pass ──► [Write Artifact]
     └─ Critical/Important exist
          │
          ▼
     [Fix Loop Round N] (N = 1..3)
          │
          ├─ apply fixes (main agent)
          ├─ stage changes
          ├─ re-review modified files
          ├─ merge new findings
          │
          ├─ no Critical/Important ──► gate_outcome = pass ──► [Write Artifact]
          └─ Critical/Important remain
               │
               ├─ N < 3 ──► [Fix Loop Round N+1]
               └─ N = 3 ──► gate_outcome = fail ──► [Write Artifact]
     │
     ▼
[Write review-findings.md] (overwrites previous)
     │
     ▼
[Report to User]
     │
     ├─ superpowers context + pass ──► proceed to verification
     ├─ superpowers context + fail ──► block completion
     ├─ manual context + pass ──► advisory, user decides
     └─ manual context + fail ──► advisory, user decides
```

### Finding Resolution States

```
[reported]
    │
    ├─ fix applied successfully ──► [fixed]
    ├─ fix not applicable ────────► [not-applicable]
    └─ fix loop exhausted ────────► [remaining]
```

## Relationships

```
ReviewSession 1──*  ReviewRound
ReviewRound   1──*  Finding
Finding       *──1  ReviewAgent (source)
Finding       *──*  ReviewAgent (also_reported_by, post-dedup)
```

## Validation Rules

- A ReviewSession has at least 1 and at most 3 ReviewRounds
- Each Finding must reference a valid file path (verified against changed files list)
- Confidence must be within [0, 100]
- Critical findings with confidence < 50 are not reported
- Non-Critical findings with confidence < 70 are not reported
- Deduplication: two Findings match if same file + overlapping line range + same category
- gate_outcome `advisory_pass`/`advisory_fail` only valid when invocation_context = `manual`
