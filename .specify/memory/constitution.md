<!-- Sync Impact Report
Version: 1.1.0 → 1.2.0 (MINOR: add release process, update verification to reflect integration tests)
Modified sections:
  - Development Workflow (added release process, updated verification from manual to automated)
Templates validated:
  - .specify/templates/plan-template.md ✅ (Constitution Check section present)
  - .specify/templates/spec-template.md ✅ (no changes needed)
  - .specify/templates/tasks-template.md ✅ (no changes needed)
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

### II. Overlay Delegation

Overlay files MUST delegate to skills. They MUST NOT inline
discipline logic.

- Each overlay file MUST be under 30 lines.
- Overlays MUST contain a sentinel marker (`<!-- SPEX-TRAIT:name -->`)
  for idempotent application.
- Overlays MUST use `{Skill: spex:skill-name}` references to invoke
  behavior, not embed the behavior directly.
- Overlays append to spec-kit command or template files. They do not
  replace content.
- Rationale: Small overlays are auditable, composable, and resistant
  to merge conflicts. Inlined logic creates maintenance burden and
  makes trait combinations unpredictable.

### III. Trait Composability

Traits MUST be independent and combinable. Enabling one trait MUST NOT
break another.

- Each trait operates through its own overlay directory
  (`spex/overlays/<trait>/`).
- Traits MUST NOT modify each other's overlay files.
- Multiple overlays targeting the same command file coexist via
  sequential appending, each behind its own sentinel marker.
- Trait enablement and disablement MUST go through `spex-traits.sh`.
  Direct file editing is not supported.
- Rationale: Users enable traits based on their workflow needs.
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
- Slash commands use the `/speckit.*` prefix (this is correct).
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
- **File organization**: Skills live in `spex/skills/<name>/SKILL.md`,
  overlays in `spex/overlays/<trait>/{commands,templates}/`, scripts in
  `spex/scripts/`. There is no `spex/commands/` directory; all user-facing
  and internal skills use the unified skills format.
- **Overlay application**: The `spex-traits.sh apply` function handles
  all overlay application. It validates target files exist before
  appending, uses sentinel markers for idempotency, and reports
  applied vs. skipped counts.
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
  checks all commands, skills, hooks, and overlays are present, then
  cleans up. Run `make install` after testing to restore the plugin.
- **Release process**: Bump the version in both
  `.claude-plugin/marketplace.json` and `spex/.claude-plugin/plugin.json`
  (plugin.json wins at install time). Run `make release` to validate,
  then `gh release create v<version> --generate-notes`. After the
  GitHub release, update the version in the `cc-rhuss-marketplace`
  repository to match.
- **Cross-reference maintenance**: When commands or skills are renamed,
  added, or removed, all cross-references in retained skills SHOULD
  be updated in the same change. `rg` verification helps catch stale
  references.

## Governance

This constitution provides guidance for plugin development decisions.
Implementation plans SHOULD include a "Constitution Check" section.

- **Amendments** can be made directly when the change is clear.
  Larger governance changes SHOULD be discussed before applying.
- **Violations** encountered during planning SHOULD be noted in the
  plan's "Complexity Tracking" table with brief justification.
- **Compliance reviews** happen during `spex:review-spec` and
  `spex:review-plan` invocations when those gates are used.

**Version**: 1.2.0 | **Ratified**: 2026-02-13 | **Last Amended**: 2026-04-03
