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
if [ ! -f ".specify/extensions/spex-collab/extension.yml" ]; then
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
   - Problem statement: extract from "## Problem Statement", "## Background", or the first substantive paragraph explaining what's broken or missing (feeds "Why This Change")
   - Feature overview: user story summaries or solution description (feeds "What Changes")
   - Scope and applicability: extract from "## Requirements" (applies when) and "## Out of Scope" (does not apply when) (feeds "When It Applies")
   - Success criteria: from the "## Success Criteria" section
   - Edge cases: from the "### Edge Cases" section if present

2. **plan.md** (if exists, feeds "How It Works"):
   - Architecture approach: modules, data flow, integration points
   - Key technical decisions: from "## Research Findings" or decision sections
   - Trade-offs and rationale: why alternatives were rejected
   - Implementation strategy: from the "## Implementation Phases" section

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

The structure follows "general to specific": a reviewer should understand the motivation and shape of the change before encountering detailed scope lists.

**Why This Change**: The problem being solved. What's broken, painful, or missing today. 2-4 sentences, written so a reviewer who has NOT read the spec understands the motivation in 30 seconds. Extract from the spec's problem statement, user stories, or the plan's research findings.

**What Changes**: One paragraph summary of the solution at the outcome level. What gets added, removed, or restructured. Stay at the "what does the user/system gain" level. Mention breaking changes upfront. Do NOT include implementation details here (those go in "How It Works").

**How It Works**: Implementation approach extracted from plan.md. Cover architecture, key modules, data flow, and integration points. This is where technical details belong. Keep it concise but specific enough that a reviewer understands the implementation strategy without reading plan.md. For spec-only PRs where plan.md doesn't exist yet, omit this section or note "Implementation approach TBD."

**When It Applies**: Reframe scope as applicability. More natural than in/out lists for a reviewer scanning the PR.
- "Applies when": conditions, contexts, or scenarios where this feature is active
- "Does not apply when": explicit exclusions with brief rationale for deferral

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

## Offer Spec PR

After writing REVIEWERS.md, check if `gh` is available and offer to create a spec-only PR for review before implementation begins.

Use AskUserQuestion (`multiSelect: false`, header: "Spec PR"):

**"REVIEWERS.md is ready. Create a spec PR for team review?"**

Options:
- "Create spec PR": "Push branch and create a PR with the [Spec] tag for review before implementation"
- "Skip": "Continue without creating a PR"

**If "Create spec PR":**

```bash
FEATURE_NAME=$(head -1 "$FEATURE_DIR/spec.md" | sed 's/^# Feature Specification: //')
REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
BRANCH=$(git branch --show-current)

# When working in a fork, target PRs against the upstream repository
REPO_FLAG=""
if git remote | grep -qx upstream 2>/dev/null; then
  UPSTREAM_REPO=$(git remote get-url upstream 2>/dev/null | sed 's|.*github\.com[:/]||; s|\.git$||')
  [ -n "$UPSTREAM_REPO" ] && REPO_FLAG="--repo $UPSTREAM_REPO"
fi
REVIEWERS_REL="${FEATURE_DIR#$(git rev-parse --show-toplevel)/}/REVIEWERS.md"
REMOTE_URL=$(git remote get-url "$REMOTE" 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
REVIEWERS_URL="${REMOTE_URL}/blob/${BRANCH}/${REVIEWERS_REL}"

# Read label config
COLLAB_CONFIG=".specify/extensions/spex-collab/collab-config.yml"
LABELS_ENABLED=$(yq -r '.labels.enabled // true' "$COLLAB_CONFIG" 2>/dev/null || echo "true")
SPEC_LABEL=$(yq -r '.labels.spec // "spex/spec"' "$COLLAB_CONFIG" 2>/dev/null || echo "spex/spec")
LABEL_FLAG=""
if [ "$LABELS_ENABLED" = "true" ]; then
  LABEL_FLAG="--label ${SPEC_LABEL}"
fi

git push -u "$REMOTE" "$BRANCH"

Extract the "Why This Change", "What Changes", and "How It Works" sections from the REVIEWERS.md just written. Use the actual content, not placeholders. If "How It Works" was omitted (no plan.md yet), skip it.

```bash
gh pr create ${REPO_FLAG} --base main --title "${FEATURE_NAME} [Spec]" ${LABEL_FLAG} --body "$(cat <<PR_BODY
## Why This Change

[extracted from REVIEWERS.md "Why This Change" section]

## What Changes

[extracted from REVIEWERS.md "What Changes" section]

## How It Works

[extracted from REVIEWERS.md "How It Works" section, omit if absent]

---

> [!IMPORTANT]
> **[Review Guide](${REVIEWERS_URL})** contains the full review guidance: key decisions, scope boundaries, areas needing attention, and review checklist.

This PR contains the specification artifacts for **${FEATURE_NAME}**. Implementation follows after spec approval.

Assisted-By: 🤖 Claude Code
PR_BODY
)"
```

If the label doesn't exist in the repo, `gh pr create --label` will fail. In that case, retry without the label and warn:
```
Warning: Label "${SPEC_LABEL}" not found in this repo. PR created without label.
To create it: gh label create "${SPEC_LABEL}" --color 0075ca --description "Spec PR awaiting review"
Or disable labels: set labels.enabled to false in .specify/extensions/spex-collab/collab-config.yml
```

Report the PR URL.

**If "Skip":** Continue without creating a PR.

## Report

Output a brief confirmation:
```
Generated REVIEWERS.md in [feature-dir]/
Sections: Why This Change, What Changes, How It Works, When It Applies, Key Decisions, Areas Needing Attention, Open Questions, Review Checklist
```

If this was a re-run with preserved code phase sections, also note:
```
Preserved N existing code phase section(s)
```
