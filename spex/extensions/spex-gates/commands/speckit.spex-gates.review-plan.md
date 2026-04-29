---
description: "Post-planning quality validation with coverage matrix, red flag scanning, and task quality enforcement"
---

# Post-Planning Quality Validation

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous pipeline. Check the `ask` field:
- If `ask` is `"smart"` or `"never"`: suppress all user prompts (do NOT use AskUserQuestion), complete the review autonomously, and return immediately so the pipeline can advance.
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

In autonomous mode: do NOT output a completion summary, do NOT ask "Shall I proceed?", do NOT suggest next steps. Complete the review and return.

## Overview

This skill validates plan and task quality after `/speckit-plan` and `/speckit-tasks` have run. It checks coverage, scans for red flags, and enforces task quality standards.

## Prerequisites

Spec-kit must be initialized. If `.specify/` directory does not exist, tell the user to run `/spex:init` first and stop.

**Both plan.md and tasks.md MUST exist before running this skill.** If either is missing, stop with an error:

```bash
SPEC_DIR="specs/[feature-name]"
[ -f "$SPEC_DIR/plan.md" ] && echo "plan.md found" || echo "ERROR: plan.md missing - run /speckit-plan first"
[ -f "$SPEC_DIR/tasks.md" ] && echo "tasks.md found" || echo "ERROR: tasks.md missing - run /speckit-tasks first"
```

If either file is missing, stop and instruct the user to generate the missing artifact.

## 0. Scope Check

Before detailed validation, check whether the plan attempts to cover multiple independent subsystems in a single document. Indicators:

- Tasks span subsystems with no shared interfaces or dependencies
- The plan has distinct groups of tasks that could each produce working software independently
- File changes cluster into unrelated areas of the codebase

If the plan covers multiple independent subsystems, flag it: "This plan may benefit from being split into separate plans, one per subsystem. Each plan should produce working, testable software on its own."

This is advisory, not blocking. Some plans legitimately span subsystems.

## 1. Task Quality Enforcement

After tasks.md exists, verify every task meets these criteria:

- **Actionable**: Clear what to do (not "figure out..." or "investigate...")
- **Testable**: Can verify completion objectively
- **Atomic**: One clear outcome per task
- **Ordered**: Dependencies between tasks are respected, phases are sequenced correctly

Also check:
- Every task specifies concrete file paths (not "somewhere" or "TBD")
- Phase ordering is logical (setup before core, tests before integration)
- No tasks duplicate work already covered by other tasks

Verify the plan includes a file structure mapping:
- Files to be created or modified are listed with their responsibilities
- Each file has one clear responsibility (not vague "utils" or "helpers" without defined scope)
- Design units have clear boundaries and well-defined interfaces
- In existing codebases, the plan follows established patterns rather than unilaterally restructuring

If the plan lacks a file structure mapping, note it as a gap: tasks without a file map are harder to verify for completeness and overlap.

If tasks fail these checks, note the issues and suggest refinements.

## 2. Coverage Matrix

Produce a coverage matrix mapping every spec requirement to its implementing tasks:

```
Requirement 1 -> Tasks [X,Y]
Requirement 2 -> Tasks [Z]
NFR 1         -> Tasks [W]
...
```

Flag any requirement without task coverage. All requirements must have at least one implementing task.

Also verify:
- Every error case in the spec has a handling approach
- Every edge case from the spec is addressed
- Success criteria have verification approaches

## 3. Red Flag Scanning

Search plan.md and tasks.md for vague or incomplete language:

```bash
SPEC_DIR="specs/[feature-name]"
rg -i "figure out|tbd|todo|implement later|somehow|somewhere|not sure|maybe|probably|add appropriate|add validation|handle edge cases|similar to task" "$SPEC_DIR/plan.md" "$SPEC_DIR/tasks.md" || echo "No red flags found"
```

Review any matches:
- "Figure out..." = missing research, needs concrete approach
- "TBD" / "TODO" = incomplete planning, must be resolved
- "Implement later" = deferred work, scope explicitly
- "Add appropriate error handling" / "add validation" / "handle edge cases" = vague placeholders, must show actual code
- "Write tests for the above" (without actual test code) = test code must be included
- "Similar to Task N" = repeat the code, the engineer may read tasks out of order
- Steps that describe what to do without showing how = code blocks required for code steps
- Missing file paths = tasks are not actionable

## 4. Type and Name Consistency

Check that types, method signatures, property names, and function names used across tasks are consistent:

- If a function is called `clearLayers()` in Task 3, it must not be called `clearFullLayers()` in Task 7
- If a type is defined in an early task, later tasks must reference the same type name
- If a constant or config key is introduced, verify spelling is consistent across all tasks
- If an API endpoint path is defined, verify all references use the same path

Inconsistencies between tasks are plan bugs that will become code bugs during implementation.

## 5. NFR Validation

For each non-functional requirement in the spec, verify the plan includes:
- A concrete measurement method (not just "should be fast")
- A validation approach (how will you verify the NFR is met?)
- Acceptance thresholds where applicable

If any NFR lacks a measurement method, flag it.

## 6. Present Results

Report to the user:
- Task quality check results (pass/issues)
- Coverage matrix summary
- Red flag scan results
- NFR validation results

## 7. Offer Remediation

After presenting results, collect ALL findings from steps 0-4 into a numbered list. Include both blocking and non-blocking issues. Present them as a consolidated findings summary:

```
Findings:

  1. [BLOCKING] Task T003 is not actionable: "figure out auth approach"
  2. [advisory] Plan may benefit from splitting (2 independent subsystems)
  3. [gap] FR-007 has no implementing task in the coverage matrix
  4. [red-flag] tasks.md line 42: "TBD" placeholder
  5. [nfr] NFR-002 "response time < 200ms" has no measurement method
```

Then ask the user how to proceed (skip in autonomous mode, default to "Fix all"):

Use AskUserQuestion with:
- header: "Findings"
- multiSelect: false
- Options:
  - "Fix all": "Address every finding automatically"
  - "Let me pick": "Select specific findings to fix (you can add comments)"
  - "Skip": "Proceed without changes"

**If "Fix all"**: Apply fixes to plan.md and/or tasks.md for each finding, then re-run the relevant checks to confirm resolution.

**If "Let me pick"**: Use AskUserQuestion with multiSelect: true, listing up to 4 findings as options (if more than 4, batch them across multiple rounds). Each option's label is the short finding (e.g., "#1 Task T003 not actionable") and the description is the detail. The user can select which to fix and use "Other" to add comments or instructions for specific findings.

After the user selects findings, apply fixes to plan.md and/or tasks.md. For each selected finding:
1. Read the user's comment (if any) to understand their intent
2. Make the minimal targeted edit to resolve the finding
3. Report what was changed

After all selected fixes are applied, re-present any remaining unaddressed findings as informational (no further prompting).

**If "Skip"**: Proceed without changes. Note that blocking issues remain unresolved.

## 8. Update Flow State

After validation completes (regardless of whether findings were fixed or skipped), mark the review-plan gate as passed in the flow state:

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ] && jq -e '.mode == "flow"' "$STATE_FILE" >/dev/null 2>&1; then
  jq '.review_plan_passed = true | .running = ""' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi
```

This updates the status line to show `P ✓`.

## Integration

**This command is invoked by:**
- The spex-gates extension hook for `after_tasks`
- Users directly via `speckit.spex-gates.review-plan`

**This command invokes:**
- Prerequisite check for `.specify/` directory
