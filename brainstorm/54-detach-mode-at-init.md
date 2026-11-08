# Brainstorm: Select Detach Mode at Init

**Date:** 2026-11-02
**Status:** active (revisited 2026-11-04)
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

---

## Revisit: 2026-11-04

Deliverable 1 shipped as spec 060 (`41874bd`). Its open thread is resolved: `specify extension add` does reset the config, so spex saves and restores it around refresh.

### New Thread: When Specs Reach the Specs Repo

**Problem.** Spec artifacts reach the specs repo only at `finish`, through the `before_finish` archive step. Until then they exist only as excluded files in the checkout. In stealth mode, a worktree gets its spec directory by copy (`rsync` in `spex-worktree.sh`), so removing a worktree without `finish` loses the specs. The same risk the corgi case showed for brainstorms applies to every feature in progress.

Current archive behavior (`cmd_archive` in `spex-detach.py`):
- It can run any time with `/speckit-spex-detach-detach archive`, but nothing runs it before `finish`.
- It copies and never deletes. A file that was removed or renamed locally stays in the archive.
- The target folder is named after the current branch. On the default branch it archives into `<project>/main/`.
- It copies all of `.specify/` and all of `brainstorm/` per feature, so every feature folder holds its own snapshot of project-level files.

### Approaches Considered

**A: Symlink the spec directories into the specs repo.** `specs/` (and `brainstorm/`) in the checkout become links into the specs repo, so there is one copy and nothing to sync. Spec-kit only reads and writes files under `specs/`, which works through a directory link. Checked on a scratch repo on 2026-11-04:
- The exclude entry `specs/` does not hide a symlink. Git treats the link as a file, and only `specs` (no trailing slash) matches it.
- `rg` does not follow symlinks while walking a tree. A search from the repo root found nothing under the linked `specs/`, and `rg -L` found it. Claude's search tools are built on ripgrep, so the agent would likely not see its own specs.
- Each worktree needs its own link, and a relative link breaks when a worktree sits at a different depth. `.specify/` can't be linked, since it holds per-checkout state (`feature.json`, `.spex-state`, installed extensions).
- `rm -rf specs/` with a trailing slash deletes the contents in the specs repo, not the link.
- Windows: real symlinks need Developer Mode or admin rights. In Git Bash, `ln -s` silently makes a copy unless `MSYS=winsymlinks:nativestrict` is set, so the two copies drift without warning. Directory junctions (`mklink /J`) avoid the admin requirement but need absolute paths, local NTFS and Windows-specific code.

**B: Continuous mirror through phase hooks.** Keep copying, but automatically and as a true mirror. Archive runs after each phase (specify, clarify, plan, tasks, implement, each review gate) and at `finish`. It removes files that were deleted locally. Each run commits to the specs repo when something changed (and pushes when `auto_push` is on).
- Works the same on every platform and needs no change to exclude entries or search.
- Specs survive a lost worktree up to the last phase boundary.
- The specs repo gets a readable history: one commit per phase.

**C: Archive only at finish (today).** Simple, but loses work when a worktree is removed early, and the specs repo has no history of how a spec evolved.

### Leaning

B as the default. A may come later as an opt-in "live" mode for macOS and Linux, if the exclude pattern and search issues get handled. To confirm when Deliverable 2 is specified.

### Key Requirements (new thread)

- Spec artifacts reach the specs repo without the user remembering to archive.
- A worktree removed without `finish` loses at most the edits since the last phase boundary.
- Deleting or renaming a spec file locally is reflected in the specs repo.
- Archive folders are per feature (the spec directory), not per branch.
- Project-level files (`spex.json`, constitution) are synced once per project, not copied into every feature folder.
- A failed archive or push warns and never blocks a phase or `finish`.

### Open Threads

- Which hooks trigger the mirror: every `after_*` phase hook, only gate passes, or a file-change hook? (new thread)
- Mirror scope: should a mirror run be allowed to delete files in the specs repo that were added there by hand?
- Commit granularity: one commit per phase, or amend a running commit per feature until `finish`?
- Migration of existing archives laid out as `<project>/<branch>/` to the per-feature layout.
- Brainstorm sync: mirror `brainstorm/` on every brainstorm save, independent of a feature?
