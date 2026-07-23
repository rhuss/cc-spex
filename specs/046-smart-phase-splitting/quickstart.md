# Quickstart Validation: Smart Phase Splitting

## Prerequisites

- `specify` CLI installed and project initialized (`/spex:init`)
- `spex-collab` extension enabled
- A feature with spec.md, plan.md, and tasks.md in the feature directory

## Scenario 1: Small Feature Skips Phase Prompt

**Setup**: Create a feature with < 20 estimated files.

1. Ensure plan.md references ~15 file paths
2. Ensure tasks.md has 12 tasks across 3 `## Phase` headings
3. Run `/speckit-implement`

**Expected**: No phase split prompt appears. Implementation runs all tasks uninterrupted. Phase-manager fires once at the end.

**Verify**:
```bash
# After implementation, check .spex-state
jq '.collab.phase_plan | length' .specify/.spex-state
# Expected: 1 (single phase)
```

## Scenario 2: Single Phase No Interruption

**Setup**: Same as Scenario 1, or manually select "Single phase (no split)" when prompted.

1. Run `/speckit-implement`
2. Observe that implementation does not pause between task groups

**Expected**: Implementation runs continuously. No "Phase N is ready" prompts appear mid-implementation. Phase-manager fires once at the end with review gate and PR offer.

## Scenario 3: Large Feature Gets Merged Phases

**Setup**: Create a feature with > 20 estimated files and many small phases.

1. Ensure plan.md references ~45 file paths
2. Ensure tasks.md has 30 tasks across 7 `## Phase` headings (2-5 tasks each)
3. Run `/speckit-implement`

**Expected**: Phase split prompt appears with merged phases (fewer than 7). Each merged phase touches at least ~10 files. User can confirm, adjust, or select single phase.

## Scenario 4: Configurable Threshold

**Setup**: Set custom threshold in collab-config.yml.

1. Edit `.specify/extensions/spex-collab/collab-config.yml`:
   ```yaml
   phases:
     file_threshold: 10
   ```
2. Create a feature with ~15 estimated files
3. Run `/speckit-implement`

**Expected**: Phase split prompt appears (since 15 > 10). With default threshold of 20, this feature would have been single-phase.

## Scenario 5: Ship Pipeline Bypass

**Setup**: Run the full ship pipeline.

1. Run `/speckit-spex-ship brainstorm/NN-feature.md`

**Expected**: Phase split is skipped entirely (ship mode guard). No phase prompt during the pipeline.

## Validation Commands

```bash
# Verify schema validation still passes
make release

# Check that command files have valid frontmatter
head -5 spex/extensions/spex-collab/commands/speckit.spex-collab.phase-split.md
head -5 spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md

# Verify config template has new phases section
grep -A2 'phases:' spex/extensions/spex-collab/config-template.yml
```
