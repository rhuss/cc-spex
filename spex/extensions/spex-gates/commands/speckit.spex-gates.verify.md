---
description: "Final verification gate: tests, code hygiene, spec compliance, and drift check"
---

# Verification Before Completion (Spec-Aware)

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous pipeline. Check the `ask` field:
- If `ask` is `"smart"` or `"never"`: {harness:suppress-prompts-verify} autonomously, and return immediately so the pipeline can advance.
- If `ask` is `"always"`: prompt the user as normal.

```bash
if [ -f ".specify/.spex-state" ]; then
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  ASK=$(jq -r '.ask // "always"' .specify/.spex-state 2>/dev/null)
  if [ "$STATUS" = "running" ] && [ "$ASK" != "always" ]; then
    echo "AUTONOMOUS_MODE=true"
  else
    echo "AUTONOMOUS_MODE=false"
  fi
else
  echo "AUTONOMOUS_MODE=false"
fi
```

In autonomous mode: do NOT output a completion summary, do NOT ask "Shall I proceed?", do NOT suggest next steps. Complete the verification and return.

## Arguments

```text
/speckit-spex-gates-verify [--embedded] [--auto] [<path/to/spec.md>]
```

- `--embedded`: set `EMBEDDED=true`. Finish and submit pass this flag when they invoke verify as one phase of their own run. Embedded runs perform every gate and record a pass exactly like standalone runs, but skip step 8 (no completion banner, no removal of `.specify/.spex-state`), because the caller owns state cleanup. Without the flag, `EMBEDDED=false` and step 8 runs as described.
- `--auto`: set `AUTONOMOUS_MODE=true` regardless of `.specify/.spex-state`. Finish passes this when it runs unattended (`finish --auto` or a ship pipeline), so verify never prompts in that case.
- `<path/to/spec.md>`: optional spec to verify. Any remaining argument that is not a flag is the spec path.

```bash
EMBEDDED=false
SPEC_ARG=""
for arg in "$@"; do
  case "$arg" in
    --embedded) EMBEDDED=true ;;
    --auto) AUTONOMOUS_MODE=true ;;
    --*) ;;  # ignore unknown flags
    *) SPEC_ARG="$arg" ;;
  esac
done
```

## Overview

**Core principle:** Evidence before claims, always.

Verify implementation is complete by running tests AND validating spec compliance.

**Key Steps:**
- **Step 0: Closeout gate** (blocks on unresolved Critical/Important findings)
- Step 0a: Walkthrough reminder (runbook status)
- Step 1: Run tests (existing behavior)
- **Step 2: Code hygiene review** (mechanical defect detection)
- **Step 3: Validate spec compliance** (spec-driven)
- **Step 4: Check for spec drift** (spec-driven)
- Blocks completion if closeout gate, tests, code hygiene, OR spec compliance fails

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this message, you cannot claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. CHECK SPEC: Does implementation match spec?
   - If NO: State actual compliance with evidence
   - If YES: State compliance score WITH evidence
6. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## When to Use

- After implementation and code review
- Before claiming work is complete
- Before committing/merging/deploying
- As final gate in the implementation pipeline (via spex-gates hook)

## Spec Selection

Resolve `FEATURE_SPEC` (the spec file) and `FEATURE_DIR` (its directory, relative to the repository root, for example `specs/055-x`) once. Every later step uses this `FEATURE_DIR`, and step 7 records the pass for exactly this directory.

**If a spec path was given** (`SPEC_ARG` is set), use it directly:

```bash
if [ -n "$SPEC_ARG" ]; then
  FEATURE_SPEC="$SPEC_ARG"
  FEATURE_DIR=$(dirname "$SPEC_ARG")
fi
```

If `$FEATURE_SPEC` does not exist, report `no spec` (see below) and stop.

**Otherwise**, attempt branch-based resolution:

```bash
.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null
```

If this succeeds (outputs JSON with `FEATURE_SPEC`), use the resolved spec path. Parse the JSON to extract `FEATURE_SPEC` and `FEATURE_DIR`, and convert `FEATURE_DIR` to a path relative to the repository root (strip the `$(git rev-parse --show-toplevel)/` prefix).

If this fails (not on a feature branch, no matching spec directory):

- **Unattended run** (`AUTONOMOUS_MODE=true`): do not show a picker. Report `no spec` and stop:
  ```
  VERIFY_RESULT:
    status: NO_SPEC
  ```
- **Interactive run**: fall back to interactive selection:

```bash
find specs/ -name "spec.md" -type f 2>/dev/null | head -20
```

**If specs found:** Present list and ask user to select one {harness:interactive-choice-skip}. Set `FEATURE_SPEC` to the chosen file and `FEATURE_DIR` to its directory. If the user cancels the selection, emit the `NO_SPEC` result block below and stop.

**If no specs found:** Inform user:
```
No specs found in specs/ directory.

Verification requires a spec to validate against.
Use `speckit-spex-brainstorm` or `/speckit-specify` to create one first.
```

Then emit the result block and stop (callers such as finish read it):
```
VERIFY_RESULT:
  status: NO_SPEC
```

## The Process

**Capture the code state before the first gate.** The pass recorded in step 7 must cover exactly the code the gates ran against. `begin` stores the current fingerprint in the git directory, so step 7 finds it even when it runs in a separate shell:

```bash
RECORD=".specify/extensions/spex-gates/scripts/spex-verify-record.sh"
[ -f "$RECORD" ] || RECORD="spex/scripts/spex-verify-record.sh"
sh "$RECORD" begin
```

If `begin` fails, continue; step 7 then records without the comparison and adds a warning.

If any step below edits code (for example a test or hygiene fix), the gates already run no longer cover the new code: after the fix, restart from step 0 (run `begin` again). Step 7 refuses to record a pass when the code no longer matches the stored start state.

### 0. Closeout Gate

Before any other verification, check whether unresolved Critical or Important findings remain from a deep review.

Use the `FEATURE_DIR` resolved in Spec Selection (do not re-derive it). Run the closeout gate script:

```bash
CLOSEOUT_GATE=".specify/extensions/spex-gates/scripts/spex-closeout-gate.sh"
if [ -x "$CLOSEOUT_GATE" ] && [ -n "${FEATURE_DIR:-}" ]; then
  GATE_OUTPUT=$("$CLOSEOUT_GATE" "$FEATURE_DIR" 2>&1) || {
    echo "Closeout gate failed: $GATE_OUTPUT"
    # STOP: Do not proceed. Unresolved findings must be fixed and review re-run.
    exit 1
  }
fi
```

**If the gate fails** (exit code non-zero): STOP. Report the blocking findings from the gate output and do not proceed to any further verification steps. The developer must fix the findings and re-run the deep review. Emit the step 7 `VERIFY_RESULT` block with `closeout` as the failing gate; do not record a pass.

**If the gate passes** (exit code 0, or script not found, or no spec dir): proceed to the next step.

### 0a. Walkthrough Reminder

Before running verification, read the runbook status for the feature:

```bash
STATUS=".specify/extensions/spex-gates/scripts/spex-runbook-status.sh"
[ -f "$STATUS" ] || STATUS="spex/scripts/spex-runbook-status.sh"

# FEATURE_DIR comes from Spec Selection
WT_STATUS="missing"
WT_NOT_TESTABLE=false
if [ -n "$FEATURE_DIR" ]; then
  SHOW=$("$STATUS" show "$FEATURE_DIR" 2>/dev/null)
  WT_STATUS=$(printf '%s' "$SHOW" | jq -r '.status // "missing"')
  WT_NOT_TESTABLE=$(printf '%s' "$SHOW" | jq -r '.not_testable')
fi
```

**Remind when there is no runbook, or the runbook is not `passed`, and the feature is not `not_testable`** (`WT_NOT_TESTABLE` is not `true` AND `WT_STATUS` is not `passed`):

Display a reminder (informational only, does NOT block verification):
```
NOTE: This feature has not been tried with a runbook (status: <WT_STATUS>).
Consider running `/speckit-spex-walkthrough` to try the feature before verifying.
```

**If the runbook is `passed`** or **the feature is `not_testable`**: proceed silently.

### 1. Run Tests

**Execute all tests:**
```bash
# Run full test suite
npm test  # or pytest, go test, etc.
```

**Check results:**
- All tests passing?
- No flaky tests?
- Coverage adequate?

**If tests fail:**
- STOP: Fix tests before proceeding
- Do not skip this step
- Do not claim completion

### 2. Code Hygiene Review

**Before checking spec compliance, review every changed file for mechanical defects.
These are craft-level issues that no spec describes but that cause real bugs.**

**For each function you wrote or modified, check:**

#### Dead Code and Logic
- [ ] Every conditional branch produces a **different** outcome (no branches that do the same thing)
- [ ] Every parameter is **actually used** to change behavior (no unused parameters)
- [ ] Every exported function has **at least one caller** outside tests (no orphaned API surface)
- [ ] No variables assigned but never read

#### Copy and Mutation Safety
- [ ] When copying a data structure, verify whether **nested references are shared**
- [ ] If the copy is later mutated, confirm the original is **not affected**
- [ ] If a function receives a pointer/reference, verify whether it is expected to **mutate or read-only**

#### Cleanup and Consistency
- [ ] When removing/disabling something, verify **all references** to it are also cleaned up (no orphaned entries, dangling references, stale indices)
- [ ] When adding to a collection, verify **duplicates are handled** (deduplicate or reject)
- [ ] When deriving a value from an identifier, verify the **derivation uses the correct source** (e.g., a display name vs an internal ID vs a type name are different things)

#### Unnecessary Operations
- [ ] No sorting/ordering when the result doesn't depend on order (counting, summing, existence checks)
- [ ] No intermediate data structures that serve no purpose (building a list just to iterate it once)

**If any issue found:** Fix before proceeding. These are not style nits; they are latent bugs.

### 3. Validate Spec Compliance

**Load spec:**
```bash
cat specs/features/[feature-name].md
```

**Assess compliance against LIVE spec items only (after an evolve).**

A feature that went through `speckit-spex-evolve` records accepted changes with flow-back markers. Build the compliance set from **live** spec items only — those with no trailing `**SUPERSEDED by <ID>**`, `**SUPERSEDED**` (the ID-less form on superseded acceptance scenarios and edge-case entries), or `**RETIRED**` marker:

- **FR-022**: An item marked `SUPERSEDED by <ID>`, the ID-less `**SUPERSEDED**`, or `RETIRED` is no longer intent. It MUST NOT be counted as `MISSING` and MUST NOT fail the gate. Assess its live replacement instead.
- **FR-023**: Do NOT raise a drift or compliance finding whose only evidence is the wording of a completed task (`- [x]`/`- [X]`) in `tasks.md`. A completed task's old wording differing from the current spec is not a gap.
- **FR-024**: Still mark every **live** spec item the code does not satisfy as `MISSING`. Excluding superseded/retired items MUST NOT suppress genuine gaps against current intent.

**Check each LIVE requirement and emit a machine-readable compliance matrix:**

For each live functional requirement in the spec, determine its status. There are exactly two valid statuses:

- **IMPLEMENTED**: Code fully implements the requirement. You can point to the function, the test, and the behavior.
- **MISSING**: Code does not implement the requirement, or implements it only partially.

There is NO "PARTIAL" status. There is NO "COMPLIANT (with documented gap)" status. There is NO "IMPLEMENTED (known limitation)" status. If the code doesn't fully do what the spec says MUST happen, the status is MISSING.

```markdown
Functional Requirement 1: [From spec]
  Status: IMPLEMENTED | MISSING
  Evidence: [file:line where it's implemented, or why it's missing]

Functional Requirement 2: [From spec]
  Status: IMPLEMENTED | MISSING
  Evidence: [file:line where it's implemented, or why it's missing]
```

**After checking ALL requirements, emit a machine-readable gate result block:**

```
SPEC_COMPLIANCE_RESULT:
  total: N
  implemented: N
  missing: N
  percentage: XX%
  gate: PASS | FAIL
```

The gate value is determined mechanically: if `missing > 0`, the gate is `FAIL`. No exceptions. No judgment calls. No "but it's a known gap." If the spec says MUST and the code doesn't, it's MISSING, and the gate is FAIL.

**Anti-rationalization guardrails (read these before making your compliance decision):**

You WILL be tempted to let partial compliance pass. You will find plausible reasons. All of them are wrong:

| Rationalization | Why it's wrong |
|-----------------|---------------|
| "It's a known gap" | Known gaps are still gaps. MISSING. |
| "It's documented as future work" | Future work means not implemented. MISSING. |
| "There's a workaround" | Workarounds are not implementations. MISSING. |
| "The spec assumption section mentions this" | Assumptions don't override MUST requirements. MISSING. |
| "It's only partially implemented" | Partial is not complete. MISSING. |
| "The user knows about this" | User awareness doesn't change compliance. MISSING. |

The only valid paths when the gate is FAIL:
1. Implement the missing requirement, then re-run verify
2. Run `/speckit-spex-evolve` to formally remove or defer the requirement from the spec, then re-run verify

**If compliance = 100%:** Proceed to next step.
**If compliance < 100%:** STOP. Do not proceed. Report the MISSING requirements and suggest the two valid resolution paths above.

### 4. Check for Spec Drift

**Compare:**
- What spec says NOW
- What code does NOW
- Any divergence?

**Common drift sources:**
- Spec updated but code not
- Code changed but spec not
- Undocumented additions
- Forgotten requirements

**If drift detected:**
- Document each instance
- Use `speckit-spex-evolve` to reconcile
- Do not proceed with drift

**FR-016 — evolve triggered by verify appended convergence tasks:** When reconciling through `speckit-spex-evolve` causes `/speckit-converge` to append tasks (a `## Phase N: Convergence` section with open `- [ ]` tasks), that is unbuilt work against live intent. Verify MUST NOT pass in this case, and evolve MUST NOT start implementation from inside verify (this takes precedence over evolve's normal implement-and-reconfirm flow). Report `spec compliance` (or `spec drift`) as a failing gate, tell the user to implement the appended convergence tasks and re-run verify, and do not record a pass.

### 5. Verify Success Criteria

**From spec, check each criterion:**

```markdown
Success Criteria (from spec):
- [ ] Criterion 1: [Description]
      Status: Met / Not met
      Evidence: [How verified]

- [ ] Criterion 2: [Description]
      ...
```

**All criteria must be met.**

If any criterion not met:
- STOP: Criterion not met
- Implement missing piece
- Re-verify

### 6. Generate Verification Report

**Report structure:**

```markdown
# Verification Report: [Feature Name]

**Date:** YYYY-MM-DD
**Spec:** specs/features/[feature].md

## Test Results

**Status:** PASS / FAIL

[Test output]

**Summary:**
- Total: X tests
- Passed: X
- Failed: X
- Coverage: XX%

## Spec Compliance

**Status:** COMPLIANT / NON-COMPLIANT

**Compliance Score:** XX%

### Requirements Status
- Functional: X/X (XX%)
- Error Cases: X/X (XX%)
- Edge Cases: X/X (XX%)
- Non-Functional: X/X (XX%)

### Deviations
[List any deviations found]

## Spec Drift Check

**Status:** NO DRIFT / DRIFT DETECTED

[Details if drift found]

## Success Criteria

**Status:** ALL MET / INCOMPLETE

- [x] Criterion 1
- [x] Criterion 2
...

## Overall Status

**VERIFIED - Ready for completion**

OR

**NOT VERIFIED - Issues must be resolved**

**Blocking Issues:**
- [Issue 1]
- [Issue 2]

**Next Steps:**
[What needs to be done]
```

### 7. Make Go/No-Go Decision

**All conditions must be true:**
- [x] All tests passing
- [x] Code hygiene review clean (no dead code, no mutation bugs, no orphans)
- [x] `SPEC_COMPLIANCE_RESULT.gate` is `PASS` (100% compliance, zero MISSING)
- [x] No spec drift
- [x] All success criteria met

**If ALL true:**
- VERIFIED: Proceed to completion
- Safe to commit/merge/deploy
- **Record the pass** for the current code state, so finish and the pre-commit reminder recognize it (also across `/clear` and new sessions, until code outside `specs/` and `brainstorm/` changes):
  ```bash
  RECORD=".specify/extensions/spex-gates/scripts/spex-verify-record.sh"
  [ -f "$RECORD" ] || RECORD="spex/scripts/spex-verify-record.sh"
  # record compares against the start state stored by `begin`
  sh "$RECORD" record --feature "$FEATURE_DIR"
  RECORD_EXIT=$?
  ```
  The recorded feature is exactly the `FEATURE_DIR` that was verified.
  - `RECORD_EXIT=0`: the pass is recorded. If `begin` had failed at the start, add `warning: pass recorded without a start-state check` to the result block.
  - `RECORD_EXIT=1`: code changed while the gates ran, so nothing was recorded and the run is not verified (do not report PASS). Restart **once** from the start of The Process: run `begin` again (the failed `record` removed the start state), then step 0. If `record` exits 1 again on the restarted run, stop and report `ERROR` with `error: code changed during verification` and the output of `git status --short` (outside `specs/` and `brainstorm/`); a test suite that writes untracked artifacts (coverage, reports, snapshots) causes this, and the fix is to add those artifacts to `.gitignore`.
  - Any other non-zero `RECORD_EXIT` (2: no git repository, missing `jq` or Python, unwritable git directory; 127: script not found): the gates passed but the pass could not be recorded. Report PASS and add `warning: pass not recorded: <first stderr line>` to the result block, so the caller knows finish and the pre-commit reminder will not see it.

**If ANY false:**
- NOT VERIFIED: Block completion
- Fix issues before proceeding
- Re-run verification after fixes

**A failed or interrupted run never records a pass.** Only call `record` after every gate above passed in this run. If any step errors, is interrupted, or is skipped, do not call `record`.

**Emit the result block** at the end of every run (callers such as finish read it):

```
VERIFY_RESULT:
  status: PASS | FAIL | NO_SPEC | ERROR
  feature: <FEATURE_DIR>
  failed_gates:
    - <gate>: <one-line reason>
  warning: <only when the pass was not recorded, or recorded without a start-state check>
```

Gate names: `closeout`, `tests`, `code hygiene`, `spec compliance`, `spec drift`, `success criteria`. List only failing gates (empty on PASS). Use `ERROR` with a one-line `error:` field when the run could not complete.

### 8. Completion Celebration

**Skip this entire step when `EMBEDDED=true`**: no banner, and do NOT remove `.specify/.spex-state`. The calling command (finish or submit) owns state cleanup.

**After all verification passes** (go decision is positive) and `EMBEDDED=false`, check if a state file exists:

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ]; then
  MODE=$(jq -r '.mode // empty' "$STATE_FILE" 2>/dev/null)
fi
```

**If a state file exists** (flow or ship mode), display a celebration:

1. **Compute stats:**
   ```bash
   FEATURE=$(jq -r '.feature_branch // "unknown"' "$STATE_FILE" 2>/dev/null)
   STARTED=$(jq -r '.started_at // empty' "$STATE_FILE" 2>/dev/null)
   SPEC_DIR=$(jq -r '.spec_dir // empty' "$STATE_FILE" 2>/dev/null)
   # If spec_dir not in state (ship mode), derive from branch
   [ -z "$SPEC_DIR" ] && SPEC_DIR="specs/$FEATURE"
   REVIEW_COUNT=$(ls "$SPEC_DIR"/REVIEW-*.md 2>/dev/null | wc -l | tr -d ' ')
   COMMIT_COUNT=$(git rev-list --count main..HEAD 2>/dev/null || echo "?")
   ```
   - Duration: compute from `started_at` to now (human-readable, e.g., "2h 15m" or "3d 4h")
   - If `started_at` is empty, skip duration

2. **Display celebration banner:**
   ```
   +-------------------------------------------+
   |                                           |
   |   ALL CHECKS PASSED                       |
   |                                           |
   |   Feature:  <feature_branch>              |
   |   Duration: <duration>                    |
   |   Reviews:  <count> passed                |
   |   Commits:  <count>                       |
   |                                           |
   |   <random sign-off message>               |
   |                                           |
   +-------------------------------------------+
   ```

3. **Sign-off message pool** (select one randomly):
   - "Ship it!"
   - "Another one bites the dust."
   - "That's a wrap."
   - "Clean as a whistle."
   - "Nailed it."
   - "Spec met. Code shipped. Coffee earned."
   - "Nothing left to prove."

4. **Remove state file** after displaying:
   ```bash
   rm -f "$STATE_FILE"
   ```

**If no state file exists**, skip the celebration (no-op).

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Spec compliant | Line-by-line requirement check | "Looks complete" |
| Linter clean | Linter output: 0 errors | Partial check |
| Build succeeds | Build command: exit 0 | Linter passing |
| Bug fixed | Test original symptom: passes | Code changed |
| Requirements met | Line-by-line checklist | Tests passing |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!")
- About to commit/push/PR without verification
- Relying on partial verification
- Thinking "just this once"
- Tired and wanting work over
- **ANY wording implying success without having run verification**
- **Modified CLAUDE.md without explicit user request** (CLAUDE.md is user-maintained, never auto-update)

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence is not evidence |
| "Just this once" | No exceptions |
| "Tests pass" | Did you check spec compliance? |
| "Spec compliant" | Did you run the tests? |
| "I'm tired" | Exhaustion is not an excuse |
| "Partial check is enough" | Partial proves nothing |

## Quality Gates

**This command enforces quality gates:**

1. **All tests must pass**
2. **Code hygiene review clean** (mechanical defects)
3. **100% spec compliance required**
4. **No spec drift allowed**
5. **All success criteria must be met**

**No exceptions. No shortcuts.**

These gates exist to prevent:
- Incomplete implementations
- Untested code
- Spec/code divergence
- False claims of completion

