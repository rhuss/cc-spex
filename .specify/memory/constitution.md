<!-- Sync Impact Report
Version: 2.1.1 → 2.2.0 (MINOR: declare flow-back persistence model; clarify generate-directive timing)
Added sections: none
Modified sections:
  - I. Spec-Guided Development: the plan/tasks generate-directive
    (`/speckit-plan`, `/speckit-tasks`) applies before implementation
    begins; after implementation, flow-back edits (speckit-spex-evolve)
    plus converge-appended tasks are the expected path. Declared the
    flow-back persistence model (see the bullet below). Corrected the
    dotted plan/tasks command references to the hyphen form (Naming
    Discipline).
Follow-up TODOs: none
-->

# Spex Plugin Constitution

## Core Principles

### I. Spec-Guided Development

SDD (Specification-Driven Development) is the methodology for significant feature work. It is not a
gate on every code change. Code can change without documentation.

- New features and cross-cutting changes SHOULD follow the SDD
  workflow: specify, plan, tasks, implement.
- Bug fixes, small improvements, and refactors MAY go straight to
  code without a spec.
- Specs define WHAT and WHY. Plans define HOW. But when the code
  tells a clearer story than the docs, the code wins.
- Spec artifacts (plan.md, tasks.md) SHOULD be generated via
  `/speckit-plan` and `/speckit-tasks` for tracked features. This
  generate-directive applies **before implementation begins**. After
  implementation (at least one task complete), plan.md and tasks.md are
  NOT regenerated: `speckit-spex-evolve` flows accepted changes back into
  spec.md and plan.md (supersede/retire markers and dated revision notes),
  and `/speckit-converge` appends any remaining work as traced tasks. This
  preserves completed-task history.
- Persistence model: flow-back
  - This project's post-delivery artifact convention: accepted discoveries
    are reconciled into whichever artifacts they affect, never by
    regeneration that would destroy completed `tasks.md` history.
- Specs and docs are living documents. They do not need to be
  updated for every code change. Drift is acceptable when the
  cost of updating docs exceeds the value.
- Rationale: SDD provides structure for complex work. Applying it
  dogmatically to trivial changes creates overhead that slows
  development without improving quality.

### II. Extension Architecture

Extensions provide commands and lifecycle hooks. They MUST be
self-contained and portable across AI agents.

- Each extension lives in `spex/extensions/<ext-id>/` with an
  `extension.yml` manifest, a `commands/` directory, and optional
  config files.
- Extension commands are markdown files following the
  `speckit.{ext-id}.{command}` naming pattern.
- Extensions register lifecycle hooks (before/after events) in
  their manifest. Hooks fire automatically at spec-kit command
  boundaries.
- Extensions are installed via `specify extension add <path> --dev`
  and managed via `specify extension enable/disable`.
- Rationale: Spec-kit's native extension system provides standardized,
  agent-portable capabilities without custom overlay machinery.

### III. Extension Composability

Extensions MUST be independent and combinable. Enabling one extension
MUST NOT break another.

- Each extension operates through its own directory and manifest.
- Extensions MUST NOT modify each other's files or hooks.
- Multiple hooks on the same lifecycle event execute sequentially
  in the order they appear in `.specify/extensions.yml`.
- Extension dependencies are declared in the manifest's `requires`
  section and validated by spec-kit on enable.
- Rationale: Users enable extensions based on their workflow needs.
  Independence ensures predictable behavior regardless of combination.

### IV. Quality Gates

When working through the spex workflow, quality gates provide
valuable checkpoints. They apply to spec-driven feature work,
not to every code change.

- For spec-driven features: spec review SHOULD run before planning,
  plan review SHOULD run after task generation, code review SHOULD
  run after implementation.
- Verification SHOULD produce evidence before completion claims on
  tracked features.
- When spec and code diverge, prefer updating whichever is wrong
  rather than forcing compliance in one direction.
- Rationale: Quality gates catch real problems in complex feature
  work. They are tools to help, not bureaucracy to satisfy.

### V. Naming Discipline

Tool and command names MUST follow established conventions exactly.

- The CLI tool is `specify` (not speckit, not spec-kit).
- The package is `specify-cli`.
- Slash commands use the `/speckit-*` prefix (this is correct).
- spex skills use the `spex:` prefix.
- Feature branches MUST match the pattern `NNN-feature-name`
  (three-digit prefix, hyphen, lowercase name).
- Rationale: Naming inconsistency causes user confusion and breaks
  script automation. The `specify` vs `speckit` distinction is a
  known source of errors.

### VI. Skill Autonomy

Each skill MUST be self-contained with a clear, single purpose.

- Skills MUST declare their purpose in frontmatter.
- Skills MUST NOT duplicate logic that belongs in another skill.
  Use `{Skill: spex:other-skill}` for delegation.
- Infrastructure skills (spec-kit, init) handle setup.
  Workflow skills handle process. Review skills handle validation.
  These roles MUST NOT be mixed.
- The routing skill (`using-superpowers`) dispatches to workflow
  skills. It MUST NOT contain workflow logic itself.
- Rationale: Autonomous skills are independently testable, replaceable,
  and comprehensible. Tangled dependencies make the plugin fragile.

### VII. State as Scripts

Workflow state management MUST use external shell scripts, not
inline bash snippets in skill markdown files.

- State operations (create, update, query) MUST be implemented
  in dedicated scripts under `spex/scripts/` (e.g.,
  `spex-ship-state.sh`, `spex-flow-state.sh`).
- Skill markdown files MUST delegate to these scripts rather than
  embedding `jq` pipelines or `cat > file` blocks.
- Scripts execute deterministically. AI-interpreted bash snippets
  in markdown are unreliable: they get skipped after context
  compression, ignored at the tail of long skills, or executed
  with subtle variations.
- Scripts are testable in isolation and produce consistent results
  regardless of which AI model interprets the skill.
- Rationale: The flow state file was repeatedly corrupted or not
  created because the AI skipped inline bash at the end of long
  skill files. Moving state management to scripts eliminated
  the entire class of bugs.

## Plugin Architecture Constraints

These constraints govern the structure of the spex plugin codebase.

- **Extension-local scripts**: Commands reference helper scripts via
  `.specify/extensions/<own-ext-id>/scripts/<script>` relative to the
  project root. Scripts are installed alongside commands by
  `specify extension add`. No `$PLUGIN_ROOT` extraction or "Step 0"
  preamble is needed.
- **Hook filtering**: The context hook (`context-hook.py`) MUST only
  fire for `/spex:` prefixed commands. Non-spex commands MUST NOT
  receive spex context injection.
- **File organization**: Extension bundles live in
  `spex/extensions/<ext-id>/` with manifests, commands, and scripts.
  Canonical scripts live in `spex/scripts/` and are synced to
  extension directories via `make sync-scripts`. Hooks live in
  `spex/scripts/hooks/`.
- **Extension installation**: The `spex-init.sh` script and the
  setup workflow (`spex/setup.yml`) install all bundled extensions
  from `spex/extensions/` using `specify extension add <path> --dev`,
  regardless of where the source tree lives (checkout, temporary
  directory, plugin cache).
- **Dual-harness plugin root**: `spex/` is both the Claude Code
  plugin (`spex/.claude-plugin/plugin.json`) and the Codex plugin
  `cc-spex` (`spex/.codex-plugin/plugin.json`, published through
  `.agents/plugins/marketplace.json`). The Codex plugin bundles the
  whole spex source, and its init skill runs the setup workflow from
  the installed tree; it never clones or downloads spex. Codex skills
  live in `spex/codex/skills/` (only `cc-spex-init`), so Claude-only
  skills under `spex/skills/` are not exposed to Codex.
- **Release versions**: `make release` sets the same release version
  in the Claude Code manifests, the Codex manifest
  (`spex/.codex-plugin/plugin.json`) and the setup workflow.
- **No compiled artifacts**: This plugin consists entirely of Markdown
  and Bash. There are no compiled binaries or package dependencies
  beyond `jq` and the `specify` CLI. The only build step is
  `make sync-scripts`, which copies canonical scripts to extension
  directories.

## Development Workflow

The plugin's own development follows these workflow rules.

- **Spec package per feature**: Significant features live in
  `specs/NNN-feature-name/` with spec.md, plan.md, and tasks.md.
- **Branch per feature**: Features get a branch named
  `NNN-feature-name` matching their spec directory.
- **Incremental delivery**: Features are implemented in user-story
  phases. Each phase is independently testable. The MVP (first user
  story) is validated before proceeding to subsequent stories.
- **Code can change without docs**: Bug fixes, refactors, small
  improvements, and exploratory changes do not require spec updates.
  Update docs when it helps, not because a process demands it.
- **Verification**: `make release` runs schema validation and a full
  integration test that installs the plugin from the local marketplace,
  checks all extensions, commands, hooks, and skills are present, then
  cleans up. Run `make install` after testing to restore the plugin.
- **Release process**: Set the version in `VERSION` (remove the `-dev`
  suffix), then run `make release`. This validates, updates
  `marketplace.json`, commits, tags, pushes, creates the GitHub release,
  and bumps `VERSION` to the next dev version automatically.
- **Cross-reference maintenance**: When commands or skills are renamed,
  added, or removed, all cross-references in retained skills SHOULD
  be updated in the same change. `rg` verification helps catch stale
  references.
- **Documentation maintenance**: When adding, removing, or renaming
  extensions, commands, hooks, or workflows, README.md and all
  relevant documentation MUST be updated in the same commit or PR.
  This includes the Bundled Extensions section, Commands Reference
  table, workflow descriptions, and any migration guides. Stale
  documentation misleads users and erodes trust.

## Governance

This constitution provides guidance for plugin development decisions.
Implementation plans SHOULD include a "Constitution Check" section.

- **Amendments** can be made directly when the change is clear.
  Larger governance changes SHOULD be discussed before applying.
- **Violations** encountered during planning SHOULD be noted in the
  plan's "Complexity Tracking" table with brief justification.
- **Compliance reviews** happen during `spex:review-spec` and
  `spex:review-plan` invocations when those gates are used.

**Version**: 2.2.0 | **Ratified**: 2026-02-13 | **Last Amended**: 2026-11-06
