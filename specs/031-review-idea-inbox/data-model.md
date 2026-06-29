# Data Model: Review Idea Inbox

## Entities

### Inbox Entry

A single idea captured from a review source.

| Field | Format | Required | Description |
|-------|--------|----------|-------------|
| Theme slug | `### <slug>` (H3 heading) | Yes | Kebab-case identifier for the idea theme (e.g., `interface-evolution`, `error-handling-consistency`) |
| Source | `triage` \| `deep-review` | Yes | Which review mechanism captured this idea |
| Date | `YYYY-MM-DD` | Yes | Date the idea was captured |
| PR/Feature | URL or branch name | Yes | Reference to the PR or feature where the idea surfaced |
| Summary | 1-2 sentences | Yes | What the idea is about |
| Context | Quoted text | Yes | Relevant snippet from the review comment or discussion |

### Inbox File

**Path**: `brainstorm/idea-inbox.md`
**Lifecycle**: Created on first write, entries removed on consumption, file persists (may be empty)

```markdown
# Idea Inbox

Ideas captured from code reviews for future brainstorming.

### interface-evolution
- **Source:** triage
- **Date:** 2026-06-29
- **PR/Feature:** https://github.com/org/repo/pull/42
- **Summary:** Adding Profiles() and Refresh() to ProviderInterface breaks external implementations. Need an interface evolution strategy before Phase 2b adds more methods.
- **Context:** "Devin flagged that adding methods to ProviderInterface is a breaking change. We dismissed it (pre-1.0) but Phase 2b will compound this."

### watch-event-semantics
- **Source:** deep-review
- **Date:** 2026-06-29
- **PR/Feature:** 031-review-idea-inbox
- **Summary:** Blocking vs non-blocking sends for watch events is a real design tension that should be resolved before enhanced watch implementation.
- **Context:** "Notable: The current non-blocking send pattern silently drops events under backpressure. This works for the current single-consumer case but will fail when log/event streaming adds multiple consumers."
```

### Theme Cluster (triage internal, not persisted)

A grouping used during triage Step 15 to determine which findings are related.

| Field | Description |
|-------|-------------|
| Theme name | Human-readable theme (e.g., "error handling consistency") |
| Theme slug | Kebab-case version for inbox heading |
| Findings | List of deferred and rejected findings belonging to this theme |
| Deferred count | Number of deferred findings in this cluster |
| Rejected count | Number of rejected findings in this cluster |

**Trigger condition**: `deferred_count + rejected_count >= 2`

### Notable Finding (deep review extension to existing schema)

Extension to the existing finding schema in `speckit.spex-deep-review.run.md`.

| Field | Change |
|-------|--------|
| `severity` | Enum extended from `Critical\|Important\|Minor` to `Critical\|Important\|Minor\|Notable` |

**Notable-specific rules**:
- Does NOT count toward gate check (gate still checks Critical + Important only)
- Does NOT enter the fix loop
- Appears in a dedicated "Notable Observations" section of `review-findings.md`
- Is appended to `brainstorm/idea-inbox.md` after review completion

## Relationships

```
Triage Step 15 ──writes──▶ brainstorm/idea-inbox.md ◀──writes── Deep Review Step 8
                                      │
                                      ▼
                            Brainstorm Skill (step 2)
                                reads + presents
                                      │
                                      ▼
                            Brainstorm Skill (step 7)
                               removes consumed
                                      │
                                      ▼
                           brainstorm/NN-topic.md
```
