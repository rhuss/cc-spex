# Brainstorm 02: Spec Evolution and Drift Management

**Date**: 2026-03-03
**Origin**: Observed during antwort project session (specs 034-039)
**Status**: Decision made, implementation pending

## Problem

Specifications describe the system at a point in time. As the codebase evolves, specs drift from reality in three distinct ways:

### Scenario 1: Code changes without a spec

A bug fix or small enhancement changes behavior that a spec described. No new spec is created.

**Example**: The `/builtin/files` to `/v1/files` API path fix in antwort. Spec 034 described endpoints at `/builtin/files`, but the fix moved them to `/v1/files`. No spec was created for this change.

### Scenario 2: A new spec supersedes parts of an earlier spec

A refactoring or enhancement spec changes the architecture that an earlier spec established.

**Example**: Spec 039 (vectorstore-unification) unified `VectorStoreBackend` (defined in spec 018) and `VectorIndexer` (defined in spec 034) into a single `pkg/vectorstore/Backend`. After implementation, specs 018 and 034 describe an architecture that no longer exists.

### Scenario 3: A new spec extends an earlier spec

A feature adds fields, types, or behaviors to entities an earlier spec defined, without changing the original design.

**Example**: Spec 035 (annotations) added `FileID`, `Quote`, `URL`, `Title` fields to the `Annotation` type originally defined in spec 001 (core protocol).

## Decision

Handle each scenario differently:

### Scenario 1: Reverse-update the spec

When code changes happen without a formal spec (bug fixes, small enhancements), the affected specs MUST be updated in-place to reflect the new reality. No "amended by" note needed. The spec is a living document for non-breaking changes.

**Who does it**: The developer making the change (or the AI assistant). Should be part of the commit that makes the code change.

**SDD plugin integration**: The `/sdd:evolve` skill should detect spec-code divergence and offer to update the spec. When run, it compares the spec's description of APIs, types, and behaviors against the actual code and proposes edits to bring the spec in line.

### Scenario 2: Amend the old spec, document in the new spec

When a new spec supersedes parts of an earlier spec:

1. The **new spec** documents what changed and why (the refactoring rationale)
2. The **old spec** gets an amendment header:
   ```markdown
   > **Amended by**: [Spec 039 - Vector Store Unification](../039-vectorstore-unification/spec.md)
   > The VectorStoreBackend interface described here has been unified into
   > `pkg/vectorstore/Backend`. See spec 039 for the current architecture.
   ```
3. The old spec is NOT rewritten. It preserves the original design decisions and rationale, which remain valuable for understanding why the system was built the way it was.

**Who does it**: The amendment should happen as part of the new spec's review. Specifically:
- During `/sdd:review-spec`, when the reviewer checks for dependencies and scope, it should detect that the new spec supersedes parts of existing specs
- The review should flag: "This spec supersedes [spec NNN, section X]. An amendment note should be added to spec NNN."
- The amendment is applied when the new spec is approved

**SDD plugin integration**: Add a check to `/sdd:review-spec`:
1. When processing the spec's Dependencies section, check if any dependency is being replaced or fundamentally changed
2. If so, flag it in the review with a suggested amendment note
3. Optionally, auto-apply the amendment as part of the spec commit

### Scenario 3: No action needed

When a new spec merely extends an earlier one (adds fields, new capabilities), the original spec remains accurate. It just describes a subset of the current system. No amendment needed unless the extension changes the semantics of what the original spec described.

## Implementation in the SDD Plugin

### `/sdd:evolve` (enhanced)

Add a "spec drift detection" mode:

```
/sdd:evolve --check-drift [spec-dir]
```

For each spec:
1. Extract described APIs, types, and interfaces from the spec
2. Compare against actual code (grep for type names, endpoint patterns, etc.)
3. Report divergences:
   - "Spec 034 references `/builtin/files` but code uses `/v1/files`"
   - "Spec 018 describes `VectorStoreBackend` but it's now an alias for `vectorstore.Backend`"
4. Offer to update the spec in-place (scenario 1) or suggest an amendment (scenario 2)

### `/sdd:review-spec` (enhanced)

When reviewing a new spec, add a "supersession check":

1. Parse the Dependencies section
2. For each dependency, check if the new spec changes or replaces anything the dependency defines
3. If yes, add to the review output:
   ```
   ### Supersession Warning
   This spec changes the VectorStoreBackend interface defined in spec 018.
   Recommended: Add an amendment note to spec 018 linking to this spec.
   ```
4. When the spec is approved and committed, auto-apply the amendment notes to superseded specs

### Amendment Format

Standardize the amendment block:

```markdown
> **Amended by**: [Spec NNN - Title](../NNN-name/spec.md) (YYYY-MM-DD)
> Brief description of what changed.
```

Place it immediately after the spec header (before User Scenarios).

## Open Questions

1. Should amendments be tracked in a central "spec changelog" file (like `specs/CHANGELOG.md`), or is the in-spec amendment sufficient?
2. Should the `/sdd:evolve --check-drift` run automatically as part of CI, flagging specs that have drifted?
3. For scenario 3 (extensions), at what point does an extension become significant enough to warrant an amendment? (Judgment call, no rule)

## References

- Antwort specs 018, 034, 035, 039 (the concrete examples)
- Antwort constitution v1.6.0 (Specification-Driven Development section)
- The `/builtin/` to `/v1/` fix commit (scenario 1 example)
