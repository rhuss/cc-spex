---
description: "Manage phase boundaries, PR creation, and REVIEWERS.md updates between implementation phases"
---

# Phase Manager

Coordinates the boundary between implementation phases: runs code review, updates REVIEWERS.md with code-specific guidance, offers PR creation, and manages phase state for cross-session continuity.

## Ship Pipeline Guard

```bash
if [ -f ".specify/.spex-state" ]; then
  MODE=$(jq -r '.mode // empty' .specify/.spex-state 2>/dev/null)
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  if [ "$MODE" = "ship" ] || [ "$STATUS" = "running" ]; then
    echo "Ship mode active, skipping phase manager"
  fi
fi
```

If ship mode is detected, return immediately.

## Extension Enabled Check

```bash
if [ ! -f ".specify/extensions/spex-collab/extension.yml" ]; then
  echo "spex-collab extension not found, skipping"
fi
```

If the extension is not found, return without action.

## Read Phase State

Load the phase plan and completion state from `.specify/.spex-state`:

```bash
PHASE_PLAN=$(jq -r '.collab.phase_plan // empty' .specify/.spex-state 2>/dev/null)
COMPLETED=$(jq -r '.collab.completed_phases // []' .specify/.spex-state 2>/dev/null)
PR_BASE=$(jq -r '.collab.pr_base_branch // "main"' .specify/.spex-state 2>/dev/null)
```

If no phase plan exists (`collab.phase_plan` is empty or missing):
- Output: "No phase plan found. Run the phase-split command first, or invoke `/speckit.spex-collab.phase-split` to create one."
- Return.

## Determine Current Phase

Find the next phase to process:
- Get the list of phase numbers from `phase_plan`
- Filter out any phase numbers present in `completed_phases`
- The current phase is the lowest remaining phase number

If all phases are in `completed_phases`:
- Output: "All phases complete. Implementation is finished."
- List each phase with its PR status if available
- Return.

Display the current phase:
```
## Phase [N]: [Phase Name]

Tasks in this phase: [task IDs]
Previously completed phases: [list or "none"]
```

## Resolve Spec Directory

```bash
PREREQ=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
FEATURE_DIR=$(echo "$PREREQ" | jq -r '.FEATURE_DIR')
```

## Invoke Code Review Gate

Before updating REVIEWERS.md, ensure the code review gate has run for this phase's changes.

Check if `REVIEW-CODE.md` exists in FEATURE_DIR:

```bash
if [ ! -f "${FEATURE_DIR}/REVIEW-CODE.md" ]; then
  echo "REVIEW-CODE.md not found, invoking code review gate"
fi
```

If REVIEW-CODE.md does not exist, invoke the code review gate:
- Execute `speckit.spex-gates.review-code` (the review-code skill/command)
- Wait for it to complete before proceeding

If REVIEW-CODE.md exists, read its findings for use in the REVIEWERS.md update.

## Update REVIEWERS.md with Code Phase Section

After the code review gate passes, update REVIEWERS.md with a code-specific phase section.

### Gather Phase Information

1. **What Changed**: Run `git diff --stat` against the PR base branch to get a summary of changed files:
   ```bash
   git diff --stat "${PR_BASE}..HEAD" 2>/dev/null
   ```

2. **Spec Compliance**: Extract findings from REVIEW-CODE.md (compliance score, deviations, covered requirements)

3. **Focus Areas**: Identify where the reviewer should concentrate:
   - Files with the most changes
   - Areas flagged by the code review gate
   - Complex logic or non-obvious patterns

4. **AI Assumptions**: Decisions made during implementation that were not explicitly specified in spec.md. Look for:
   - Implementation choices not dictated by the spec
   - Default values or behaviors chosen by the AI
   - Error handling approaches not specified

### Compose Phase Section

Create a new section following this structure:

```markdown
## Phase [N]: [Phase Name] (YYYY-MM-DD)

### What Changed

[Summary of files and functionality added/modified, based on git diff --stat]

### Spec Compliance

[Which requirements this phase addresses, compliance findings from REVIEW-CODE.md]

### Focus Areas for Review

[Where the reviewer should concentrate, based on complexity and review gate findings]

### AI Assumptions

[Decisions made during implementation that were not in the spec]
```

### Append to REVIEWERS.md

Read the existing REVIEWERS.md from FEATURE_DIR.

Append the new phase section at the end of the file. Ensure:
- A `---` separator precedes the phase section (if not already present)
- The phase number matches the current phase from the phase plan
- Existing phase sections are never overwritten or modified

If REVIEWERS.md does not exist:
- Warn: "REVIEWERS.md not found. It should have been created by the reviewers command after task generation. Creating a minimal version."
- Create a minimal REVIEWERS.md with just the phase section

## Offer PR Creation

Check if `gh` CLI is available:

```bash
command -v gh >/dev/null 2>&1
```

### If gh is available

Construct PR details:

**Title format**: `[Feature Name] [Spec + Impl (N/T)]` where N is the current phase and T is the total number of phases.

```bash
FEATURE_NAME=$(head -1 "$FEATURE_DIR/spec.md" | sed 's/^# Feature Specification: //')
TOTAL_PHASES=$(jq '.collab.phase_plan | length' .specify/.spex-state 2>/dev/null || echo 1)
CURRENT_PHASE_NUM=[N]  # current phase number

if [ "$TOTAL_PHASES" -gt 1 ]; then
  PR_TITLE="${FEATURE_NAME} [Spec + Impl (${CURRENT_PHASE_NUM}/${TOTAL_PHASES})]"
else
  PR_TITLE="${FEATURE_NAME} [Spec + Impl]"
fi
```

If a spec-only PR was created earlier (titled `... [Spec]`), update its title to reflect the implementation phase using `gh pr edit`.

- **Body**: Start with a link to REVIEWERS.md for full review context, then include the phase section.

Construct a full GitHub URL for REVIEWERS.md and read label config:

```bash
BRANCH=$(git branch --show-current)
REVIEWERS_REL="${FEATURE_DIR#$(git rev-parse --show-toplevel)/}/REVIEWERS.md"
REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
REMOTE_URL=$(git remote get-url "$REMOTE" 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
REVIEWERS_URL="${REMOTE_URL}/blob/${BRANCH}/${REVIEWERS_REL}"

# Read label config
COLLAB_CONFIG=".specify/extensions/spex-collab/collab-config.yml"
LABELS_ENABLED=$(yq -r '.labels.enabled // true' "$COLLAB_CONFIG" 2>/dev/null || echo "true")
SPEC_LABEL=$(yq -r '.labels.spec // "spex/spec"' "$COLLAB_CONFIG" 2>/dev/null || echo "spex/spec")
SPEC_APPROVED_LABEL=$(yq -r '.labels.spec_approved // "spex/spec-approved"' "$COLLAB_CONFIG" 2>/dev/null || echo "spex/spec-approved")
IMPL_LABEL=$(yq -r '.labels.implement // "spex/implement"' "$COLLAB_CONFIG" 2>/dev/null || echo "spex/implement")
LABEL_FLAG=""
if [ "$LABELS_ENABLED" = "true" ]; then
  LABEL_FLAG="--label ${IMPL_LABEL}"
fi
```

The PR body MUST begin with:
```
> **[Review Guide](REVIEWERS_URL)** for full context: motivation, key decisions, and scope boundaries.
```

Followed by the phase section content (What Changed, Spec Compliance, Focus Areas, AI Assumptions).

Use AskUserQuestion to ask:

**Question**: "Phase [N] is ready. What would you like to do?"
**Options**:
- "Create PR" - create PR via gh and pause
- "Skip PR, continue to next phase" - mark complete, proceed
- "Pause here" - mark current phase, stop for manual action

**If "Create PR"**:

```bash
gh pr create --base "${PR_BASE}" --title "$PR_TITLE" ${LABEL_FLAG} --body "$(cat <<PR_BODY
> **[Review Guide](${REVIEWERS_URL})** for full context: motivation, key decisions, and scope boundaries.

[PR body content from REVIEWERS.md phase section]
PR_BODY
)"
```

After PR creation:
- Capture the PR URL from gh output
- If labels are enabled, update labels on the PR to reflect the implementation phase:
  ```bash
  # If an existing PR has spex/spec, transition labels
  PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null)
  if [ -n "$PR_NUM" ] && [ "$LABELS_ENABLED" = "true" ]; then
    gh pr edit "$PR_NUM" --remove-label "$SPEC_LABEL" --add-label "$SPEC_APPROVED_LABEL","$IMPL_LABEL" 2>/dev/null || true
  fi
  ```
- Mark the phase as completed (see below)
- Output: "PR created: [URL]"
- Output: "Phase [N] complete. After the PR is merged, invoke `/speckit.spex-collab.phase-manager` to continue with Phase [N+1]."
- Stop execution (pause for user to handle the PR)

**If "Skip PR, continue to next phase"**:
- Mark the phase as completed
- Output: "Phase [N] complete (no PR created). Continuing to Phase [N+1]..."
- Do NOT stop execution, the implementation command can continue

**If "Pause here"**:
- Set `current_phase` to N in `.spex-state`
- Output: "Paused at Phase [N]. Invoke `/speckit.spex-collab.phase-manager` when ready to continue."
- Stop execution

### If gh is NOT available

Warn and provide manual instructions:

```
gh CLI not found. To create the PR manually:

Branch: [current branch name]
Target: [PR_BASE]
Suggested title: [Feature Name] [Spec + Impl (N/T)]
Suggested body (start with the review guide link):
  > **[Review Guide](REVIEWERS_URL)** for full context: motivation, key decisions, and scope boundaries.
  [phase section content]
```

Then use AskUserQuestion:
- "Mark phase complete and continue" - proceed
- "Pause here" - stop for manual action

## Update Phase State

When marking a phase as completed:

```bash
tmp=$(mktemp) && jq \
  --argjson phase_num [N] \
  '.collab.completed_phases += [$phase_num] | .collab.completed_phases |= unique | .collab.current_phase = null' \
  .specify/.spex-state > "$tmp" && mv "$tmp" .specify/.spex-state
```

When setting current phase (for pause):

```bash
tmp=$(mktemp) && jq \
  --argjson phase_num [N] \
  '.collab.current_phase = $phase_num' \
  .specify/.spex-state > "$tmp" && mv "$tmp" .specify/.spex-state
```

## Final Report

After processing the phase, output a summary:

```
Phase [N] ([Phase Name]): [COMPLETE / PAUSED]
PR: [URL or "not created"]
REVIEWERS.md: updated with Phase [N] section
Next: [Phase N+1 name or "All phases complete"]
```
