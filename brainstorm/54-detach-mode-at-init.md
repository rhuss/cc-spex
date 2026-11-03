# Brainstorm: Select Detach Mode at Init

**Date:** 2026-11-02
**Status:** active (revisited 2026-11-03)
**Related:** #23 (dual-repo-spec-workflow), attic #37 (spex-detach hardening)

## Problem Framing

For a fork of a project that doesn't use SDD, the user wants two things set up in one go: spec artifacts hidden from the code repo, and those artifacts versioned somewhere else. Today `/spex:init` covers only the first half, and only partly.

What init offers: the "Workflow" question has a `spex-detach` option ("Strip spec artifacts at PR time..."). Selecting it enables the extension and runs `spex-detach enable`. Init never asks where the artifacts should be archived. `archive.path` in `.specify/extensions/spex-detach/spex-detach-config.yml` stays `""`, so brainstorms live only as excluded, unversioned files in the checkout. #23 already decided (2026-06-23) that init should configure the specs-repo path; that part never shipped.

Real-world evidence, corgi fork (`rhuss/corgi`, upstream `tals/corgi`), 2026-11-02:
- Eight brainstorm documents plus an idea inbox existed only as excluded files in the main checkout. Deleting the checkout would have lost them. They were moved by hand to a new sibling repo (`rhuss/corgi-specs`) and `archive.path` was edited by hand.
- **Stealth mode was incomplete.** `.git/info/exclude` held `brainstorm/` but not `specs/` or `.specify/`, although the detach config lists all three. The spex block written by `configure_git_exclude` re-includes `.specify/spex.json` and `.specify/memory/constitution.md`. Result: `git check-ignore` reports `specs/<feature>/spec.md`, `.specify/spex.json` and the constitution as visible. No feature branch had committed them yet, but one `git add -A` would leak them into an upstream PR.
- **Likely root cause of the gap (traced in the code, not reproduced):** on init, `spex-init.sh` calls `run_detach_enable` right after `install_extensions`. At that point spex-detach is still disabled (`install_extensions` keeps it off unless it was on before or the declaration names it), so `run_detach_enable` returns silently. The user's selection is applied afterwards by the init skill through `spex-apply-extensions.sh`, which enables the extension but never runs `spex-detach enable`. The extension's `after_init` hook doesn't fire for `/spex:init`. Net effect: selecting spex-detach in init enables the extension without writing a single exclude entry. Corgi's `brainstorm/` line had no `# spex-detach` header, so it was added another way, not by `enable`.
- **Manual fix applied in corgi (2026-11-02):** running `spex-detach.sh enable` by hand added `.specify/` and `specs/`; `git check-ignore` then reported all four probe paths (`specs/...`, `.specify/spex.json`, the constitution, `brainstorm/...`) as ignored. The `.specify/` directory entry overrides the init block's `!` re-includes, which is the wanted outcome in a fork.
- The archive path has to be absolute. The brainstorm skill and `spex-detach.py` use it as given, so a relative `../corgi-specs` resolves differently from `.claude/worktrees/<feature>`.

Success: one init run in a fork leaves the user with (1) every spec artifact hidden from the code repo, verified, and (2) a sibling specs repo that brainstorms and archived specs land in, surviving `--refresh`.

Failure even if it works technically:
- Stealth mode reports "enabled" while spec files are still visible to git.
- The archive path is lost on `/spex:init --refresh`.
- Users must know about and hand-edit a YAML file inside `.specify/extensions/`.
- Non-fork projects get asked about detach and specs repos they will never need.

## Approaches Considered

### A: Follow-up questions in init when spex-detach is selected
- When `spex-detach` is in the selection, init asks one more question: where to keep spec artifacts. Options: create `../<project>-specs` (proposed default), use an existing path, or keep local only (today's behavior, with a warning that nothing is versioned).
- Creating the repo means `git init`, plus optionally a GitHub repo (public or private). The absolute path is stored in the `spex.json` declaration so `--refresh` re-applies it.
- Init verifies stealth mode afterwards with `git check-ignore` on `specs/`, `.specify/` and `brainstorm/` and reports anything still visible.
- Pros: one place, discoverable, matches #23's decision; users who don't select detach see no change.
- Cons: init grows another question; repo creation is outward-facing and needs its own confirmation.

### B: Separate setup command, init only points to it
- Init enables detach as today and prints "run `/speckit-spex-detach-detach setup` to configure the specs repo". The setup command asks for the path, creates the repo, verifies exclusion.
- Pros: init stays small; setup can be re-run later on an existing project.
- Cons: easy to skip, which is exactly how corgi ended up without a specs repo.

### C: Convention over configuration
- No question: if `../<project>-specs` exists, use it; the brainstorm skill already detects `../*-specs` and only prints a NOTE today.
- Pros: zero prompts.
- Cons: silent magic; the repo still has to be created by hand; doesn't fix the exclude gap or refresh persistence.

## Decision

Not yet decided. Leaning A (with B's command as the re-runnable backend that init calls), since a skippable step is what failed in the corgi case. To be confirmed in a follow-up session.

## Key Requirements

- Selecting detach at init must also settle where artifacts are archived, or say clearly that they are not.
- Stealth mode must cover every configured exclude path and be verified, not assumed. The init exclude block must not re-include files that detach hides.
- The archive path is stored absolute and survives `/spex:init --refresh` (today the config lives inside the extension directory, which refresh removes and re-adds; likely reset, not verified).
- Pushing the specs repo is not automatic today (`auto_commit` commits only); the setup should at least offer a remote.

## Open Questions

- Where the archive path lives: `spex.json` declaration, `init-options.json` (#23's proposal), or the detach config with refresh preservation.
- Whether `spex.json` and the constitution should stay committed in detach mode, or be hidden like the rest. In a fork they are spex artifacts too.
- Default visibility when init offers to create a GitHub repo for the specs.
- Whether `auto_commit` should also push when a remote exists.
- How init detects "this is a fork" to suggest detach (upstream remote present, as the brainstorm skill's issue flow already checks).
- Whether to fix the exclude gap separately as a bug before the init work. Smallest fix: run `spex-detach enable` (and the `check-ignore` verification) after the extension selection is applied, in `spex-apply-extensions.sh` or the init skill's Step 2.
- How existing projects that selected detach before the fix get repaired: a one-time check on `--refresh` that runs `enable` when detach is on but its entries are missing.

---

## Revisit: 2026-11-03

### Updated Problem Framing

Two claims from the first session were checked against the code:

- **Exclude gap confirmed (code reading).** `run_detach_enable` (`spex/scripts/spex-init.sh`) returns early because `install_extensions` keeps spex-detach disabled until the selection is applied. `spex-apply-extensions.sh` then enables the extension without calling `enable`.
- **Refresh loses the archive path (code reading, previously "likely").** `install_extensions` runs `specify extension remove spex-detach` without `--keep-config`, so `spex-detach-config.yml` is deleted and re-created from the template on every `--refresh`.

The brainstorm mixes two bugs that leak or lose data with one new init feature. They ship separately so the leak risk is closed before the larger feature lands.

### Updated Decision

Approach A, split into two deliverables.

**Deliverable 1: bug fix (first, small PR)**
- After the extension selection is applied, run `spex-detach enable` and verify every configured exclude path with `git check-ignore`. Report any path still visible to git. "Enabled" must never be shown while spec files are visible.
- `--refresh` preserves `spex-detach-config.yml` instead of resetting it to the template.
- `--refresh` repairs existing projects: if detach is enabled but its exclude entries are missing, run `enable` and report the repair.

**Deliverable 2: init feature (own spec afterwards)**
- When spex-detach is selected, init asks where spec artifacts go: create `../<project>-specs` (default), use an existing path, or keep local only (with a warning that nothing is versioned).
- The archive path is stored absolute in `spex-detach-config.yml` (the place scripts and the brainstorm skill already read). Not in `spex.json` (machine-specific path in a shared file) and not in `init-options.json` (spec-kit owned).
- Creating the repo: `git init` locally, then offer a GitHub remote, private by default; public only on explicit choice. Remote creation is a separate confirmation (outward-facing).
- New `archive.auto_push` setting, separate from `auto_commit`. Init turns it on when it creates the remote. A failed push warns and never blocks `finish`.
- `spex.json` and the constitution stay hidden from the code repo (the `.specify/` exclude overrides the init block's re-includes) and are versioned in the specs repo, so a fresh checkout can restore them.
- Fork hint: when an `upstream` remote exists and upstream's default branch has no `.specify/`, init marks spex-detach as suggested in the Workflow question. Not pre-selected; no hint otherwise.

**Out of scope:** convention-only discovery (approach C); a standalone setup command as the primary entry point (B may still exist as the re-runnable backend init calls).

### Key Requirements (updated)

- Stealth mode is verified, not assumed, on init and on refresh.
- The archive path survives `--refresh`.
- Users never need to hand-edit a YAML file under `.specify/extensions/` for the common fork setup.
- Projects that aren't forks see no new questions.

### Open Threads
- Does `specify extension add` overwrite an existing config file when refresh uses `--keep-config`, or does spex need its own backup/restore? (deliverable 1)
- Layout of project-level files in the specs repo (for example `project/spex.json`, `project/constitution.md`) and when they are synced: on every archive, on change, or on finish. (deliverable 2)
- Restore path: how a fresh checkout of the fork pulls the constitution and `spex.json` back from the specs repo. (deliverable 2)
- How the fork hint checks upstream for `.specify/` without a network call when the upstream ref is not fetched. (deliverable 2)
