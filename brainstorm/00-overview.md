# Brainstorm Overview

Last updated: 2026-07-15

## Sessions

| # | Date | Topic | Status | Spec | Issue |
|---|------|-------|--------|------|-------|
| 01 | 2026-02-27 | teams-integration | spec-created | 005 | - |
| 02 | 2026-03-03 | spec-evolution | decided | - | - |
| 03 | 2026-03-08 | teams-trait-consolidation | idea | - | - |
| 04 | - | rename-to-cc-spex | - | - | - |
| 05 | - | yolo-autonomous-workflow | - | - | - |
| 06 | 2026-03-30 | superpowers-assessment | completed | - | - |
| 07 | 2026-04-05 | upgrade-speckit-commands | draft | - | - |
| 08 | - | flow-status-line | - | - | - |
| 08 | 2026-04-18 | workflows-and-integrations | resolved | - | - |
| 09 | - | traits-to-extensions | - | - | - |
| 10 | 2026-05-05 | superpowers-wrapping-integration | active | - | - |
| 11 | 2026-05-19 | cc-deck-badge-auto-config | active | - | - |
| 12 | 2026-05-22 | hardening-review-process | active | - | - |
| 13 | 2026-05-30 | pr-review-triage | active | - | - |
| 14 | 2026-06-02 | collab-triage-lifecycle | active | - | - |
| 15 | 2026-06-08 | opencode-adaptation | idea | - | - |
| 17 | 2026-06-11 | backpressure-loops | spec-created | 024 | - |
| 18 | 2026-06-11 | guided-smoke-test | abandoned (superseded by #24) | 025 | - |
| 19 | 2026-06-11 | cross-feature-amendments | active | - | - |
| 20 | 2026-06-11 | mid-impl-review | active | - | - |
| 21 | 2026-06-19 | before-finish-hooks | active | - | - |
| 22 | 2026-06-22 | smoke-test-v2 | abandoned (superseded by #24) | - | - |
| 23 | 2026-06-23 | dual-repo-spec-workflow | active (revisited 2026-06-24) | - | - |
| 24 | 2026-06-28 | smoke-test-rethink | active | - | - |
| 25 | 2026-06-28 | submit-finish-workflow | active | - | - |
| 26 | 2026-06-29 | review-idea-inbox | active | - | - |
| 27 | 2026-06-30 | worktree-cwd-persistence | active (revisited 2026-07-08) | - | - |
| 28 | 2026-07-02 | harness-agnostic-spex | active (revisited 2026-07-08) | - | - |
| 29 | 2026-07-02 | replace-find-with-plugin-root | active | - | - |
| 30 | 2026-07-03 | closeout-gate | active | - | [#9](https://github.com/rhuss/cc-spex/issues/9) |
| 31 | 2026-07-04 | plugin-discovery-fix | parked | - | [#7](https://github.com/rhuss/cc-spex/issues/7) |
| 32 | 2026-07-04 | update-check | active | - | [#12](https://github.com/rhuss/cc-spex/issues/12) |
| 33 | 2026-07-06 | extension-local-scripts | spec-created | 036 | [#13](https://github.com/rhuss/cc-spex/pull/13) |
| 34 | 2026-07-07 | workflow-based-setup | active | - | - |
| 35 | 2026-07-12 | robust-harness-markers | spec-created | 039 | - |
| 36 | 2026-07-13 | codex-hook-contract | active | - | - |
| 37 | 2026-07-14 | spex-detach-hardening | active (revisited 2026-07-14) | - | - |
| 38 | 2026-07-14 | codex-deep-review | active | - | - |
| 39 | 2026-07-15 | extension-owned-scripts | active | - | - |

## Open Threads

- Constitution Principle III amendment for trait dependencies (from #01)
- "5 teammate maximum" configurability (from #01)
- CC Teams API stability: traits will need updating if API changes (from #01)
- Central "spec changelog" file vs in-spec amendments (from #02)
- Auto-run spec drift checks (`/sdd:evolve --check-drift`) in CI (from #02)
- Extension significance threshold for requiring amendments (from #02)
- Decision gate: hook (hard enforcement) or prompt injection (soft guidance)? (from #03)
- Should teams-research be folded into the consolidated teams trait? (from #03)
- Minimum task count threshold for mandatory teams usage (from #03)
- Agent Teams env var not set and user can't restart: fallback to sequential? (from #03)
- Sync mechanism future: absorb-and-freeze or maintain ongoing syncs (from #06)
- Release/3.x deprecation warning for upcoming v4.0.0 migration (from #07)
- init-options.json `speckit_version` field update responsibility (from #07)
- Historical brainstorm/spec file naming: update to new format or leave as artifacts? (from #07)
- Should `/spex:evolve` reset review artifacts when spec is revised? (from #08)
- Flow status line "stale review" warning when spec.md is newer than REVIEW-SPEC.md (from #08)
- Celebration timing: before or after ship's PR creation step? (from #08)
- Hook ordering: multiple `after_implement` hooks need guaranteed sequential execution (from #09)
- `spex:traits` command: keep as thin wrapper around `specify extension enable/disable` or drop? (from #09)
- Init defaults: install all extensions by default or let user choose? (from #09)
- Ship-mode awareness: do hook commands need to detect autonomous mode? (from #09)
- Superpowers availability detection mechanism (from #10)
- Inline essentials freshness strategy: frozen vs manually refreshed (from #10)
- Category 3 pass-through spec context injection (from #10)
- Badge version comment for future icon set updates (from #11)
- cc-deck CLI binary check (`which cc-deck`) alongside config file detection (from #11)
- `--no-cc-deck` flag on `spex-init.sh` to skip badge configuration (from #11)
- Fix loop test failure interaction with round counter (from #12)
- Spec-anchored validation for specs with implicit verification methods (from #12)
- review-hints.md structure: flat file vs per-language sections (from #12)
- Reply signature/tag format for open-detection logic (from #13)
- Re-request review from bots after pushing fixes (from #13)
- Handling bot comments that reference code changed by another fix in the same batch (from #13)
- Gate check: count bot comments only or all comments? (from #14)
- Auto-merge spec PR on split or require user confirmation? (from #14)
- Should triage-impl also have a gate check for recommending impl splits? (from #14)
- Deep review suggestion + triage-impl suggestion: sequential or combined message? (from #14)
- OpenCode variant: separate npm package or `--ai opencode` flag? (from #15)
- Enforcement degradation tolerance: is spex without hooks still spex? (from #15)
- Feature request to OpenCode for `prompt.before` plugin event? (from #15)
- OpenCode `question` tool: does it support multi-select with grouped options? (from #15)
- OpenCode custom tools via plugins as hook workaround? (from #15)
- Post-PR watch mechanism: `/loop`, cron, or manual `--watch` flag? (from #17)
- Per-task checkpoints: test suite only or also linting? (from #17)
- State file lifecycle for watch mode (survive past PR creation, eventual cleanup) (from #17)
- Watch mode merge conflict handling (rebase against target branch?) (from #17)
- Ship pipeline integration: auto-enter watch mode after finish? (from #17)
- How to store confirmed amendments between review-spec and finish? (from #19)
- Reliability of entity/API overlap detection via text scanning (from #19)
- Should amendment blocks be machine-parseable or free-form markdown? (from #19)
- Handling concurrent amendments to the same older spec from parallel branches (from #19)
- Checkpoint findings vs test checkpoint ordering (review before or after tests?) (from #20)
- Task count handling after checkpoint fixes (restart or continue?) (from #20)
- Checkpoint review scope: diff since last checkpoint or entire implementation so far? (from #20)
- Cross-run statistics aggregation for per-project trends (from #20)
- Statistics report format: file (appended to REVIEW-CODE.md) or console only? (from #20)
- Should finish skill also gain after_finish hook boilerplate (fixing existing dead config)? (from #21)
- Extract hook-reading boilerplate into shared include to avoid copy-pasting across extension commands? (from #21)
- What should `specify init` upstream mode option be called? (from #23)
- Should archive step at finish be automatic or interactive? (from #23)
- How to flow context from archived specs back into new features? (from #23)
- Should upstream mode auto-add spec dirs to `.git/info/exclude`? (from #23)
- How to handle worktree-to-worktree spec migration? (from #23)
- Should `## Smoke Test` section be generated by specify or always hand-written? (from #24)
- Maximum scenario count enforcement for smoke test section? (from #24)
- Playwright MCP availability: graceful degradation or require for browser scenarios? (from #24)
- Should submit run before_submit hooks? (from #25)
- Should finish support --no-smoke-test flag? (from #25)
- How should collab-triage integrate with submit --watch? (from #25)
- Should squash be extractable as a standalone command? (from #25)
- Inbox max size or age-based pruning suggestion? (from #26)
- Merge vs separate entries when multiple sources flag the same theme? (from #26)
- Auto-group inbox items by theme or show flat chronological? (from #26)
- Should consumed inbox items leave a trace in the overview? (from #26)
- Does Codex persist CWD after `cd` within a session? (from #27)
- Should setup workflow configure worktree base path during `adapt-harness`? (from #27)
- Is `.worktrees/` visible enough for users, or does the `list` action suffice? (from #27)
- Commands neutral-first then specialize for ALL harnesses, or Claude-first then de-specialize? (from #28)
- Delimiter marker approach noise in command files (from #28)
- Testing neutral commands on each harness for acceptable behavior (from #28)
- Is the `source: "./subdir"` field in a cloned repo's marketplace.json supposed to be followed by Claude Code's installer? (from #31)
- Does Claude Code have documentation on how nested plugin sources are resolved? (from #31)
- Would symlinks in option A survive GitHub clone on all platforms (macOS, Linux, Windows)? (from #31)
- Should the update check also run during `--refresh` and `--update` modes, or only on normal init? (from #32)
- Should the repo URL for the API call be hardcoded or derived from git remote? (from #32)
- Should spex-init.sh (hooks, adapters) also be refactored into the extension model? (from #33)
- Build-time sync: Makefile target only, or also git pre-commit hook? (from #33)
- Can workflow `prompt` step output be used in subsequent `if`/`switch` conditions? (from #34)
- Does `specify bundle install` handle extension dependency ordering? (from #34)
- Minimum spec-kit version required for workflow + bundle support? (from #34)
- Should the setup workflow be idempotent (safe to re-run)? (from #34)
- Multi-line token values: JSON `\n` strings vs external file references? (from #35)
- `--debug` output: stderr to avoid polluting stdout in dry-run mode? (from #35)
- Verify Codex stdin contract against actual v0.144.1 binary or trust the docs? (from #36)
- `transcript_path` in UserPromptSubmit: useful for richer context injection? (from #36)
- Exit code 2 vs JSON deny: which is more reliable across Codex versions? (from #36)
- Exact output format of `codex review`: need to test with a real diff to determine parsing strategy (from #38)
- Should Codex review run in parallel with internal agents or sequentially in Step 4? (from #38)
- Auth failure handling: log and skip, or surface to user? (from #38)
- Should `make sync-scripts-check` verify no stale copies of extension-owned scripts in `spex/scripts/`? (from #39)
- Should constitution's "Extension-local scripts" constraint distinguish shared vs extension-owned? (from #39)

## Parked Ideas

- Plugin discovery fix (#31): Plugin marketplace install resolves plugin source incorrectly for nested plugin structures.
  Reason: Needs upstream Claude Code documentation or bug confirmation before proceeding.
