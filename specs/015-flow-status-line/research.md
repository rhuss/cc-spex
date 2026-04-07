# Research: Flow Status Line

## Decision 1: Status Line Script Architecture

**Decision**: Extend `spex-ship-statusline.sh` with a mode switch rather than creating a separate script.

**Rationale**: The status line is already invoked from a single hook entry point. Adding a mode branch (`ship` vs `flow`) in the existing script keeps the integration surface minimal. Both modes share trait display logic, so a single script avoids duplication.

**Alternatives considered**:
- Separate `spex-flow-statusline.sh`: Would require updating the hook configuration and duplicating trait display. Rejected for unnecessary complexity.
- Unified status library sourced by both: Over-engineering for what amounts to two display branches in a ~80-line script.

## Decision 2: State File Rename Strategy

**Decision**: Rename `.spex-ship-phase` to `.spex-state` in all scripts, hooks, skills, and overlays in a single pass.

**Rationale**: The state file is internal (not user-facing, not in any external API). All references are within the spex plugin codebase. A clean rename avoids indefinite backward-compatibility shims. The transition period (FR-015a) only applies to REVIEWERS.md, not the state file itself.

**Files requiring update** (from research):
- `spex/scripts/spex-ship-statusline.sh` (2 refs)
- `spex/scripts/spex-ship-state.sh` (1 ref, plus rename consideration)
- `spex/scripts/hooks/pretool-gate.py` (3 refs)
- `spex/skills/ship/SKILL.md` (multiple refs)
- `.claude/skills/speckit-specify/SKILL.md` (guard section)
- `.claude/skills/speckit-clarify/SKILL.md` (guard section)
- `.claude/skills/speckit-plan/SKILL.md` (guard section)
- `.claude/skills/speckit-tasks/SKILL.md` (guard section)
- `.claude/skills/speckit-implement/SKILL.md` (guard section)
- All overlay files referencing `.spex-ship-phase`

**Alternatives considered**:
- Keep `.spex-ship-phase` name: Misleading for flow mode. Users encountering the file would assume ship-only. Rejected.
- Gradual migration with fallback: Adds complexity for an internal file nobody reads directly. Rejected.

## Decision 3: Review Artifact Split Approach

**Decision**: Each review skill writes its own file (REVIEW-SPEC.md, REVIEW-PLAN.md, REVIEW-CODE.md). The ship pipeline's `verify_stage_artifacts()` function checks for split files with a fallback to REVIEWERS.md during transition.

**Rationale**: Clean artifact detection requires one file per review. The fallback handles in-progress pipelines on branches that started before this change.

**Alternatives considered**:
- Keep REVIEWERS.md with sections: Cannot cleanly detect individual review completion from file existence alone. Rejected.
- Use state file flags instead of artifacts: Would make review state session-dependent, violating SC-002. Rejected.

## Decision 4: Flow State Creation Timing

**Decision**: Create `.spex-state` with `"mode": "flow"` in the speckit-specify skill's Ship Pipeline Guard section (or equivalent insertion point), only when no state file exists or an existing flow state should be overwritten.

**Rationale**: The specify step is always the entry point for manual workflow. Creating state here ensures flow tracking begins at the natural start of work.

**Alternatives considered**:
- Create on any speckit command: Would create orphan state files if user runs `/speckit-plan` without specify. Rejected.
- Require explicit `/spex:flow start`: Adds friction. The whole point is automatic activation. Rejected.

## Decision 5: Trait Display Format

**Decision**: Show trait names as a comma-separated list in square brackets at the end of the status line, e.g., `[superpowers, deep-review]`. Use dim/muted color to avoid competing with milestone/review status.

**Rationale**: Square brackets visually separate traits from the progress display. Comma separation is compact and scannable. Muted color signals "configuration info" rather than "action required."

**Alternatives considered**:
- Icons per trait: No established emoji mapping, would be cryptic. Rejected.
- Separate line: Status line is a single line by design. Rejected.

## Decision 6: Celebration Implementation

**Decision**: Add celebration logic to the verification-before-completion skill (stamp). After all checks pass, display ASCII banner, compute stats from state file and git, show random sign-off, then remove state file.

**Rationale**: Stamp is the terminal step in both flow and ship. Adding celebration here means it works for both modes. Stats computation (duration from `started_at`, commit count from git, review count from artifacts) is straightforward.

**Alternatives considered**:
- Separate celebration script: Over-engineering for a display-only feature. Rejected.
- Celebration in state cleanup: Mixes display concerns with state management. Rejected.
