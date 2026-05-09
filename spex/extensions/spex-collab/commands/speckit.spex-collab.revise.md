---
description: "Revise spec artifacts based on PR review feedback, cascade to plan/tasks, and update REVIEWERS.md with revision history"
argument-hint: "[--pr <number>] [description of changes]"
---

# Revise Spec from PR Feedback

Handles the spec revision loop: read PR review comments, update spec, cascade to plan and tasks, document the revision in REVIEWERS.md, and push back to the PR.

## Ship Pipeline Guard

If `.specify/.spex-state` exists with `mode: "ship"`, return immediately. Spec revision is an interactive collab workflow.

## Resolve Context

```bash
PREREQ=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
FEATURE_DIR=$(echo "$PREREQ" | jq -r '.FEATURE_DIR')
BRANCH=$(git branch --show-current)
```

Verify required artifacts exist:
```bash
[ -f "${FEATURE_DIR}/spec.md" ] || { echo "ERROR: No spec.md found in ${FEATURE_DIR}"; exit 1; }
```

## Gather Feedback

Determine the review feedback to address. Two input modes:

### Mode 1: PR number provided (`--pr <number>`)

Fetch unresolved review comments from the PR:

```bash
PR_NUM="<number>"
gh pr view "$PR_NUM" --json reviews,comments --jq '.reviews[].body, .comments[].body' 2>/dev/null
gh api "repos/{owner}/{repo}/pulls/${PR_NUM}/comments" --jq '.[] | select(.position != null) | "\(.path):\(.position) - \(.body)"' 2>/dev/null
```

Present a summary of the feedback to the user:

```
## PR #<number> Review Feedback

Found N review comments:

1. @reviewer: "The hard removal of stdout seems risky..."
2. @reviewer: "Should subagent merging be in scope?"
...

Which comments should we address in this revision?
```

Use AskUserQuestion (`multiSelect: true`, header: "Feedback"):
**"Which review comments should this revision address?"**

Options: one per comment (label: truncated comment, description: full text)

### Mode 2: User describes changes (arguments or conversation)

If no `--pr` flag, the user's arguments or conversation describe what to change. Use that directly as the revision input.

## Plan the Revision

Before making changes, summarize what will change. Read the current spec.md and identify which sections are affected by the feedback.

Present a revision plan:

```
## Revision Plan

Based on the feedback, these changes are needed:

**Spec changes**:
- Section "Requirements": add deprecation warning for stdout access
- Section "Out of Scope": move subagent merging to in-scope

**Expected cascade**:
- plan.md: will need regeneration (new requirements affect implementation approach)
- tasks.md: will need regeneration (task count may change)
- REVIEWERS.md: Key Decisions and Scope Boundaries sections affected

Proceed with revision?
```

Use AskUserQuestion (`multiSelect: false`, header: "Revise"):
**"Proceed with the revision plan?"**
- "Yes, revise all": "Update spec, regenerate plan and tasks, update REVIEWERS.md"
- "Spec only": "Update spec.md only, skip plan/tasks regeneration"
- "Cancel": "Abort revision"

If "Cancel", stop.

## Update Spec

Apply the planned changes to `${FEATURE_DIR}/spec.md`. Edit the affected sections, preserving the overall structure and unaffected content.

After editing, verify the spec is still well-formed:
- All required sections present
- No orphaned references
- No contradictions introduced by the changes

### Clarify Updated Spec

Invoke `/speckit-clarify` on the updated spec to detect any new ambiguities introduced by the revision. In the revise context, answer clarification questions yourself using the PR feedback as context (the reviewer's intent guides the answers). Update the spec with any clarifications.

### Review Updated Spec

Invoke `/speckit-spex-gates-review-spec` to validate the revised spec. This runs as a subagent for clean context separation:

```
You are reviewing a revised specification after PR feedback.

Feature directory: <FEATURE_DIR>
Spec: <FEATURE_DIR>/spec.md

Invoke /speckit-spex-gates-review-spec to validate spec quality.
Report the overall assessment and any findings.
```

If the review surfaces issues (UNSOUND or critical findings):
- Fix the spec issues before proceeding
- Re-run the review (max 2 retries)
- If issues persist after retries, warn the user and proceed

### Track Gate Results

Record gate outcomes for the revision entry:
```bash
SPEC_GATE="PASS"  # or the actual assessment from review-spec
```

## Cascade to Plan and Tasks

**Skip this step if user chose "Spec only".**

### Regenerate Plan

Invoke `/speckit-plan` to regenerate `plan.md` based on the updated spec. The plan command reads the current spec and produces an updated plan.

After plan regeneration, verify:
```bash
[ -f "${FEATURE_DIR}/plan.md" ] && echo "plan.md regenerated"
```

### Regenerate Tasks

Invoke `/speckit-tasks` to regenerate `tasks.md` based on the updated plan.

After task regeneration, capture the new task count:
```bash
NEW_TASK_COUNT=$(grep -c '^\- \[' "${FEATURE_DIR}/tasks.md" 2>/dev/null || echo "?")
```

### Review Updated Plan

Invoke `/speckit-spex-gates-review-plan` to validate the regenerated plan and tasks. This runs as a subagent:

```
You are reviewing a regenerated plan after spec revision from PR feedback.

Feature directory: <FEATURE_DIR>
Spec: <FEATURE_DIR>/spec.md
Plan: <FEATURE_DIR>/plan.md
Tasks: <FEATURE_DIR>/tasks.md

Invoke /speckit-spex-gates-review-plan to validate plan coverage and task quality.
Report the findings and overall assessment.
```

If the review surfaces critical issues:
- Fix the plan/task issues before proceeding
- Re-run the review (max 2 retries)
- If issues persist after retries, warn the user and proceed

Record gate outcome:
```bash
PLAN_GATE="PASS"  # or the actual assessment from review-plan
```

## Update REVIEWERS.md

### Regenerate Spec Sections

Invoke the reviewers command logic to regenerate the spec-facing sections (Why This Change, What Changes, Key Decisions, etc.) while preserving any existing code phase sections.

Read the current REVIEWERS.md:
```bash
REVIEWERS_PATH="${FEATURE_DIR}/REVIEWERS.md"
```

If code phase sections exist (lines starting with `## Phase`), preserve them. Regenerate the spec sections above the `---` separator by re-running the reviewers synthesis from the updated spec, plan, and tasks.

### Append Revision Entry

After the review checklist and before the `---` separator (or at the end if no separator), append a revision history section.

If a `## Revision History` section already exists, append a new entry. If not, create the section.

Determine the revision number:
```bash
REV_COUNT=$(grep -c '^### Rev ' "$REVIEWERS_PATH" 2>/dev/null || echo 0)
NEXT_REV=$((REV_COUNT + 1))
```

Compose the revision entry:

```markdown
## Revision History

### Rev N (YYYY-MM-DD) - [Brief trigger description]

**Trigger**: [PR review feedback from #NNN / User-requested changes / ...]

**Spec changes**:
- [Bullet list of what changed in spec.md, one per meaningful change]

**Quality gates**:
- review-spec: [PASS/SOUND (score) / findings fixed / warning: issues remain]
- review-plan: [PASS (score) / findings fixed / skipped (spec-only revision)]

**Cascade impact**:
- plan.md: [regenerated (summary of changes) / unchanged]
- tasks.md: [regenerated (N tasks, was M) / unchanged]
- REVIEWERS.md: [which sections were updated]
```

If the revision history section already exists, append the new `### Rev N` entry at the end of the section (before `---` or end of file).

## Commit and Push

Stage all changed artifacts:

```bash
git add "${FEATURE_DIR}/spec.md"
git add "${FEATURE_DIR}/REVIEWERS.md"
[ -f "${FEATURE_DIR}/plan.md" ] && git add "${FEATURE_DIR}/plan.md"
[ -f "${FEATURE_DIR}/tasks.md" ] && git add "${FEATURE_DIR}/tasks.md"

git commit -m "spec: revise based on review feedback (rev ${NEXT_REV})

Assisted-By: 🤖 Claude Code"
```

Push to the remote:
```bash
REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
git push "$REMOTE" "$BRANCH"
```

## Comment on PR

If a PR number is known (from `--pr` flag or detected from the branch):

```bash
PR_NUM=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)
```

If a PR exists, post a summary comment:

```bash
gh pr comment "$PR_NUM" --body "$(cat <<COMMENT
## Spec Revision ${NEXT_REV}

Addressed review feedback with the following changes:

**Spec changes**:
- [same bullet list as revision entry]

**Quality gates**:
- review-spec: ${SPEC_GATE}
- review-plan: ${PLAN_GATE}

**Cascade**:
- plan.md: [regenerated / unchanged]
- tasks.md: [regenerated (N tasks, was M) / unchanged]
- REVIEWERS.md: updated with revision history

See the [Review Guide](${REVIEWERS_URL}) for the full updated context.
COMMENT
)"
```

Construct `REVIEWERS_URL` the same way as other commands:
```bash
REMOTE_URL=$(git remote get-url "$REMOTE" 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
REVIEWERS_URL="${REMOTE_URL}/blob/${BRANCH}/${FEATURE_DIR#$(git rev-parse --show-toplevel)/}/REVIEWERS.md"
```

## Report

```
## Revision Complete

**Rev**: ${NEXT_REV}
**Spec changes**: N sections updated
**Quality gates**: review-spec ${SPEC_GATE}, review-plan ${PLAN_GATE}
**Cascade**: plan.md [regenerated/unchanged], tasks.md [regenerated/unchanged]
**REVIEWERS.md**: revision history appended
**PR**: [comment posted to #NNN / no PR found]
**Pushed**: ${BRANCH} → ${REMOTE}
```

## Suggest Reconciliation

After reporting, check if implementation files already exist on the branch:

```bash
IMPL_FILES=$(git diff --name-only main...HEAD 2>/dev/null | grep -v '^specs/' | grep -v '^brainstorm/' | grep -v '^\.' | grep -c . 2>/dev/null || echo 0)
```

If implementation files exist (`IMPL_FILES` > 0):

```
Implementation files detected on this branch (${IMPL_FILES} files).
The revised tasks may conflict with existing code.

Run /speckit-spex-collab-reconcile to scan existing code against
the updated tasks and produce a delta for re-implementation.
```
