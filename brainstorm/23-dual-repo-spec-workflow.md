# Brainstorm: Dual-Repo Spec Workflow (Specs Repo + Code Fork)

**Date:** 2026-06-23
**Status:** active
**Revisited:** 2026-06-24

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
