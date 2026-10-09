---
description: "Post-planning quality validation with coverage matrix, red flag scanning, and task quality enforcement"
---

# Post-Planning Quality Validation

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous pipeline. Check the `ask` field:
- If `ask` is `"smart"` or `"never"`: suppress all user prompts (do NOT prompt the user interactively), complete the review autonomously, and return immediately so the pipeline can advance.
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
- **Right-sized**: Setup, configuration, scaffolding, and documentation steps are folded into the task whose deliverable needs them. Split only where a reviewer could meaningfully reject one task while approving its neighbor. Each task ends with an independently testable deliverable.

Also check:
- Every task specifies concrete file paths (not "somewhere" or "TBD")
- Phase ordering is logical (setup before core, tests before integration)
- No tasks duplicate work already covered by other tasks
- Tasks that consume outputs from earlier tasks declare explicit **Interfaces** (function names, parameter types, return types). A task's implementer sees only their own task; the Interfaces block is how they learn the names and types neighboring tasks use.
- If the spec has project-wide requirements (version floors, dependency limits, naming rules, platform requirements), the plan includes a **Global Constraints** section with those values copied verbatim from the spec. Every task implicitly inherits this section.
- The plan header includes a **Spec:** field pointing to the spec file it implements. The plan argues from the spec, so the spec path travels with it; executors read both.

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

### Review Focus (uncovered failure modes)

The coverage matrix proves every *stated* requirement has a task. This check looks past the stated list. A spec is a vision document: it says what the software must do, not every input it will meet, and its silence on an input is not permission for that input to break the program.

Scan for the input classes or failure modes the spec *implies* but no task's tests exercise. Name the ones most likely to bite a real user (empty input, malformed data, concurrent access, missing dependency, boundary values, and the like). For each, there should be a task whose tests pin that behavior. If the plan has a **Review Focus** section listing these, verify each listed item has its test added to the owning task. If the plan has no such section, flag the most likely uncovered modes as gaps and suggest adding tests to the owning tasks. Finding none is a valid outcome, but only after the check was actually run.

## 3. Red Flag Scanning

Search plan.md and tasks.md for vague or incomplete language:

```bash
SPEC_DIR="specs/[feature-name]"
rg -i "figure out|tbd|todo|implement later|somehow|somewhere|not sure|maybe|probably|add appropriate|add validation|handle edge cases|similar to task" "$SPEC_DIR/plan.md" "$SPEC_DIR/tasks.md" || echo "No red flags found"
```

A plan carries the decisions the implementer cannot make alone: which files, which names and signatures, which values from the spec, which tests prove each task. It is not a transcript of the code. Both under-specification (a step that decides nothing) and over-specification (a function body the signature and tests already determine) are failures. Scan for both.

**Under-specification** (the step leaves a decision unmade):
- "Figure out..." = missing research, needs concrete approach
- "TBD" / "TODO" = incomplete planning, must be resolved
- "Implement later" = deferred work, scope explicitly
- "Add appropriate error handling" / "add validation" / "handle edge cases" = vague placeholder; name the behavior and the test that pins it
- "Write tests for the above" without the test's name and assertions = test steps must carry the assertions, as code, with the spec's exact values
- A type, function, or method referenced by no task's Interfaces block = undefined dependency
- Missing file paths = tasks are not actionable

**Over-specification** (the step transcribes code the implementer would write anyway):
- A full function body where the exact signature (name, parameters, return type), its file, and the task's tests already determine the implementation. A code step should carry the signature + file + spec-pinned values; a body appears only for an algorithm those do not determine, or for exact copy the spec fixes.
- "Similar to Task N" followed by repeated code = reference that task's **Interfaces** block instead; the plan does not repeat another task's code. (This supersedes the old "repeat the code" guidance: spex plans carry Interfaces blocks precisely so code need not be duplicated across tasks read out of order.)

**Proportion check:** Compare the plan's length to the spec's. A plan several times longer than the spec it implements, or one where code blocks are most of the document, has written the code instead of planning it. When this happens, flag it and suggest replacing function bodies with signatures, test names, and assertions, then confirming each step still lets the implementer write exactly one reasonable thing.

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
  4. [review-focus] Empty-token input implied by FR-003 has no task exercising it
  5. [red-flag] tasks.md line 42: "TBD" placeholder
  6. [proportion] Task T005 transcribes a full function body its signature and tests already determine
  7. [nfr] NFR-002 "response time < 200ms" has no measurement method
```

Then ask the user how to proceed (skip in autonomous mode, default to "Fix all"):

{harness:interactive-choice}:
- header: "Findings"
- Options (single-select):
  - "Fix all": "Address every finding automatically"
  - "Let me pick": "Select specific findings to fix (you can add comments)"
  - "Skip": "Proceed without changes"

**If "Fix all"**: Apply fixes to plan.md and/or tasks.md for each finding, then re-run the relevant checks to confirm resolution.

**If "Let me pick"**: Present a multi-select prompt, listing up to 4 findings as options (if more than 4, batch them across multiple rounds). Each option's label is the short finding (e.g., "#1 Task T003 not actionable") and the description is the detail. The user can select which to fix and use "Other" to add comments or instructions for specific findings.

After the user selects findings, apply fixes to plan.md and/or tasks.md. For each selected finding:
1. Read the user's comment (if any) to understand their intent
2. Make the minimal targeted edit to resolve the finding
3. Report what was changed

After all selected fixes are applied, re-present any remaining unaddressed findings as informational (no further prompting).

**If "Skip"**: Proceed without changes. Note that blocking issues remain unresolved.

## 8. Suggest Collaboration Skills

Skip this step in autonomous mode.

After plan review completes, check whether the plan has characteristics that benefit from collaboration skills. Suggest them when ANY of these apply:

- The plan has **multiple phases** or the tasks group into distinct stages
- The plan mentions **reviewers, stakeholders, or collaborators**
- The feature touches **multiple subsystems** (flagged in step 0)

When applicable, print:

```
Before implementation, consider:
  /speckit-spex-collab-phase-split  - propose how to split into separate PRs
  /speckit-spex-collab-reviewers    - generate a review guide for PR reviewers
```

This is informational, not blocking. Do not prompt or gate on it.

## 9. Update Flow State

**MANDATORY: Update flow state.** This MUST run on every exit path, including early returns (e.g., "already passed", "no findings"). Use the flow state script:

```bash
FLOW_STATE=".specify/extensions/spex-gates/scripts/spex-flow-state.sh" && [ -x "$FLOW_STATE" ] && "$FLOW_STATE" gate review-plan
```

This updates the status line to show `P ✓`.

## 10. Auto-Commit (if enabled)

Check the git extension's auto-commit config. Only commit if the user has enabled auto-commit for this stage:

```bash
GIT_CONFIG=".specify/extensions/git/git-config.yml"
AUTO_COMMIT=$(yq -r '.auto_commit.after_tasks.enabled // .auto_commit.default // false' "$GIT_CONFIG" 2>/dev/null)
AUTO_COMMIT=${AUTO_COMMIT:-false}
```

If `AUTO_COMMIT` is `true` and there are uncommitted changes:

```bash
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard specs/ .specify/ 2>/dev/null)" ]; then
  git add -u
  git add specs/ .specify/ 2>/dev/null || true
  git commit -m "review-plan: gate passed, artifacts updated

Assisted-By: 🤖 Claude Code"
fi
```

Do NOT suggest manual commit commands or next steps. The workflow continues automatically (either via the ship pipeline or the user's next command).

## Integration

**This command is invoked by:**
- The spex-gates extension hook for `after_tasks`
- Users directly via `speckit.spex-gates.review-plan`

**This command invokes:**
- Prerequisite check for `.specify/` directory
