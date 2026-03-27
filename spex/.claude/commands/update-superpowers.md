---
description: "[Plugin Dev] Sync modified skills with upstream superpowers while preserving SDD enhancements"
---

# Upstream Superpowers Sync Workflow

**Purpose**: Sync modified skills with upstream superpowers while preserving SDD enhancements.

**Context**: This command is for maintaining the cc-sdd plugin, not for end users.

## Safety Check

Before proceeding, verify we're in the plugin development directory:

```bash
# Check for plugin marker
if [ ! -f "sdd/.superpowers-sync" ] || [ ! -f "sdd/.claude-plugin/plugin.json" ]; then
  echo "ERROR: This command only works in cc-sdd plugin directory"
  echo "Current directory: $(pwd)"
  exit 1
fi

# Verify we're in the right repo
if ! grep -q "cc-sdd" sdd/.claude-plugin/plugin.json 2>/dev/null; then
  echo "ERROR: This doesn't appear to be the cc-sdd repository"
  exit 1
fi

echo "Plugin directory confirmed"
```

**If checks fail, STOP and inform user this command is only for plugin maintenance.**

## Pre-Sync Preparation

### 1. Load Current Sync State

```bash
cat sdd/.superpowers-sync
```

Extract:
- `last_sync_commit`: Last upstream commit we synced from
- `modified_skills`: Which skills are modified and how
- `upstream_repo`: Upstream repository URL

### 2. Clone/Update Upstream Repository

```bash
# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Clone upstream
git clone https://github.com/obra/superpowers superpowers-upstream
cd superpowers-upstream

# Get current HEAD
CURRENT_COMMIT=$(git rev-parse HEAD)
CURRENT_DATE=$(git log -1 --format=%cd --date=short)

echo "Upstream HEAD: $CURRENT_COMMIT ($CURRENT_DATE)"
```

### 3. Check What Changed

For each modified skill, get the diff:

```bash
LAST_SYNC=$(jq -r '.last_sync_commit' sdd/.superpowers-sync)

# For each modified skill
for skill in writing-plans code-review verification-before-completion brainstorming; do
  UPSTREAM_FILE="skills/${skill}/SKILL.md"

  # Get changes since last sync
  if [ "$LAST_SYNC" != "INITIAL" ]; then
    echo "=== Changes to $skill ==="
    git log --oneline $LAST_SYNC..HEAD -- "$UPSTREAM_FILE"
    echo ""
  else
    echo "=== $skill (INITIAL SYNC) ==="
    echo "Will use current upstream version as baseline"
    echo ""
  fi
done
```

Save the temp directory path for later: `echo $TEMP_DIR`

## AI-Assisted Merge Workflow

For each modified skill, we'll use AI agents to merge upstream changes with SDD enhancements.

### Per-Skill Merge Process

For each skill in `sdd/.superpowers-sync` → `modified_skills`:

**Special case: writing-plans (reference-only)**

If the skill has `"sync_mode": "reference-only"` in `.superpowers-sync`:
1. Read the upstream changes to `skills/writing-plans/SKILL.md`
2. Read the target skill specified in `"feeds_into"` (e.g., `sdd/skills/plan/SKILL.md`)
3. Identify new quality patterns, validation approaches, or anti-rationalization improvements
4. Adapt relevant changes into the target skill's post-generation quality checks
5. Status becomes "Evaluated" instead of "Merged"
6. **Do NOT create a local writing-plans SKILL.md.** All patterns go into `sdd:plan`.

**Standard case: all other skills**

1. **Read three sources**:
   - Upstream current version: `$TEMP_DIR/superpowers-upstream/skills/[skill]/SKILL.md`
   - Local current version: `sdd/skills/[skill]/SKILL.md`
   - Modification metadata: from `sdd/.superpowers-sync`

2. **Get upstream changes** (if not INITIAL sync):
   ```bash
   cd $TEMP_DIR/superpowers-upstream

   # Get patch of changes
   git diff $LAST_SYNC..HEAD -- skills/[skill]/SKILL.md > /tmp/upstream-changes-[skill].patch

   # Get commit messages for context
   git log --format="%h %s" $LAST_SYNC..HEAD -- skills/[skill]/SKILL.md > /tmp/upstream-commits-[skill].txt
   ```

3. **Launch merge agent**:

   Use the Task tool to launch a merge agent for EACH skill:

   ```
   Prompt for agent:

   You are merging upstream superpowers changes into a modified skill that has SDD enhancements.

   **Context:**
   - Skill: [skill-name]
   - Upstream repo: https://github.com/obra/superpowers
   - Local repo: cc-sdd (this plugin)

   **Your task:**
   1. Read the current local version: sdd/skills/[skill]/SKILL.md
   2. Read the upstream current version: $TEMP_DIR/superpowers-upstream/skills/[skill]/SKILL.md
   3. Read the modification metadata from sdd/.superpowers-sync
   4. If not INITIAL sync, read upstream changes: /tmp/upstream-changes-[skill].patch
   5. Analyze:
      - What improved in upstream (better examples, new patterns, fixes)
      - What SDD enhancements exist in local (from modification_summary)
      - Where conflicts might occur
   6. Create merged version that:
      - Preserves ALL SDD sections (listed in sdd_additions)
      - Integrates upstream improvements (better wording, examples, anti-rationalization)
      - Maintains consistency in tone and structure
      - Keeps both superpowers discipline AND spec-awareness
   7. Output:
      - The complete merged SKILL.md content
      - Summary of changes made
      - List of conflicts (if any) and how resolved
      - Recommendation: "READY TO APPLY" or "NEEDS REVIEW" with reasons

   **Critical rules:**
   - DO NOT remove SDD-specific sections
   - DO NOT weaken spec-first principles
   - DO integrate better examples/wording from upstream
   - DO preserve quality gates from both sources
   - DO maintain anti-rationalization patterns from both versions

   **Modification metadata for this skill:**
   ```json
   [paste relevant section from .superpowers-sync]
   ```

   Begin merge analysis and output merged content.
   ```

4. **Review agent output**:
   - Check that SDD sections are preserved
   - Verify upstream improvements are integrated
   - Confirm no conflicts or all conflicts resolved
   - If "NEEDS REVIEW", examine conflicts carefully

5. **Apply or defer**:
   - If "READY TO APPLY": Write merged content to `sdd/skills/[skill]/SKILL.md`
   - If "NEEDS REVIEW": Save to `sdd/skills/[skill]/SKILL.md.proposed` and mark for manual review

## Run Merge for All Modified Skills

Execute the above process for each skill:

1. `writing-plans` (upstream: `skills/writing-plans/SKILL.md`)
2. `review-code` (upstream: `skills/code-review/SKILL.md`)
3. `verification-before-completion` (upstream: `skills/verification-before-completion/SKILL.md`)
4. `brainstorm` (upstream: `skills/brainstorming/SKILL.md`)

**Use TodoWrite to track progress:**
- [ ] Evaluate writing-plans changes for sdd:plan quality gates
- [ ] Merge review-code
- [ ] Merge verification-before-completion
- [ ] Merge brainstorm
- [ ] Review all merged files
- [ ] Update .superpowers-sync
- [ ] Update CHANGELOG
- [ ] Test merged skills

## Post-Merge Actions

### 1. Generate Sync Report

Create `docs/sync-reports/sync-YYYY-MM-DD.md`:

```markdown
# Superpowers Sync Report: YYYY-MM-DD

**Upstream Commit**: [COMMIT_HASH]
**Upstream Date**: [DATE]
**Previous Sync**: [LAST_SYNC_COMMIT]

## Skills Updated

### writing-plans (reference-only, feeds into sdd:plan)
**Status**: ✅ Evaluated / ⚠️ Needs Review

**Upstream Changes Identified**:
- [List improvements from upstream commits]

**Adapted into sdd:plan**:
- [New quality patterns adapted into post-generation checks]
- [New validation approaches integrated]
- [Anti-rationalization improvements absorbed]

**Not Applicable**:
- [Changes that don't apply to the sdd:plan model, with reason]

---

[Repeat for each skill]

## Summary

- Modified skills synced: X/4
- Skills needing manual review: X
- SDD enhancements: All preserved ✅
- Upstream improvements: [count] integrated

## Next Steps

- [ ] Review any skills marked "NEEDS REVIEW"
- [ ] Test all merged skills for consistency
- [ ] Update CHANGELOG with sync entry
- [ ] Commit with message: "Sync with superpowers@[COMMIT]"
```

### 2. Update .superpowers-sync

```bash
# Update tracking file
jq --arg commit "$CURRENT_COMMIT" --arg date "$(date +%Y-%m-%d)" \
  '.last_sync_commit = $commit | .last_sync_date = $date | .note = "Synced via /update-superpowers"' \
  sdd/.superpowers-sync > sdd/.superpowers-sync.tmp

mv sdd/.superpowers-sync.tmp sdd/.superpowers-sync
```

### 3. Update CHANGELOG

Add entry:

```markdown
## [Unreleased]

### Changed
- Synced with superpowers@[COMMIT_SHORT] ([DATE])
  - `writing-plans`: [evaluated, adapted into sdd:plan quality gates]
  - `review-code`: [summary]
  - `verification-before-completion`: [summary]
  - `brainstorm`: [summary]
  - All SDD spec-compliance enhancements preserved
```

### 4. Cleanup

```bash
# Remove temp directory
rm -rf $TEMP_DIR

# Show status
git status
```

## Testing Merged Skills

After merge, verify each skill:

```bash
# Read through each modified skill
cat sdd/skills/review-code/SKILL.md
cat sdd/skills/verification-before-completion/SKILL.md
cat sdd/skills/brainstorm/SKILL.md

# writing-plans is reference-only: check that sdd:plan absorbed any new patterns
cat sdd/skills/plan/SKILL.md

# Check for:
# - SDD sections still present (spec-first, compliance checking, etc.)
# - Superpowers discipline maintained (anti-rationalization, quality gates)
# - Improved examples/wording from upstream integrated
# - No merge artifacts (<<<<<<, >>>>>>, etc.)
# - Consistent tone and structure
# - sdd:plan quality gates reflect any new writing-plans patterns
```

## Final Output

Present to user:

```
✅ Superpowers Sync Complete

**Synced from**: obra/superpowers@[COMMIT] ([DATE])
**Skills updated**: 4

**Summary**:
- writing-plans: ✅ [evaluated, X patterns adapted into sdd:plan]
- review-code: ✅ [X changes integrated]
- verification-before-completion: ✅ [X changes integrated]
- brainstorm: ✅ [X changes integrated]

**Reports**:
- Detailed report: docs/sync-reports/sync-YYYY-MM-DD.md
- Changes staged for review

**Next steps**:
1. Review changed files: `git diff`
2. Test skills work correctly
3. Commit: `git commit -m "Sync with superpowers@[COMMIT_SHORT]"`
4. Update CHANGELOG if needed

[If any skills need manual review]:
⚠️  Manual review needed:
- sdd/skills/[skill]/SKILL.md.proposed - [reason]

Please review and resolve before committing.
```

## Usage Example

```bash
# User runs in cc-sdd directory
/update-superpowers

# Claude executes:
# 1. Verifies we're in plugin directory ✅
# 2. Reads sdd/.superpowers-sync
# 3. Clones upstream superpowers
# 4. Checks for changes since last sync
# 5. Launches merge agents for each modified skill
# 6. Reviews agent outputs
# 7. Applies merged versions
# 8. Generates sync report
# 9. Updates sdd/.superpowers-sync
# 10. Suggests CHANGELOG entry
# 11. Shows summary and next steps
```

## Notes

- This command is **only for plugin maintainers**
- It will fail if run outside cc-sdd directory
- Always review merged skills before committing
- SDD enhancements should NEVER be removed
- Upstream improvements should be integrated when they don't conflict
- When in doubt, mark for manual review
