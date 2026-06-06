---
name: speckit.spex-deep-review.review
description: Multi-perspective code review with autonomous fix loop - dispatches 5 specialized review agents, merges findings, auto-fixes Critical/Important issues
---

# Deep Review: Multi-Perspective Code Review

## Overview

This command orchestrates a multi-perspective code review using five specialized review agents. Each agent analyzes code from a distinct angle (correctness, architecture, security, production readiness, test quality). Findings are merged, deduplicated, and classified by severity. Critical and Important findings trigger an autonomous fix loop (up to 3 rounds). Results are documented in `review-findings.md`.

**This command is invoked by `speckit-spex-gates-review-code` when the deep-review extension is enabled, or via the `after_implement` hook.**

## Prerequisites

The caller (review-code or ship) may provide these values. When not provided, the deep-review command resolves them itself:

1. **Stage 1 result**: spec compliance score (or null if no spec)
2. **Invocation context**: `superpowers` or `manual`
3. **Hint text**: optional focus area from user (or null)
4. **External tool settings**: `{coderabbit: true/false, copilot: true/false}` (see resolution below)
5. **Spec path**: path to spec.md (or null, see Spec Resolution below)
6. **Feature directory**: path to the spec directory for artifact output

### Spec Resolution

If the caller does not provide a spec path, attempt branch-based resolution:

```bash
.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null
```

If this succeeds (outputs JSON with `FEATURE_SPEC`), use the resolved spec path and feature directory. If this fails (not on a feature branch, no matching spec directory), proceed without a spec (spec compliance checks will be skipped).

### External Tool Settings Resolution

If external tool settings are provided by the caller, use them directly. If not (e.g., when invoked directly by `speckit-spex-ship` or manually), resolve from config:

```bash
# Read config defaults from deep-review extension config (all default to true if key is missing)
DEEP_REVIEW_CONFIG=".specify/extensions/spex-deep-review/deep-review-config.yml"
DEFAULT_CODERABBIT=$(yq -r '.external_tools.coderabbit // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)
DEFAULT_CODERABBIT=${DEFAULT_CODERABBIT:-true}
DEFAULT_COPILOT=$(yq -r '.external_tools.copilot // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)
DEFAULT_COPILOT=${DEFAULT_COPILOT:-true}
```

```
Resolution:
  coderabbit = DEFAULT_CODERABBIT
  copilot    = DEFAULT_COPILOT
```

This ensures CodeRabbit and Copilot are enabled by default regardless of how deep-review is invoked.

### Test Suite Configuration

The deep review config (`deep-review-config.yml`) supports these test-related keys:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `test_command` | string | `""` (empty) | Override auto-detected test command. When set, skips auto-detection. Example: `"make integration-test"` |
| `test_timeout_seconds` | integer | `300` | Maximum seconds for test suite execution before timeout. Timeout is treated as a test failure. |

When `test_command` is empty, the fix loop auto-detects the test command from the project structure (see Step 2).

### Review Hints

Projects can provide framework-specific patterns in `.specify/review-hints.md`. When this file exists and is non-empty, its content is injected into every review agent's preamble (see Common Preamble item 10). This allows projects to document non-obvious framework behaviors (e.g., API client side effects, implicit state mutations) that review agents should know about.

## Orchestration Flow

### Step 1: Determine Changed Files

Identify the files to review:

```bash
# Get the main branch name
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

# Files changed between main branch and HEAD
git diff --name-only "${MAIN_BRANCH}...HEAD" 2>/dev/null

# Uncommitted changes (staged + unstaged)
git diff --name-only HEAD 2>/dev/null
git diff --name-only --cached 2>/dev/null
```

Combine all results into a deduplicated list. Filter to only source code files (exclude binary, images, lock files). **Exclude files under `specs/` and `brainstorm/`** as these are spec artifacts, not implementation code.

**For re-review rounds (fix loop):** narrow scope to only files modified by the most recent fix round:
```bash
# Files changed since last staging
git diff --name-only --cached 2>/dev/null
```

### Step 2: Detect External Tools

Check for external review CLIs, respecting the external tool settings from the caller:

```bash
# CodeRabbit (skip only if explicitly disabled in config)
which coderabbit >/dev/null 2>&1 && echo "CODERABBIT_AVAILABLE=true"

# GitHub Copilot CLI (skip if copilot setting is false)
which copilot >/dev/null 2>&1 && echo "COPILOT_AVAILABLE=true"

```

**External tool resolution:**
1. Use the external tool settings from Prerequisites (either caller-provided or self-resolved from config)
2. **CodeRabbit is enabled by default.** Only skip if the config explicitly sets `coderabbit: false`
3. If `copilot` is `false`, skip Copilot detection entirely
4. If a tool is enabled in settings but not installed, proceed silently without it
5. **When CodeRabbit is available and enabled, it MUST be invoked.** Do not skip it for performance or convenience reasons. CodeRabbit provides external validation that complements the internal review agents.

**Test command auto-detection:**

Detect the project's test command for use in the fix loop (Step 7.6). Check sources in this order; first match wins:

```bash
# 1. Config override (highest priority)
DEEP_REVIEW_CONFIG=".specify/extensions/spex-deep-review/deep-review-config.yml"
TEST_CMD=$(yq -r '.test_command // ""' "$DEEP_REVIEW_CONFIG" 2>/dev/null)
TEST_TIMEOUT=$(yq -r '.test_timeout_seconds // 300' "$DEEP_REVIEW_CONFIG" 2>/dev/null)

# 2. Makefile with test target
[ -z "$TEST_CMD" ] && grep -q '^test:' Makefile 2>/dev/null && TEST_CMD="make test"

# 3. Go module
[ -z "$TEST_CMD" ] && [ -f go.mod ] && TEST_CMD="go test ./..."

# 4. Node.js with test script
[ -z "$TEST_CMD" ] && [ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1 && TEST_CMD="npm test"

# 5. Python project
[ -z "$TEST_CMD" ] && ([ -f pyproject.toml ] || [ -f setup.py ]) && TEST_CMD="pytest"
```

If `TEST_CMD` is non-empty, log: `Test command detected: $TEST_CMD (timeout: ${TEST_TIMEOUT}s)`
If `TEST_CMD` is empty, log: `No test command detected; post-fix test step will be skipped`

**Review hints detection:**

Check if the project provides framework-specific review hints:

```bash
REVIEW_HINTS_FILE=".specify/review-hints.md"
REVIEW_HINTS=""
if [ -f "$REVIEW_HINTS_FILE" ] && [ -s "$REVIEW_HINTS_FILE" ]; then
  REVIEW_HINTS=$(cat "$REVIEW_HINTS_FILE")
fi
```

If `REVIEW_HINTS` is non-empty, the content will be injected into every review agent's preamble (see Common Preamble item 10). If the file does not exist or is empty, agents run with their standard prompts (no error, no warning, silent skip).

### Step 3: Dispatch Review Agents

**Check for teams extension:**

Read `.specify/extensions/.registry` and check if `spex-teams` extension is enabled (query: `.extensions["spex-teams"].enabled`).

**Sequential mode** (teams NOT enabled):
- Dispatch each agent one at a time using the Agent tool
- Each agent gets a fresh, isolated context (no session history)
- Report progress after each agent completes:
  ```
  Agent 1/5: Correctness... done, N findings
  Agent 2/5: Architecture & Idioms... done, N findings
  ...
  ```

**Parallel mode** (teams IS enabled):
- Dispatch all 5 agents in a single message using multiple Agent tool calls
- Each agent runs in isolated context
- Report progress as each agent completes:
  ```
  Agent completed: Security... 2 findings
  Agent completed: Test Quality... 0 findings
  ...
  ```

**For each agent dispatch**, use the Agent tool with:
- `subagent_type: "general-purpose"`
- The full agent prompt (from the Agent Prompts section below)
- Include the list of changed files and their contents
- **Include the spec text** (spec.md content, if available). Agents need the spec to check code behavior against requirements. Without it, they can only find code-level issues, not spec compliance gaps.
- Include the hint text (if provided) as additional review focus
- **Include review hints** (if detected in Step 2): When `REVIEW_HINTS` is non-empty, include item 10 (PROJECT REVIEW HINTS) in the Common Preamble for every agent. Read the file `.specify/review-hints.md` and substitute its content into the preamble template between the `--- BEGIN PROJECT REVIEW HINTS ---` and `--- END PROJECT REVIEW HINTS ---` delimiters. If `REVIEW_HINTS` is empty, omit item 10 entirely from the preamble (do not include empty delimiters).

### Step 4: Dispatch External Tools (if available)

**CodeRabbit** (if available):

**IMPORTANT: CodeRabbit MUST be run when the CLI is installed and the config allows it. Do NOT skip it. CodeRabbit findings are high-value external validation and MUST be included in the fix loop alongside internal agent findings.**

First, build the file list excluding spec artifacts:
```bash
# Get changed files, excluding specs/ and brainstorm/ directories
REVIEW_FILES=$(git diff --name-only "${MAIN_BRANCH}...HEAD" 2>/dev/null | grep -v -E '^(specs/|brainstorm/)' | sort -u)
```

Then invoke CodeRabbit with the explicit file list:
```bash
# Initial review (Stage 2): review changed source files only
coderabbit review --agent --files $REVIEW_FILES 2>&1

# Fix loop re-review rounds: review only the files that were modified by fixes
coderabbit review --agent --type uncommitted 2>&1
```

The `--agent` flag produces structured, detailed findings with rationale (preferred over `--prompt-only` which only shows prompts). The `--files` flag ensures spec artifacts under `specs/` and `brainstorm/` are never reviewed.

Parse output:
1. Check for "Review completed" (no issues found)
2. Split on `=============` delimiters
3. For each block: extract file, line, severity keyword, description, and **rationale/explanation**
4. Map severity: critical -> Critical, major -> Important, minor -> Minor
5. Set category = "external", source_agent = "coderabbit", confidence = 75
6. **Preserve the full rationale** from CodeRabbit output for inclusion in review-findings.md
7. **All CodeRabbit findings with severity Critical or Important MUST enter the fix loop** (Step 7). They are treated identically to internal agent findings for gate and fix purposes.

**Copilot CLI** (if available):
```bash
copilot -s -p "Review the following git diff for bugs, security issues, and code quality problems. Output ONLY a structured list of findings. For each finding use this exact format:

### FINDING
- Severity: Critical|Important|Minor
- File: <relative path>
- Line: <number>
- Description: <what is wrong and how to fix it>

End each finding with ---

$(git diff HEAD)" 2>&1
```
Parse output:
1. Split on "### FINDING" markers
2. For each block: extract Severity, File, Line, Description fields
3. **Discard findings for files under `specs/`** (spec artifacts are not code to review)
4. Set category = "external", source_agent = "copilot", confidence = 75

**Error handling for external tools:**
If a tool times out, crashes, or returns an error:
- Log the failure (tool name, error reason) for inclusion in review-findings.md
- Continue with findings from internal agents and any other working tools
- Do NOT block the review

### Step 5: Merge and Deduplicate Findings

1. Collect all findings from internal agents and external tools
2. Normalize to common schema:
   ```
   {
     id: "FINDING-N",
     severity: Critical|Important|Minor,
     confidence: 0-100,
     file: "relative/path",
     line_start: N,
     line_end: N,
     category: correctness|architecture|security|production-readiness|test-quality|external|regression,
     description: "what is wrong",
     rationale: "why it matters",
     fix: "how to fix it",
     source_agent: "agent-name",
     also_reported_by: [],
     external_rationale: "full rationale from external tool (CodeRabbit/Copilot), or null",
     resolution: "pending",
     round_found: N
   }
   ```
3. Sort by file path, then line number
4. Deduplicate: for each pair of findings where:
   - Same file path AND
   - Overlapping line ranges (A.line_start <= B.line_end AND B.line_start <= A.line_end) AND
   - Same category
   Then: keep the finding with the longer description, add the other's source_agent to `also_reported_by`, use the higher severity and confidence
5. Assign sequential IDs to merged findings

### Step 6: Gate Check

Count findings by severity:
- **Critical count**: findings with severity = Critical
- **Important count**: findings with severity = Important
- **Minor count**: findings with severity = Minor

**Gate logic:**
- If Critical + Important = 0: **GATE PASS**
- If Critical + Important > 0: proceed to fix loop (or fail if max rounds reached)

### Step 7: Autonomous Fix Loop

**Maximum 3 rounds.**

For each round:
1. Report: `Fix round N/3: N Critical + N Important findings to address`
2. Collect all Critical and Important findings, sorted by file
3. For each file with findings, sort findings by line number **descending** (reverse order to prevent line shifts)
4. Apply each fix:
   - Read the file
   - Apply the fix suggestion at the specified location
   - The main conversation agent performs fixes (not review agents)
5. Stage all changes: `git add <modified files>`
6. **Run test suite** (if a test command was detected in Step 2):
   - If `TEST_CMD` is empty, skip with log: `No test command detected, skipping post-fix test run`
   - Execute the test command with a timeout:
     ```bash
     timeout "${TEST_TIMEOUT:-300}" $TEST_CMD 2>&1
     TEST_EXIT=$?
     ```
   - If the command times out (exit code 124), treat as a test failure:
     ```
     Test suite timed out after ${TEST_TIMEOUT}s - treating as failure
     ```
   - If `TEST_EXIT = 0`: Report `[Test suite... passed]` and proceed to step 7
   - If `TEST_EXIT != 0`: Convert test failures to Critical findings:
     - Parse test output for individual test failure names, files, and messages
     - For each identifiable test failure, create a finding:
       ```
       {
         source_agent: "test-suite",
         category: "regression",
         confidence: 95,
         severity: "Critical",
         description: "Test [test name] failed after fix round N: [failure message]",
         file: "[test file path]",
         line_start: 0,
         fix: "Revert or correct the fix that caused the regression"
       }
       ```
     - If the test command exits non-zero but produces no parseable test output, create a single Critical finding:
       ```
       {
         source_agent: "test-suite",
         category: "regression",
         confidence: 95,
         severity: "Critical",
         description: "Test suite failed with exit code TEST_EXIT (no parseable output). stderr: [available stderr]",
         file: "",
         line_start: 0,
         fix: "Investigate test suite failure; the most recent fix round may have introduced a regression"
       }
       ```
     - Test failures consume a fix round (same as review findings). The failures become Critical findings and enter the next round for fixing.
     - Report: `[Test suite... N failures]`
7. Report: `Fix round N/3: applied N fixes, re-reviewing...`
8. Re-dispatch review agents on **only the modified files** (narrowed scope)
9. Merge new findings with existing Minor findings (and any test-suite findings from step 6)
10. Gate check:
   - If Critical + Important = 0: **GATE PASS**, exit loop
   - If round < 3: continue to next round
   - If round = 3: **GATE FAIL**, exit loop

**No user approval needed.** Fixes are applied autonomously. The user reviews all accumulated changes after the loop completes via `git diff`.

### Step 7b: Post-Fix Spec Compliance Check

**This step is MANDATORY when the fix loop removed code (deleted lines, removed functions, or deleted files).** Code removal is the operation most likely to silently drop a spec requirement. Edits and additions don't carry the same risk.

After the fix loop completes (regardless of PASS or FAIL), check if any fix round removed code:

```bash
# Check if any fix round deleted lines
REMOVED_LINES=$(git diff --stat HEAD~1 2>/dev/null | grep -oE '[0-9]+ deletion' | head -1)
```

If code was removed AND a spec is available:

1. Read the spec's functional requirements (all FR-NNN entries or requirement bullet points)
2. For each functional requirement, verify that at least one code path still implements it:
   - Search for key terms, function names, or class names associated with the requirement
   - Check that the implementation file still exists
   - Verify the function/method body is not empty or a stub
3. Build a coverage check:

```
Post-fix spec coverage:
  FR-001: parse JSONL events         → agent_eval/events.py:parse_events()  ✓
  FR-002: event type discriminator   → agent_eval/events.py:EventType       ✓
  ...
  FR-009: tool result from user msgs → MISSING (removed in fix round 1)     ✗
```

4. If any FR is MISSING or STUB:
   - Add a new Critical finding for each: `"Spec requirement FR-NNN dropped during fix loop: [requirement text]"`
   - If the fix loop has remaining rounds (< 3), run another fix round to re-implement the dropped requirements
   - If max rounds reached, report the dropped requirements as Critical findings in the gate outcome

5. Update the gate outcome:
   - If dropped requirements were re-implemented successfully: maintain GATE PASS
   - If dropped requirements remain: **GATE FAIL** (spec coverage gaps override code quality PASS)

If no code was removed, or no spec is available, skip this step.

### Step 8: Write review-findings.md

Write `specs/<feature>/review-findings.md` (overwrite if exists):

```markdown
# Deep Review Findings

**Date:** YYYY-MM-DD
**Branch:** branch-name
**Rounds:** N
**Gate Outcome:** PASS|FAIL
**Invocation:** superpowers|manual

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | N | N | N |
| Important | N | N | N |
| Minor | N | - | N |
| **Total** | **N** | **N** | **N** |

**Agents completed:** 5/5 (+ N external tools)
**Agents failed:** [list if any]

## Findings

### FINDING-1
- **Severity:** Critical
- **Confidence:** 85
- **File:** path/to/file.go:142-148
- **Category:** correctness
- **Source:** correctness-agent (also reported by: coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
[Describe the issue clearly. What specific code pattern, logic error, or
vulnerability was found? Include the relevant code snippet if it helps
understanding.]

**Why this matters:**
[Explain the impact. What could go wrong if this is not fixed? Is it a
runtime error, data corruption risk, security exposure, or maintenance
burden? Be specific about the failure scenario.]

**How it was resolved:**
[If fixed: explain what was changed and why this fix is correct.
If remaining: explain what needs to happen to resolve it.]

[If CodeRabbit or Copilot reported this finding, include their analysis:]

**External tool analysis (CodeRabbit):**
> [Preserve the full rationale from the external tool's output. This gives
> reviewers the external AI's perspective, which may differ from or
> complement the internal agent's analysis.]

### FINDING-2
[Same structure. Every finding gets the full treatment.]

...

## Post-Fix Spec Coverage

[If Step 7b ran, include the coverage check results:]

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001: ... | file.py:func() | ✓ |
| FR-009: ... | MISSING (removed in fix round 1) | ✗ |

[If all FRs covered: "All spec requirements verified after fix loop."]
[If any dropped: "N spec requirements dropped during fix loop and flagged as Critical findings."]

## Test Suite Results

[If test suite was executed during the fix loop, include results per round:]

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1     | make test   | 0         | 0        | passed |
| 2     | make test   | 1         | 3        | failed |
| ...   | ...         | ...       | ...      | ...    |

[If test failures were converted to findings, list them:]

Test-originated findings:
- FINDING-N: Test [name] failed after fix round N: [message] (regression, Critical)
- ...

[If no test command was detected: "No test command detected; post-fix test step was skipped."]
[If test suite passed in all rounds: "Test suite passed in all fix rounds."]

## Remaining Findings

[If gate failed, list unresolved findings here with the same detailed
format. Explain why they could not be auto-fixed and what human action
is needed.]
```

### Step 9: Report Gate Outcome with Agent Summary

After writing `review-findings.md`, output a tabular console summary showing what each agent found, what was fixed, and the gate outcome. This is the primary output the user sees.

**Always output this summary to the console:**

```
Deep review completed.

Gate: PASS|FAIL (after fix round N)

Review Agents:

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     N |     N |         N | completed |
| Architecture & Idioms   |     N |     N |         N | completed |
| Security                |     N |     N |         N | completed |
| Production Readiness    |     N |     N |         N | completed |
| Test Quality            |     N |     N |         N | completed |
| CodeRabbit (external)   |     N |     N |         N | completed/skipped/failed |
| Copilot (external)      |     N |     N |         N | completed/skipped/failed |
| Test Suite (regression) |     N |     N |         N | passed/N failures/skipped |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |     N |     N |         N |           |

Key fixes applied:
  1. [Brief description of fix] (agent-name)
  2. [Brief description of fix] (agent-name)
  ...

Remaining findings (N Important):
  - [Finding summary] (agent-name, file:line)
  ...

Post-fix spec coverage: N/N requirements verified [✓ all covered | ✗ N dropped]

Details: review-findings.md
```

**Constraints:**
- Always include the agent table, even if some agents found nothing (show 0)
- Include external tools in the table even if skipped (show "skipped" with reason in Status)
- "Key fixes applied" lists up to 10 most significant fixes, grouped by theme
- "Remaining findings" lists only Critical and Important severity items
- If gate PASSED with zero remaining: omit the "Remaining findings" section
- If an external tool was skipped: show reason (e.g., "skipped (CLI not installed)" or "skipped (disabled in config)")

### Step 10: Update Flow State

**MANDATORY: Update flow state.** This MUST run after deep review completes (regardless of gate outcome). Deep review completing means the code review phase is done, even if findings remain. Use the flow state script:

```bash
FLOW_STATE="$(find ~/.claude -name 'spex-flow-state.sh' 2>/dev/null | head -1)" && [ -x "$FLOW_STATE" ] && "$FLOW_STATE" gate review-code && "$FLOW_STATE" implemented
```

This ensures the status line shows `R ✓` after deep review finishes, since review-code delegates to deep review and its own final state update may not execute.

### Step 11: Next Steps (tell the user)

After deep review passes, tell the user:

```
Deep review complete. To close out this feature:
  1. /clear                    (free context for final gate)
  2. /speckit-spex-finish       (verify + merge/PR, all-in-one)
```

This prompt is mandatory on every PASS exit. The user needs to know how to finalize.

---

## Reference: Finding Output Schema

Each review agent MUST return findings in this exact format:

```markdown
## Findings

### FINDING-1
- **Severity**: Critical|Important|Minor
- **Confidence**: 0-100
- **File**: relative/path/to/file.ext
- **Lines**: start-end
- **Category**: [agent's category]
- **Description**: [what is wrong]
- **Rationale**: [why it matters, with evidence from the code]
- **Fix**: [concrete fix suggestion with code if applicable]

### FINDING-2
...

## Self-Verification
- [ ] Each finding has file:line evidence from actual code I read
- [ ] No findings invented for code that is actually clean
- [ ] No duplicate findings (same issue reported twice)
- [ ] Confidence scores reflect my actual certainty, not padding
- [ ] If I found zero issues, I re-read the code a second time to confirm
- [ ] Every finding includes a concrete, implementable fix
- [ ] If a spec was provided, I checked my findings against specific FR/NFR requirements
- [ ] I checked boundary/last-iteration behavior in all loops and retry logic
```

If an agent finds no issues after careful review, it MUST return:

```markdown
## Findings

No issues found. Code was reviewed twice to confirm.

## Self-Verification
- [x] Re-read code a second time after initial zero-finding pass
- [x] Confirmed no issues in my focus area
```

---

## Reference: Agent Prompts

### Common Preamble (included in every agent prompt)

The following instructions are prepended to every agent's prompt:

```
IMPORTANT INSTRUCTIONS - READ BEFORE REVIEWING:

1. ANTI-SYCOPHANCY: Do NOT start with praise. Do NOT say "Great implementation!",
   "Nice work!", or any positive affirmation. Start directly with your findings.
   Zero findings is a red flag - if you find nothing, re-read the entire codebase
   a second time before confirming zero findings.

2. DISTRUST: Do NOT trust the implementer's report, comments, or commit messages.
   Verify EVERYTHING by reading the actual code. Comments may be wrong. Variable
   names may be misleading. Test names may not match what they test.

   ISOLATION: Do NOT read git log, commit messages, brainstorm documents, or
   plan.md/tasks.md. These reveal implementation intent and bias your review.
   Review the CODE and the SPEC only. Judge what was built, not what was intended.

3. DO NOT trust test results as proof of correctness. Read the actual assertions.
   A passing test with weak assertions proves nothing. Verify what is actually
   being tested, not what the test name claims.

4. FAILURE MODES - You MUST NOT:
   - Inflate nits to fill a quota. If the code is clean in your area, say so.
   - Invent issues that don't exist. Every finding must cite specific code.
   - Repeat the same finding in different words.
   - Report issues outside your designated scope (see your role gate below).

5. CONFIDENCE SCORING: Rate every finding 0-100.
   - Only report findings with confidence >= 70
   - EXCEPTION: Critical findings may be reported at confidence >= 50
   - Be honest about uncertainty. 60% confidence on a real issue is better
     than 95% confidence on a manufactured one.

6. EVERY FINDING MUST INCLUDE:
   - File path and line number(s)
   - What is wrong (specific, not vague)
   - Why it matters (impact if not fixed)
   - How to fix it (concrete suggestion, not "consider improving")

7. LANGUAGE AWARENESS: Adapt your checklist based on the programming languages
   detected in the changed files. For mixed-language changes, apply language-specific
   checks for each language present.

8. OUTPUT FORMAT: Use the Finding Output Schema exactly as specified. Do not
   deviate from the format. Your output will be parsed programmatically.

9. SPEC AWARENESS: If a spec (spec.md) is provided, cross-check the code
   against specific requirements. For each functional requirement (FR-NNN),
   verify the code implements exactly what the spec says, not more, not less.
   Flag mismatches as findings. Common spec compliance gaps:
   - Code handles a broader or narrower set of cases than the spec defines
   - Metrics or observability the spec requires but code doesn't expose
   - Error codes or status codes that differ from the spec
   - Behavioral differences on edge cases (last iteration, empty input, etc.)

10. PROJECT REVIEW HINTS: [CONDITIONAL - only include this item when
    `.specify/review-hints.md` exists and is non-empty]

    The following framework-specific patterns have been identified by the
    project maintainers. Use this knowledge when reviewing code. These
    patterns describe non-obvious behaviors that may not be apparent from
    reading the code alone.

    --- BEGIN PROJECT REVIEW HINTS ---
    [contents of .specify/review-hints.md]
    --- END PROJECT REVIEW HINTS ---
```

### Agent 1: Correctness

```
You are the CORRECTNESS REVIEW AGENT.

YOUR ROLE: You ARE responsible for finding bugs, logic errors, and correctness issues.
YOUR SCOPE: Mutation safety, shared references, logic errors, resource cleanup,
error path correctness, off-by-one errors, null/nil handling, type confusion.

YOU ARE NOT RESPONSIBLE FOR: Code style, naming conventions, documentation quality,
performance optimization, test coverage, security vulnerabilities, or architecture
decisions. Those belong to other agents. Stay in your lane.

CHECKLIST - Check each item against the code:

For all languages:
- [ ] Shared mutable state: Are references copied before mutation? Are slices/arrays
      cloned before passing to goroutines/threads/async functions?
- [ ] Error paths: Do all error returns clean up resources (close files, release locks,
      cancel contexts)? Are errors propagated correctly (not silently swallowed)?
- [ ] Logic errors: Are conditions correct (not inverted)? Are loops bounded?
      Are edge cases handled (empty input, single element, max values)?
- [ ] Null/nil safety: Can any dereference panic? Are optional values checked
      before use? Are map lookups verified?
- [ ] Resource lifecycle: Are all opened resources (files, connections, channels)
      properly closed? In the right order? In defer/finally blocks?
- [ ] Concurrency: Are shared variables protected? Can race conditions occur?
      Are channels properly drained on cancellation?
- [ ] Last-iteration behavior: In loops with retries, attempts, or pagination,
      does the final iteration behave correctly? Common bugs: sleeping after the
      last attempt, returning a generic error instead of the original, off-by-one
      in attempt counting, unnecessary work on the last pass.
- [ ] Boundary correctness: Does the code match the spec's exact boundaries?
      If the spec says "retry on 502/503/504", does the code retry exactly
      those, not all 5xx? If the spec says "max 3 attempts", is it 3 not 4?

For Go specifically:
- [ ] Slice append in loops: Does `append` modify a shared backing array?
- [ ] Goroutine variable capture: Are loop variables captured by value, not reference?
- [ ] Context cancellation: Is context.Cancel() called in defer?
- [ ] Error wrapping: Are errors wrapped with %w for proper unwrapping?

For Python specifically:
- [ ] Mutable default arguments: Are lists/dicts used as default parameters?
- [ ] Iterator exhaustion: Are generators consumed only once when multiple reads needed?
- [ ] Exception handling: Are bare `except:` clauses catching too broadly?

For JavaScript/TypeScript specifically:
- [ ] Async/await: Are promises properly awaited? Can unhandled rejections occur?
- [ ] Closure variable capture: Are `var` variables captured in closures inside loops?
- [ ] Type narrowing: After type guards, is the narrowed type used correctly?

For Bash specifically:
- [ ] Unquoted variables: Can word splitting cause unexpected behavior?
- [ ] Exit codes: Are command failures checked? Is `set -e` or explicit checks used?
- [ ] Subshell variable scope: Are variables set in subshells expected in parent?

SWALLOWED ERROR DETECTION:

For all languages, check for functions that call fallible operations (API server
calls, file I/O, network requests, database queries) and log the error but do
NOT return or propagate it to the caller. Silent error swallowing hides failures
and prevents callers from reacting appropriately.

For all languages:
- [ ] Swallowed errors: Are there functions that call a fallible operation,
      check or catch the error, log it (or discard it), but do not return,
      re-raise, or propagate the error? Flag with category = "correctness",
      confidence = 85. Include the specific function name and line number.

For Go specifically:
- [ ] Pattern: `if err != nil { log.Error(err, ...); }` without a subsequent
      `return err` or `return fmt.Errorf(...)`. The error is logged but the
      function continues as if it succeeded.
- [ ] Pattern: `_ = someFunc()` where someFunc returns an error from an I/O
      or API call. The error is explicitly discarded.

For Python specifically:
- [ ] Pattern: `except SomeException as e: logger.error(e)` without a
      subsequent `raise` or `raise ... from e`. The exception is caught,
      logged, and silently swallowed.
- [ ] Pattern: `except: pass` or `except Exception: pass` that swallows
      errors from I/O or network operations.

For JavaScript/TypeScript specifically:
- [ ] Pattern: `.catch(err => console.error(err))` without re-throwing or
      returning a rejected promise. The error is logged but the promise
      chain continues as resolved.
- [ ] Pattern: `try { ... } catch(e) { console.log(e); }` without re-throw.

For Bash specifically:
- [ ] Pattern: `some_command || echo "failed"` where the failure of
      some_command should cause the script to exit or return non-zero.

INTENTIONAL SWALLOW HANDLING:
- [ ] If a function swallows an error but explicitly documents WHY (e.g.,
      a comment like "best-effort cleanup", "fire-and-forget", or
      "intentionally ignoring error because..."), produce a Minor finding
      (not Critical) with reduced confidence (50-60). The documentation
      shows the developer considered the error path.
```

### Agent 2: Architecture & Idioms

```
You are the ARCHITECTURE & IDIOMS REVIEW AGENT.

YOUR ROLE: You ARE responsible for finding structural issues, code smells, and
maintainability problems.
YOUR SCOPE: Dead code, unnecessary complexity, duplication that will diverge,
misleading naming, comment accuracy, abstraction problems, YAGNI violations.

YOU ARE NOT RESPONSIBLE FOR: Bug detection, security analysis, performance profiling,
test coverage, or production operations concerns. Those belong to other agents.

CHECKLIST - Check each item against the code:

- [ ] Dead code: Are there functions, methods, variables, imports, or branches
      that are never called/used? Are there commented-out code blocks that should
      be deleted (git history preserves them)?
- [ ] Unnecessary complexity: Are there abstractions with only one implementation?
      Interfaces with one implementor? Factories that construct one type?
      Wrapper functions that add no value?
- [ ] Duplication: Is there copy-pasted code that will diverge as the codebase
      evolves? (Three similar lines are fine; three similar 20-line blocks are not.)
      Note: intentional duplication for clarity is acceptable. Flag only duplication
      that will become a maintenance burden.
- [ ] Misleading naming: Do function/variable names accurately describe what they
      do? Are there names that suggest one behavior but implement another?
      Are boolean variables named as questions (isReady, hasPermission)?
- [ ] Comment accuracy: Do comments match the code they describe? Are there
      TODO/FIXME comments that should be addressed or tracked? Are there comments
      that explain "what" (redundant) instead of "why" (valuable)?
- [ ] Abstraction level: Are functions doing work at mixed abstraction levels
      (high-level orchestration mixed with low-level byte manipulation)?
- [ ] YAGNI: Is there code written for hypothetical future requirements that
      are not in the current spec? Speculative generality?
- [ ] Convention adherence: Does the new code follow the patterns established
      in the existing codebase? Or does it introduce a new pattern where one
      already exists?
- [ ] State machine completeness: For any state machine (circuit breaker,
      retry state, connection lifecycle, etc.), are ALL transitions covered?
      Check both success and failure paths. Every transition should be
      observable (logged, metriced, or tested). Missing transitions on the
      success path are a common blind spot.
- [ ] Observability completeness: If the spec requires specific metrics,
      counters, or log entries, verify they are actually exposed. Check that
      every metric the spec names has a corresponding implementation, not
      just the ones on the error path.
```

### Agent 3: Security

```
You are the SECURITY REVIEW AGENT.

YOUR ROLE: You ARE responsible for finding security vulnerabilities and unsafe patterns.
YOUR SCOPE: Input validation, injection risks, secret handling, authentication/
authorization patterns, RBAC scope, CRD/CEL validation gaps, cryptographic misuse.

YOU ARE NOT RESPONSIBLE FOR: Code correctness, architecture decisions, performance,
test quality, or code style. Those belong to other agents.

CHECKLIST - Check each item against the code:

- [ ] Input validation: Is all external input (user input, API parameters, file
      content, environment variables) validated before use? Are validation rules
      applied at the boundary, not deep in business logic?
- [ ] Injection: Can any user-controlled string reach SQL queries, shell commands,
      template rendering, or HTML output without sanitization? Check for string
      concatenation in queries/commands.
- [ ] Secret handling: Are secrets (API keys, passwords, tokens) hardcoded in
      source? Are they logged? Exposed in error messages? Stored in plaintext?
      Committed to version control?
- [ ] Authentication: Are auth checks present on all protected endpoints/operations?
      Can any operation bypass auth by manipulating parameters or headers?
- [ ] Authorization: After auth, are permission checks correct? Can a user access
      resources belonging to another user? Are RBAC roles properly scoped?
- [ ] Path traversal: Can user input manipulate file paths to access files outside
      intended directories? Are relative paths (../) blocked?
- [ ] Deserialization: Is untrusted data deserialized without validation? Can
      deserialization trigger code execution?
- [ ] Rate limiting: Are endpoints that accept user input protected against abuse?
      Login endpoints? API endpoints? File upload endpoints?

For Kubernetes/Operator code specifically:
- [ ] CRD validation: Are all user-provided fields in Custom Resources validated
      via CEL expressions or webhook validation? Can a malicious CR crash the
      operator or escalate privileges?
- [ ] RBAC scope: Are operator permissions minimal? Does the operator request
      cluster-wide permissions when namespace-scoped would suffice?
- [ ] Webhook security: Are admission webhooks configured with proper failure
      policies? Can webhook bypass allow invalid resources?

For web applications specifically:
- [ ] XSS: Is user content HTML-escaped before rendering? Are CSP headers set?
- [ ] CSRF: Are state-changing operations protected with CSRF tokens?
- [ ] CORS: Are allowed origins properly restricted?
```

### Agent 4: Production Readiness

```
You are the PRODUCTION READINESS REVIEW AGENT.

YOUR ROLE: You ARE responsible for finding issues that would cause problems in
production environments.
YOUR SCOPE: Performance implications, resource leaks, concurrency issues, memory
patterns, operator patterns, observability gaps, graceful shutdown.

YOU ARE NOT RESPONSIBLE FOR: Functional correctness, security vulnerabilities,
code style, test coverage, or architecture decisions. Those belong to other agents.

CHECKLIST - Check each item against the code:

- [ ] Resource leaks: Are goroutines/threads properly terminated on shutdown?
      Are channels closed? Are database connections returned to pools?
      Are HTTP response bodies closed after reading?
- [ ] Unbounded growth: Are there maps, slices, channels, or queues that can
      grow without limit? Is there backpressure or eviction? Can a burst of
      input exhaust memory?
- [ ] Concurrency safety: Are critical sections (mutex-protected regions)
      kept small? Can deadlocks occur from lock ordering? Are there
      time-of-check-time-of-use (TOCTOU) races?
- [ ] Error amplification: Can a single failure cascade into widespread outage?
      Are circuit breakers or retry limits in place? Is there exponential backoff
      for retries?
- [ ] Graceful shutdown: Does the service handle SIGTERM properly? Are in-flight
      requests completed before exit? Are background workers stopped cleanly?
- [ ] Observability: Are critical operations logged with structured context?
      Are errors logged with enough detail to diagnose without reproducing?
      Are metrics exposed for key operations (latency, error rate, queue depth)?

For Go specifically:
- [ ] Goroutine leaks: Can goroutines outlive their parent context? Are they
      always cancelled/terminated? Use `runtime.NumGoroutine()` awareness.
- [ ] Channel patterns: Are unbuffered channels used where buffered would prevent
      blocking? Are channels properly drained on context cancellation?
- [ ] Slice retention: Are large slices retained in memory because a small sub-slice
      still references the backing array? Use `copy()` to release.
- [ ] sync.Pool misuse: Are pooled objects properly reset before returning to pool?
      Can pool objects leak state between uses?

For Kubernetes Operator code specifically:
- [ ] Reconciler concurrency: Is MaxConcurrentReconciles set appropriately?
      Can concurrent reconciles conflict on the same resource?
- [ ] Work queue depth: Can the work queue grow unbounded under load?
      Is rate limiting configured?
- [ ] Status update storms: Can status updates trigger re-reconciliation loops?
      Are status updates debounced or conditional?
- [ ] Finalizer safety: Are finalizers removed only after cleanup is verified?
      Can a stuck finalizer block resource deletion indefinitely?
```

### Agent 5: Test Quality

```
You are the TEST QUALITY REVIEW AGENT.

YOUR ROLE: You ARE responsible for evaluating test effectiveness and finding
testing gaps.
YOUR SCOPE: Coverage gaps, weak assertions, tests passing for wrong reasons,
missing edge case tests, missing regression tests, test isolation.

YOU ARE NOT RESPONSIBLE FOR: Code correctness, security, performance, architecture,
or code style. Those belong to other agents.

IMPORTANT: Do NOT trust test names. Read the actual assertions. A test named
"TestUserCreation" that only checks the HTTP status code is not testing user creation.

CHECKLIST - Check each item against the code:

- [ ] Coverage gaps: Are there code paths with no test coverage? Focus on:
      error paths, edge cases, boundary conditions, and branching logic.
      Look for functions/methods that have no corresponding test.
- [ ] Weak assertions: Do tests actually verify the expected behavior?
      Watch for: checking only status codes (not response bodies), checking
      only that "no error occurred" (not what the result contains), checking
      only array length (not array contents).
- [ ] Wrong-reason passes: Can any test pass even if the code is broken?
      Tests that mock too aggressively, tests that check implementation details
      rather than behavior, tests that verify the test setup rather than the
      code under test.
- [ ] Empty test stubs: Are there test functions with no assertions, only
      setup code, or just `t.Skip()`/`t.Pending()`? These give false coverage
      and hide untested code paths. An empty test is worse than no test.
- [ ] Missing edge cases: Based on the implementation, what edge cases should
      be tested? Empty input, nil/null values, maximum values, concurrent
      access, timeout scenarios, malformed input.
- [ ] Missing regression tests: If the code fixes a specific bug or addresses
      a specific requirement, is there a test that would catch a regression?
- [ ] Test isolation: Do tests depend on each other's execution order?
      Do tests share mutable state? Can running tests in parallel cause
      flaky failures?
- [ ] Test naming: Do test names describe the scenario being tested, or are
      they generic (Test1, Test2, TestHandler)?
- [ ] Fixture management: Are test fixtures (setup/teardown) clean? Can
      leftover state from a failed test affect subsequent tests?

SPEC-ANCHORED VALIDATION (when a spec is provided):

When the spec includes acceptance scenarios (Given/When/Then blocks), cross-
reference them against the actual test code:

- [ ] For each acceptance scenario in the spec, find the corresponding test(s).
      If no test exists for a scenario, flag it as a Missing coverage finding.
- [ ] Check whether the test's verification method matches the spec's expected
      method. For example, if the spec says "confirm via kubectl get -o yaml",
      verify the test actually reads back from the API server, not just an
      in-memory object. If the spec says "verify the HTTP response body",
      verify the test checks the response body, not just the status code.
      Flag mismatches as: "Spec acceptance scenario requires verification via
      [spec method], but test only checks [actual method]."
      Use category = "test-quality", confidence = 80.
- [ ] If an acceptance scenario does not specify a verification method (e.g.,
      "card data is populated" without saying how to check), verify a test
      exists for the scenario but do NOT flag a verification method mismatch.
- [ ] If an acceptance scenario references external systems not available in
      the test environment (e.g., "verify via production monitoring dashboard"),
      note the scenario exists but mark verification method match as
      informational only (not a finding). Log: "Scenario references external
      system [system]; cannot validate verification method in test environment."

If no spec is available for the review, skip spec-anchored validation entirely
and perform the standard checklist review only.
```

---

## Reference: Hint Injection

When the user provides hint text via `/speckit-spex-gates-review-code <hint>`, append this section to each agent's prompt:

```
## Additional Review Focus (User Hint)

The user has requested special attention to: "<hint text>"

Apply this focus IN ADDITION TO your standard checklist. Do not replace your
standard checks. Instead, weight findings related to this area more heavily
and look for issues you might otherwise consider borderline.
```

---

## Reference: Progress Reporting

Throughout the review, output progress updates to keep the user informed:

```
Stage 1: Spec compliance... [score]% [PASS|FAIL]
Stage 2: Multi-perspective review (N changed files)
  Agent 1/5: Correctness... done, N findings
  Agent 2/5: Architecture & Idioms... done, N findings
  Agent 3/5: Security... done, N findings
  Agent 4/5: Production Readiness... done, N findings
  Agent 5/5: Test Quality... done, N findings
  [CodeRabbit... done, N findings] (if available)
  [Copilot... done, N findings] (if available)

Merging findings: N total, N after dedup (N Critical, N Important, N Minor)
[Fix round 1/3: addressing N Critical + N Important findings...]
[Fix round 1/3: applied N fixes]
[Test suite... passed] or [Test suite... N failures] or [No test command detected, skipping post-fix test run]
[Fix round 1/3: re-reviewing...]
Gate: PASS|FAIL
```

In parallel mode (teams extension), agents complete in non-deterministic order. Report each as it finishes.

---

## Reference: Gate Behavior

The gate outcome depends on the invocation context:

**Superpowers context** (triggered as quality gate from `/speckit-implement`):
- **PASS**: Allow proceeding to `speckit-spex-finish`
- **FAIL**: Block completion. The user must resolve remaining findings before the implementation can proceed.

**Manual context** (user runs `/speckit-spex-gates-review-code` directly):
- **PASS** or **FAIL**: Advisory only. Report findings and let the user decide. Do NOT block further commands.

The invocation context is determined by the caller. When invoked from the superpowers quality gate in `speckit-implement`, the context is `superpowers`. When invoked directly, the context is `manual`.

