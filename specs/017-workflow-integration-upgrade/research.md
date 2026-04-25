# Research: Spec-Kit 0.7.x Workflow and Integration Capabilities

## Decision: Workflow Engine for Ship Pipeline

**Decision**: Use spec-kit 0.7.4's native workflow engine (`specify workflow`) to replace the procedural ship command.

**Rationale**: The workflow engine provides declarative YAML pipelines with typed inputs, conditional steps, gate steps, `pre_run`/`post_run` hooks, resume functionality, and status tracking. All capabilities were verified through test workflow installation on spec-kit 0.7.4.

**Alternatives considered**:
- Keep procedural ship command (788 lines): Rejected because spec-kit now provides the same functionality natively with less code and better resume semantics.
- Extend the built-in `speckit` workflow: Rejected because it has different gate semantics (interactive approve/reject only) and doesn't support oversight levels, subagent forking, or teams routing.

**Verification**:
- Extension commands as workflow steps: Verified (test workflow with `speckit.git.validate`)
- Conditional step routing: Verified (test workflow with `condition` field)
- Workflow-level hooks: Verified (test workflow with `pre_run`/`post_run`)

## Decision: Integration Management for Init

**Decision**: Use `specify integration install/upgrade` for agent-specific file management instead of custom logic in `spex-init.sh`.

**Rationale**: Spec-kit 0.7.x supports 28+ agent integrations with native directory mapping. The `integration` subcommand handles skill file installation, directory mapping, and upgrade paths.

**Alternatives considered**:
- Keep custom agent detection in init: Rejected because spec-kit handles this natively and maintaining custom logic creates drift risk.

## Decision: Hook Suppression via Marker File with PID

**Decision**: Use `.specify/.spex-workflow-active` JSON file with PID and timestamp. Review commands check PID liveness before suppressing. Init cleans stale markers.

**Rationale**: Extension hook conditions (`extensions.yml`) don't support file-based predicates (all current conditions are `null`). Suppression must happen inside command logic. PID liveness prevents stale markers from silencing hooks after crashes.

**Alternatives considered**:
- Hook condition-based suppression: Rejected because `extensions.yml` conditions don't support file checks.
- Simple marker file without PID: Rejected because crashes would leave stale markers that suppress all future hook-based reviews.

## Decision: Plugin Detection via Configurable Mapping File

**Decision**: Use `spex/plugin-integrations.yml` to define companion plugins with detection paths and injection targets. Validate directories contain `plugin.json` or `.claude-plugin/plugin.json`.

**Rationale**: Keeps plugin knowledge out of the init script code. New plugins are added by editing the mapping file. The `plugin.json` marker is the standard Claude Code plugin identifier.

**Alternatives considered**:
- Hardcoded plugin detection: Rejected because it requires code changes for each new plugin.
- Directory-existence-only detection: Rejected because empty or unrelated directories could false-positive.
