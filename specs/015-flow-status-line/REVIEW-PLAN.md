# Review Guide: Flow Status Line

## What This Spec Does

This feature extends the spex status line (previously ship-mode only) to work during manual workflow ("flow mode"). When a developer runs speckit commands one at a time across sessions, the status line shows which milestones are done, which reviews are done, what step comes next, and which traits are active. It also renames the internal state file, splits the monolithic REVIEWERS.md into per-review files, and adds a celebration moment when stamp passes.

## Bigger Picture

spex currently has two workflow paths: the autonomous `/spex:ship` pipeline and manual command-by-command usage. Ship has always had a status line showing progress. Manual workflow had nothing, which meant developers lost track of where they were, especially across sessions. This feature brings parity by using artifact-based detection (does spec.md exist? does plan.md exist?) rather than session state, so progress survives restarts. The review split is a structural prerequisite: you can't show "which reviews passed" if all three dump into one file. The state file rename from `.spex-ship-phase` to `.spex-state` reflects that the file now serves both modes.

## Spec Review Guide

1. **State file rename scope**: The plan calls for a codebase-wide rename (T001-T007). Are there references outside `spex/` and `.claude/` that might be missed? Check overlay directories, template files, and any documentation that references the state file by name.

2. **Backward compatibility window**: FR-015a requires accepting both REVIEWERS.md and REVIEW-*.md during transition. How long should this window last? Is there a mechanism to eventually remove the fallback, or does it stay forever?

3. **Flow state creation in specify**: T023 creates the state file in the speckit-specify overlay or guard section. Review whether this is the right insertion point. Should it be in the spec-kit script layer (Bash) or the skill layer (Markdown instructions)?

4. **Implementation detection asymmetry**: Three milestones use file existence, but "implement" uses a state file flag. Is the `"implemented": true` approach robust enough? What happens if the state file is deleted mid-implementation but code changes exist?

5. **Trait display density**: With 4 possible traits plus milestones plus reviews plus next step, could the status line become too long for narrow terminals? Is there a truncation or wrapping strategy?

6. **Ship mode trait display**: FR-023 and the clarification say traits show in both modes. The ship status line already has stage info, progress bar, and ask level. Verify the trait append doesn't break the ship line format.

7. **Celebration idempotency**: FR-022 removes the state file after celebration. What if stamp is interrupted between displaying the celebration and removing the file? Could the user see a double celebration on retry?

8. **Performance of flow mode**: The flow status line checks 7 files (3 milestones + 3 reviews + traits config) plus reads the state file and parses JSON. Is this within the 500ms budget on slow filesystems (network mounts, encrypted volumes)?

9. **Review skill output location**: The split review files go in the spec directory. How does each review skill determine the spec directory path? Is it from the branch name, the state file, or a parameter?

10. **Edge case: stale state file**: If a developer abandons a feature branch and comes back weeks later, the state file persists with an old `started_at`. Does the celebration duration stat become misleadingly large? Is that acceptable?

## Areas where I'm less certain

- The plan phases in plan.md (numbered 1-6) don't exactly match the task phases in tasks.md (numbered 1-9). The tasks are more granular, splitting some plan phases into separate task phases. This is fine for execution but could confuse reviewers comparing the two documents.

- The context-hook.py is listed in the project structure as needing modification (state file path), but no task in tasks.md explicitly covers updating context-hook.py. T003 covers pretool-gate.py but context-hook.py may also reference the old state file name.

- The relationship between the ship-guard overlays and the state file rename is covered by T006, but "all overlay files" is vague. An explicit enumeration of which overlay files exist would strengthen confidence.

## Risks and open questions

- **~~Missing task for context-hook.py?~~** Verified: `context-hook.py` does NOT reference `.spex-ship-phase`. No task needed. Risk resolved.

- **Overlay enumeration**: T006 covers exactly 5 files in `spex/overlays/_ship-guard/skills/`: `speckit-specify`, `speckit-clarify`, `speckit-plan`, `speckit-tasks`, `speckit-implement` (each has `SKILL.append.md`). Scope is clear and manageable.

- **Review skill spec directory resolution**: The review skills need to know where to write REVIEW-*.md files. The current REVIEWERS.md is written to the spec directory, but the mechanism for determining that path varies across skills. Ensure consistency.

## Prior Review Feedback

Spec review (REVIEW-SPEC.md) found:
- FR numbering is non-sequential (cosmetic, acknowledged)
- Edge case for malformed `spex-traits.json` not covered (accepted for v1, low risk)
- Both items are optional and do not block planning
