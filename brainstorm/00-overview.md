# Brainstorm Overview

Last updated: 2026-06-19

## Sessions

| # | Date | Topic | Status | Spec | Issue |
|---|------|-------|--------|------|-------|
| 01 | 2026-02-27 | teams-integration | spec-created | 005 | - |
| 02 | - | spec-evolution | - | - | - |
| 03 | 2026-03-08 | teams-trait-consolidation | idea | - | - |
| 04 | - | rename-to-cc-spex | - | - | - |
| 05 | - | yolo-autonomous-workflow | - | - | - |
| 06 | 2026-03-30 | superpowers-assessment | completed | - | - |
| 07 | 2026-04-05 | upgrade-speckit-commands | Draft | - | - |
| 08 | - | flow-status-line | - | - | - |
| 08 | - | workflows-and-integrations | - | - | - |
| 09 | - | traits-to-extensions | - | - | - |
| 10 | 2026-05-05 | superpowers-wrapping-integration | active | - | - |
| 11 | - | cc-deck-badge-auto-config | idea | - | - |
| 12 | 2026-05-22 | hardening-review-process | active | - | - |
| 13 | 2026-05-30 | pr-review-triage | active | - | - |
| 14 | 2026-06-02 | collab-triage-lifecycle | active | - | - |
| 15 | 2026-06-08 | opencode-adaptation | idea | - | - |
| 17 | 2026-06-11 | backpressure-loops | spec-created | 024 | - |
| 18 | 2026-06-11 | guided-smoke-test | spec-created | 025 | - |
| 19 | 2026-06-11 | cross-feature-amendments | active | - | - |
| 20 | 2026-06-11 | mid-impl-review | active | - | - |
| 21 | 2026-06-19 | before-finish-hooks | active | - | - |

## Open Threads
- Superpowers availability detection mechanism (from #10)
- Inline essentials freshness strategy: frozen vs manually refreshed (from #10)
- Category 3 pass-through spec context injection (from #10)
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
- Post-PR watch mechanism: `/loop`, cron, or manual `--watch` flag? (from #17)
- Per-task checkpoints: test suite only or also linting? (from #17)
- State file lifecycle for watch mode (survive past PR creation, eventual cleanup) (from #17)
- Watch mode merge conflict handling (rebase against target branch?) (from #17)
- Ship pipeline integration: auto-enter watch mode after finish? (from #17)
- Smoke test for projects that can't be started locally (cloud, DB, external services)? (from #18)
- Smoke test results: persistent file (like REVIEW-CODE.md) or state file only? (from #18)
- Ship pipeline stop behavior: explicit next-step instructions or silent stop? (from #18)
- Smoke test interaction with existing `/run` skill: delegate or independent? (from #18)
- Marking acceptance scenarios as "manual only" vs "automatable" in spec? (from #18)
- How to store confirmed amendments between review-spec and finish? (from #19)
- Reliability of entity/API overlap detection via text scanning (from #19)
- Should amendment blocks be machine-parseable or free-form markdown? (from #19)
- Handling concurrent amendments to the same older spec from parallel branches (from #19)
- Statistics report format: file (REVIEW-STATS.md) or console only? (from #20)
- Checkpoint findings vs test checkpoint ordering (review before or after tests?) (from #20)
- Task count handling after checkpoint fixes (restart or continue?) (from #20)
- Checkpoint review scope: diff since last checkpoint or entire implementation so far? (from #20)
- Cross-run statistics aggregation for per-project trends (from #20)
- Should finish skill also gain after_finish hook boilerplate (fixing existing dead config)? (from #21)
- Extract hook-reading boilerplate into shared include to avoid copy-pasting across extension commands? (from #21)

## Parked Ideas
(none)
