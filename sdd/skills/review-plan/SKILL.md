---
name: review-plan
description: Post-planning quality validation - coverage matrix, red flag scanning, task quality enforcement, NFR validation, and REVIEWERS.md generation
---

# Post-Planning Quality Validation

## Overview

This skill validates plan and task quality after `/speckit.plan` and `/speckit.tasks` have run. It checks coverage, scans for red flags, enforces task quality standards, and generates `REVIEWERS.md`.

## Prerequisites

{Skill: spec-kit}

**Both plan.md and tasks.md MUST exist before running this skill.** If either is missing, stop with an error:

```bash
SPEC_DIR="specs/[feature-name]"
[ -f "$SPEC_DIR/plan.md" ] && echo "plan.md found" || echo "ERROR: plan.md missing - run /speckit.plan first"
[ -f "$SPEC_DIR/tasks.md" ] && echo "tasks.md found" || echo "ERROR: tasks.md missing - run /speckit.tasks first"
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

## 5. Generate REVIEWERS.md (MANDATORY)

Generating `REVIEWERS.md` is **mandatory**. The planning workflow MUST NOT proceed to PR creation without this file. After validation passes, generate `specs/[feature-name]/REVIEWERS.md`.

**CRITICAL: This file is for HUMAN reviewers, not a self-assessment.**

`REVIEWERS.md` guides human reviewers through the spec and plan. It is NOT a place to write your own quality scores, verdicts, coverage matrices, or validation results. Those go to console output in step 6.

Do NOT output coverage matrices, quality scores, or pass/fail verdicts as REVIEWERS.md. Those are internal validation artifacts (step 6 console output), not reviewer documentation.

Do NOT include in `REVIEWERS.md`:
- Your quality scores or pass/fail verdicts
- Coverage matrix tables (those are step 6 console output)
- Red flag scan results
- Phrases like "Quality Score: X/Y", "Verdict: PASS", "Recommendation: proceed to..."

DO include in `REVIEWERS.md`:
- Executive Summary explaining the feature for a non-specialist
- Review Recipe guiding a human through a 30-minute review
- Technical Decisions with alternatives and trade-offs for humans to evaluate
- Critical References pointing humans to sections that need their attention
- Reviewer Checklist with concrete items for humans to verify

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

## Review Response Matrix (conditional)

> Include this section ONLY when the spec revision addresses feedback from a prior
> PR or review. Skip entirely for first-time specs.

**Detection:** Check if any of these indicators are present:
- spec.md contains a "Clarifications" section referencing prior reviews
- research.md mentions "revised after PR #NNN review"
- Commit messages reference prior PR numbers
- Open Questions reference prior PR discussions

**If prior review feedback exists:**

1. Collect all original reviewer comments from the referenced PR(s)
   using `gh api repos/{owner}/{repo}/pulls/{number}/comments`
2. Build a 1:1 mapping from each reviewer comment to its resolution
3. Group by reviewer (not by theme) so each reviewer can verify their
   specific concerns were addressed
4. Never collapse multiple distinct reviewer comments into one row,
   even if they address the same underlying concept

| # | Reviewer | Original Comment | Resolution | Spec Location |
|---|----------|-----------------|------------|---------------|
| 1 | @reviewer | [Paraphrased concern with link] | [How resolved] | FR-XXX, section Y |
| 2 | @reviewer | [Another concern with link] | [Resolution] | FR-YYY |

For any unaddressed comments, mark explicitly as:
- **Deferred** (with rationale and link to tracking issue)
- **Disagreed** (with justification visible to the original reviewer)
- **Out of scope** (with explanation of why)

Never silently omit a reviewer comment.

## PR Contents

This spec PR includes the following artifacts:

| Artifact | Description |
|----------|-------------|
| `spec.md` | [One-line summary of what the spec defines] |
| `plan.md` | [One-line summary of the implementation approach] |
| `tasks.md` | [Number of tasks across N phases] |
| `REVIEWERS.md` | This file |
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
- When a Review Response Matrix is present, the Technical Decisions section MUST be derived from the matrix entries (not authored independently). This ensures every reviewer concern maps to a visible spec change and nothing is lost in thematic summarization.
- Each distinct reviewer comment gets its own row in the matrix, even if multiple comments address the same architectural concept. Reviewers scan for their name and need to find every comment they made.

**Structural validation (run after writing REVIEWERS.md):**

REVIEWERS.md MUST contain at least 5 of these 8 headings: Executive Summary, Review Recipe, Technical Decisions, Critical References, Reviewer Checklist, Scope Boundaries, Risk Areas, PR Contents.

After writing the file, verify:

```bash
SPEC_DIR="specs/[feature-name]"
REQUIRED_HEADINGS="Executive Summary|Review Recipe|Technical Decisions|Critical References|Reviewer Checklist|Scope Boundaries|Risk Areas|PR Contents"
HEADING_COUNT=$(grep -cE "^##\s+($REQUIRED_HEADINGS)" "$SPEC_DIR/REVIEWERS.md" 2>/dev/null || echo 0)
if [ "$HEADING_COUNT" -lt 5 ]; then
  echo "ERROR: REVIEWERS.md has only $HEADING_COUNT of 8 expected sections. Regenerate with the template from step 5."
fi
```

If the check fails, the file was likely generated as a self-review instead of a reviewer guide. Delete it and regenerate using the template above.

## 6. Present Results

Report to the user:
- Task quality check results (pass/issues)
- Coverage matrix summary
- Red flag scan results
- NFR validation results
- Path to generated REVIEWERS.md

## Integration

**This skill is invoked by:**
- The superpowers trait overlay for `/speckit.plan` (after task generation)
- Users directly via `/sdd:review-plan`

**This skill invokes:**
- `{Skill: spec-kit}` for initialization
