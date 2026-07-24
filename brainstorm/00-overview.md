# Brainstorm Overview

Last updated: 2026-07-24

## Sessions

| # | Date | Topic | Status | Spec | Issue |
|---|------|-------|--------|------|-------|
| 10 | 2026-05-05 | superpowers-wrapping-integration | active | - | - |
| 11 | 2026-05-19 | cc-deck-badge-auto-config | active | - | - |
| 12 | 2026-05-22 | hardening-review-process | active | - | - |
| 15 | 2026-06-08 | opencode-adaptation | idea | - | - |
| 19 | 2026-06-11 | cross-feature-amendments | active | - | - |
| 23 | 2026-06-23 | dual-repo-spec-workflow | active (revisited 2026-06-24, 2026-07-21) | - | - |
| 28 | 2026-07-02 | harness-agnostic-spex | active (revisited 2026-07-08) | - | - |
| 31 | 2026-07-04 | plugin-discovery-fix | parked | - | [#7](https://github.com/rhuss/cc-spex/issues/7) |
| 40 | 2026-07-15 | brainstorm-sync | active | 044 | - |
| 41 | 2026-07-23 | smart-phase-splitting | active | - | - |
| 42 | 2026-07-24 | first-class-codex-plugin | active | - | - |

## Open Threads

- Superpowers availability detection mechanism (from #10)
- Inline essentials freshness strategy: frozen vs manually refreshed (from #10)
- Category 3 pass-through spec context injection (from #10)
- Badge version comment for future icon set updates (from #11)
- cc-deck CLI binary check (`which cc-deck`) alongside config file detection (from #11)
- `--no-cc-deck` flag on `spex-init.sh` to skip badge configuration (from #11)
- Fix loop test failure interaction with round counter (from #12)
- Spec-anchored validation for specs with implicit verification methods (from #12)
- review-hints.md structure: flat file vs per-language sections (from #12)
- OpenCode variant: separate npm package or `--ai opencode` flag? (from #15)
- Enforcement degradation tolerance: is spex without hooks still spex? (from #15)
- Feature request to OpenCode for `prompt.before` plugin event? (from #15)
- OpenCode `question` tool: does it support multi-select with grouped options? (from #15)
- OpenCode custom tools via plugins as hook workaround? (from #15)
- How to store confirmed amendments between review-spec and finish? (from #19)
- Reliability of entity/API overlap detection via text scanning (from #19)
- Should amendment blocks be machine-parseable or free-form markdown? (from #19)
- Handling concurrent amendments to the same older spec from parallel branches (from #19)
- Should global gitignore also get exclude entries as belt-and-suspenders? (from #23)
- How should brainstorm skill handle archive path when detach is enabled? (from #23)
- Should `spex-detach enable` warn if spec files are already tracked? (from #23)
- Best upstream engagement format for SPECIFY_ROOT proposal: Discussion, Issue, or PR? (from #23)
- Commands neutral-first then specialize for ALL harnesses, or Claude-first then de-specialize? (from #28)
- Delimiter marker approach noise in command files (from #28)
- Testing neutral commands on each harness for acceptable behavior (from #28)
- Is the `source: "./subdir"` field in a cloned repo's marketplace.json supposed to be followed by Claude Code's installer? (from #31)
- Does Claude Code have documentation on how nested plugin sources are resolved? (from #31)
- Would symlinks in option A survive GitHub clone on all platforms (macOS, Linux, Windows)? (from #31)
- Should `--sync` also validate that "active" brainstorms without recent git activity are flagged as potentially stale? (from #40)
- Should the attic directory preserve any index file of its own for historical reference? (from #40)
- Should `--sync` be its own standalone command rather than a flag on the brainstorm skill? (from #40)
- What is the right minimum files-per-phase threshold for merging? (from #41)
- Should file estimation also consider test files, or only production code? (from #41)
- How to handle files shared across phases in the count? (from #41)
- What canonical shared-source layout lets both marketplace manifests package one core without duplicating generated artifacts? (from #42)
- Which Codex project configuration should implement Safe, Autonomous, and bounded-YOLO modes across supported versions? (from #42)
- What finite recovery budget should ship use before declaring a genuine terminal failure? (from #42)
- Should recovery spikes remain in the feature worktree or use disposable experimental worktrees? (from #42)
- Which harness adaptations should be generation-time transforms versus adapter-owned files? (from #42)
- What evidence should be required before Codex Teams graduates from experimental to recommended? (from #42)

## Parked Ideas

- Plugin discovery fix (#31): Plugin marketplace install resolves plugin source incorrectly for nested plugin structures.
  Reason: Needs upstream Claude Code documentation or bug confirmation before proceeding.
