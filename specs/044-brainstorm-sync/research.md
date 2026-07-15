# Research: Brainstorm Directory Sync

## Existing Brainstorm Skill Argument Handling

**Decision**: The brainstorm skill receives arguments via the `ARGUMENTS` variable in the skill markdown. The `--sync` flag is detected by checking if the arguments string contains `--sync`. When detected, the skill short-circuits the normal checklist flow and executes the sync-specific logic.

**Rationale**: This follows the pattern used by other spex skills that accept flags (e.g., `--resume` in ship). No argument parsing library is needed since the skill only checks for the presence of a single flag.

**Alternatives considered**: A standalone command (`speckit-spex-sync`) was considered but rejected because sync is conceptually maintenance of the brainstorm directory, not a separate workflow.

## Brainstorm Document Status Parsing

**Decision**: Parse the `**Status:**` line from the document header using grep. The status value is the text after `**Status:**`, trimmed of whitespace. Handle variations like `**Status**: active`, `**Status:** active (revisited 2026-07-08)`, and `**Status:** abandoned (superseded by #24)`. Extract only the first word as the canonical status.

**Rationale**: All existing brainstorm documents follow this pattern. Parenthetical annotations (like "superseded by #24") are metadata, not the status itself.

**Alternatives considered**: YAML frontmatter was considered but rejected because existing documents use bold markdown metadata, not frontmatter.

## Overview Table Spec Column Parsing

**Decision**: Parse the overview markdown table to extract Spec column values. Each row has format `| NN | date | topic | status | spec | issue |`. The Spec column contains either `-` (no spec) or a spec number like `024`. Use this mapping to supplement slug-based matching.

**Rationale**: The overview table is already maintained by the brainstorm skill and contains curated human-verified spec mappings that are more reliable than slug inference.

**Alternatives considered**: Ignoring the overview table was considered but would miss cases where slug matching fails due to different naming conventions between brainstorm and spec directories.

## Git Mv for File Moves

**Decision**: Use `git mv` to move files from `brainstorm/` to `brainstorm/attic/`. This preserves file history in git.

**Rationale**: Users may want to trace the history of archived brainstorms. `git mv` ensures `git log --follow` works on the moved file.

**Alternatives considered**: Plain `mv` + `git add` would also work but loses the rename tracking signal in git.

## Overview Update Strategy

**Decision**: Selectively remove entries for attic'd documents from the overview rather than doing a full rebuild. Read the overview, remove matching rows from the Sessions table, remove matching `(from #NN)` entries from Open Threads, and write back.

**Rationale**: The overview contains curated content (thread descriptions, parked idea reasons) that would be lost in a full rebuild. The review-spec gate identified this as an important distinction.

**Alternatives considered**: Full rebuild from remaining documents (the approach used by the existing overview update logic) was considered but rejected because it would lose curated thread descriptions and parked idea reasons.
