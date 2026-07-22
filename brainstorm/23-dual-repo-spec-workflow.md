# Brainstorm: Dual-Repo Spec Workflow (Specs Repo + Code Fork)

**Date:** 2026-06-23
**Status:** active
**Revisited:** 2026-06-24, 2026-07-21

## Problem Framing

When contributing to an upstream project (e.g., NVIDIA/OpenShell) using
spex's spec-driven workflow, the natural setup is a dual-repo layout:

- **Parent directory** (private repo): Brainstorms, specs, plans, tasks,
  and `.specify/` configuration. This is the "specs repo."
- **Subdirectory** (public fork): The actual code repo where
  implementation and PRs happen.

This layout exists because upstream projects don't use spex, so spec
artifacts can't be committed into the fork. The specs repo tracks
the design work privately; the fork tracks the code publicly.

### Observed Problems

1. **State file mismatch**: The flow state script writes
   `.specify/.spex-state` relative to cwd. When hooks or commands run
   from the code subdirectory (e.g., during `spex:init` which runs
   inside the code repo), the state file lands in the wrong place.
   Later commands running from the parent can't find it. The status
   line breaks silently.

2. **`.specify/` duplication**: `spex:init` installs `.specify/`
   into the code repo's directory. If the parent already has
   `.specify/`, the two directories diverge. Moving artifacts manually
   is error-prone and leaves orphan files.

3. **Branching strategy unclear**: The specs repo and the code fork
   have independent git histories. When spex creates a feature branch
   (e.g., `002-cli-json-output`), it does so in whichever repo's
   `.git/` is in scope. Should both repos branch in sync? Should only
   the specs repo branch? What happens when the upstream PR merges but
   the spec branch is still open?

4. **`mise run` commands**: Build/test commands must run from the code
   subdirectory, but spex hooks expect cwd to be the specs repo root.
   Agents need to know which directory to use for which operation.

## Approaches Considered

### A: Parent-Anchored Workflow (Recommended)

The specs repo (parent) is the spex project root. All `.specify/`
state, flow state, and spec artifacts live there. The code
subdirectory is treated as a "remote implementation target" that spex
never initializes.

**How it works:**
- `spex:init` runs in the parent directory only, never in the code
  subdirectory.
- `.specify/` lives exclusively in the parent.
- All flow state commands run from the parent directory.
- The `CLAUDE.md` in the parent points to `OpenShell/AGENTS.md` etc.
  for build/test context.
- Implementation tasks explicitly prefix paths with the code
  subdirectory name (e.g., `OpenShell/crates/openshell-cli/src/`).
- Build/test commands are run with explicit `cd OpenShell && mise run ci`
  or via absolute paths.

**Branching strategy:**
- Specs repo (parent): Feature branch per spec (e.g., `002-cli-json-output`).
  Tracks the spec lifecycle.
- Code fork (child): Feature branch per PR (e.g., `feat/cli-json-output`).
  Tracks the code lifecycle. Branch name follows upstream conventions
  (no numeric prefix).
- The two branches are independent. The spec branch may outlive the
  code branch (spec stays open for follow-up work after PR merges).
- Link between them: spec's `plan.md` references the upstream issue
  number; the PR references the upstream issue with `Fixes #NNN`.

**Pros:**
- Clean separation. No `.specify/` in the fork.
- Flow state is always in one place.
- No risk of committing spec artifacts into the public fork.
- Branching is independent, matching reality (specs have a different
  lifecycle than code).

**Cons:**
- Agents must be aware of the two-directory layout (already true via
  CLAUDE.md).
- Build commands need explicit directory context.

### B: Symlink/Mount Approach

Create a symlink from `OpenShell/.specify` to `../.specify` so that
commands running from either directory find the same state.

**Pros:** Transparent to scripts that use relative paths.
**Cons:** Fragile across git operations, OS-dependent, `.gitignore`
complexity, confusing to debug.

### C: Environment Variable Override

Set `SPECIFY_ROOT=/Users/rhuss/Work/projects/openshell` as an env var
that all spex scripts respect, overriding the cwd-based `.specify/`
lookup.

**Pros:** Works regardless of cwd. Could be set in `.envrc` or
`mise.toml`.
**Cons:** Requires all spex scripts to support it (they currently
don't). Would need upstream changes to cc-spex.

### D: Monorepo with `.gitignore`

Run `spex:init` in the parent, add the code fork as a git submodule
or subtree, and use `.gitignore` to exclude spec artifacts from the
fork's tree.

**Pros:** Single git history. One branch strategy.
**Cons:** Submodules are painful. The fork's git history must stay
clean for upstream PRs. Pollutes the fork with parent repo structure.

## Decision

**Approach A (Parent-Anchored Workflow)** for the immediate term.
This is what we're already doing, but we need to formalize it and
fix the rough edges.

**Approach C (Environment Variable Override)** is the right long-term
fix for cc-spex itself. Filing as a feature request.

## Key Requirements

### For this project (openshell-specs)

1. `.specify/` MUST live only in the parent directory.
2. `spex:init` MUST NOT be run inside `OpenShell/`.
3. All flow state commands MUST run from the parent directory.
4. The `CLAUDE.md` MUST document the dual-directory layout and
   instruct agents to run build commands from `OpenShell/` and
   spex commands from the parent.
5. Task file paths MUST prefix with `OpenShell/` for code locations.

### For cc-spex (upstream feature request)

1. Introduce `SPECIFY_ROOT` or `SPEX_PROJECT_ROOT` env var that all
   scripts respect for `.specify/` and `.spex-state` lookups.
2. `spex-flow-state.sh` should use `$SPECIFY_ROOT/.specify/.spex-state`
   when the var is set, falling back to cwd-relative `.specify/`.
3. The `spex:init` command should detect a nested code repo (via
   `.gitignore` patterns or a config option) and set up the parent
   as the project root.
4. Document the "contributing to upstream" workflow as a first-class
   use case.

### Branching Strategy

| Repo | Branch naming | Lifecycle | Linked by |
|------|--------------|-----------|-----------|
| openshell-specs (parent) | `NNN-feature-slug` | Spec lifecycle (brainstorm to spec-created) | Spec references issue # |
| OpenShell (fork) | `feat/feature-slug` or upstream convention | PR lifecycle (branch to merge) | PR references issue # |

- Specs repo branches are created by `/speckit-specify` (via
  `speckit-git-feature`).
- Code fork branches are created manually or by `build-from-issue`
  skill when implementation starts.
- The two branches share the upstream issue number as their common
  link, not a naming convention.
- When the upstream PR merges, the code branch is deleted. The spec
  branch can be merged to main in the specs repo (marking the spec
  as completed).

## Open Questions

- Should `spex:init` gain a `--target-dir` option to configure a code
  subdirectory path at init time, stored in `.specify/init-options.json`?
- Should the flow state script detect when it's running inside a
  subdirectory and walk up to find `.specify/`?
- Should `speckit-implement` gain awareness of a "code root" vs
  "spec root" distinction, or is CLAUDE.md sufficient?

---

## Revisit: 2026-06-24

### Updated Problem Framing

The original brainstorm assumed a parent-anchored layout (specs repo
contains code repo as subdirectory). Practical experience revealed a
critical flaw: **multiple worktrees with parallel Claude Code sessions
share a single `.specify/.spex-state`**, causing state collisions.

Additionally, the CLAUDE.md approach for pointing to the code
directory breaks with worktrees because the active code directory
is dynamic, not a hardcodeable path.

The core requirement was refined: contribute to upstream projects
that don't use SDD, keeping PRs completely free of spec artifacts,
while supporting parallel feature work across multiple worktrees.

### Spec-Kit Research Findings

- `specify` CLI only checks cwd for `.specify/`, no directory walking
- No "code root" or "target directory" concept in any config file
- One relevant env var: `SHIP_STATE_FILE` overrides state file path
- `CLAUDE_PROJECT_DIR` used as fallback in statusline script
- All shell scripts use a `CWD` variable pattern extensible to a
  root override
- No upstream changes needed if running from the directory containing
  `.specify/`

### New Approaches Considered

#### E: Worktree-Native with Clean PR Branch (Chosen)

Specs live inside the code worktree, committed to the fork's feature
branch. Each worktree is fully self-contained with its own `.specify/`
and flow state. At PR time, a clean branch is created that strips
spec directories. Specs are archived to a personal project-specs repo.

**Key properties:**
- Each worktree has independent `.specify/` and flow state
- No shared state between parallel sessions
- PR branch (`pr/feature-name`) is created from the feature branch
  with `.specify/`, `specs/` removed
- Feature branch keeps specs intact for continued work/revision
- Brainstorm documents always live in the project-specs repo (not
  in code worktrees), since spec-kit doesn't need them
- This is a spec-kit feature, configured at `specify init` time,
  off by default

**Pros:**
- Solves parallel worktree/session problem completely
- Specs are version-controlled during development
- PRs are guaranteed clean (no spec artifacts)
- No changes to spec-kit core path resolution needed
- Backward compatible (opt-in)

**Cons:**
- Need to automate clean-branch + archive steps in `spex-finish`
- `.specify/` must be initialized per worktree
- Two-repo mental model (but only at finish time)

### Updated Decision

**Approach E (Worktree-Native with Clean PR Branch)** replaces
Approach A as the chosen strategy. The parent-anchored approach
(Approach A) fails under parallel worktree usage due to shared
flow state.

Approach C (Environment Variable Override) remains a potential
future enhancement but is no longer the primary long-term path.

### Updated Key Requirements

#### Spec-kit feature: upstream contribution mode

1. `specify init` gains an option to enable upstream contribution
   mode. Off by default, preserving existing single-repo behavior.
2. When enabled, `spex-finish` creates a clean PR branch by
   branching from the feature branch and removing `.specify/`,
   `specs/`, and `brainstorm/` directories.
3. When enabled, `spex-finish` archives spec artifacts to a
   configured project-specs repo path before creating the clean
   branch.
4. The archive target (project-specs repo path) is stored in
   `.specify/init-options.json`.

#### Artifact placement

| Artifact | Location | When |
|----------|----------|------|
| Brainstorm docs | Project-specs repo (always) | During brainstorming |
| `.specify/`, `specs/` | Code worktree (feature branch) | During specify/plan/implement |
| Archived specs | Project-specs repo | At finish time |
| Clean code | PR branch (`pr/feature-name`) | At PR creation |

#### Branching strategy (revised)

| Repo | Branch strategy | Lifecycle |
|------|----------------|-----------|
| Project-specs repo | Everything on `main` | Accumulates brainstorms + archived specs |
| Code fork (worktree) | Feature branch per upstream convention | Development lifecycle |
| Code fork (PR) | Clean branch (`pr/feature-name`) | PR lifecycle, stripped of spec dirs |

- No feature branches in the project-specs repo.
- Status fields in brainstorm docs and archived specs track lifecycle.
- Feature branch in code fork keeps specs for revision if PR
  needs changes.
- Clean PR branch is regenerated from feature branch as needed.

#### Project-specs repo structure

```
project-specs/                    # personal specs repo, always on main
  brainstorm/                     # brainstorm docs (all projects)
    00-overview.md
    NN-topic.md
  archive/                        # archived specs by project
    openshell/
      001-json-output/
        spec.md
        plan.md
        tasks.md
    another-project/
      001-feature/
        ...
  .specify/                       # optional, for constitution/memory
    memory/
      constitution.md
```

### Open Questions

- What should the `specify init` option be called? (`--upstream`,
  `--contrib`, `--external`?)
- Should the archive step be automatic at finish time, or offer
  an interactive prompt?
- How should context from archived specs flow back into new
  features for the same upstream project?
- Should `specify init` in upstream mode auto-add `.specify/` and
  `specs/` to the code repo's `.git/info/exclude` as a safety net?
- How to handle worktree-to-worktree spec migration if a feature
  moves between worktrees?

---

## Revisit: 2026-07-21

### Updated Problem Framing

Approach E (Worktree-Native with Clean PR Branch) from the previous
revisit was implemented as the spex-detach extension. After using it
on real upstream contributions, two failure modes emerged:

1. **Spec files leak into unrelated PRs.** Even though detach creates
   a clean `pr/` branch at PR time, the spec directories (`.specify/`,
   `specs/`, `brainstorm/`) remain in the working tree. When working
   on a subsequent task outside the SDD workflow (no spec-kit
   initialized), `git add .` or rebase operations carry these files
   into unrelated commits and PRs. This happened twice in practice.

2. **Re-initialization burden.** After a PR is submitted and the
   developer returns to the main branch, the `.specify/` directory
   is either stale or absent. Re-running `specify init` is required
   to restore spec-kit functionality, losing constitution and memory
   state unless carefully preserved.

The root cause: Approach E commits spec files to the feature branch
during development, then strips them at PR time. This means spec
files exist in git history and can be carried forward by rebase or
merge operations.

### Upstream Research Findings

The upstream spec-kit community has the same pain points:

- [Issue #2612](https://github.com/github/spec-kit/issues/2612):
  "Global installation mode" requests separating tooling from project
  state. Maintainer acknowledged complexity, community clearly wants
  it. Approved for contribution.
- [Issue #2681](https://github.com/github/spec-kit/issues/2681):
  "Separate framework assets from project memory" raises the same
  ownership-boundary concern.
- [Issue #1173](https://github.com/github/spec-kit/issues/1173):
  Brownfield documentation request, still open with no solution.
- [PR #1579](https://github.com/github/spec-kit/pull/1579): Adds
  `SPECIFY_SPECS_DIR` env var for external specs directory. Open but
  stale (unmerged, has conflicts). Would enable sibling-directory
  workflows.
- No stealth-mode documentation exists upstream. No `.gitignore`
  template for projects using spec-kit on brownfield/upstream repos.

The `specify` CLI hardcodes `project_root = Path.cwd()` everywhere.
No env var override exists on main. Waiting for upstream changes is
not practical for a near-term solution.

### New Approaches Considered

#### F: git-info-exclude Stealth Mode (Chosen)

Instead of committing spec files and stripping them at PR time, never
commit them at all. Use `.git/info/exclude` to make spec files
invisible to git while keeping them on disk for spec-kit to use.

**Key insight (verified experimentally):** `.git/info/exclude` works
identically to `.gitignore` but is local-only (never committed, never
pushed, never appears in PRs). When spec paths are excluded:

- `git add .` and `git add -A` do NOT stage excluded files
- `git status` does NOT show them as untracked
- Since files are never committed to any branch, rebase and merge
  operations cannot carry them forward
- Files remain on disk, fully accessible to spec-kit (cwd resolution)
- Only `git add -f` (explicit force) can override the exclusion

This makes leaks structurally impossible rather than defended against.

**How it works:**

1. When the detach extension is enabled and `specify init` runs,
   auto-add `.specify/`, `specs/`, `brainstorm/` to
   `.git/info/exclude`. A manual `spex-detach enable` command can
   verify/fix entries for existing clones.
2. During development, spec files live as untracked (excluded) files
   in the working directory. Spec-kit works normally via cwd
   resolution. No `pr/` branch mechanism needed.
3. At `spex-finish` time (when detach is enabled), archive spec
   artifacts to the configured sibling specs repo for version control,
   then finish normally.

**What gets removed:** The entire `pr/` clean-branch-stripping
mechanism (detach subcommand, leak scanning, merge-base diff
filtering). This code is no longer needed because there is nothing
to strip.

**Tradeoff:** Spec files have no version control within the code
repo. The archive to a sibling specs repo provides version control
at feature-completion time. During active development, specs are
unversioned working files. This is acceptable because spec files
rarely change once written, and the archive captures the final state.

#### G: Sibling Directory (Considered, Deferred)

Move all spec artifacts to a sibling directory entirely outside the
code repo. Explored but deferred because:

- Requires `cd` to specs dir for all spec-kit commands (no upstream
  env var override available)
- Would need significant changes to all spex skills to handle
  two-directory navigation
- The `.git/info/exclude` approach achieves the same leak prevention
  with far less disruption

May revisit if upstream adds `SPECIFY_ROOT` env var support.

### Updated Decision

**Approach F (git-info-exclude Stealth Mode)** replaces Approach E.
The `pr/` branch mechanism is removed entirely. The detach extension
becomes a lightweight setup step (write exclude entries) plus an
archive step at finish time.

**Upstream engagement:** Open a discussion on github/spec-kit
proposing a `SPECIFY_ROOT` env var, referencing community demand
from issues #2612, #2681, and #1173. This would enable the sibling
directory approach (G) as a future option.

### Updated Key Requirements

#### Detach extension changes

1. **New: `enable` subcommand** writes `.specify/`, `specs/`,
   `brainstorm/` to `.git/info/exclude`. Idempotent (skips entries
   that already exist). Also called automatically during
   `specify init` when detach extension is active.
2. **New: archive at finish time.** The `before_finish` hook archives
   `.specify/`, `specs/`, and `brainstorm/` to the configured sibling
   specs repo path. Only when detach is enabled.
3. **Removed: `detach` subcommand.** The `pr/` clean-branch mechanism
   is removed. No more merge-base diff, leak scanning, or branch
   switching.
4. **Removed: `verify` subcommand.** No longer needed without the
   `pr/` branch approach.
5. **Removed: `clean-branch-name` subcommand.** No longer needed.
6. **Kept: `archive` subcommand.** Simplified to copy-and-commit
   without the move semantics or branch context.
7. **Kept: `is-enabled` subcommand.** Still needed for other
   extensions to check detach state.

#### Extension integration points

| Hook | Behavior |
|------|----------|
| `specify init` (when detach enabled) | Write `.git/info/exclude` entries |
| `before_finish` (when detach enabled) | Archive specs to sibling repo |

#### Default mode (no detach extension)

No changes. Everything stays in a single directory, committed to the
repo. The detach extension is purely opt-in.

### Open Questions

- Should we also add the exclude entries to the user's global
  gitignore (`~/.gitignore`) as a belt-and-suspenders measure?
- How should the brainstorm skill handle the archive path when
  detach is enabled? Currently it checks `spex-detach-config.yml`
  for `archive.path` and writes brainstorms there.
- Should `spex-detach enable` also verify that no spec files are
  currently tracked (already committed) and warn if so?
- What is the right upstream engagement format: GitHub Discussion,
  Issue, or PR? Given the existing stale PR #1579, a Discussion
  proposing `SPECIFY_ROOT` may get more traction.
