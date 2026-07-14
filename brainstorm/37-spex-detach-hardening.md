# Brainstorm: Harden spex-detach for Reliable Upstream Contributions

**Date:** 2026-07-14
**Status:** active
**Related:** Brainstorm #23 (dual-repo spec workflow), Spec 029 (upstream-contrib-mode)

## Problem Framing

The spex-detach extension (spec 029) was designed to strip SpecKit
artifacts from PR branches when contributing to upstream projects that
don't use spec-driven development. The implementation exists but has
gaps that cause spec artifacts to leak into upstream PRs.

Real-world evidence: the OpenShell fork (NVIDIA/OpenShell) has 8+
commits in its history containing `brainstorm/`, `specs/`, and
`.specify/` content that reached upstream branches. These leaked
because the detach flow was never fully wired into `spex-finish`.

### Three Implementation Gaps

**1. Finish command not integrated**

The spex-detach spec (029) designed tasks T009-T012 for wiring detach
into the finish command. These tasks are marked [X] complete in
`specs/029-upstream-contrib-mode/tasks.md`, but the actual finish
command (`speckit.spex.finish.md`, 461 lines) contains zero references
to "detach". The integration was never implemented.

The finish command should detect `.specify/extensions/spex-detach`
after Phase 2 (commit outstanding changes), call `spex-detach.py
detach` to create the clean `pr/<branch>` branch, and offer "Push
clean PR branch" as an option in Phase 4.

**2. Brainstorm skill script path bug**

The brainstorm skill (`speckit.spex.brainstorm.md`) has
detach-awareness code that checks whether to redirect brainstorm
output to the project-specs repo. But it references the wrong script
path:

- **Wrong**: `.specify/extensions/spex/scripts/spex-detach.sh`
- **Correct**: `.specify/extensions/spex-detach/scripts/spex-detach.sh`

This means the detach check always fails silently and brainstorms are
never redirected.

**3. No post-detach verification**

After creating the clean PR branch, there is no verification step that
scans the branch for remaining SpecKit fingerprints. If the strip
misses something (e.g., a file placed outside the configured
`strip_paths`), the leak goes undetected.

### Artifact Coverage

The current `strip_paths` default is `[".specify", "specs",
"brainstorm"]`. This is complete for today's SpecKit layout:

- `.specify/` catches all config, extensions, scripts, workflows,
  templates, integrations, memory, and flow state
- `specs/` catches spec.md, plan.md, tasks.md, research, checklists,
  contracts, review findings
- `brainstorm/` catches brainstorm documents and overview

The risk is future extensions placing files outside these three
directories. A post-detach verification step would catch this.

## Approaches Considered

### A: Harden the existing extension (Chosen)

Fix the three gaps directly:

1. **Wire detach into spex-finish**: Add the detection block after
   Phase 2 in the finish command, exactly as spec 029 designed.
   When `.specify/extensions/spex-detach` exists, call
   `spex-detach.py detach`. Add "Push clean PR branch" option to
   Phase 4 action selection. This is additive modification, same
   pattern as existing collab/gates detection in the finish command.

2. **Fix brainstorm script path**: Correct the reference in
   `speckit.spex.brainstorm.md` from
   `.specify/extensions/spex/scripts/spex-detach.sh` to
   `.specify/extensions/spex-detach/scripts/spex-detach.sh`.

3. **Add post-detach verification**: After creating the clean PR
   branch, scan it for remaining SpecKit fingerprints:
   - Any `.specify/` directory or files
   - Any `specs/` directory containing spec.md, plan.md, or tasks.md
   - Any `brainstorm/` directory
   Fail the detach with a clear error if any are found.

4. **Defense-in-depth via .gitignore guidance**: Update the quickstart
   to recommend adding `.specify/`, `specs/`, `brainstorm/` to the
   upstream fork's `.gitignore`. This prevents `git add .` from
   staging spec artifacts even when someone skips `spex-finish`.
   Not automated, just documented.

5. **Auto-detect fork and warn**: When spex-detach is enabled and the
   repo has an `upstream` remote, check if `.gitignore` includes the
   SpecKit paths. Warn if not. This catches the "forgot to set up
   .gitignore" case without being intrusive.

**Pros**: Minimal new code, fixes actual bugs, works within the
existing architecture, no new concepts.

**Cons**: Still relies on `spex-finish` being invoked. But the
`.gitignore` defense covers the bypass case for new files.

### B: Pre-commit hook enforcement (Not chosen)

Everything from A, plus a git pre-commit hook that rejects commits
containing SpecKit artifacts on `pr/*` branches.

**Why not chosen**: `.gitignore` defense-in-depth already prevents
accidental staging. A pre-commit hook adds complexity, is
per-developer (not upstream-enforceable), and doesn't add meaningful
safety beyond what `.gitignore` + verified detach provides.

### C: CI-side GitHub Action (Deferred)

A GitHub Action that rejects PRs containing SpecKit artifacts. This
would be upstream-enforceable but requires the upstream project to
install it. Worth considering for v2 but not for this fix.

## Decision

**Approach A: Harden the existing extension.** Surgical fixes to
complete the unfinished integration, fix the path bug, and add
verification. No new architecture.

## Key Requirements

1. **Finish integration (FR-003 completion)**: `spex-finish` must
   detect spex-detach and call the detach script after Phase 2
   (commit). The clean PR branch `pr/<feature-branch>` must be
   offered as a push target in Phase 4.

2. **Correct script paths**: All skill files referencing spex-detach
   scripts must use the correct path at
   `.specify/extensions/spex-detach/scripts/spex-detach.sh`.

3. **Post-detach verification (new FR)**: After creating the clean
   PR branch, verify zero SpecKit artifacts remain. Check the actual
   branch content via `git ls-tree`, not just the diff. Fail with
   a clear error listing leaked files if any are found.

4. **Idempotent re-run**: Running `spex-finish` multiple times must
   regenerate the clean PR branch cleanly (already works via
   delete + recreate in `spex-detach.py`).

5. **Fork detection warning**: When detach is enabled and an
   `upstream` remote exists, check `.gitignore` for SpecKit paths
   and warn if missing. Non-blocking, just advisory.

6. **Quickstart update**: Document the `.gitignore` recommendation
   as a setup step for upstream contributions.

## Additional Requirements: Sibling Specs Repo Model

### Archive to sibling specs repo at finish time

The intended production workflow uses a sibling directory layout:

```
~/Work/projects/openshell/           # code fork (upstream contributions)
~/Work/projects/openshell-specs/     # private specs, brainstorms, archive
```

SpecKit runs inside the code fork during development. At `spex-finish`
time, the detach extension should:

1. Archive `specs/<feature>/` and `.specify/` to the sibling specs
   repo (configured via `archive.path` in `spex-detach-config.yml`)
2. Strip all SpecKit artifacts from the PR branch
3. Verify the clean branch has no leaks

The sibling specs repo is a regular git repo. The archive command
already supports this (`spex-detach.py archive --target <path>`), but
the `archive.path` config needs to be set during `specify init` when
`spex-detach` is enabled. The init flow should prompt for the archive
path.

### Brainstorm discovery from sibling specs repo

When running brainstorming in the code fork, the brainstorm skill
should also scan the sibling specs repo's `brainstorm/` directory for
existing documents on similar topics. This prevents duplicate
brainstorms and helps the user discover prior thinking.

The lookup path is already available via `archive.path` in the detach
config. The brainstorm skill should:

1. Check if spex-detach is enabled and `archive.path` is set
2. Scan `<archive.path>/brainstorm/` for related documents (same
   keyword overlap logic as local brainstorm revisit detection)
3. Present matches alongside any local brainstorm matches
4. If the user chooses to update an existing sibling brainstorm,
   append a revisit section to the document in the sibling repo

This keeps brainstorm history centralized in the specs repo while
allowing brainstorming from the code fork where SpecKit operates.

### Archive at detach time (move, not just copy)

At `spex-finish` with detach enabled, the archive step should move
(not just copy) the spec artifacts to the sibling specs repo. This
ensures:

- The specs repo has the authoritative copy
- The code fork is clean after finish (no orphaned spec dirs)
- The `.gitignore` entries in the code fork prevent re-creation

The current `archive` subcommand copies. It should be updated to
optionally move (delete source after successful copy and commit to
the archive repo). The move behavior should be the default when
detach is also being performed in the same finish flow, since the
files are about to be stripped from the PR branch anyway.

## Open Questions

- Should spec archiving (`spex-detach.py archive`) be mandatory
  before detach, or remain optional? Currently optional, which means
  specs could be lost if the worktree is deleted without archiving.
  The sibling specs repo model (where brainstorms already live in a
  separate repo) makes archiving less critical since the design
  context is preserved there.
- The `spex-detach.py` script uses `git apply --index` to apply the
  filtered diff. Does this handle all edge cases (binary files,
  renames, permission changes)? The `--binary` flag on `git diff`
  should cover binaries, but this hasn't been tested at scale.
- Should the verification step run against `git ls-tree` (checks
  all files on the branch) or `git diff` (checks only changed files)?
  `ls-tree` is more thorough but could flag SpecKit files that
  existed in the upstream base branch (unlikely but possible).
- Should brainstorm documents also be moved to the sibling specs
  repo at archive time, or only `specs/` and `.specify/`? Brainstorms
  may span multiple features and moving them could break references
  from other in-progress features.
- How should the init flow prompt for `archive.path`? Auto-detect
  sibling `*-specs` directories, or always ask explicitly?
