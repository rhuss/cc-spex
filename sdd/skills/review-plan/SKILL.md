---
name: review-plan
description: Post-planning quality validation - coverage matrix, red flag scanning, task quality enforcement, NFR validation, and review-summary.md generation
---

# Post-Planning Quality Validation

## Overview

This skill validates plan and task quality after `/speckit.plan` and `/speckit.tasks` have run. It checks coverage, scans for red flags, enforces task quality standards, and generates `review-summary.md`.

## Prerequisites

{Skill: spec-kit}

**Both plan.md and tasks.md MUST exist before running this skill.** If either is missing, stop with an error:

```bash
SPEC_DIR="specs/[feature-name]"
[ -f "$SPEC_DIR/plan.md" ] && echo "plan.md found" || echo "ERROR: plan.md missing - run /speckit.plan first"
[ -f "$SPEC_DIR/tasks.md" ] && echo "tasks.md found" || echo "ERROR: tasks.md missing - run /speckit.tasks first"
```

If either file is missing, stop and instruct the user to generate the missing artifact.

## Beads Readiness Check (conditional)

Check if the beads trait is enabled:

```bash
BEADS_ENABLED=$(jq -r '.traits.beads // false' .specify/sdd-traits.json 2>/dev/null)
```

If beads is enabled (`true`), verify that bd issues exist for this feature:

```bash
ISSUE_COUNT=$(bd list --json 2>/dev/null | jq 'if type == "object" and .error then 0 else length end')
TASK_COUNT=$(grep -c '^\- \[ \]' "$SPEC_DIR/tasks.md" 2>/dev/null || echo 0)
```

- If `bd` is not installed: flag as **"beads trait enabled but bd CLI missing"**
- If issue count is 0 but task count > 0: flag as **"beads sync required before implementation"** and instruct user to run `/sdd:beads-task-sync`
- If issues exist: report count and note beads is ready for implementation

Include the beads readiness result in the final report (step 6).

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

If tasks fail these checks, note the issues and suggest refinements.

## 2. Coverage Matrix

Produce a coverage matrix mapping every spec requirement to its implementing tasks:

```
Requirement 1 → Tasks [X,Y]     ✓
Requirement 2 → Tasks [Z]       ✓
NFR 1         → Tasks [W]       ✓
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
rg -i "figure out|tbd|todo|implement later|somehow|somewhere|not sure|maybe|probably" "$SPEC_DIR/plan.md" "$SPEC_DIR/tasks.md" || echo "No red flags found"
```

Review any matches:
- "Figure out..." = missing research, needs concrete approach
- "TBD" = incomplete planning, must be resolved
- "Implement later" = deferred work, scope explicitly
- Missing file paths = tasks are not actionable

## 4. NFR Validation

For each non-functional requirement in the spec, verify the plan includes:
- A concrete measurement method (not just "should be fast")
- A validation approach (how will you verify the NFR is met?)
- Acceptance thresholds where applicable

If any NFR lacks a measurement method, flag it.

## 5. Generate review-summary.md (MANDATORY)

Generating `review-summary.md` is **mandatory**. The planning workflow MUST NOT proceed to PR creation without this file. After validation passes, generate `specs/[feature-name]/review-summary.md`:

```markdown
# Review Summary: [Feature Name]

**Spec:** specs/[feature-name]/spec.md | **Plan:** specs/[feature-name]/plan.md
**Generated:** YYYY-MM-DD

---

## Executive Summary

[0.5 to 1 page (roughly 200-400 words) written in plain, accessible language that a
non-specialist can follow. Cover: what problem this feature solves, how it works at a
high level, what changes it introduces, and why it matters. Avoid jargon where possible;
where technical terms are necessary, explain them briefly. This section should give a
reviewer enough context to understand the feature without reading the full spec.]

## Review Recipe (30 minutes)

> Step-by-step guide to review this spec efficiently. Focus on the most critical
> parts first. The full review should take no longer than 30 minutes.

### Step 1: Understand the problem (5 min)
- Read the Executive Summary above
- Skim `spec.md` Section 1 (Problem Statement / Motivation)
- Ask yourself: Is this problem worth solving? Is the scope right?

### Step 2: Check critical references (10 min)
- Review each item in the **Critical References** table below
- These are the sections that carry the most risk or define key contracts
- For each: read the referenced section, check the reasoning, flag concerns

### Step 3: Evaluate technical decisions (8 min)
- Review the **Technical Decisions** section below
- For each decision: Are the rejected alternatives valid? Is the trade-off acceptable?
- Pay special attention to decisions marked with a "Reviewer question"

### Step 4: Validate coverage and risks (5 min)
- Scan the **Risk Areas** table: Are mitigations sufficient for high-impact risks?
- Check **Scope Boundaries**: Is anything missing that should be in scope?
- Glance at the coverage matrix in the review output to spot gaps

### Step 5: Complete the checklist (2 min)
- Work through the **Reviewer Checklist** below
- Mark items as checked, flag concerns as PR comments

## PR Contents

This spec PR includes the following artifacts:

| Artifact | Description |
|----------|-------------|
| `spec.md` | [One-line summary of what the spec defines] |
| `plan.md` | [One-line summary of the implementation approach] |
| `tasks.md` | [Number of tasks across N phases] |
| `review-summary.md` | This file |
| [Other artifacts if any, e.g. checklist.md, diagrams] | [Description] |

## Technical Decisions

> Key technical choices made during design, including alternatives that were considered and why they were rejected.

### [Decision Title]
- **Chosen approach:** [What was decided]
- **Alternatives considered:**
  - [Alternative 1]: [Why rejected, e.g. "adds unnecessary complexity", "poor scaling characteristics"]
  - [Alternative 2]: [Why rejected]
- **Trade-off:** [What we gain and what we give up]
- **Reviewer question:** [Specific question for the reviewer, if any]

[Repeat for each significant decision]

## Critical References

> Specific sections in the spec or plan that need elevated human attention. Reviewers should prioritize reading these sections and discuss them on the PR.

| Reference | Why it needs attention |
|-----------|----------------------|
| `spec.md` Section [X.Y]: [Section title] | [Why this is critical, e.g. "defines the public API contract", "contains security-sensitive logic"] |
| `plan.md` Phase [N]: [Phase title] | [Why this needs review, e.g. "complex migration strategy", "touches shared infrastructure"] |
| `spec.md` [NFR-N]: [NFR title] | [Why, e.g. "performance threshold may be too aggressive"] |
| ... | ... |

## Reviewer Checklist

> Things the reviewer should actively verify, question, or potentially reject.

### Verify
- [ ] [Concrete thing to check, e.g. "Schema fields cover all use cases listed in FR-003"]
- [ ] [Another verification item]

### Question
- [ ] [Area where reviewer input is needed, e.g. "Is the flat directory structure sufficient as the project grows?"]
- [ ] [Another open question needing stakeholder input]

### Watch out for
- [ ] [Potential issue, e.g. "Skill file may become too large with added sections"]
- [ ] [Risk or concern, e.g. "No backward compatibility path if naming convention changes"]

## Scope Boundaries
- **In scope:** [What this includes]
- **Out of scope:** [What this explicitly excludes]
- **Why these boundaries:** [Brief justification]

## Naming & Schema Decisions

| Item | Name | Context |
|------|------|---------|
| ... | ... | ... |

[If schemas are defined, include condensed key-fields-only summaries here]

## Risk Areas

| Risk | Impact | Mitigation |
|------|--------|------------|
| ... | High/Med/Low | ... |

---
*Share this with reviewers. Full context in linked spec and plan.*
```

**Constraints:**
- Target length: ~1000-1500 words (the executive summary alone should be 200-400 words)
- Prioritize: Executive Summary > Technical Decisions > Critical References > Reviewer Checklist > Scope
- The executive summary MUST be understandable by someone who has not read the spec
- Technical Decisions MUST include rejected alternatives with reasoning
- Critical References MUST point to specific sections (with section numbers or anchors) in spec.md and plan.md
- Reviewer Checklist items should be concrete and actionable, not vague
- Summarize, don't transcribe

## 6. Present Results

Report to the user:
- Task quality check results (pass/issues)
- Coverage matrix summary
- Red flag scan results
- NFR validation results
- Path to generated review-summary.md

## Integration

**This skill is invoked by:**
- The superpowers trait overlay for `/speckit.plan` (after task generation)
- Users directly via `/sdd:review-plan`

**This skill invokes:**
- `{Skill: spec-kit}` for initialization
