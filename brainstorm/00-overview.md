# Brainstorm Overview

Last updated: 2026-06-08
Note: Brainstorm 16 has a companion file `16-speckit-hook-adapter-proposal.md` (upstream issue draft, pending review)

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
| 16 | 2026-06-08 | multi-agent-support | active | - | - |

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
- Codex stdin/stdout JSON contract for UserPromptSubmit and PreToolUse: needs testing (from #16)
- OpenCode tool.execute.before: can it add context or only deny? (from #16)
- Agent detection: static (init-time) vs dynamic (runtime) for multi-agent projects? (from #16)
- AGENTS.md AskUser pattern: generic ("ask the user") vs agent-specific tool name? (from #16)
- Upstream spec-kit hook adapter framework proposal: pending review (from #16)

## Parked Ideas
(none)
