---
description: "Generate REVIEWERS.md review guide for spec and code PRs"
argument-hint: "[--regenerate]"
---

# Generate REVIEWERS.md Review Guide

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `mode` is `"ship"` or `status` is `"running"`, skip REVIEWERS.md generation entirely and return immediately.

```bash
if [ -f ".specify/.spex-state" ]; then
  MODE=$(jq -r '.mode // empty' .specify/.spex-state 2>/dev/null)
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  if [ "$MODE" = "ship" ] || [ "$STATUS" = "running" ]; then
    echo "Ship mode active, skipping REVIEWERS.md generation"
  fi
fi
```

If ship mode is detected, output nothing further and return. Do not generate or modify any files.

## Extension Enabled Check

Verify spex-collab is active. If the extension directory does not exist, skip silently:

```bash
if [ ! -f "spex/extensions/spex-collab/extension.yml" ]; then
  echo "spex-collab extension not found, skipping"
fi
```

If the extension is not found, return without generating REVIEWERS.md. Vanilla spec-kit behavior is preserved.

## Resolve Spec Directory

Run the prerequisites script to locate the feature directory:

```bash
.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null
```

Parse the JSON output to extract:
- `FEATURE_DIR`: absolute path to the spec directory (e.g., `/path/to/specs/018-collab-extension`)
- `FEATURE_SPEC`: path to spec.md

If resolution fails, inform the user and stop:
```
Cannot resolve spec directory. Are you on a feature branch?
```

## Check for Existing REVIEWERS.md

```bash
REVIEWERS_PATH="${FEATURE_DIR}/REVIEWERS.md"
if [ -f "$REVIEWERS_PATH" ]; then
  echo "REVIEWERS.md exists, checking for code phase sections to preserve"
fi
```

If REVIEWERS.md already exists:
1. Read its content
2. Look for the first line matching `## Phase [0-9]` (a code phase section heading)
3. If found: preserve everything from that line onwards (these are code phase sections from previous implementation phases). Only regenerate the spec sections above that boundary.
4. If no phase headings found: regenerate the entire file

Store any preserved code phase content for later appending.

## Read Source Artifacts

Read these files from FEATURE_DIR to extract review guide content:

1. **spec.md** (required):
   - Feature overview: the first substantive paragraph or user story summaries
   - Scope boundaries: extract from "## Requirements" (in-scope) and "## Out of Scope" (exclusions)
   - Success criteria: from the "## Success Criteria" section
   - Edge cases: from the "### Edge Cases" section if present

2. **plan.md** (required):
   - Key technical decisions: from "## Research Findings" or decision sections
   - Trade-offs and rationale: why alternatives were rejected
   - Architecture approach: from the "## Implementation Phases" section

3. **tasks.md** (if exists):
   - Phase count and task distribution
   - Complexity indicators (total tasks, parallel markers)

4. **research.md** (if exists):
   - Additional context on technical decisions
   - Explored alternatives

## Compose REVIEWERS.md

Read the template from `spex/extensions/spex-collab/templates/reviewers-template.md` for the structural skeleton.

Synthesize a human-readable review guide. This is NOT a dump of automated review findings. Write it as if briefing a colleague who needs to review the PR efficiently.

### Section Guidelines

**Feature Overview**: 2-3 sentences capturing what this feature does and why it matters. Written for someone who has NOT read the spec.

**Scope Boundaries**: Two bullet lists:
- "In scope": the concrete deliverables and behaviors
- "Out of scope": what was explicitly excluded and why

**Key Decisions**: Numbered list of the most significant design choices. For each, include:
- What was decided
- What alternatives were considered
- Why this approach was chosen

**Areas Needing Attention**: Points where reasonable engineers might disagree. Flag:
- Trade-offs that favor one quality over another
- Assumptions that could be wrong
- Patterns that deviate from project conventions
- Complexity that might be over-engineered or under-engineered

**Open Questions**: Remaining ambiguities or deferred decisions. If none, state "No open questions identified."

**Review Checklist**: Use the standard checklist from the template. Add feature-specific items if the spec has unusual constraints.

### Replace Template Placeholders

- `[Feature Name]`: extract from spec.md title or first heading
- `YYYY-MM-DD`: use today's date
- `[spec.md](spec.md)`: keep as relative link

## Write REVIEWERS.md

Write the composed content to `${FEATURE_DIR}/REVIEWERS.md`.

If code phase sections were preserved from an earlier version (step 4), append them after the `---` separator at the end of the spec sections.

## Report

Output a brief confirmation:
```
Generated REVIEWERS.md in [feature-dir]/
Sections: Feature Overview, Scope Boundaries, Key Decisions, Areas Needing Attention, Open Questions, Review Checklist
```

If this was a re-run with preserved code phase sections, also note:
```
Preserved N existing code phase section(s)
```
