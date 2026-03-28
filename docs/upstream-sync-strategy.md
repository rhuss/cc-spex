# Upstream Sync Strategy

**Purpose**: Maintain sync with upstream superpowers while preserving spex enhancements

**Upstream**: https://github.com/obra/superpowers by Jesse Vincent

## Overview

This plugin modifies 4 superpowers skills to add spec-awareness. We need a strategy to:
1. Stay current with upstream improvements
2. Preserve our spex enhancements
3. Minimize manual merge conflicts

**Chosen approach**: AI-Assisted Merge (Option 3)

## Architecture

### Files Involved

```
cc-spex/
├── spex/                           # Nested plugin directory
│   ├── .superpowers-sync          # Tracking file (committed to git)
│   ├── .claude/commands/
│   │   └── update-superpowers.md  # Slash command for AI-assisted sync
│   ├── scripts/
│   │   └── check-upstream-changes.sh  # Helper to check for changes
│   └── skills/
│       ├── writing-plans/         # Modified from superpowers
│       ├── review-code/           # Modified from superpowers
│       ├── verification-before-completion/  # Modified from superpowers
│       └── brainstorm/            # Modified from superpowers
├── docs/
│   ├── sync-reports/              # Generated sync reports
│   └── upstream-sync-strategy.md  # This file
└── Makefile                       # Build and install targets
```

### Modified Skills Mapping

| Local Skill | Upstream Skill | Modifications |
|-------------|----------------|---------------|
| `writing-plans` | `skills/writing-plans/SKILL.md` | Plans from specs; validates coverage |
| `review-code` | `skills/code-review/SKILL.md` | Spec compliance focus; scoring |
| `verification-before-completion` | `skills/verification-before-completion/SKILL.md` | Adds spec compliance + drift checking |
| `brainstorm` | `skills/brainstorming/SKILL.md` | Output is spec; WHAT/WHY focus |

## Workflow

### 1. Check for Upstream Changes

**Quarterly** (or before major release), check for upstream changes:

```bash
# Option A: Run via Makefile
make check-upstream

# Option B: Run helper script from spex/
cd spex && ./scripts/check-upstream-changes.sh

# Option C: Manual check
cat spex/.superpowers-sync | jq -r '.last_sync_commit'
# Visit: https://github.com/obra/superpowers/commits/main
# Compare against last_sync_commit
```

**Output**:
```
Checking for upstream superpowers changes...

Last sync: abc123def (2025-11-12)
Upstream HEAD: xyz789ghi (2025-12-01)

Changes since last sync:
  * xyz7890 Improve anti-rationalization examples
  * ghi3456 Add quality gate for verification
  * def1234 Fix typo in brainstorming workflow

Modified skills to check:
  ✓ writing-plans - no changes
  ● review-code - HAS CHANGES
    Commits: 2
      - Improve anti-rationalization examples (xyz7890)
      - Add quality gate for verification (ghi3456)
  ✓ verification-before-completion - no changes
  ✓ brainstorming - no changes

⚡ 1 skill(s) have upstream changes

To sync, run: /update-superpowers
```

### 2. Run AI-Assisted Sync

**In cc-spex directory**, run:

```bash
/update-superpowers
```

**What happens**:

1. **Safety check**: Verifies you're in the plugin directory
2. **Load state**: Reads `.superpowers-sync`
3. **Clone upstream**: Gets latest superpowers in temp directory
4. **Analyze changes**: For each modified skill, gets diff since last sync
5. **Launch merge agents**: One AI agent per modified skill to:
   - Read upstream changes
   - Read local version
   - Read modification metadata
   - Merge preserving spex enhancements
   - Output merged version + report
6. **Review outputs**: Check that spex sections preserved
7. **Apply changes**: Write merged files
8. **Generate report**: Create `docs/sync-reports/sync-YYYY-MM-DD.md`
9. **Update tracking**: Update `.superpowers-sync` with new commit
10. **Suggest changelog**: Provide CHANGELOG entry

### 3. Review and Commit

```bash
# Review changes
git diff spex/skills/

# Read through merged skills
cat spex/skills/writing-plans/SKILL.md
cat spex/skills/review-code/SKILL.md
cat spex/skills/verification-before-completion/SKILL.md
cat spex/skills/brainstorm/SKILL.md

# Check sync report
cat docs/sync-reports/sync-2025-12-01.md

# If good, commit
git add .
git commit -m "Sync with superpowers@xyz7890

- Integrated upstream improvements to review-code
- Preserved all spex spec-compliance enhancements
- See docs/sync-reports/sync-2025-12-01.md for details"

# Update CHANGELOG
# Add entry to Unreleased section
```

## AI Merge Agent Instructions

Each skill gets its own merge agent with these instructions:

**Prompt template**:
```
You are merging upstream superpowers changes into a modified skill.

**Skill**: [name]
**Upstream file**: skills/[name]/SKILL.md
**Local file**: skills/[name]/SKILL.md

**Your task**:
1. Read local version
2. Read upstream version
3. Read modification metadata from .superpowers-sync
4. Read upstream changes patch (if not initial sync)
5. Analyze:
   - Upstream improvements (examples, patterns, fixes)
   - spex enhancements (from modification_summary)
   - Potential conflicts
6. Create merged version:
   - Preserve ALL spex sections
   - Integrate upstream improvements
   - Maintain consistency
   - Keep both superpowers discipline AND spec-awareness
7. Output:
   - Complete merged SKILL.md
   - Summary of changes
   - Conflicts and resolutions
   - Status: READY TO APPLY or NEEDS REVIEW

**Critical rules**:
- DO NOT remove spex sections
- DO NOT weaken spec-first principles
- DO integrate better examples/wording
- DO preserve quality gates from both
- DO maintain anti-rationalization patterns

**Modification metadata**:
[paste from .superpowers-sync]

Begin merge analysis.
```

## Tracking File Format

`.superpowers-sync` structure:

```json
{
  "upstream_repo": "https://github.com/obra/superpowers",
  "last_sync_commit": "abc123",
  "last_sync_date": "2025-11-12",
  "note": "...",
  "modified_skills": {
    "skill-name": {
      "upstream_file": "path/in/upstream",
      "local_file": "path/in/local",
      "modification_summary": "High-level description",
      "key_sections_modified": [
        "Section name: what changed"
      ],
      "spex_additions": [
        "New sections added for spex"
      ]
    }
  },
  "new_spex_skills": ["list", "of", "spex-only", "skills"],
  "referenced_skills": ["list", "of", "used-as-is", "skills"]
}
```

## Why This Approach?

### Advantages

1. **AI understands context**: Can intelligently merge by understanding both versions
2. **Preserves enhancements**: Clear documentation of what to preserve
3. **Semi-automated**: Reduces manual work while maintaining control
4. **Git-tracked**: `.superpowers-sync` committed = baseline across systems
5. **Local command**: `/update-superpowers` only available in plugin directory
6. **Auditable**: Sync reports document what changed
7. **Recoverable**: Can revert if merge goes wrong

### Trade-offs

- Requires review of AI output (good! we want this)
- Need clear modification documentation (we have it)
- Still some manual work for complex conflicts (acceptable)

### Compared to Alternatives

| Approach | Automation | Control | Merge Quality |
|----------|-----------|---------|---------------|
| Manual copy | Low | High | Error-prone |
| Git subtree | Low | High | Manual merge |
| **AI-assisted** | **Medium** | **High** | **Good** |
| Full automation | High | Low | Risky |

## Sync Schedule

**Recommended**:
- **Quarterly check**: Run `make check-upstream`
- **Sync on major changes**: If upstream has significant improvements
- **Before major releases**: Ensure we have latest upstream improvements

**Not recommended**:
- ❌ Sync on every upstream commit (too frequent)
- ❌ Never sync (miss important improvements)
- ❌ Automatic sync (lose control)

## Testing After Sync

After syncing, verify:

1. **spex sections present**:
   ```bash
   # Check for spec-first language
   grep -n "spec" spex/skills/writing-plans/SKILL.md
   grep -n "compliance" spex/skills/review-code/SKILL.md
   grep -n "drift" spex/skills/verification-before-completion/SKILL.md
   ```

2. **No merge artifacts**:
   ```bash
   grep -r "<<<<<<" spex/skills/
   grep -r ">>>>>>" spex/skills/
   grep -r "======" spex/skills/
   ```

3. **Consistency**:
   - Read through each skill
   - Check tone is consistent
   - Verify examples make sense
   - Confirm quality gates intact

4. **Functionality** (manual):
   - Try using `/spex:implement` with a test spec
   - Verify it still generates plans from specs
   - Check review-code still does spec compliance
   - Confirm verification checks spec drift

## Example Sync Session

```
$ /update-superpowers

✅ Plugin directory confirmed

Loading sync state from .superpowers-sync...
  Last sync: abc123 (2025-11-12)
  Modified skills: 4

Cloning upstream superpowers...
  Upstream HEAD: xyz789 (2025-12-01)

Checking for changes...
  writing-plans: No changes
  review-code: 2 commits found
  verification-before-completion: No changes
  brainstorm: No changes

Launching merge agents...
  [Agent 1/4] review-code
    Reading local version...
    Reading upstream version...
    Reading modification metadata...
    Analyzing changes...
    Creating merged version...
    Status: READY TO APPLY ✅

Applying merged skills...
  ✅ skills/review-code/SKILL.md updated

Generating sync report...
  ✅ docs/sync-reports/sync-2025-12-01.md created

Updating .superpowers-sync...
  ✅ Tracking file updated

---

✅ Superpowers Sync Complete

Synced from: obra/superpowers@xyz789 (2025-12-01)
Skills updated: 1

Summary:
- review-code: ✅ 2 changes integrated
  - Improved anti-rationalization examples
  - Added quality gate pattern

Reports:
- docs/sync-reports/sync-2025-12-01.md

Next steps:
1. Review: git diff skills/
2. Test skills work correctly
3. Commit: git commit -m "Sync with superpowers@xyz789"
4. Update CHANGELOG

```

## Troubleshooting

### "This command only works in cc-spex"

**Cause**: You're not in the plugin directory

**Fix**:
```bash
cd /path/to/cc-spex
/update-superpowers
```

### "Agent marked NEEDS REVIEW"

**Cause**: Merge agent found complex conflicts

**Fix**:
1. Read `skills/[skill]/SKILL.md.proposed`
2. Compare with current version
3. Manually resolve conflicts
4. Apply or reject proposed version
5. Document resolution in sync report

### "spex sections seem to be missing"

**Cause**: Merge agent removed important sections

**Fix**:
1. **Do not commit**
2. Review `.superpowers-sync` modification_summary
3. Re-read local version for spex sections
4. Manually restore missing sections
5. Update merge agent prompt if pattern identified

### "Upstream file moved/renamed"

**Cause**: Superpowers reorganized skills

**Fix**:
1. Update `.superpowers-sync` with new upstream_file path
2. Update `/update-superpowers` command if mapping changed
3. Document in sync report
4. May need manual merge for this sync

## Future Improvements

Potential enhancements:

1. **Pre-sync validation**: Check skill structure before merge
2. **Post-sync tests**: Automated testing of merged skills
3. **Diff viewer**: Better visualization of changes
4. **Conflict resolution patterns**: Learn from past merges
5. **Selective sync**: Sync only specific skills

## Maintenance Notes

**For plugin maintainers**:

- `.superpowers-sync` is the source of truth
- Always review AI merge output
- Document conflicts in sync reports
- Update CHANGELOG after each sync
- Test skills after merging
- When in doubt, manual review > automation

**Never**:
- Auto-commit without review
- Remove spex enhancements
- Skip testing after merge
- Ignore NEEDS REVIEW status

## References

- Upstream: https://github.com/obra/superpowers
- Plugin repo: https://github.com/rhuss/cc-spex
- Sync command: `spex/.claude/commands/update-superpowers.md`
- Check script: `spex/scripts/check-upstream-changes.sh`
- Tracking file: `spex/.superpowers-sync`
