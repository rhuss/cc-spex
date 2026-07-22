# Brainstorm: Review Idea Inbox

**Date:** 2026-06-29
**Status:** active

## Problem Framing

Code reviews (bot reviewers like CodeRabbit/Copilot, deep review agents, and human reviewers) frequently surface ideas that are out of scope for the current PR but worth pursuing. These ideas get lost because:

1. **Triage Step 15 rarely triggers.** The brainstorm-deferred-findings step requires 3+ rejected findings per pass. In practice, PRs rarely hit this threshold, so the mechanism is effectively dead code.
2. **Conversational review bypasses triage entirely.** When reviews are processed through discussion rather than the structured triage pipeline, Step 15 never executes.
3. **Deep review has no idea capture.** The 5-agent deep review classifies findings as Critical/Important/Minor and auto-fixes, but has no verdict for design-level observations that aren't bugs. These observations vanish after the review.
4. **The brainstorm skill doesn't mine context.** When invoked after a review discussion, it starts its normal clarification flow from scratch instead of scanning the conversation for review-derived seeds.

The result: reviewers' most valuable contribution (cross-cutting design insights) is the most likely to be discarded.

## Approaches Considered

### A: Triage-Centric with Conversation Nudge

Strengthen the existing triage pipeline: fix Step 15 thresholds, add Notable verdict to deep review, add a conversational nudge to `receiving-code-review`. No new state files or infrastructure.

- Pros: Minimal new infrastructure. Strengthens existing pipeline.
- Cons: Only captures ideas when triage or review skills are actively running. Ideas between sessions are lost. No accumulation across multiple reviews.

### B: Brainstorm Skill Mining

Make the brainstorm skill context-aware: when invoked after a review discussion, scan the conversation for themes before starting the normal flow.

- Pros: Single skill to change. Natural since brainstorm already has conversation context.
- Cons: Only fires on explicit invocation. Reactive, not proactive. Doesn't solve the "ideas get lost because nobody thought to brainstorm" problem.

### C: Idea Inbox (Chosen)

Create a persistent `brainstorm/idea-inbox.md` that collects seeds from multiple sources (triage, deep review, conversational nudge). The brainstorm skill checks the inbox at startup and offers accumulated ideas as seeds. Combine with thematic clustering in triage and a Notable verdict in deep review.

- Pros: Decouples capture from exploration. Ideas accumulate across sessions. Multiple sources feed one inbox. Nothing gets lost even if brainstorm isn't invoked immediately.
- Cons: Another file to manage. Needs manual pruning to avoid staleness.

## Decision

**Approach C: Idea Inbox (Full Package).** The persistent inbox decouples the moment an idea surfaces from the moment someone explores it. Combined with fixes to triage thematic clustering, a new Notable verdict in deep review, and a conversational nudge, this creates a comprehensive idea-capture net across all review workflows.

## Key Requirements

### 1. Idea Inbox (`brainstorm/idea-inbox.md`)

- Committed to repo, survives worktree switches
- Structured markdown with one entry per idea:
  ```markdown
  ### <theme-slug>
  - **Source:** triage | deep-review | conversation
  - **Date:** YYYY-MM-DD
  - **PR/Feature:** <reference>
  - **Summary:** <1-2 sentences>
  - **Context:** <relevant snippet from review comment or discussion>
  ```
- Consumed items are removed when a brainstorm doc is created from them
- The brainstorm skill checks the inbox during step 2 (explore context) and offers accumulated ideas as brainstorm seeds before the normal clarification flow
- If the inbox is empty, brainstorm proceeds normally (no change to existing behavior)

### 2. Triage Step 15 — Thematic Clustering

- Replace the "3+ rejected" threshold with thematic grouping
- Group deferred and rejected findings by theme (interface design, error handling, concurrency, naming, etc.)
- Trigger when any cluster has 2+ findings, regardless of verdict mix (2 deferred, or 1 deferred + 1 rejected, or 2 rejected)
- Selected themes write to the idea inbox instead of invoking brainstorm directly
- Unselected themes are discarded (user explicitly chose not to capture them)

### 3. Deep Review — Notable Verdict

- Add "Notable" alongside Critical/Important/Minor in the deep review agent classification
- Notable = not a bug, but a design-level observation worth revisiting (e.g., "this interface will need to evolve for the next phase", "this pattern will break under concurrent access but current usage is single-threaded")
- Notable findings are collected into a dedicated section of `review-findings.md`
- Notable findings are also appended to the idea inbox with source `deep-review`

### 4. Conversational Nudge in `receiving-code-review`

- When review discussion contains deferred-idea signals ("out of scope", "worth considering later", "design tension", "follow-up", "for a future PR"), end the review discussion with a gentle suggestion
- Suggestion text: "Some ideas surfaced during this review that might be worth capturing. You can add them to the idea inbox (`brainstorm/idea-inbox.md`) or run `/speckit-spex-brainstorm` to explore them."
- No blocking, no auto-action, no auto-writing to inbox from conversation — just awareness
- The user decides whether to manually add items or invoke brainstorm

### 5. README.md Section: Idea Capture During Reviews

- New section in the README explaining the idea capture workflow
- Cover the problem: reviewers surface ideas that don't fit the current scope but are still valuable
- Describe the idea inbox mechanism and how seeds flow in from different review sources:
  - External bot reviewers (CodeRabbit, Copilot) via triage
  - Internal deep review agents via Notable verdict
  - Human reviewers and conversational review via nudge
- Show how to consume inbox items via `/speckit-spex-brainstorm`
- Position near existing review/triage documentation in the workflow section

## Out of Scope

- Inbox staleness/cleanup automation (manual pruning for now)
- Auto-creating GitHub issues from inbox items (happens when brainstorm creates a doc)
- Notification system for inbox growth
- Cross-repo inbox aggregation
- Auto-writing to inbox from conversational review (nudge only, user decides)

## Open Questions

- Should the inbox have a maximum size or age-based pruning suggestion? (e.g., "You have 12 ideas older than 30 days — consider reviewing")
- When multiple review sources flag the same theme, should inbox entries be merged or kept separate with cross-references?
- Should the brainstorm skill auto-group inbox items by theme when presenting them, or show them flat in chronological order?
- How should the inbox interact with the brainstorm overview (`00-overview.md`)? Should consumed items leave a trace in the overview's "Open Threads" section?
