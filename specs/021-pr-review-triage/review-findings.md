# Deep Review Findings

**Date:** 2026-05-31
**Branch:** 021-pr-review-triage
**Rounds:** 1
**Gate Outcome:** PASS (after fix round 1)
**Invocation:** manual

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 1 | 1 | 0 |
| Important | 11 | 9 | 2 |
| Minor | 8 | 1 | 7 |
| **Total** | **20** | **11** | **9** |

**Agents completed:** 5/5 (+ 1 external tool)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Critical
- **Confidence:** 95
- **File:** spex/scripts/spex-triage-state.sh:66
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent, production-agent, test-quality-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `do_set` function used `($rid | tonumber)` in the jq expression to coerce the `reply_id` argument to a number. If `reply_id` is not a valid numeric string (empty string, GraphQL node ID), jq fails, `set -e` kills the script, and the state update is lost despite the reply already being posted on GitHub.

**Why this matters:**
If the state update fails after a reply is posted, the next triage invocation re-processes that comment and posts a duplicate reply.

**How it was resolved:**
Removed `tonumber`, storing `ourReplyId` as a string (`$rid` instead of `$rid | tonumber`). This handles both numeric database IDs and string node IDs.

### FINDING-2
- **Severity:** Important
- **Confidence:** 95
- **File:** spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md:103-109
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The triage command referenced `.specify/collab-config.yml` for config overrides, but all other spex-collab commands use `.specify/extensions/spex-collab/collab-config.yml`.

**Why this matters:**
Users configuring bot profiles at the canonical path would have their overrides silently ignored by triage.

**How it was resolved:**
Updated to use `.specify/extensions/spex-collab/collab-config.yml`, matching the established convention.

### FINDING-3
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/scripts/spex-triage-state.sh:71-80
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`do_list_unhandled` passed handled comment IDs as a newline-delimited string via `--arg`, then split inside jq. No validation on the input JSON.

**Why this matters:**
Malformed JSON input crashes the script. The newline-split pattern is fragile.

**How it was resolved:**
Changed to pass handled IDs as a JSON array via `--argjson`. Added input validation that checks `comment_ids_json` is valid JSON before processing.

### FINDING-4
- **Severity:** Important
- **Confidence:** 92
- **File:** spex/scripts/spex-triage-state.sh:34-41,63-67,89-91
- **Category:** production-readiness
- **Source:** production-agent (also reported by: correctness-agent, security-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Temp files created via `mktemp` were never cleaned up on script failure or interruption.

**Why this matters:**
In loop mode with repeated failures, orphaned temp files accumulate.

**How it was resolved:**
Added a cleanup trap (`trap _cleanup_tmp EXIT`) and registered all temp files in `_TMPFILES` array.

### FINDING-5
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/scripts/spex-triage-state.sh:100-112
- **Category:** production-readiness
- **Source:** security-agent (also reported by: production-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Handler functions had no argument count validation. Missing arguments produced cryptic `unbound variable` errors.

**Why this matters:**
Debugging failures from API response issues is harder without clear error messages.

**How it was resolved:**
Added `[ $# -eq N ]` checks at the top of each handler function with usage messages.

### FINDING-6
- **Severity:** Important
- **Confidence:** 82
- **File:** spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md:43-74
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The GraphQL query fetched `reviewThreads(first: 100)` without cursor-based pagination. PRs with more than 100 threads would silently lose threads beyond position 100.

**Why this matters:**
The skill would report "0 open bot comments" when threads beyond page 1 were never seen, giving a false completion signal for loop mode.

**How it was resolved:**
Added `pageInfo { hasNextPage endCursor }` to the GraphQL query and cursor-based pagination instructions.

### FINDING-7
- **Severity:** Important
- **Confidence:** 82
- **File:** spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md:30-33
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
No validation that extracted `OWNER` and `REPO` values are non-empty after sed extraction from the remote URL.

**Why this matters:**
Empty values would produce malformed API URLs.

**How it was resolved:**
Added validation instruction: if `OWNER` or `REPO` is empty, report error and stop.

### FINDING-8
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md:19-22
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
No validation that `PR_NUM` from `--pr` argument is numeric.

**Why this matters:**
Non-numeric PR number could produce malformed API URLs.

**How it was resolved:**
Added validation instruction: ensure `PR_NUM` is a positive integer.

### FINDING-9
- **Severity:** Important
- **Confidence:** 72
- **File:** spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md:83-88
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Bot detection used dual heuristics (GraphQL Bot type AND `[bot]` login suffix) without specifying priority. The spec says to use the API type (FR-002).

**Why this matters:**
If heuristics disagree, a human could be misclassified as a bot and receive automated replies without approval.

**How it was resolved:**
Clarified that GraphQL `Bot` type is the primary indicator per FR-002, with `[bot]` login suffix as a secondary fallback only.

### FINDING-10
- **Severity:** Important
- **Confidence:** 82
- **File:** tests/test_marketplace_install.sh:218-232
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The integration test's `EXPECTED_EXT_COMMANDS` array did not include the triage command.

**Why this matters:**
A missing or misnamed triage command file would not be caught by the install test.

**How it was resolved:**
Added `spex-collab/commands/speckit.spex-collab.triage.md` to the expected commands array.

### FINDING-11
- **Severity:** Important
- **Confidence:** 78
- **File:** spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md:115-218
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
The skill processes all bot comments, then batch commits, then posts replies. If the session is interrupted between assessment and reply posting, all assessment work is lost and re-done on next invocation.

**Why this matters:**
On large PRs (20+ comments), session interruption wastes significant tokens and time. Repeated assessments may produce different decisions due to LLM non-determinism.

**How to resolve:**
Consider saving assessment results to the state file as an intermediate "assessed" state before the commit/reply phase. On re-invocation, load cached assessments. This is an enhancement for a future iteration.

### FINDING-12
- **Severity:** Important
- **Confidence:** 95
- **File:** spex/scripts/spex-triage-state.sh (entire file)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
The state management script has no unit tests despite being the most testable and correctness-critical component.

**Why this matters:**
Regressions in state tracking directly affect duplicate reply prevention, which is the core safety property.

**How to resolve:**
Create `tests/test_triage_state.sh` with the test cases described in the test-quality agent findings. The `TRIAGE_STATE_FILE` env var already supports test injection.

## Remaining Minor Findings

| # | File | Issue |
|---|------|-------|
| M1 | extension.yml:7 | Extension description was outdated (fixed as part of round 1) |
| M2 | spex-triage-state.sh:82-97 | `do_cleanup` accepts empty PR number |
| M3 | spex-triage-state.sh:46-57 | `do_get` output format (raw JSON) undocumented |
| M4 | spex-triage-state.sh:16 | `TRIAGE_STATE_FILE` env var allows arbitrary path (intentional for testing) |
| M5 | triage.md:178-179 | Theoretical prompt injection via bot comment bodies (low practical risk) |
| M6 | spec.md:91-97 | `yq` dependency undeclared in spec |
| M7 | spex-triage-state.sh:63-67 | Race condition with concurrent invocations (low practical risk) |
