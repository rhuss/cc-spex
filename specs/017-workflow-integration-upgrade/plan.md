# Implementation Plan: Leverage Spec-Kit 0.7.x Workflows and Integrations

**Branch**: `016-traits-to-extensions` | **Date**: 2026-04-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/017-workflow-integration-upgrade/spec.md`

## Summary

Replace the 788-line procedural ship command with a declarative spec-kit workflow YAML, simplify the 474-line init script by delegating agent management to `specify integration install/upgrade`, add configurable companion plugin detection, and add hook/workflow coordination via marker files with PID liveness checking. All extension manifests bump to `>=0.7.4` and all legacy migration code is removed.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Python 3 (hooks), Markdown (commands)
**Primary Dependencies**: `specify` CLI (>=0.7.4), `jq` (JSON parsing)
**Storage**: File-based (YAML workflows, JSON state files, Markdown commands)
**Testing**: `make release` (integration test: install plugin, validate extensions/commands/hooks)
**Target Platform**: macOS/Linux with Claude Code (or compatible AI agent)
**Project Type**: Claude Code plugin (AI agent extension system)
**Constraints**: No compiled artifacts, Bash + Markdown + Python only
**Scale/Scope**: ~15 files modified/created, ~600 lines removed, ~300 lines added

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | Pass | Following SDD workflow |
| II. Extension Architecture | Pass | Building on existing extension bundles |
| III. Extension Composability | Pass | Hook coordination preserves independence |
| IV. Quality Gates | Pass | Hooks for ad-hoc, workflow gates for pipeline |
| V. Naming Discipline | Pass (with amendment) | FR-017 adds workflow naming to constitution |
| VI. Skill Autonomy | Pass | Ship becomes workflow, not monolithic skill |

No violations requiring complexity tracking.

## Project Structure

### Documentation (this feature)

```text
specs/017-workflow-integration-upgrade/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (file-based entities)
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
spex/
├── extensions/
│   ├── spex/
│   │   ├── extension.yml                          # Update requires version
│   │   ├── commands/
│   │   │   ├── speckit.spex.ship.md               # Rewrite as thin workflow wrapper
│   │   │   └── speckit.spex.init.md               # Update for simplified init
│   │   └── workflows/
│   │       └── spex-ship.yml                      # NEW: declarative ship workflow
│   ├── spex-gates/
│   │   ├── extension.yml                          # Update requires version
│   │   └── commands/
│   │       ├── speckit.spex-gates.review-spec.md  # Add marker check
│   │       ├── speckit.spex-gates.review-plan.md  # Add marker check
│   │       ├── speckit.spex-gates.review-code.md  # Add marker check
│   │       ├── speckit.spex-gates.verify.md       # Add marker check
│   │       └── speckit.spex-gates.stamp.md        # Add marker check
│   ├── spex-teams/
│   │   └── extension.yml                          # Update requires version
│   ├── spex-worktrees/
│   │   └── extension.yml                          # Update requires version
│   └── spex-deep-review/
│       └── extension.yml                          # Update requires version
├── plugin-integrations.yml                        # NEW: companion plugin mapping
├── scripts/
│   ├── spex-init.sh                               # Rewrite (thin wrapper)
│   ├── spex-ship-state.sh                         # REMOVE (replaced by workflow engine)
│   └── spex-ship-statusline.sh                    # Update for workflow status
└── .specify/memory/constitution.md                # Amendment: workflow naming
```

**Structure Decision**: Existing plugin structure preserved. New files added within existing directories. Ship state script removed (workflow engine replaces it). Workflow YAML lives inside the spex extension bundle since it's installed alongside the extension.

## Implementation Phases

### Phase 1: Version Bump and Legacy Cleanup (US-5, FR-007, FR-008, FR-014)

The simplest, most mechanical change. Gets the codebase to a clean starting point.

**Files modified:**
- `spex/extensions/spex/extension.yml` - bump `speckit_version` to `>=0.7.4`
- `spex/extensions/spex-gates/extension.yml` - bump version
- `spex/extensions/spex-teams/extension.yml` - bump version
- `spex/extensions/spex-worktrees/extension.yml` - bump version
- `spex/extensions/spex-deep-review/extension.yml` - bump version
- `spex/scripts/spex-init.sh` - remove all `migrate_*` functions, `fix_constitution`, `do_beads_migration`, bump version check to `>=0.7.4`

**Files removed:**
- `spex/scripts/spex-ship-state.sh` (251 lines, replaced by workflow engine)

**Verification**: `rg "migrate_|fix_constitution|do_beads" spex/scripts/spex-init.sh` returns nothing. All `extension.yml` files show `>=0.7.4`.

### Phase 2: Init Simplification (US-2, FR-005, FR-006, FR-007)

Rewrite `spex-init.sh` to a thin wrapper. The current 474-line script becomes ~100 lines.

**What stays:**
- Version check (updated to `>=0.7.4`)
- `check_ready()` fast path
- `install_extensions()` (installs bundled extensions via `specify extension add <path> --dev`)
- `configure_statusline()` (status line setup)
- `configure_gitignore()` (.gitignore patterns)
- `--refresh`, `--update`, `--clear` flags

**What changes:**
- `do_init()`: Replace `specify init --here --ai claude --force` with `specify init --here --force` followed by `specify integration install claude` (or `upgrade` if already installed)
- Remove: `migrate_traits_config`, `migrate_phase_marker`, `migrate_old_commands`, `migrate_from_beads`, `do_beads_migration`, `fix_constitution`, `detect_old_traits`
- Add: stale workflow marker cleanup (check `.specify/.spex-workflow-active`, verify PID, remove if stale)

**What gets removed (functions):**
- `migrate_traits_config()` (~10 lines)
- `migrate_phase_marker()` (~4 lines)
- `migrate_old_commands()` (~15 lines)
- `migrate_from_beads()` (~15 lines)
- `do_beads_migration()` (~40 lines)
- `fix_constitution()` (~30 lines)
- `detect_old_traits()` (~8 lines)

**Verification**: `wc -l spex/scripts/spex-init.sh` shows under 120 lines. `rg "migrate_" spex/scripts/spex-init.sh` returns nothing.

### Phase 3: Plugin Ecosystem Detection (US-3, FR-009, FR-010, FR-011)

Add configurable companion plugin detection.

**New files:**
- `spex/plugin-integrations.yml` - mapping file defining plugins, detection paths, skills, and injection targets
- Init writes `.specify/spex-plugins.json` during setup

**Plugin mapping structure:**
```yaml
plugins:
  prose:
    detect: "~/.claude/plugins/cc-prose"
    marker: "plugin.json"  # or .claude-plugin/plugin.json
    skills:
      - prose:check
      - prose:rewrite
    inject_into:
      review-spec: "Run prose:check on spec content before accepting"
      review-code: "Run prose:check on documentation changes"
  copyedit:
    detect: "~/.claude/plugins/cc-copyedit"
    marker: "plugin.json"
    skills:
      - copyedit:consistency
      - copyedit:flow
    inject_into:
      review-spec: "Run copyedit:consistency on spec terminology"
```

**Init integration:** Add a `detect_plugins()` function to `spex-init.sh` that:
1. Reads `spex/plugin-integrations.yml` (from plugin root, resolved via `$PLUGIN_ROOT`)
2. For each plugin entry, checks if `detect` path exists and contains `marker` file
3. Writes results to `.specify/spex-plugins.json`

**Command integration:** The following review commands read `.specify/spex-plugins.json` at startup and append injection instructions to their review criteria when plugins are available:

**Modified files for plugin integration (FR-011):**
- `spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md` - add plugin check section
- `spex/extensions/spex-gates/commands/speckit.spex-gates.review-plan.md` - add plugin check section
- `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md` - add plugin check section

Each command adds a "Plugin Integration" section that:
1. Checks if `.specify/spex-plugins.json` exists
2. For each available plugin, looks up injection targets matching the current command name
3. Appends the injection instruction text to the review criteria

**Verification**: Install prose plugin, run init, check `.specify/spex-plugins.json` shows prose as available. Run review-spec, verify it includes "Run prose:check on spec content before accepting." Remove prose plugin, run init again, check it shows unavailable. Run review-spec, verify prose instruction is absent.

### Phase 4: Ship Workflow YAML (US-1, FR-001, FR-002, FR-003, FR-004, FR-015, FR-016)

Replace the procedural ship command with a declarative workflow.

**New files:**
- `spex/extensions/spex/workflows/spex-ship.yml` - declarative workflow definition

**Workflow structure:**
```yaml
schema_version: "1.0"
workflow:
  id: "spex-ship"
  name: "Spex Autonomous Ship Pipeline"
  version: "1.0.0"
  author: "cc-spex"
  description: "Full SDD cycle with quality gates and configurable oversight"

requires:
  speckit_version: ">=0.7.4"
  integrations:
    any: ["claude", "copilot", "gemini", "codex"]

inputs:
  spec:
    type: string
    required: true
    prompt: "Brainstorm file or feature description"
  ask:
    type: string
    default: "smart"
    enum: ["always", "smart", "never"]

hooks:
  pre_run:
    - run: "echo '{\"pid\": '$$', \"started_at\": \"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"}' > .specify/.spex-workflow-active"
  post_run:
    - run: "rm -f .specify/.spex-workflow-active"

steps:
  - id: specify
    command: speckit.specify
    input:
      args: "{{ inputs.spec }}"

  - id: review-spec
    command: speckit.spex-gates.review-spec
    input:
      ask: "{{ inputs.ask }}"
    # Review command reads `ask` to control behavior:
    # never = auto-fix all, smart = auto-fix unambiguous, always = pause

  - id: plan
    command: speckit.plan

  - id: review-plan
    command: speckit.spex-gates.review-plan
    input:
      ask: "{{ inputs.ask }}"

  - id: tasks
    command: speckit.tasks

  - id: implement
    command: speckit.implement
    # Command auto-detects teams: checks if spex-teams is enabled and
    # tasks.md has 2+ independent tasks, routes to teams if so.
    # Command also spawns a subagent for isolation when inside a workflow.

  - id: review-code
    command: speckit.spex-gates.review-code
    input:
      ask: "{{ inputs.ask }}"
    # Command spawns a subagent for isolation when inside a workflow,
    # ensuring the reviewer has no implementation context.

  - id: verify
    command: speckit.spex-gates.verify
```

**Modified files:**
- `spex/extensions/spex/commands/speckit.spex.ship.md` - rewrite as thin wrapper (~50 lines) that:
  1. Parses arguments (`--ask`, `--create-pr`, brainstorm file)
  2. Invokes `specify workflow run spex-ship -i spec=... -i ask=...`
  3. After workflow completes, handles PR creation if `--create-pr` was set (using `gh pr create`)
  4. Reports completion summary
- `spex/extensions/spex/extension.yml` - add workflow reference

**Workflow installation:** The `install_extensions()` function in `spex-init.sh` already installs extensions via `specify extension add`. The workflow YAML lives inside the extension bundle, so it should be picked up automatically. If not, add `specify workflow add <path>` to init.

**Verification**: `specify workflow info spex-ship` shows all steps. `specify workflow run spex-ship -i spec="test"` starts the pipeline.

### Phase 5: Hook/Workflow Coordination (US-4, FR-012, FR-013)

Add marker-based coordination between hooks and workflow.

**Modified files (5 review commands):**
- `spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md`
- `spex/extensions/spex-gates/commands/speckit.spex-gates.review-plan.md`
- `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md`
- `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`
- `spex/extensions/spex-gates/commands/speckit.spex-gates.stamp.md`

**Change pattern (same for all 5):** Add a "Workflow Coordination" section at the top of each command (after frontmatter, before the existing content):

```markdown
## Workflow Coordination

Check if this command is being invoked by a hook while a workflow is already handling reviews:

\```bash
if [ -f ".specify/.spex-workflow-active" ]; then
  MARKER_PID=$(jq -r '.pid // empty' .specify/.spex-workflow-active 2>/dev/null)
  if [ -n "$MARKER_PID" ] && kill -0 "$MARKER_PID" 2>/dev/null; then
    echo "SKIP: Review handled by active workflow (PID $MARKER_PID)"
    exit 0
  else
    echo "Stale workflow marker detected (PID $MARKER_PID not running). Removing."
    rm -f .specify/.spex-workflow-active
  fi
fi
\```

If the marker exists and the PID is alive, this command was invoked by a hook while the workflow is already managing reviews. Exit early. If the PID is dead, remove the stale marker and proceed normally.
```

**Also update:** The existing "Ship Pipeline Guard" sections in these commands can be removed or simplified since the workflow marker replaces the `.spex-state` check for hook suppression. The `.spex-state` guard logic was for the old procedural ship; the new workflow handles state internally.

**Subagent isolation (FR-016):** Two commands need workflow-aware subagent forking to prevent context accumulation:

1. **`speckit.implement` (in speckit-implement SKILL.md or via the spex-teams extension)**:
   When `.specify/.spex-workflow-active` exists, the implement command MUST spawn a subagent via the Agent tool to do the actual implementation work. The subagent receives only file paths (spec.md, plan.md, tasks.md), not conversation history. The orchestrator captures the subagent's summary (completed tasks, any failures) without absorbing implementation context.

   The implement command also handles teams auto-detection at this point:
   ```bash
   TEAMS_ENABLED=$(specify extension list 2>/dev/null | grep -c 'spex-teams.*enabled' || echo 0)
   INDEPENDENT_TASKS=$(grep -c '^\- \[ \]' specs/*/tasks.md 2>/dev/null || echo 0)
   if [ "$TEAMS_ENABLED" -gt 0 ] && [ "$INDEPENDENT_TASKS" -ge 2 ]; then
     # Route to speckit.spex-teams.implement
   fi
   ```

2. **`speckit.spex-gates.review-code`**:
   When `.specify/.spex-workflow-active` exists, the review-code command MUST spawn a subagent for the review. The subagent starts fresh (no implementation context), reads spec/plan/tasks from disk, runs the review, and returns findings. This ensures unbiased code review.

Both commands already work normally when invoked ad-hoc (no marker = no subagent forking).

**Modified files for subagent isolation:**
- `.claude/skills/speckit-implement/SKILL.md` (or the speckit-implement skill) - add workflow isolation section
- `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md` - add workflow isolation section

**Verification**: Run `/speckit.specify` ad-hoc, verify review-spec hook fires. Start ship workflow, verify review-spec hook is suppressed during the workflow's specify step. Verify implement and review-code stages run in subagents during workflow (check that orchestrator context doesn't contain implementation details).

### Phase 6: Constitution Amendment (FR-017)

Update the constitution to document workflow naming conventions.

**Modified file:** `.specify/memory/constitution.md`

**Change:** Add to section V (Naming Discipline):
```markdown
- Workflow IDs use the `spex-*` prefix (e.g., `spex-ship`).
  Invocation: `specify workflow run spex-ship`.
```

**Also:** Bump constitution version to 2.1.0.

**Verification**: `rg "spex-ship" .specify/memory/constitution.md` returns the new entry.

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Workflow engine doesn't support extension commands as steps at runtime | High | Low (verified at install time) | Test with `specify workflow run` before committing to workflow approach |
| `specify integration install` doesn't detect Claude Code correctly | Medium | Low | Fall back to `specify init --ai claude` if integration command fails |
| Plugin detection adds startup latency to init | Low | Medium | Detection is file-existence checks only, should be sub-second |
| Stale marker causes hooks to silently skip | Medium | Low | PID liveness check catches crashes; init cleanup catches stale markers |

## Dependencies

- Spec-kit 0.7.4+ (workflow engine, integration management)
- Existing 016 extension bundles (spex, spex-gates, spex-teams, spex-worktrees, spex-deep-review)
- `jq` for JSON parsing in bash scripts
