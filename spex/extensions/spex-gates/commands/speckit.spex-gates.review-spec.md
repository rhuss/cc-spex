---
description: "Review specifications for soundness, completeness, and implementability"
---

# Reviewing Specifications for Soundness

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

Validate specification quality before implementation begins.

A poor spec leads to confusion, rework, and spec/code drift. A sound spec enables smooth implementation.

This skill checks: completeness, clarity, implementability, and testability.

## When to Use

- After spec creation (before implementation)
- Before generating implementation plan
- When spec seems unclear or incomplete
- Periodically for important specs

## Prerequisites

Spec-kit must be initialized. If `.specify/` directory does not exist, tell the user to run `/spex:init` first and stop.

## Spec Selection

If a spec path is provided as an argument, use it directly.

Otherwise, attempt branch-based resolution:

```bash
.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null
```

If this succeeds (outputs JSON with `FEATURE_SPEC`), use the resolved spec path. Parse the JSON to extract `FEATURE_SPEC` and `FEATURE_DIR`.

If this fails (not on a feature branch, no matching spec directory), fall back to interactive selection:

```bash
find specs/ -name "spec.md" -type f 2>/dev/null | head -20
```

**If specs found:** Present list and ask user to select one using AskUserQuestion (skip in autonomous mode).

**If no specs found:** Inform user:
```
No specs found in specs/ directory.

To create a spec first:
- Use `speckit-spex-brainstorm` to refine ideas into a spec
- Use `/speckit-specify` to create a spec from clear requirements

Cannot review without a spec to review.
```

## spec-kit Integration

This skill can use `/speckit-*` slash commands when available:

- `/speckit-clarify` - Find underspecified areas in the spec
- `/speckit-analyze` - Cross-artifact consistency check (if plan/tasks exist)

**If `/speckit-*` commands are available:**
Use them to assist with review, but always perform manual review as well.

**If `/speckit-*` commands are not available:**
Proceed with manual review only. This is acceptable.

## Review Dimensions

### 1. Completeness
- All sections filled
- No TBD or placeholder text
- All requirements defined
- Success criteria specified

### 2. Clarity
- No ambiguous language
- Concrete, specific requirements
- Edge cases explicitly defined
- Error handling specified

### 3. Implementability
- Can generate implementation plan
- Dependencies identified
- Constraints realistic
- Scope manageable

### 4. Testability
- Success criteria measurable
- Requirements verifiable
- Acceptance criteria clear

## The Process

### 1. Load and Read Spec

**Read the spec:**

```bash
cat specs/[feature-name]/spec.md
```

Read thoroughly, take notes on issues.

### 2. Check Structure

**Required sections (should exist):**
- [ ] Purpose/Overview
- [ ] Functional Requirements
- [ ] Success Criteria
- [ ] Error Handling

**Recommended sections:**
- [ ] Non-Functional Requirements
- [ ] Edge Cases
- [ ] Dependencies
- [ ] Constraints
- [ ] Out of Scope

**If sections missing:**
- Note which ones
- Assess if truly needed for this spec
- Recommend additions

### 3. Review Completeness

**For each section, check:**

**Purpose:**
- [ ] Clearly states why feature exists
- [ ] Describes problem being solved
- [ ] Avoids implementation details

**Functional Requirements:**
- [ ] Numbered/listed clearly
- [ ] Each requirement is specific
- [ ] No "TBD" or placeholders
- [ ] All aspects covered

**Success Criteria:**
- [ ] Measurable outcomes defined
- [ ] Clear completion indicators
- [ ] Testable assertions

**Error Handling:**
- [ ] All error cases identified
- [ ] Handling approach specified
- [ ] Error messages/codes defined

**Edge Cases:**
- [ ] Boundary conditions listed
- [ ] Expected behavior specified
- [ ] Not marked as "TBD"

### 4. Check for Ambiguities

**Red flag words/phrases:**
- "should" (vs "must")
- "might", "could", "probably"
- "fast", "slow" (without metrics)
- "user-friendly" (vague)
- "handle appropriately" (non-specific)
- "etc." (incomplete list)
- "similar to..." (unclear)

**For each ambiguity:**
- Identify the vague requirement
- Note what's unclear
- Suggest specific alternative

### 5. Validate Implementability

**Ask:**
- Can I generate an implementation plan from this?
- Are file locations/components identifiable?
- Are dependencies clear?
- Is scope reasonable?

**Check for:**
- Unknown dependencies
- Unrealistic constraints
- Scope too large
- Conflicting requirements

### 6. Assess Testability

**For each requirement:**
- How will this be tested?
- Is the outcome verifiable?
- Can success be measured?

**For success criteria:**
- Are they specific enough to test?
- Can they be automated?
- Are they objective (not subjective)?

### 7. Check Against Constitution

**If constitution exists:**

```bash
if [ -f ".specify/memory/constitution.md" ]; then
  cat .specify/memory/constitution.md
else
  echo "no-constitution"
fi
```

**Validate:**
- Does spec follow project principles?
- Are patterns consistent?
- Does error handling match standards?
- Are architectural decisions aligned?

**Note any violations with reasoning.**

### 8. Run Cross-Artifact Consistency Check (Optional)

**If plan or tasks exist and `/speckit-analyze` is available:**

Invoke `/speckit-analyze` to check consistency between:
- spec.md (requirements)
- plan.md (implementation approach)
- tasks.md (task list)

**Report any mismatches or gaps found.**

### 9. Generate Review Report

Output the review findings to the console. Do NOT write a `REVIEW-SPEC.md` file. All review information is presented directly in the conversation output.

### 10. Make Recommendation

**If sound (minor issues only):**
- Ready for implementation
- Proceed with `/speckit-implement`

**If needs work (important issues):**
- Fix issues before implementing
- Update spec, re-review

**If major issues:**
- Not ready for implementation
- Significant rework needed
- May need re-brainstorming

## Review Checklist

- [ ] Load and read spec thoroughly
- [ ] Check structure (all sections present)
- [ ] Review completeness (no TBD, all covered)
- [ ] Identify ambiguities (vague language)
- [ ] Validate implementability (can plan from this)
- [ ] Assess testability (can verify requirements)
- [ ] Check constitution alignment (if exists)
- [ ] Run `/speckit-analyze` for cross-artifact consistency (if available)
- [ ] Generate review report
- [ ] Make recommendation (ready/needs work/major issues)

## Quality Standards

**A sound spec has:**
- All sections complete
- No ambiguous language
- Specific, measurable requirements
- Identified dependencies
- Realistic constraints
- Clear error handling
- Defined edge cases
- Testable success criteria

**A poor spec has:**
- Missing sections
- Vague language
- Unmeasurable requirements
- Unknown dependencies
- Unrealistic constraints
- Unclear error handling
- Ignored edge cases
- Subjective criteria

## Remember

**Reviewing specs saves time in implementation.**

- 1 hour reviewing spec saves 10 hours debugging
- Ambiguities caught early prevent rework
- Complete specs enable smooth TDD
- Sound specs reduce spec/code drift

**Be thorough but not pedantic:**
- Flag real issues, not nitpicks
- Focus on what blocks implementation
- Suggest specific improvements
- Balance perfection with pragmatism

**The goal is implementability, not perfection.**

## Update Flow State

After the review completes, mark the review-spec gate as passed in the flow state:

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ] && jq -e '.mode == "flow"' "$STATE_FILE" >/dev/null 2>&1; then
  jq '.review_spec_passed = true | .running = ""' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi
```

This updates the status line to show `S ✓`.
