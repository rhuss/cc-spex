---
description: "Handle spec/code mismatches through AI-guided analysis and user-controlled evolution"
---

# Spec Evolution and Reconciliation

## Overview

Handle spec/code mismatches through AI-guided analysis and user-controlled evolution.

Specs WILL diverge from code. This is normal and healthy. The question is: which should change?

This skill detects divergence, analyzes the mismatch, recommends resolution, and executes the change.

## When to Use

**Use this skill when:**
- Code review detects spec/code mismatch
- Verification finds spec compliance issues
- Developer explicitly requests evolution
- Implementation reveals better approach than spec
- Spec ambiguity discovered during implementation

**Auto-triggered by:**
- `speckit-spex-gates-review-code` (when deviations found)
- `speckit-spex-gates-verify` (when compliance fails)
- `speckit-spex-finish` (when verification finds compliance issues)

**Don't use this skill when:**
- No mismatch exists (everything compliant)
- Spec doesn't exist yet -> Use `/speckit-specify`
- Multiple specs need consolidation -> Use `speckit-spex-spec-refactoring`

## Prerequisites

Spec-kit must be initialized. If `.specify/` directory does not exist, tell the user to run `/spex:init` first and stop.

## Spec Selection

If no spec is specified, discover available specs:

```bash
# List all specs in the project
find specs/ -name "spec.md" -type f 2>/dev/null | head -20
```

**If specs found:** Present list and ask user to select one using the agent's interactive prompt mechanism.

Example:
```
Found 2 specs in this project:
1. specs/0001-user-auth/spec.md
2. specs/0002-api-gateway/spec.md

Which spec needs evolution/reconciliation?
```

**If no specs found:** Inform user:
```
No specs found in specs/ directory.

Spec evolution requires an existing spec to evolve.
Use `speckit-spex-brainstorm` or `/speckit-specify` to create one first.
```

## The Process

### 0. Check Existing Artifacts

Before analyzing or modifying, verify spec-kit artifacts exist:

```bash
# Check what artifacts exist for this feature
SPEC_DIR="specs/[feature-dir]"  # Replace with actual spec directory
echo "Checking for existing artifacts..."
[ -f "$SPEC_DIR/spec.md" ] && echo "spec.md exists" || echo "spec.md missing"
[ -f "$SPEC_DIR/plan.md" ] && echo "plan.md exists" || echo "plan.md not present"
[ -f "$SPEC_DIR/tasks.md" ] && echo "tasks.md exists" || echo "tasks.md not present"
```

**If spec.md is missing:** Cannot proceed with evolution. Use `/speckit-specify` first.

**If plan.md or tasks.md exist, the path depends on whether implementation has started:**

Check `tasks.md` for a **completed task** — a line starting with `- [x]` or `- [X]`.

- **No completed task yet** (pre-implementation): nothing built would be lost, so evolve MAY regenerate `plan.md` and `tasks.md` via `/speckit-plan` and `/speckit-tasks`, as before. This is the pre-implementation path only.
- **At least one completed task** (post-implementation): evolve is spex's **flow-back** implementation. It records accepted changes in `spec.md` and `plan.md` with supersede/retire markers and revision notes, then hands off to `/speckit-converge` to append any remaining work. In this state:
  - **FR-001**: Evolve MUST NOT invoke `/speckit-plan` or `/speckit-tasks`. Regeneration would destroy the completion state spec-kit keeps inside `tasks.md`.
  - **FR-003**: Evolve MUST NOT edit `tasks.md`. After implementation, tasks are added **only** by `/speckit-converge` (append-only).

The per-resolution cascade is defined in "Resolution cascade" below, and the full flow-back mechanics in section 5 (Execute Resolution).

### Persistence model

Before applying the cascade, determine the project's **persistence model** from the constitution (`.specify/memory/constitution.md`). Look for a line of the form `Persistence model: <value>`, matched **leniently** (FR-019):

- case-insensitive for both the `Persistence model:` label and its value;
- an internal hyphen and a space are equivalent within the value, so `living-spec` and `living spec` both match;
- a leading Markdown list marker (`-`, `*`, `+`) and surrounding whitespace are tolerated;
- the line may appear anywhere in the file; the **first** matching line wins.

Recognized values: `flow-back`, `flow-forward`, `living-spec`. When no such line exists, or its value is not one of these three, the model counts as **not declared**: flow-back applies, and evolve states **once** that the project can declare a persistence model with a `Persistence model:` line in its constitution.

Apply the model:

- **flow-back** (this project's default): the per-resolution cascade in "Resolution cascade" below applies once at least one task is complete.
- **flow-forward** (FR-020): a **delivered** feature — one whose tasks are **all** complete — is immutable. Evolve MUST NOT change any file in that feature's directory; instead it recommends starting a new feature directory for the change and explains that this project records post-delivery changes there. Before delivery (not all tasks complete), discoveries are part of delivery, so the normal pre-implementation / flow-back rules apply as usual.
- **living-spec** (FR-021): evolve MAY regenerate `plan.md` and `tasks.md` via `/speckit-plan` and `/speckit-tasks` **only when no task is complete**. Once at least one task is complete, evolve MUST apply the flow-back cascade and MUST NOT regenerate.

### Resolution cascade (flow-back)

**Definitions** (used throughout this skill):

- **Completed task**: a `tasks.md` line starting with `- [x]` or `- [X]`.
- **Open task**: a `tasks.md` line starting with `- [ ]`.
- **Spec item**: a functional requirement, success criterion, acceptance scenario, or edge-case entry in `spec.md`. It is either `live`, `SUPERSEDED by <ID>`, or `RETIRED`.

Once at least one task is complete, each resolution routes through this cascade instead of regenerating artifacts (**FR-002**):

| Resolution | Cascade |
|---|---|
| Update or clarify spec | Spec edits (section 5 Option A: FR-005–FR-008), plan edits if plan content is affected (FR-009–FR-011), then `/speckit-converge` |
| Fix code — severity Minor, Major, or Critical | `/speckit-converge` only; `spec.md` and `plan.md` unchanged |
| Fix code — severity Trivial | Direct code fix; no artifact change, converge does not run |

Converge runs **once** after all of a session's spec and plan edits (FR-004), never per resolution. Several mismatches in one session produce a single revision-note entry per file, then one converge run.

### 1. Detect Mismatches

**Identify all spec/code divergences:**

```bash
# Read spec
cat specs/features/[feature-name].md

# Compare to implementation
# For each requirement in spec:
#   - What does spec say?
#   - What does code do?
#   - Do they match?
```

**Categorize each mismatch:**
- **Missing in code**: Spec requires it, code doesn't have it
- **Extra in code**: Code implements it, spec doesn't mention it
- **Different behavior**: Spec says X, code does Y
- **Ambiguous spec**: Spec unclear, code made assumption

**Document all mismatches with:**
- Spec requirement (quote from spec)
- Actual implementation (what code does)
- Location (file:line in code, section in spec)

### 2. Analyze Each Mismatch

**For each mismatch, determine:**

**Type:**
- Architectural (affects system design)
- Behavioral (changes functionality)
- Cosmetic (naming, organization, details)

**Severity:**
- **Critical**: Breaking change, security issue, data loss
- **Major**: Significant behavior change, API contract change
- **Minor**: Small deviation, non-breaking addition
- **Trivial**: Naming, formatting, implementation details

**Impact:**
- User-facing vs internal
- Breaking vs non-breaking
- Risky vs safe

### 3. Recommend Resolution

**For each mismatch, recommend:**

**Option A: Update Spec**
- When: Implementation reveals better approach
- Why: Spec was incomplete/wrong, code is better
- Impact: Spec changes to match reality

**Option B: Fix Code**
- When: Code deviates from intended design
- Why: Spec is correct, code is wrong
- Impact: Code changes to match spec

**Option C: Clarify Spec**
- When: Spec was ambiguous, code made reasonable choice
- Why: Make implicit explicit
- Impact: Spec expanded with details, code unchanged

**Provide reasoning for recommendation:**
- Why this option is best
- Trade-offs of alternatives
- Risk assessment
- User impact

### 4. Decide Resolution

**Decision flow:**

```
Is this mismatch trivial/minor AND auto-update enabled?
  Yes -> Auto-update with notification
  No -> Ask user to decide

User decides:
  A) Update spec
  B) Fix code
  C) Clarify spec
  D) Defer (mark as known deviation)
```

> **Post-implementation restriction (flow-back):** once at least one task is complete, the `trivial/minor → auto-update` shortcut above applies only to Trivial fixes and meaning-preserving wording clarifications. A Minor-or-higher change to what a live spec item requires is a `SUPERSEDED by`/`RETIRED` decision that always needs the user (or, inside a ship run, a decision under that run's oversight level) and routes through the section-5 cascade, not a direct in-place edit. See the restriction at the top of section 5 (Execute Resolution).

**Check user configuration:**

```json
{
  "spex": {
    "auto_update_spec": {
      "enabled": true,
      "threshold": "minor",
      "notify": true
    }
  }
}
```

**Thresholds:**
- `none`: Never auto-update
- `minor`: Auto-update trivial/minor mismatches
- `moderate`: Include non-breaking behavioral changes

Post-implementation (flow-back), these thresholds govern only Trivial fixes and meaning-preserving clarifications. A `SUPERSEDED by`/`RETIRED` marking always needs the user's decision regardless of threshold (see section 5).

### 5. Execute Resolution

Before implementation (no completed task), use the legacy regenerate path from section 0. Once at least one task is complete, apply the flow-back cascade below. Accepting a `SUPERSEDED by` or `RETIRED` change is always a human decision (or, inside a ship run, a decision under that run's oversight level); evolve's auto-update setting applies only to Trivial fixes and meaning-preserving wording clarifications.

#### Option A: Update or clarify spec

Apply the spec edits, then plan edits if plan content is affected, then hand off to `/speckit-converge`.

**A.1 Spec edits (FR-005–FR-007)** — use these exact marker strings on the original line:

| Situation | Marker on the original line | Where the replacement goes |
|---|---|---|
| Live item with an ID is replaced | append ` **SUPERSEDED by <new-ID>**` | new item with the next unused ID of that kind (e.g. `FR-012`, `SC-007`) |
| Live item without an ID is replaced (acceptance scenario, edge-case entry) | append ` **SUPERSEDED**` | replacement directly after the old item |
| Live item is dropped | append ` **RETIRED**` | none |
| Wording clarification, meaning unchanged | none — edit in place | listed in the revision note only |

Rules:
- Leave the original item's text otherwise unchanged.
- Never reuse, renumber, or delete a spec item ID (FR-007).
- Never edit or revive an item already marked `SUPERSEDED by`, the ID-less `SUPERSEDED`, or `RETIRED`; the change always goes to the live item. A superseding item can itself later be superseded, gaining its own marker while earlier markers stay, so the supersede chain stays followable.
- A wording clarification that does not change what an implementation must do MAY be edited in place with no marker; still list it under "Clarified" in the revision note.
- Reference ID-less items by position, e.g. `US1/AS2` (User Story 1, Acceptance Scenario 2).

**A.2 Spec revision note (FR-008)** — append one entry **per session** under a `## Revision Notes` section at the end of `spec.md` (create the section if missing). Use the same dated-subheading convention as plan.md (bodies differ):

```markdown
### YYYY-MM-DD: <short title>

- Superseded: FR-004 → FR-012
- Retired: SC-003
- Added: FR-012, SC-007
- Clarified: US1/AS2
- Rationale: <one line>
```

Omit a line whose kind is empty for the session. One entry per file per session even when the session resolved several mismatches.

**A.3 Plan edits (FR-009–FR-011)** — only when the accepted change contradicts something `plan.md` states (a target, threshold, technology, or design decision):
- Edit that passage in place so `plan.md` states only current intent (FR-009).
- Append one entry per session that edits the plan, under a `## Revision Notes` section at the end of `plan.md`:

  ```markdown
  ### YYYY-MM-DD: <short title>

  **Change**: <old statement> → <new statement>
  **Rationale**: <why>
  **Requirements**: FR-012, SC-007
  **Tasks** (optional): T031, T034   # completed task IDs whose stated targets the change replaces
  ```

- Leave `plan.md` unchanged when no plan content is affected (FR-011). Change `research.md`, `data-model.md`, `quickstart.md`, or `contracts/` only where the accepted change contradicts what they state.

**A.4 Invalidate downstream checks (FR-029, FR-030)** — when the session's spec revision note lists any **Superseded**, **Retired**, or **Added** IDs (the spec now requires something different), checks that ran against the old spec no longer count. After the spec and plan edits and **before** the converge hand-off, run both scripts from the project root:

```bash
.specify/extensions/spex/scripts/spex-flow-state.sh invalidate
.specify/extensions/spex/scripts/spex-runbook-status.sh reset "$FEATURE_DIR" --reason "spec evolved <YYYY-MM-DD>: <changed IDs>"
```

- `invalidate` resets the clarify and review gates (`clarified`, `review_spec_passed`, `review_plan_passed`, `review_code_passed`) so the status line shows C/S/P/R as not passed. It leaves `implemented` alone, never creates a state file, and is a no-op inside a ship run.
- `reset` marks an existing walkthrough runbook `stale` (status line `WT ⟳ 0/N`): every step goes back to pending and the old results stop counting until the walkthrough is rerun. With no runbook it prints `"reset": false` and changes nothing.
- Name the changed IDs in the reason (for example `spec evolved 2026-11-08: FR-004 → FR-029, retired SC-003`). Report both outcomes in one line. A non-zero exit is a warning only; it never blocks evolve.
- Skip this step for sessions whose only spec changes are meaning-preserving wording clarifications, and for fix-code-only sessions (the spec is unchanged; a code change already makes the runbook "not current" through its fingerprint).
- The same step applies on the pre-implementation path (section 0 regeneration) whenever the spec change alters what an item requires.

#### Option B: Fix code

Routed by evolve's existing severity scale (Critical, Major, Minor, Trivial) — see "Fix-code routing by severity" below. Non-trivial fixes do not edit `spec.md` or `plan.md`; they hand off to `/speckit-converge`, which appends a traced task. Trivial deviations (naming, formatting) are fixed directly with no artifact change.

#### Option D: Defer

Document the mismatch as a known deviation (in the feature's own deviation notes) with the reason and a plan to address it. This changes no spec item, no plan passage, and no `tasks.md` line, and does not run converge.

#### Fix-code routing by severity

A "fix code" resolution is routed by evolve's existing severity scale (FR-002 rows 2–3):

- **Minor, Major, or Critical** → `/speckit-converge` only. Leave `spec.md` and `plan.md` unchanged (the requirement is already correct). Converge appends a task traced to the affected requirement, typically tagged `contradicts`, and implementation then fixes the code. The fix is recorded as a task so `tasks.md` stays an honest record of post-implementation work.
- **Trivial** (naming, formatting, implementation detail) → fix the code directly. Converge does **not** run, and `spec.md`, `plan.md`, and `tasks.md` are all unchanged.

A session whose only resolutions are Trivial fix-code ones does not invoke converge at all (FR-004: no resolution routes to converge).

#### Converge hand-off

After **all** of a session's spec and plan edits, invoke `/speckit-converge` **once** (FR-004) — but only when **all** of these hold:
- `spec.md`, `plan.md`, and `tasks.md` all exist;
- at least one task is complete;
- no task is open; and
- at least one resolution in the session routes to converge per the cascade table (Update/clarify spec, or Fix code of severity Minor/Major/Critical).

When open tasks remain, do **not** invoke converge. Instead, list the open tasks related to superseded or retired items so the user can review them before implementing, and report that converge runs after the open tasks are done (FR-004). When `plan.md`/`tasks.md` do not exist, edit the spec only and do not run converge.

Pass this guidance to converge as its `$ARGUMENTS` (FR-012), verbatim in substance:

```text
Items marked "SUPERSEDED by <ID>", the ID-less "SUPERSEDED", or "RETIRED" in spec.md
are no longer intent; do not treat them as requirements and do not re-add tasks for
them. Completed tasks that
implemented those items are history, not obligations. The "## Revision Notes" sections
at the end of spec.md and plan.md explain what changed in this session and why. Append
only the work still missing against the live spec items.
```

**Converge outcomes:**

| Converge result | Evolve's behavior |
|---|---|
| Converged (nothing appended) | Report that spec, plan, and code agree. Do **NOT** start implementation. `tasks.md` is byte-identical (FR-013). |
| Tasks appended, normal run | Proceed to `/speckit-implement` inside an autonomous pipeline, or offer it interactively; then run converge once more with the same guidance and report converged or the remaining gaps. Do not loop further (FR-014). See "After converge appends tasks" below. |
| Tasks appended, triggered by verify/finish | Verify does not pass; finish stops before squash/merge. Do **NOT** start implementation; tell the user to implement the appended tasks and re-run (FR-016, precedence over FR-014). |
| Converge unavailable or errors | Keep the spec and plan edits; report the missing command (with the `/spex:init --update` hint) or the error; do **NOT** regenerate or edit `tasks.md` (FR-018). |

#### After converge appends tasks

When converge appends a `## Phase N: Convergence` section, follow this sequence (FR-014):

1. **Implement.** Inside an autonomous pipeline, proceed to `/speckit-implement` to build the appended tasks. Interactively, offer `/speckit-implement` and let the user decide.
2. **Confirm once.** After implementation, run `/speckit-converge` once more with the same FR-012 guidance.
3. **Report and stop.** Report a converged result, or list the remaining gaps converge still reports. Do **NOT** loop further on your own (FR-014).

**`unrequested` tasks (FR-015).** Converge tags each appended task with a gap type: `missing`, `partial`, `contradicts`, or `unrequested`. `unrequested` tasks describe code the spec never asked for, so removing or keeping that code is a judgment call. Present every `unrequested` task to the user before implementation acts on it. Inside an autonomous ship run, `unrequested` tasks MUST pause the pipeline at **every** oversight level (`smart`, `never`, and `always`); do not auto-resolve them.

**Pipeline containment (FR-017).** When evolve runs inside an active ship pipeline (triggered from the review-code stage; detected by `.specify/.spex-state` present with `status: running`), the converge → implement → confirming-converge sequence runs **within** the review-code stage. It counts against that stage's existing retry limit and adds no new pipeline stage. The `/speckit-implement` evolve invokes here MUST run in pipeline mode and skip its `after_implement` hooks (review-code, deep-review), so the review-code stage is not re-entered recursively. This implement path applies **only** when evolve was triggered by the review-code stage itself. A `status: running` state alone does NOT select it: verify and finish also run with `.specify/.spex-state` present and `status: running`, so when the trigger is verify or finish the FR-016 path below takes precedence and evolve does not implement. The trigger (which command invoked evolve), not the state flag alone, selects the branch.

**Triggered by verify or finish (FR-016, precedence over FR-014).** When evolve was triggered by verify or finish and converge appended tasks, do **NOT** run the implement-and-reconfirm sequence above. Instead: verify MUST NOT pass, finish MUST stop before squash or merge, and evolve MUST NOT start implementation. Tell the user to implement the appended tasks and re-run verify or finish.

**Converge unavailable or errors (FR-018).** If `/speckit-converge` is not installed or stops with an error, keep the spec and plan edits already made, report the missing command with the `/spex:init --update` upgrade hint (or report the error), and do **NOT** regenerate or edit `tasks.md`.

### 6. Verify Reconciliation

Reconciliation for a feature with completed tasks is confirmed by `/speckit-converge`, **not** by regenerating artifacts. Do not invoke `/speckit-plan` or `/speckit-tasks` here, and do not edit `tasks.md`.

**After the converge hand-off:**

- **Converged**: spec, plan, and code agree. `tasks.md` is byte-identical to before the session. Report the converged result and stop; do not start implementation (FR-013).
- **Tasks appended**: follow the converge-outcomes table in section 5 — implement the appended tasks (or offer it / defer to the user per the trigger), then run one confirming converge and report converged or the remaining gaps (FR-014, FR-016).

`/speckit-analyze` MAY still be run to spot-check cross-artifact consistency, but it is advisory here; the append-only cascade, not regeneration, is the source of truth. See the `/speckit-analyze` guidance note at the end of this skill for how to read its findings after an evolve.

**Confirm:**
- Live spec items and code are aligned (superseded/retired items are not obligations).
- Every pre-existing `tasks.md` line is unchanged; any new work appears only as converge-appended tasks.
- Tests still passing; no regressions introduced.

## Checklist

Use TodoWrite to track:

- [ ] Detect all spec/code mismatches
- [ ] Categorize each mismatch (type, severity, impact)
- [ ] Analyze and recommend resolution for each
- [ ] Check user configuration for auto-update
- [ ] Decide resolution (auto or ask user)
- [ ] Execute resolution (update spec, fix code, or clarify)
- [ ] Invalidate downstream checks after a requirement-changing spec amendment (flow gates + walkthrough runbook, A.4)
- [ ] Verify reconciliation complete
- [ ] Commit changes with clear messages
- [ ] Update documentation if needed

## Examples

> **These three examples illustrate the pre-implementation path only** (a feature with no completed task, where evolve MAY edit the spec in place and auto-update under the threshold configuration above). Once at least one task is complete, the flow-back cascade in section 5 governs instead: a meaning-changing spec update uses the `**SUPERSEDED by <ID>**` marker plus a `## Revision Notes` entry (never an in-place `Changelog:` edit); a Minor, Major, or Critical fix-code resolution routes through `/speckit-converge` as a traced task (only a Trivial deviation is patched directly); and a `SUPERSEDED by`/`RETIRED` marking always needs the user's decision.

### Example 1: Auto-Update (Minor Addition)

```
[During verification]

Spec compliance check: 95%

Mismatch detected:

**Mismatch 1: Response includes timestamp (MINOR)**
- **Spec says:** Return `{ id, name, email }`
- **Code does:** Returns `{ id, name, email, updated_at }`
- **Location:** src/api/users.ts:45, specs/features/user-api.md#response

**Analysis:**
- Type: Behavioral (but non-breaking addition)
- Severity: Minor
- Impact: Non-breaking, adds useful information

**Recommendation: Update Spec (Option A)**

**Reasoning:**
- `updated_at` is standard practice for update endpoints
- Provides useful information to clients
- Non-breaking addition (clients can ignore it)
- Implementation is better than spec

**User config:** auto_update_spec.threshold = "minor"

**Action:** Auto-updating spec...

Updated specs/features/user-api.md:
- Added `updated_at` to response format
- Changelog: "2025-11-10: Added updated_at timestamp to responses"

Spec updated
Compliance now 100%
Committed to git

Notification: Spec auto-updated with updated_at field (minor addition)
```

### Example 2: User Decision (Major Change)

```
[During code review]

Spec compliance check: 85%

Mismatch detected:

**Mismatch 1: Validation behavior difference (MAJOR)**
- **Spec says:** "Reject requests with invalid avatar_url, return 422"
- **Code does:** "Accept invalid URLs, set avatar_url to null, return 200"
- **Location:** src/middleware/validation.ts:78, specs/features/user-profile.md#validation

**Analysis:**
- Type: Behavioral (changes error handling)
- Severity: Major
- Impact: User-facing, affects API contract

**Options:**

**A) Update Spec - Lenient validation**
- Pros: More user-friendly, prevents frustration
- Cons: Inconsistent with other validation (strict)
- Risk: Users might not know avatar failed

**B) Fix Code - Strict validation**
- Pros: Consistent with spec and other validation
- Cons: Worse UX when URL is invalid
- Risk: None (matches spec)

**C) Clarify Spec - Explicit fallback**
- Pros: Best of both (validate but handle gracefully)
- Cons: More complex
- Risk: None

**Recommendation: Option C**

**Reasoning:**
Best practice is to validate input but handle gracefully. Update spec to explicitly define fallback behavior: validate URL, set to null if invalid, log warning, return success with indication.

Which option do you prefer?

User: C - explicit fallback

You: Perfect. Updating spec to clarify fallback behavior...

Updated spec:

## Validation Rules

### avatar_url
- Must be valid URL format if provided
- **Fallback behavior:** If URL validation fails:
  - Set avatar_url to null
  - Log validation error
  - Return 200 (success) with warning in response
  - Response includes: `warnings: ["avatar_url invalid, set to null"]`

Code now matches clarified spec

Spec compliance: 100%

Committed to git
```

### Example 3: Fix Code (Spec Correct)

```
[During verification]

Spec compliance check: 90%

Mismatch detected:

**Mismatch 1: Missing error handling (CRITICAL)**
- **Spec says:** "Handle database connection errors with retry logic (3 attempts)"
- **Code does:** "Single attempt, fails immediately on error"
- **Location:** src/db/client.ts:34, specs/features/data-persistence.md#error-handling

**Analysis:**
- Type: Architectural (missing reliability mechanism)
- Severity: Critical
- Impact: Production reliability risk

**Recommendation: Fix Code (Option B)**

**Reasoning:**
- Spec defines critical reliability requirement
- Single-attempt fails too easily (production risk)
- Retry logic is standard practice
- Code is missing required feature

**No user decision needed - critical spec requirement missing**

Fixing code to implement retry logic...

Tests updated to verify retry behavior
Spec compliance: 100%

Committed code fix
```

## Auto-Update Configuration

### Recommended Settings

**For solo projects:**
```json
{
  "auto_update_spec": {
    "enabled": true,
    "threshold": "minor",
    "notify": true
  }
}
```

**For team projects:**
```json
{
  "auto_update_spec": {
    "enabled": true,
    "threshold": "none",
    "notify": true
  }
}
```

**For experimental work:**
```json
{
  "auto_update_spec": {
    "enabled": true,
    "threshold": "moderate",
    "notify": true
  }
}
```

## Classification Guidelines

### Minor (Auto-Update Eligible)

> For a feature with completed tasks, these Minor changes are auto-update-eligible only when meaning-preserving. A Minor change that alters what a live spec item requires is a `SUPERSEDED by` decision that needs the user and routes through the section-5 flow-back cascade.

- Adding timestamps to responses
- Renaming variables/functions
- Reorganizing code structure
- Adding logging/instrumentation
- Implementation detail changes

### Major (Always Ask)
- Changing API contracts
- Modifying behavior
- Adding/removing features
- Changing error handling
- Architectural changes

### Critical (Usually Fix Code)
- Security issues
- Data integrity problems
- Missing required features
- Incorrect business logic

## Common Patterns

### Pattern: Better Error Messages

**Mismatch:** Spec says "return error", code returns detailed error with context

**Resolution:** Update spec (minor)
- More detailed errors are better
- Non-breaking improvement

### Pattern: Missing Edge Case

**Mismatch:** Spec doesn't mention empty array, code handles it

**Resolution:** Clarify spec (add edge case)
- Make implicit explicit
- Document intended behavior

### Pattern: Performance Optimization

**Mismatch:** Spec doesn't specify caching, code adds cache

**Resolution:** Update spec (moderate)
- Document optimization in spec
- Ensure cache behavior is correct

### Pattern: Different Architecture

**Mismatch:** Spec implies synchronous, code is async

**Resolution:** Ask user (major)
- Significant architectural change
- May affect other components

## Remember

**Spec evolution is normal and healthy.**

- Specs are not contracts set in stone
- Implementation reveals reality
- Better approaches emerge during coding
- Ambiguities get discovered

**The goal is alignment, not rigidity.**

- Specs guide implementation
- Implementation informs specs
- Both should reflect truth

**Always provide reasoning:**
- Why update spec vs fix code
- What's the impact
- What are the trade-offs

**Trust the process:**
- Detect mismatches early
- Analyze thoughtfully
- Recommend clearly
- Execute decisively
- Verify completely

**Spec and code in sync = quality software.**

## `/speckit-analyze` guidance note (after an evolve)

When you run `/speckit-analyze` on a feature that has been through flow-back evolution, expect findings about spec items marked `SUPERSEDED by <ID>` or `RETIRED`, and about completed tasks (`- [x]`/`- [X]`) that implemented them. These findings are **expected and not actionable** (FR-025): superseded and retired items are no longer intent, and the completed tasks that implemented them are history, not obligations. Findings about **live** spec items remain actionable as usual.
