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

### Purpose

REVIEWERS.md is a **reviewer's companion**: a document that helps a human reviewer start and complete a meaningful spec review within 30 minutes. It is NOT a self-assessment, not a validation report, and not a dump of spec contents.

### Mindset

Write this document as if you are briefing a colleague who has 30 minutes and no prior context. Your job is to:

1. Orient them quickly (what is this, what's in scope, what's not)
2. Guide them to the parts that most need human judgment
3. Ask honest questions where you are uncertain or where the spec could go either way
4. Surface the bigger picture: how does this spec fit into the project's trajectory?

### What does NOT belong in REVIEWERS.md

- Quality scores, pass/fail verdicts, coverage matrices, red flag scan results (those go to console output in step 6)
- Phrases like "Quality Score: X/Y", "Verdict: PASS", "Recommendation: proceed to..."
- Lists of what the spec contains (the reviewer can read the spec themselves)
- PR artifact inventories (except in rare cases where non-obvious artifacts need explanation)

### Writing principles

- **Questions over statements.** Guide the review through questions that point to specific spec sections. "Does the retry limit in FR-007 make sense for large features?" is better than "The retry limit is 2."
- **Honesty over confidence.** Be transparent about your own certainty level. If a spec section felt unclear or could be interpreted multiple ways, say so. "I interpreted section 3.2 as requiring X, but it could also mean Y" is valuable.
- **Bigger picture over local detail.** Help the reviewer understand how this spec relates to the rest of the project, adjacent systems, or ongoing work. Do web research if the spec touches external technologies or patterns to provide relevant context.
- **Exceptions only.** Only describe spec contents when something is surprising, counterintuitive, or easily missed. Don't summarize what a reader would learn from scanning the headings.

### Template

```markdown
# Review Guide: [Feature Name]

**Spec:** specs/[feature-name]/spec.md | **Plan:** specs/[feature-name]/plan.md
**Generated:** YYYY-MM-DD

---

## What This Spec Does

[2-4 sentences in plain language. What problem does this solve, and for whom?
A non-specialist should understand this paragraph.]

**In scope:** [Concise list of what this spec covers]

**Out of scope:** [What is explicitly excluded, and why. Be specific. These
boundaries are often where reviewers have the most useful feedback.]

## Bigger Picture

[How does this spec fit into the project's overall direction? What came before it,
what depends on it, what might follow? If this spec touches external technologies
or patterns, include relevant context from research.

Be honest: if the spec's relationship to adjacent work is unclear, say so.]

---

## Spec Review Guide (30 minutes)

> This guide helps you focus your 30 minutes on the parts of the spec and plan
> that need human judgment most. Each section points to specific locations and
> frames the review as questions.

### Understanding the approach (8 min)

Read `spec.md` sections [X] and [Y] for the core approach. As you read, consider:

- [Question about whether the problem framing is right]
- [Question about whether the chosen approach fits the project context]
- [Question about an assumption the spec makes]

### Key decisions that need your eyes (12 min)

**[Decision 1 title]** (spec.md section [X.Y])

[1-2 sentences on what was decided and what alternatives were considered.]
- Question for reviewer: [Specific question, e.g. "Is the performance trade-off
  acceptable given our current load patterns?"]

**[Decision 2 title]** (spec.md section [X.Y])

[Same pattern. Focus on decisions where alternatives were genuinely viable.]

[Repeat for 3-5 key decisions. Only include decisions where reviewer input
could change the outcome.]

### Areas where I'm less certain (5 min)

[Be honest about parts of the spec where the AI's interpretation may be wrong,
where requirements are ambiguous, or where the spec could reasonably go a
different direction. Point to specific sections.]

- `spec.md` section [X]: [What's unclear and why it matters]
- `plan.md` phase [N]: [What assumption might not hold]

### Risks and open questions (5 min)

[Frame risks as questions, not as a risk register. Point to specific sections.]

- [Risk framed as question, e.g. "If the external API changes its response
  format (spec.md FR-012), is our fallback strategy sufficient?"]
- [Another risk-question with spec reference]

## Prior Review Feedback

> Include this section ONLY when the spec revision addresses feedback from a
> prior PR or review. Skip entirely for first-time specs.

[If prior review feedback exists, map each reviewer comment to how it was
addressed. Group by reviewer so each person can find their concerns. Never
silently omit a comment. Mark unaddressed items as Deferred, Disagreed, or
Out of scope with justification.]

| # | Reviewer | Original Concern | How Addressed | Spec Location |
|---|----------|-----------------|---------------|---------------|
| 1 | @reviewer | [Paraphrased concern] | [Resolution] | section X.Y |

---
*Full context in linked spec and plan.*
```

**Note:** The Code Review Guide section is appended later by `spex:review-code` after implementation completes. See the review-code skill for that template.

### Constraints

- **Target length:** ~800-1200 words. Concise beats comprehensive.
- **Question density:** Aim for 8-15 specific questions throughout the document. Each question should point to a spec section and be answerable by reading that section.
- **Honesty requirement:** The "Areas where I'm less certain" section is mandatory. If you are fully confident about everything, you are not being honest enough. Every spec has ambiguities.
- **Bigger picture:** Do web research if the spec touches external technologies, APIs, or patterns that a reviewer might want context on. Don't assume the reviewer knows the ecosystem.
- **No spec transcription.** If you find yourself writing "The spec defines X, Y, and Z," stop. Instead ask "Does the approach in section 3.2 handle the edge case where...?"
- **Prior feedback handling:** When a Review Response Matrix is present, each distinct reviewer comment gets its own row. Group by reviewer (not by theme). Never collapse multiple comments into one row.

### Structural validation (run after writing REVIEWERS.md)

REVIEWERS.md MUST contain at least 3 of these 5 headings: What This Spec Does, Bigger Picture, Spec Review Guide, Areas where I'm less certain, Risks and open questions.

After writing the file, verify:

```bash
SPEC_DIR="specs/[feature-name]"
REQUIRED_HEADINGS="What This Spec Does|Bigger Picture|Spec Review Guide|Areas where|Risks and open"
HEADING_COUNT=$(grep -cE "^##[#]?\s+($REQUIRED_HEADINGS)" "$SPEC_DIR/REVIEWERS.md" 2>/dev/null || echo 0)
if [ "$HEADING_COUNT" -lt 3 ]; then
  echo "ERROR: REVIEWERS.md has only $HEADING_COUNT of 5 expected sections. Regenerate with the template from step 5."
fi
```

If the check fails, the file was likely generated as a summary/self-review instead of a question-driven reviewer guide. Delete it and regenerate using the template above.

## 6. Present Results

Report to the user:
- Task quality check results (pass/issues)
- Coverage matrix summary
- Red flag scan results
- NFR validation results
- Path to generated REVIEWERS.md

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

Then ask the user how to proceed:

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

## Integration

**This skill is invoked by:**
- The superpowers trait overlay for `/speckit.plan` (after task generation)
- Users directly via `/spex:review-plan`

**This skill invokes:**
- `{Skill: spec-kit}` for initialization
