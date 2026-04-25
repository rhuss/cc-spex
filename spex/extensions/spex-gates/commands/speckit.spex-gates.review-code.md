---
description: "Review code against spec compliance with deviation tracking and evolution triggers"
---

# Code Review Against Specification

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

## Flow Status Update

After successfully completing the code review, if `.specify/.spex-state` exists with `"mode": "flow"`, update it to set `"implemented": true`:

```bash
tmp=$(mktemp) && jq '.implemented = true' .specify/.spex-state > "$tmp" && mv "$tmp" .specify/.spex-state
```

## IMPORTANT: Deep Review Extension Check

**Before starting any review work**, check if the `spex-deep-review` extension is enabled:

```bash
# Check via extensions registry
jq -r '.extensions["spex-deep-review"].enabled // false' .specify/extensions/.registry 2>/dev/null
```

If deep review is enabled, this command MUST invoke `speckit.spex-deep-review.review` after spec compliance passes (>= 95%). Do NOT produce only a basic compliance review when deep-review is active. The deep review dispatches 5 specialized agents, runs a fix loop, and generates a Deep Review Report. See step 9a below for details.

## Overview

Review code implementation against specification to ensure compliance.

**Key Difference from Standard Code Review:**
- Primary focus: **Does code match spec?**
- Secondary focus: Code quality, patterns, best practices
- Output: **Compliance score** + deviation list
- Triggers: **Spec evolution** if mismatches found

## When to Use

- After implementation complete (called via spex-gates hook on after_implement)
- Before merging/deploying code
- When validating existing code against spec
- As part of verification workflow

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

Code review against spec requires a spec to compare against.
Use `speckit-spex-brainstorm` or `/speckit-specify` to create one first.
```

## The Process

### 1. Load Spec and Code

**Read specification:**
```bash
cat specs/features/[feature-name].md
```

**Identify implementation files:**
```bash
# From implementation plan or code exploration
ls -la [implementation-files]
```

### 2. Review Functional Requirements

**For each functional requirement in spec:**

1. **Find implementation** in code
2. **Compare behavior**: Does code do what spec says?
3. **Check completeness**: All aspects implemented?
4. **Note deviations**: Any differences?

**Create compliance matrix:**
```
Requirement 1: [Spec text]
  Implementation: [file:line]
  Status: Compliant | Deviation | Missing
  Notes: [If deviation, explain]

Requirement 2: [Spec text]
  ...
```

### 3. Review Error Handling

**For each error case in spec:**

1. **Find error handling** in code
2. **Check error response**: Matches spec?
3. **Verify error codes**: Correct HTTP status / error codes?
4. **Test error messages**: Clear and helpful?

**Error handling compliance:**
```
Error Case 1: [From spec]
  Implemented: Yes/No
  Location: [file:line]
  Response: [What code returns]
  Spec Expected: [What spec says]
  Status: Compliant / Deviation
```

### 4. Review Edge Cases

**For each edge case in spec:**

1. **Find handling** in code
2. **Check behavior**: Matches spec?
3. **Verify tests**: Edge case tested?

### 5. Check for Extra Features

**Identify code features NOT in spec:**

- Functions/endpoints not mentioned in spec
- Behavior beyond spec requirements
- Additional error handling
- Extra validations

**For each extra feature:**
- Document what it does
- Assess: Helpful addition or scope creep?
- Note for potential spec update

### 6. Calculate Compliance Score

**Formula:**
```
Compliance % = (Compliant Requirements / Total Requirements) x 100
```

**Include:**
- Functional requirements
- Error cases
- Edge cases
- Non-functional requirements

### 7. Generate Report

**Report structure:**

```markdown
# Code Review: [Feature Name]

**Spec:** specs/features/[feature].md
**Date:** YYYY-MM-DD
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: XX%**

- Functional Requirements: X/X (XX%)
- Error Handling: X/X (XX%)
- Edge Cases: X/X (XX%)
- Non-Functional: X/X (XX%)

## Detailed Review

### Functional Requirements

#### Requirement 1: [Spec text]
**Implementation:** src/[file]:line
**Status:** Compliant
**Notes:** Correctly implemented as specified

#### Requirement 2: [Spec text]
**Implementation:** src/[file]:line
**Status:** Deviation
**Issue:** [What differs from spec]
**Impact:** [Minor/Major]
**Recommendation:** [Update spec / Fix code]

### Error Handling

[Similar format for each error case]

### Edge Cases

[Similar format for each edge case]

### Extra Features (Not in Spec)

#### [Feature name]
**Location:** src/[file]:line
**Description:** [What it does]
**Assessment:** [Helpful / Scope creep]
**Recommendation:** [Add to spec / Remove]

## Code Quality Notes

[Secondary observations about code quality, patterns, etc.]

## Recommendations

### Critical (Must Fix)
- [ ] [Issue requiring immediate attention]

### Spec Evolution Candidates
- [ ] [Deviation that might warrant spec update]

### Optional Improvements
- [ ] [Nice-to-have suggestions]

## Conclusion

[Overall assessment]

**Next Steps:**
- If compliance < 100%: Use `speckit-spex-evolve` to reconcile deviations
- If compliance = 100%: Proceed to verification
```

### 8. Write Code Review Guide to REVIEW-CODE.md (MANDATORY)

After generating the compliance report (step 7), write a **Code Review Guide** to `REVIEW-CODE.md` in the spec directory. This section helps human reviewers focus their code review in 30 minutes, using the same structure as the Spec Review Guide.

**If REVIEW-CODE.md does not exist**, create it with the Code Review Guide.

**If a Code Review Guide already exists in REVIEW-CODE.md** (from a prior implementation phase), append a new dated subsection rather than replacing it. Incremental PRs build up the review guide over time, and reviewers need context from all phases.

**CRITICAL:** This follows the exact same philosophy as the Spec Review Guide: time-boxed, question-driven, honest about uncertainty, focused on high-level questions that need human judgment. Do NOT dump compliance scores, requirement checklists, or verification results into REVIEW-CODE.md. Those belong in the console report (step 7).

**Write the following to REVIEW-CODE.md:**

```markdown

---

## Code Review Guide (30 minutes)

> [If this is the first code review entry, use this intro:]
> This section guides a code reviewer through the implementation changes,
> focusing on high-level questions that need human judgment.
>
> [If appending to an existing code review guide, add a dated subsection:]
> ### Phase N: [brief description] (YYYY-MM-DD)

**Changed files:** [N files changed, summary of which areas: e.g. "3 source files,
2 config files, 1 script"]

### Understanding the changes (8 min)

[Point the reviewer to the 1-2 files that form the core of the change.
Explain the reading order. Frame as questions.]

- Start with `[main-file]`: [Why this is the entry point for understanding]
- Then `[second-file]`: [What it does in relation to the first]
- Question: [High-level question about the overall approach, e.g. "Does this
  decomposition make sense, or would a single module be clearer?"]

### Key decisions that need your eyes (12 min)

[For each notable implementation decision, point to the code and frame as a
question. Mirror the spec review structure: decision title, brief context,
question for the reviewer. Only include decisions where human expertise or
domain knowledge could change the outcome.]

**[Decision 1 title]** (`path/to/file:line`, relates to [FR-NNN](spec.md#anchor))

[1-2 sentences on what was decided and what alternatives existed.]
- Question: [e.g. "Is this the right data structure given our expected scale?"]

**[Decision 2 title]** (`path/to/file:line`)

[Same pattern. Focus on decisions where reviewer input adds value.]

### Areas where I'm less certain (5 min)

[Be honest about implementation areas where the AI's interpretation may be
wrong, the approach may not be idiomatic, or edge cases may not be covered.
Link to relevant spec sections where the requirement was ambiguous.]

- `[file:line]` ([spec context](spec.md#anchor)): [What's uncertain and why]
- `[file:line]`: [Another area of uncertainty]

### Deviations and risks (5 min)

[List deviations from [plan.md](plan.md) and open risks, framed as questions.
If there are no deviations, state explicitly: "No deviations from
[plan.md](plan.md) were identified."]

- `[file:line]`: [What differs from [plan section](plan.md#anchor), and why.
  Question: "Is this deviation acceptable?"]
- [Risk framed as question with spec reference]
```

**Constraints for the Code Review Guide:**
- **Same structure as Spec Review Guide.** Time-boxed sections (8+12+5+5 = 30 min), question-driven, high-level focus.
- **Target length:** ~400-800 words per entry. For incremental phases, each new subsection can be shorter (200-400 words).
- **Question density:** Aim for 5-10 questions, each pointing to a specific file/line and framed at the level a senior reviewer cares about (not code style, but architectural choices).
- **Honesty requirement:** The "Areas where I'm less certain" section is mandatory. If you implemented everything perfectly, you are not being honest enough.
- **No compliance dumps.** Don't list requirements and their status. Don't paste the compliance matrix.
- **Incremental builds.** If a Code Review Guide section already exists in REVIEW-CODE.md, add a new dated subsection (e.g., `### Phase 2: API endpoints (2026-03-29)`) rather than replacing the existing content. Each phase adds context for the reviewer.
- **Hyperlink all references.** Every mention of a spec section, plan phase, or spec artifact MUST be a markdown hyperlink using relative paths (e.g., `[FR-003](spec.md#fr-003)`, `[Phase 2](plan.md#phase-2)`). Never use bare backtick references without a link.

### 9. Deep Review Enhancement (if extension enabled)

**Note:** When deep review runs and produces fixes, re-evaluate the Code Review Guide (step 8) and update it if the fixes changed the areas of concern.

**First, parse flags from the invocation arguments:**

When this command is invoked with arguments, extract flags before treating the remainder as hint text:

- `--no-external`: disable all external tools
- `--no-coderabbit`: disable CodeRabbit only
- `--no-copilot`: disable Copilot only
- `--external`: enable all external tools
- `--coderabbit`: enable CodeRabbit only
- `--copilot`: enable Copilot only

Flags are consumed and removed from the argument string. The remaining text (if any) becomes the hint text.

**Resolve external tool settings (defaults + flag overrides):**

```bash
# 1. Read defaults from deep-review extension config (all default to true if key is missing)
DEEP_REVIEW_CONFIG=".specify/extensions/spex-deep-review/deep-review-config.yml"
DEFAULT_CODERABBIT=$(yq -r '.external_tools.coderabbit // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)
DEFAULT_COPILOT=$(yq -r '.external_tools.copilot // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)

# 2. If config file is missing, default all tools to true
```

```
Resolution logic:

1. Start with config defaults:
   coderabbit = DEFAULT_CODERABBIT
   copilot    = DEFAULT_COPILOT

2. Apply flag overrides (flags always win over defaults):
   --external       -> coderabbit = true,  copilot = true
   --no-external    -> coderabbit = false, copilot = false
   --coderabbit     -> coderabbit = true
   --no-coderabbit  -> coderabbit = false
   --copilot        -> copilot = true
   --no-copilot     -> copilot = false

3. Flags are applied in order. Later flags override earlier ones:
   --external --no-copilot -> coderabbit = true, copilot = false
   --no-external --coderabbit -> coderabbit = true, copilot = false
```

**After spec compliance is calculated, check for deep review:**

**If deep review is enabled AND spec compliance >= 95% (or no spec exists):**
- Invoke `speckit.spex-deep-review.review` with:
  - Stage 1 compliance score (or null if no spec)
  - Invocation context: `quality-gate` if called from hook, `manual` if called directly
  - Hint text: remaining argument text after flag extraction
  - External tool settings: `{coderabbit: true/false, copilot: true/false}` (resolved from defaults + flags)
  - Spec path and feature directory
- Wait for deep review to complete before proceeding

**If deep review is enabled AND spec compliance < 95%:**
- Do NOT invoke deep review
- Report the compliance score and non-compliant requirements
- Instruct the user to fix spec compliance issues first

**If deep review is NOT enabled:**
- Continue with standard review behavior (steps 9b below)

### 9b. Trigger Evolution if Needed

**If deviations found (standard review path, no deep-review):**
- Present review results to user
- Recommend using `speckit-spex-evolve`
- Don't proceed to verification until resolved

**If 100% compliant (standard review path):**
- Approve for verification
- Proceed to `speckit.spex-gates.stamp`

## Assessment Criteria

### Compliant
- Code does exactly what spec says
- No deviations in behavior
- All aspects covered

### Minor Deviation
- Small differences (naming, details)
- Non-breaking additions
- Better error messages than spec
- Typically: Update spec

### Major Deviation
- Different behavior than spec
- Missing functionality
- Wrong error handling
- Typically: Fix code or evolve spec

### Missing
- Spec requires it, code doesn't have it
- Critical gap
- Must fix code

## Anti-Rationalization: What You Must NOT Do

**DO NOT skip checking ANY requirement.** Each spec requirement must be verified against code. Not "spot checking." Not "seems fine." Every. Single. One.

**DO NOT assume compliance.** "It looks right" is not compliance. "I think it matches" is not compliance. Show the code location. Compare the behavior. Document the status.

**DO NOT hide deviations.** A deviation is not a failure; it's information. Hiding deviations breaks the feedback loop. Report every deviation, even minor ones.

**DO NOT proceed with deviations unresolved.** 89% compliance is NOT ready for verification. 99% compliance is NOT ready for verification. Only 100% compliance proceeds to verification.

**DO NOT rationalize scope creep.** "But this feature is useful!" is not justification for unspecified code. Either add it to the spec (via evolution) or remove it. Undocumented features are invisible bugs.

**DO NOT conflate code quality with spec compliance.** Code can be beautiful AND non-compliant. Code can be ugly AND compliant. Check both, report both, but never confuse them.

## Remember

**Spec compliance is primary concern.**

This is not just code quality review; it's **spec validation**.

- Does code match spec? (Most important)
- Is code quality good? (Secondary)
- Any improvements? (Tertiary)

**100% compliance is the goal.**

- < 90%: Significant issues, fix before proceeding
- 90-99%: Minor deviations, likely spec updates
- 100%: Perfect compliance, ready for verification

**Deviations trigger evolution.**

- Don't force-fit wrong spec
- Don't ignore deviations
- Use `speckit-spex-evolve` to reconcile

**The code and spec must tell the same story.**

**Evidence before assertions. Always.**
