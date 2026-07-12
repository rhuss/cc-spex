# Tasks: Unified Harness Marker Syntax

**Input**: Design documents from `/specs/039-robust-harness-markers/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Update the adaptation script and Claude mapping table before any command files are converted. All user story work depends on these.

**CRITICAL**: No command file conversion can begin until this phase is complete.

- [x] T001 [US1] Rewrite `spex/scripts/spex-adapt-commands.sh` to replace the two-phase processing (awk inline substitutions from TSV + awk section marker replacement) with unified `{harness:key}` handling: Phase 1 finds `{harness:key}...{/harness:key}` block markers and replaces entire blocks with `tokens[key]` value, Phase 2 finds remaining `{harness:key}` inline tokens and replaces with `tokens[key]` value, unmapped keys get `fallback_note` template applied. Load tokens from `command-map.json` `.tokens` object instead of `.inline` array + `.sections` object. Remove TSV extraction and old section marker awk logic. Maintain atomic writes (temp directory), `--dry-run` support, and idempotency. Handle edge cases per spec: warn to stderr and skip if `{/harness:key}` appears without a matching opener (exit 0); error with clear message identifying file and marker, exit 1 if `{harness:key}` opens without a matching `{/harness:key}` closer; replace tokens inside fenced code blocks normally (they are instructional, not literal code).
- [x] T002 [US1] Add `--debug` flag to `spex/scripts/spex-adapt-commands.sh`: parse flag alongside existing `--dry-run`, output per-marker trace lines to stderr (file name, marker key, replaced/fallback), ensure debug output does not mix with `--dry-run` stdout.
- [x] T003 [US1] Add post-adaptation validation to `spex/scripts/spex-adapt-commands.sh`: after all files are processed, scan each adapted file for leftover `{harness:` markers, warn on stderr listing file and unmapped key for each leftover, exit code remains 0 (warnings only, not errors). The validator scans final adapted output only; do not flag `{harness:` substrings that appear inside token replacement values (e.g., documentation about the marker syntax itself).
- [x] T004 [US3] Create Claude mapping table v2.0.0 at `spex/scripts/adapters/claude/command-map.json`: merge all 15 former `inline` entries and 5 former `sections` entries into a single `tokens` object using keys from the Token Registry in data-model.md. Remove `inline` and `sections` keys. Set version to `"2.0.0"`. Preserve all replacement content from the v1.0.0 table.

**Checkpoint**: Adaptation engine ready with unified marker support. Command file conversion can begin.

---

## Phase 2: User Story 2 - Convert command files to unified marker syntax (Priority: P1)

**Goal**: Convert all 7 command files from HTML-comment markers and inline prose phrases to `{harness:key}` tokens and `{harness:key}...{/harness:key}` blocks.

**Independent Test**: Run `grep -c '<!-- harness:' spex/extensions/*/commands/*.md` and verify 0 matches. Run `grep -c '{harness:' spex/extensions/*/commands/*.md` and verify at least 15 inline tokens and 5 block marker pairs across 7 files.

- [x] T005 [P] [US2] Convert `spex/extensions/spex/commands/speckit.spex.ship.md`: replace 5 inline prose phrases with `{harness:key}` tokens using keys: `interactive-choice`, `interactive-choice-skip`, `interactive-choice-must`, `spawn-worker`, `spawn-fresh-worker`. Note: `spawn-fresh-worker` neutral phrase is split across lines 646-647 ("spawn a\n   fresh-context worker agent"); rejoin and replace with the token. Match each phrase from the Claude mapping table's former inline entries. Verify no old prose phrases remain.
- [x] T006 [P] [US2] Convert `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: replace 1 HTML-comment block marker (`parallel-dispatch`) with `{harness:parallel-dispatch}...{/harness:parallel-dispatch}` block syntax, replace 4 inline prose phrases with tokens using keys: `dispatch-review-agents`, `subagent-mechanism`, `use-subagent`, `general-worker`. Note: `use-subagent` neutral phrase on line 186 starts with lowercase "use" (case mismatch with mapping table); match the actual file text. Note: the mapping table entry `no-interactive-prompts` ("do NOT present interactive prompts") does not appear in this file; locate where the concept applies and insert a `{harness:no-interactive-prompts}` token, or drop the dead entry from the mapping table and update T004 accordingly. Verify no old markers or phrases remain.
- [x] T007 [P] [US2] Convert `spex/extensions/spex-gates/commands/speckit.spex-gates.stamp.md`: replace 1 inline prose phrase with `{harness:suppress-prompts-stamp}` token. Verify no old phrase remains.
- [x] T008 [P] [US2] Convert `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`: replace 2 inline prose phrases with tokens using keys: `suppress-prompts-verify`, `interactive-choice`. Verify no old phrases remain.
- [x] T009 [P] [US2] Convert `spex/extensions/spex-teams/commands/speckit.spex-teams.implement.md`: replace 1 inline prose phrase with `{harness:teams-enabled}` token. Verify no old phrase remains.
- [x] T010 [P] [US2] Convert `spex/extensions/spex-teams/commands/speckit.spex-teams.orchestrate.md`: replace 2 HTML-comment block markers (`agent-teams`, `agent-teams-dispatch`) with `{harness:...}...{/harness:...}` block syntax, replace 2 inline prose phrases with tokens using keys: `teams-enabled`, `teams-spawn`. Verify no old markers or phrases remain.
- [x] T011 [P] [US2] Convert `spex/extensions/spex-teams/commands/speckit.spex-teams.research.md`: replace 2 HTML-comment block markers (`agent-teams`, `agent-teams-research-dispatch`) with `{harness:...}...{/harness:...}` block syntax, replace 2 inline prose phrases with tokens using keys: `teams-enabled`, `teams-research-spawn`. Verify no old markers or phrases remain.
- [x] T012 [P] [US2] Convert `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md`: replace 1 HTML-comment block marker (`worktree-isolation`) with `{harness:worktree-isolation}...{/harness:worktree-isolation}` block syntax. This file has no inline prose targets, only the block marker. Verify no old `<!-- harness:` markers remain.

**Checkpoint**: All 8 command files use unified marker syntax. Zero HTML-comment markers remain. Zero inline prose targets remain.

---

## Phase 3: User Story 3 - Update remaining mapping tables (Priority: P1)

**Goal**: Migrate Codex and OpenCode mapping tables to v2.0.0 tokens format.

**Depends on**: Phase 1 (script handles new format)

- [x] T013 [P] [US3] Update Codex mapping table at `spex/scripts/adapters/codex/command-map.json`: merge `inline` entries and `sections` entries into `tokens` object, remove `inline` and `sections` keys, set version to `"2.0.0"`.
- [x] T014 [P] [US3] Update OpenCode mapping table at `spex/scripts/adapters/opencode/command-map.json`: merge `inline` entries and `sections` entries into `tokens` object (may be empty), remove `inline` and `sections` keys, set version to `"2.0.0"`.

**Checkpoint**: All 3 mapping tables use v2.0.0 tokens format. Zero `"inline"` or `"sections"` keys remain.

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Verification, documentation, and validation

- [x] T015 [P] Verify adaptation round-trip: run `./spex/scripts/spex-adapt-commands.sh --dry-run claude .specify/extensions spex/scripts/adapters` and confirm all `{harness:key}` tokens are replaced with Claude-specific content. Run `--dry-run codex` and confirm Codex replacements. Run twice and verify byte-identical output (idempotency).
- [x] T016 [P] Verify `--debug` output: run with `--debug` flag and confirm stderr contains per-marker trace lines. Run with both `--debug` and `--dry-run` and confirm stdout has diff, stderr has traces, no mixing.
- [x] T017 [P] Update `README.md` to document the unified `{harness:key}` marker syntax, replacing references to HTML-comment capability markers and inline substitutions.
- [x] T018 [P] Update `spex/docs/help.md` to document the unified marker syntax, updated mapping table format (v2.0.0 tokens), and `--debug` flag.
- [x] T019 Run `make release` validation to verify all extensions, commands, hooks, and skills are properly registered after the migration.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Foundational)**: No dependencies, start immediately. T001-T003 are sequential (script changes build on each other). T004 can run in parallel with T001-T003.
- **Phase 2 (US2)**: Depends on Phase 1 (script must handle new format before files are converted). All 8 file conversions (T005-T012) can run in parallel.
- **Phase 3 (US3)**: Depends on Phase 1 T004 only (Claude table defines the format, Codex/OpenCode follow). T013 and T014 can run in parallel.
- **Phase 4 (Polish)**: Depends on all previous phases. T015-T018 can run in parallel. T019 must be last.

### Parallel Opportunities

- T005-T012 can ALL run in parallel (8 independent file conversions)
- T013 and T014 can run in parallel (different mapping tables)
- T015-T018 can run in parallel (independent verification/docs tasks)

---

## Implementation Strategy

### MVP First (US1 + US2 + US3)

1. Phase 1: Script + Claude mapping table (foundational)
2. Phase 2: Convert all 7 command files (parallel)
3. Phase 3: Update Codex + OpenCode tables (parallel)
4. **VALIDATE**: `--dry-run claude`, `--dry-run codex`, grep for leftovers

### Incremental Delivery

1. Script updated -> Can test with any converted file
2. Files converted -> Full adaptation pipeline works
3. All tables updated -> All harnesses supported
4. Polish -> Docs + `make release`
