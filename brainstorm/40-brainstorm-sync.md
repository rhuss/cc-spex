# Brainstorm: Brainstorm Directory Sync/Maintenance

**Date:** 2026-07-15
**Status:** active

## Problem Framing

The brainstorm directory accumulates documents over a project's lifetime. After 40+ brainstorm sessions, many are in terminal states (spec-created, abandoned, completed, resolved, decided) but still sit alongside active brainstorms. This creates noise when scanning for current work and makes the overview document bloated with stale open threads. A `--sync` option on the brainstorm skill would perform periodic maintenance to keep the directory focused on current ideation.

## Approaches Considered

### A: Full-scan with interactive confirmation (chosen)

Scan all brainstorm documents, classify by status, cross-reference against specs, present a summary, then move confirmed items to `brainstorm/attic/` after user approval.

- Pros: Safe, transparent, user stays in control. Handles edge cases like mismatched statuses.
- Cons: Interactive, requires user attention. Not scriptable for CI.

### B: Fully automatic, no confirmation

Same scan logic but moves immediately without asking.

- Pros: Fast, one command, scriptable.
- Cons: No safety net for misclassified documents.

### C: Dry-run default with --apply flag

Default produces report only, `--apply` flag executes moves.

- Pros: Safest, report itself is useful.
- Cons: Two-step process adds ceremony for routine maintenance.

## Decision

Approach A: Interactive confirmation. The sync is infrequent maintenance where transparency matters more than automation speed.

## Key Requirements

### Scan and Classification

1. Read every brainstorm document in `brainstorm/` (both numbered `NN-*.md` and unnumbered `.md` files, excluding `00-overview.md` and `idea-inbox.md`)
2. Parse each document's `Status` field from the header metadata
3. Cross-reference against `specs/` directory by filename slug overlap (e.g., `04-rename-to-cc-spex.md` matches `specs/008-rename-to-cc-spex/`)
4. Also check the overview table's Spec column for existing spec mappings
5. Auto-update status to `spec-created` when a matching spec is found but the document's status hasn't been updated

### Classification Rules

- **Attic candidates** (terminal states): `spec-created`, `abandoned`, `completed`, `resolved`, `decided`
- **Keep in main directory**: `active`, `parked`
- Parked items explicitly stay in the main directory since they're intentionally deferred, not done

### Interactive Confirmation

- Present a summary table showing: document number/name, current status, inferred status (if changed), proposed action (move/keep)
- User confirms the batch before any moves happen
- Allow the user to override individual items if needed

### File Operations

- Create `brainstorm/attic/` directory if it doesn't exist
- Move confirmed documents to `brainstorm/attic/` (preserving filenames)
- Remove open threads from the overview that belong to attic'd brainstorms
- Regenerate the overview from remaining documents (same idempotent rebuild as the existing overview update)
- Commit the result

### Scope Boundaries

- Does NOT read spec file content for brainstorm references (only filename matching)
- Does NOT modify brainstorm document content (only moves files)
- Does NOT provide a non-interactive/automated mode
- Does NOT touch `idea-inbox.md`

## Open Questions

- Should `--sync` also validate that "active" brainstorms without recent git activity are flagged as potentially stale?
- Should the attic directory preserve any index file of its own for historical reference?
- Should `--sync` be its own standalone command rather than a flag on the brainstorm skill?
