# Idea Inbox

Ideas captured from code reviews for future brainstorming.

### flow-state-unconditional-update

- **Source**: deep-review
- **Date**: 2026-07-02
- **Reference**: 033-plugin-root-refs
- **Summary**: The `&&` chain in flow state update commands prevents `implemented` from running when `gate review-code` fails, contradicting the "MANDATORY: regardless of gate outcome" instruction.

> The `FLOW_STATE gate review-code && FLOW_STATE implemented` pattern in deep-review.run.md and review-code.md gates the `implemented` call on the success of `gate review-code`. If the gate fails, the status line never shows `R checkmark`. Restructuring to `{ gate review-code || true; implemented; }` would ensure the terminal state update always fires. This affects 2 files and should be a standalone fix.

### github-issue-brainstorm-flow

- **Source**: conversation
- **Date**: 2026-07-08
- **Reference**: v6.0.0 planning
- **Summary**: Add a full GitHub-based flow where a GitHub issue triggers brainstorm document creation through interactive dialogues, connecting issue tracking to the SDD pipeline entry point.

> Instead of starting brainstorming locally, allow the workflow to begin from a GitHub issue. The issue would serve as the seed, and an interactive dialogue (possibly via issue comments or a dedicated command) would refine the idea into a structured brainstorm document. This bridges the gap between project management (issues) and the spec-driven development pipeline (brainstorm -> specify -> plan -> implement).

### deep-review-trigger-hardening

- **Source**: PR #42-#44 review cycle (Codex plugin restructuring)
- **Date**: 2026-07-26
- **Reference**: 047-codex-plugin-support
- **Summary**: Deep review did not trigger because the initial code review scored 94.3% (below the 95% threshold). After fixing the 4 findings, the review was not re-run, so deep review agents and CodeRabbit never fired.

> The deep review trigger depends on the initial code review score meeting a threshold (95%). When findings are fixed but the review is not re-run, the deep review pipeline never activates. This creates a gap: PRs that improve during review never get the deep review pass. Options: (1) automatically re-trigger review after findings are resolved, (2) lower the threshold, (3) allow manual deep review invocation regardless of score, (4) track "findings resolved" as a separate trigger condition. The fix-then-forget pattern is likely common and should be handled gracefully.

_Review-related ideas (goal-alignment-skip-behavior, spec-completeness, platform-abstraction) moved to [cc-review/brainstorm/idea-inbox.md](https://github.com/rhuss/cc-review/blob/main/brainstorm/idea-inbox.md) on 2026-08-03._

### preserve-path-containment-guard

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: `spex-finish-preserve-specs.sh` and `spex-runbook-status.py` `do_locate` build copy/mkdir targets from a caller-supplied feature dir without a `..`/containment guard.

> Git ref rules forbid `..` in branch names so the documented callers are safe today, but a script whose whole job is writing into another checkout would benefit from defense-in-depth: require the path to start with `specs/`, reject `..` components, or realpath-assert the destination stays under the main checkout.

### shared-frontmatter-parser

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: The runbook frontmatter format is parsed by two independent hand-rolled parsers (`spex-runbook-check.py` and `spex-runbook-status.py`) with slightly different contracts.

> Both read a format written only by `serialize_frontmatter`. If that format ever gains multi-line or quoted values the parsers must change in lockstep or silently disagree. The single-file script model (whole-file `make sync-scripts`) makes a shared module non-free, so decide deliberately: either a shared `spex-runbook-common.py` in the sync inventory, or a cross-reference comment pinning both parsers to the canonical writer.

### runbook-version-unused

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: `runbook_version` is written into every runbook's frontmatter but never read — no required-key check, no migration or version dispatch.

> A persisted format-version marker with no reader and no migration path is speculative generality. Either drop it until a second format version exists, or mark it explicitly as an intentional forward-compat field with no current reader.

### fixture-start-record-atomicity

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: In `spex-runbook-fixture.sh` `cmd_start`, the real resource (process/container/compose) is created before `append_fixture` records it; an append failure under `set -e` leaves a live but untracked fixture.

> Narrow (requires a corrupt state file or mktemp failure) but the leak is unrecoverable by the tool, since `stop --quick` cannot see an unrecorded fixture. Consider tearing down the just-created resource on record failure, or ordering creation and recording transactionally.

### statusline-python-per-render

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: The flow-mode status line spawns a Python interpreter (`spex-runbook-status.sh show … --no-git`) on every render while a spec dir is active.

> `--no-git` already avoids the expensive fingerprint path, so this is Python startup latency, not git latency. For a per-render hot path consider parsing the runbook status inline with jq/awk, or caching the walkthrough segment keyed by the runbook's mtime so Python runs only when the file changed.

### openspec-style-proposal-short-run

- **Source**: conversation (morning-paper Context Engineering signal, 2026-10-14)
- **Date**: 2026-10-14
- **Reference**: future brainstorm
- **Summary**: Add a lightweight `propose` short-run inspired by OpenSpec's delta-proposal model (propose -> apply -> archive), as a fast path for small changes against an existing spec, alongside the current full-spec governance pipeline.

> OpenSpec (Fission-AI) treats SDD as small change proposals moving through a propose/apply/archive state machine, each describing only the delta against current behavior, no full spec per change. That wins on brownfield work where authoring and maintaining a complete spec is expensive. spex today is full-spec/governance-heavy (brainstorm -> specify -> plan -> implement, flow-state gated), which is the Spec Kit end of the spectrum. The idea: a `propose` command that starts a short run, captures the delta against the current spec, generates a minimal change proposal (not a full spec), runs a trimmed gate set, then `apply` (fold the delta into the canonical spec) and `archive` the proposal. The two modes are complementary: heavy pipeline for features, short-run for deltas. Open questions: where the canonical "current spec" lives and how `apply` reconciles overlapping proposals; whether proposals get their own flow-state lane; keeping the short-run and the full pipeline from drifting in command vocabulary (cf. 038-neutral-command-vocab). The unsolved part of the delta model generally is reconciliation: an append-only changelog of intent eventually needs a materialized current-state view, same tension as CRD/API schema evolution. See Obsidian insight `openspec-delta-proposal-model`.

### preserve-detach-error-handling

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: `spex-finish-preserve-specs.sh` collapses any failure of the detach `is-enabled` probe (bad path, `cd` failure) into `enabled=false`, indistinguishable from detach genuinely being off, and `rsync` has no fallback.

> Because the script prevents data loss before `finish` removes a worktree, misclassifying an environment/path error as "detach off" silently skips the copy. Consider validating `$WORKTREE` up front (exit non-zero on a bad path), distinguishing a clean "disabled" signal from an error, and optionally falling back to `cp -a` when `rsync` is absent.

### parallel-ship-stage0-state-collision

- **Source**: debugging (parallel ship pipelines in agentmeter)
- **Date**: 2026-10-14
- **Reference**: spex-ship-state.py, speckit.spex.ship.md (Stage 0), spex-worktrees manage
- **Summary**: Two ship pipelines started from the same main checkout at overlapping times both write `.specify/.spex-state` in main during Stage 0 (before their worktrees exist), so the second `create` overwrites the first pipeline's state.

> The worktree `create` action then copies whatever state is in main into its new worktree and deletes the main copy, so pipeline A can end up carrying pipeline B's state while B finds no state file at all (`advance` then reports `PIPELINE_COMPLETE`). Both sessions also share the main working tree while `specify` runs `git checkout -b`, so branch switches can collide as well. The statusline hijack fix (resolve state only from the session's own checkout) hides the display symptom but not this. Options: key the Stage 0 state file per session or per brainstorm (e.g. `.specify/.spex-state.<id>`) and rename it on worktree creation; refuse `create` when a running state already exists in main; or create the worktree before `specify` so Stage 0 never touches main.

### verify-record-forgeable

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 055-merge-stamp-finish
- **Summary**: Anyone with shell access (including the agent) can run `spex-verify-record.sh record` directly and forge a pass, which finish's already-verified row then trusts.

> Make bypasses visible rather than impossible: print the record details when finish uses it, flag direct `record` calls in pretool-gate, or store a summary of gate evidence in the record. Relates to brainstorm #46.

### hook-project-script-fallback

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 055-merge-stamp-finish
- **Summary**: If the plugin copy is missing, the commit hooks fall back to running a project-provided `.specify/.../spex-verify-record.sh`.

> This widens the set of hooks that run project code on their own. Consider dropping the fallback and treating a missing plugin copy as "not verified".

### fingerprint-algorithm-version

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 055-merge-stamp-finish
- **Summary**: The hooks read the record with the plugin's script copy, while verify and finish use the project-installed copies.

> If the fingerprint algorithm ever changes, the writer and reader could disagree. Store an algorithm version in the record and treat a mismatch as stale.

### readme-flowchart-closeout

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 055-merge-stamp-finish
- **Summary**: The README workflow flowchart has no finish or submit node, so the verify-and-land close-out is not shown.

> Add a close-out branch from ImplPR and Ship to `/speckit-spex-finish (verify + walkthrough + squash + land)`.

### fingerprint-file-mode

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 055-merge-stamp-finish
- **Summary**: The fingerprint ignores file mode, so `chmod +x` does not invalidate a verification pass.

> Including the mode would also change walkthrough currency (shared fingerprint), so existing runbook fingerprints would show as stale once.

### hook-commit-target-cwd

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 055-merge-stamp-finish
- **Summary**: The pre-commit reminder checks the record in the hook's cwd, not in the checkout the commit targets (`git -C`, `cd x &&`).

> The record is per worktree, so committing into a sibling worktree from the main checkout gives a false reminder. Parse `git -C` or a leading `cd` to resolve the target.

### submit-embedded-state-on-failure

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 055-merge-stamp-finish
- **Summary**: With `--embedded`, `.specify/.spex-state` stays behind when submit fails after a passing verify.

> Document this as intentional for retries, or remove the state file on submit's failure paths.

### test-record-survives-clear

- **Source**: deep-review
- **Date**: 2026-10-13
- **Reference**: 055-merge-stamp-finish
- **Summary**: No test pins FR-009d (the verification record survives `/speckit-spex-clear` and state cleanup).

> Add a test that applies spex-init's exclude patterns, records, then creates and deletes `.specify/.spex-state`, and asserts the record is still verified.

### custom-branch-repair-gap

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 056-worktree-with-branch
- **Summary**: The main-checkout finalize repair and adopt only handle feature-pattern branches, while late mode and finalize accept exact custom `--branch` names.

> A custom `--branch` plus a cwd reset ends with `not-on-a-feature-branch` and no hint about the prepared worktree; let the repair match the prepare marker's planned branch instead of the pattern.

### upstream-hook-priority-order

- **Source**: deep-review
- **Date**: 2026-10-16
- **Reference**: 056-worktree-with-branch
- **Summary**: The hook-order window for worktree-first specify only closes for good when spec-kit dispatches hooks by priority.

> Follow up on specs/056-worktree-with-branch/upstream-proposal.md once upstream answers, then drop late mode if possible.

### codex-claude-shared-worktrees

- **Source**: conversation
- **Date**: 2026-10-18
- **Reference**: [#30](https://github.com/rhuss/cc-spex/issues/30), 056-worktree-with-branch, 057-codex-bundled-init
- **Summary**: Using Claude Code and Codex on the same project and switching between them does not work cleanly yet: spex worktrees miss the Codex project setup, and a project declares a single harness.

> `copy_config` in `spex/scripts/spex-worktree.sh` copies only `.specify/` and `.claude/` (plus in-repo symlink targets) into a new worktree. Codex keeps its project setup in `.agents/skills/` and `.codex/` (both gitignored), so a Codex session in `.claude/worktrees/<branch>` has no `$speckit-*` skills or Codex hooks unless `.claude/skills` happens to link to `.agents/skills`. `.specify/spex.json` records one `harness`, and `$cc-spex-init` now always sets it to `codex`, so switching harness means re-running setup; it is unverified whether `specify init --integration <other>` keeps the other harness's generated files or replaces them. Also unverified: whether Codex's `workspace-write` sandbox allows `git worktree add`, which writes to the main repo's `.git/worktrees/`. Directions: copy `.agents/` and `.codex/` in `copy_config`, a harness-neutral default location (`.worktrees/`, as proposed in #30), and a supported way to keep both integrations installed side by side.

### repository-source-trust

- **Source**: deep-review
- **Date**: 2026-10-18
- **Reference**: 057-codex-bundled-init
- **Summary**: `$cc-spex-init` prefers `./spex` over the bundled plugin whenever a project looks like cc-spex, so any repository can ship its own `spex/setup.yml`.

> Consider an identity check or an explicit opt-in for the repository source when working in untrusted repositories.

### single-selection-orchestrator

- **Source**: deep-review
- **Date**: 2026-10-18
- **Reference**: 057-codex-bundled-init
- **Summary**: The snapshot, migrate, resolve, apply, persist sequence is written three times (setup.yml, spex-init.sh, init skill).

> One wrapper script would keep both init paths from drifting, as already happened with the git rule.

### legacy-init-path-errors

- **Source**: deep-review
- **Date**: 2026-10-18
- **Reference**: 057-codex-bundled-init
- **Summary**: The legacy spex-init.sh fast path (no setup.yml) silences install_extensions failures other than the git refusal.

> Low impact today; keep the exit status if that path stays.

### apply-before-persist-window

- **Source**: deep-review
- **Date**: 2026-10-18
- **Reference**: 057-codex-bundled-init
- **Summary**: A git refusal after apply-extensions leaves the new selection enabled but not persisted.

> Moving the git check before apply would make every failed setup leave the previous state.

### scripts-via-interpreter

- **Source**: deep-review
- **Date**: 2026-10-18
- **Reference**: 057-codex-bundled-init
- **Summary**: setup.yml runs some scripts directly and depends on executable bits surviving plugin cache copies.

> Calling them through `python3`/`sh` removes that dependency at no cost.

### shared-harness-token-fragments

- **Source**: deep-review
- **Date**: 2026-10-26
- **Reference**: 058-codex-ship-progress
- **Summary**: The OpenCode ship-progress token repeats most of the Codex token because command maps cannot share text.

> The two JSON strings will drift; a `progress --banner-only` flag or shared token fragments in the adapter would keep them in step.

### per-user-codex-progress-decline

- **Source**: deep-review
- **Date**: 2026-10-26
- **Reference**: 058-codex-ship-progress
- **Summary**: The Codex footer decline is a personal choice but lives in the team-owned `.specify/spex.json`, so one teammate's "no" applies to everyone who clones.

> Document the team-wide effect, or move the decline to an untracked per-user file later.

### aggregate-test-target-in-ci

- **Source**: deep-review
- **Date**: 2026-10-26
- **Reference**: 058-codex-ship-progress
- **Summary**: No aggregate `make test` target; release and CI do not run the per-area suites, including the Claude non-regression golden tests.

> The P1 "Claude unchanged" guarantee only holds when someone runs these tests by hand.

### claude-statusline-arithmetic-hardening

- **Source**: deep-review
- **Date**: 2026-10-26
- **Reference**: 058-codex-ship-progress
- **Summary**: The Claude status line still evaluates `stage_index` and `total_stages` in bash arithmetic, which can run `a[$(cmd)]` from a tampered state file (pre-existing).

> A digits-only check would leave output for valid states byte-identical and close the hole; it was kept out of this feature because of the byte-identical requirement.
