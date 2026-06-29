# Research: Review Idea Inbox

## Integration Points

### Triage Step 15 (spex-collab extension)

**File**: `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`, lines 473-525

**Current behavior**: Skip if no deferred AND fewer than 3 rejected. Groups findings by theme. Invokes `/speckit-spex-brainstorm` for selected themes. Posts GitHub issue links back to PR.

**Change**: Lower threshold (2+ findings per theme cluster, any verdict mix). Write to inbox file instead of invoking brainstorm. Remove GitHub issue creation from this step (brainstorm handles that when consuming inbox items later).

**Decision**: Replace brainstorm invocation with inbox append
**Rationale**: Decouples capture (triage) from exploration (brainstorm). Ideas accumulate across sessions.
**Alternatives**: Keep brainstorm invocation alongside inbox write — rejected because it creates duplicate paths and defeats the inbox purpose.

### Deep Review Finding Schema

**File**: `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`, lines 256-273

**Current schema**: `severity: Critical|Important|Minor`

**Change**: Add `Notable` to severity enum. Notable findings skip gate check and fix loop. They appear in a dedicated section of review-findings.md and are appended to the inbox.

**Decision**: Notable is a severity level, not a separate classification axis
**Rationale**: Keeping it in the same schema means the merge/dedup pipeline handles Notable findings naturally. Agents use a single classification decision, not two orthogonal ones.
**Alternatives**: Separate `observation` field alongside severity — rejected because it complicates the schema for every finding when most findings aren't Notable.

### Brainstorm Skill Integration

**File**: `spex/extensions/spex/commands/speckit.spex.brainstorm.md`

**Current behavior**: Step 2 checks specs, constitution, commits, brainstorm directory. Step 7 writes brainstorm document.

**Change**: Step 2 also checks `brainstorm/idea-inbox.md`. If entries exist, present them as brainstorm seeds before the normal flow. Step 7 removes consumed entries from inbox after writing brainstorm document.

**Decision**: Inbox check goes in step 2 (explore context), consumption in step 7 (write document)
**Rationale**: Step 2 is the natural "gather context" phase. Step 7 is when we know a brainstorm doc was actually created, so removal is safe.

### Conversational Nudge

**File**: Not a direct code modification. Upstream `receiving-code-review` skill is not tracked by spex.

**Decision**: Implement as documentation guidance (README, help) rather than modifying upstream skill
**Rationale**: Upstream superpowers skills are synced periodically. Direct modifications would be overwritten. The nudge is informational (awareness), not functional (code behavior), so documentation is the right vehicle.
**Alternatives**: Fork `receiving-code-review` into spex — rejected because it creates a maintenance burden for a one-line suggestion.

### README Placement

**Current structure**: ...Workflow → Quick Start → Extensions → Commands → Ship → Deep Review → Multi-Agent → Migration...

**Decision**: New "Idea Capture During Reviews" section goes after "Deep Review" (line 337)
**Rationale**: Idea capture is a review-adjacent feature. It naturally follows the deep review section, which describes the review agents. The new section explains what happens with the insights those agents produce.
