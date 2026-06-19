# Research: Before/After Finish Hook Support

**Date**: 2026-06-19

## Hook Pattern Reference

**Decision**: Use the exact hook-reading boilerplate from spec-kit's core `implement.md` template.
**Rationale**: This pattern is battle-tested across all core commands (implement, specify, plan, tasks, clarify). Using the same pattern ensures consistency and avoids inventing a new mechanism.
**Alternatives considered**: Custom hook logic in finish skill (rejected: breaks extension model), no hooks at all (rejected: misses all paths to finish).

## Hook Execution in spec-kit

**Decision**: Hooks are AI-instruction-driven, not framework-executed. The finish skill's markdown must contain explicit instructions for reading extensions.yml and invoking hooks.
**Rationale**: Confirmed by source code inspection of `specify_cli/extensions.py`. The `register_hooks`, `get_hooks_for_event`, and `execute_hook` methods are API surface for config management. No code path auto-executes hooks at command boundaries. Each command's markdown must include the boilerplate.
**Alternatives considered**: Framework-level hook execution (not available in current spec-kit version).

## after_finish Hook Placement

**Decision**: Execute after_finish hooks after Phase 6 (state cleanup) but before Phase 7 (watch mode).
**Rationale**: Phase 6 is where the feature action (merge/PR/keep) is complete. The after_finish hook for flow-state cleanup should fire at this point. Watch mode (Phase 7) is a post-PR monitoring loop that may run indefinitely; hooks should not wait for it.
**Alternatives considered**: After Phase 7 (too late, watch mode may never end), before Phase 6 (state file still exists, cleanup hook would be premature).
