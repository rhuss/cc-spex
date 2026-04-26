<!-- Sync Impact Report
Version: 1.2.0 → 2.0.0 (MAJOR: replace overlay/trait system with spec-kit extensions)
Modified sections:
  - II. Overlay Delegation → II. Extension Architecture
  - III. Trait Composability → III. Extension Composability
  - Plugin Architecture Constraints (updated file organization, replaced overlay application)
  - Version bump to 2.0.0
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
  `/speckit.plan` and `/speckit.tasks` for tracked features.
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

## Plugin Architecture Constraints

These constraints govern the structure of the spex plugin codebase.

- **Plugin root detection**: Commands extract `$PLUGIN_ROOT` from the
  `<spex-context>` system reminder injected by the `UserPromptSubmit`
  hook. Commands MUST include a "Step 0: Resolve Plugin Root" section.
- **Hook filtering**: The context hook (`context-hook.py`) MUST only
  fire for `/spex:` prefixed commands. Non-spex commands MUST NOT
  receive spex context injection.
- **File organization**: Extension bundles live in
  `spex/extensions/<ext-id>/` with manifests and commands. Scripts
  live in `spex/scripts/`. Hooks live in `spex/scripts/hooks/`.
- **Extension installation**: The `spex-init.sh` script installs
  all bundled extensions from `spex/extensions/` using
  `specify extension add <path> --dev`.
- **No compiled artifacts**: This plugin consists entirely of Markdown
  and Bash. There are no build steps, no compiled binaries, no
  package dependencies beyond `jq` and the `specify` CLI.

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
- **Release process**: Bump the version in `.claude-plugin/marketplace.json`,
  run `make release` to validate, then `gh release create v<version>
  --generate-notes`. After the GitHub release, update the version in the
  `cc-rhuss-marketplace` repository to match.
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

**Version**: 2.0.0 | **Ratified**: 2026-02-13 | **Last Amended**: 2026-04-10
