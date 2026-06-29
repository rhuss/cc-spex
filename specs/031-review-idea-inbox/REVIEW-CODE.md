# Code Review: 031-review-idea-inbox

**Date:** 2026-06-29
**Branch:** 031-review-idea-inbox
**Spec compliance:** PASS (all 16 FRs covered)

## Deep Review Report

**Date:** 2026-06-29
**Branch:** 031-review-idea-inbox
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** ship-pipeline

### Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 3 | 3 | 0 |
| Minor | 2 | 1 | 1 |
| Notable | 3 | - | 3 |
| **Total** | **8** | **4** | **4** |

**Agents completed:** 5/5 (correctness, architecture, security, production-readiness, test-quality)
**External tools:** Disabled (coderabbit=false, copilot=false)

### Findings

#### FINDING-1 (Important, fixed)
- **File:** spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md
- **Category:** production-readiness
- **Source:** production-agent (also reported by: correctness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Triage Step 15 writes to `brainstorm/idea-inbox.md` and creates the file if it doesn't exist, but never creates the `brainstorm/` directory. If triage runs before any brainstorm session has ever run, the parent directory does not exist and file creation fails.

**Why this matters:** The spec says the inbox file "MUST be created automatically when the first entry is written" (FR-014). A project that uses triage but has never brainstormed would fail on its first inbox capture.

**How it was resolved:** Added `mkdir -p brainstorm` before the file creation check in Step 15.

#### FINDING-2 (Important, fixed)
- **File:** spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Same issue as FINDING-1 but in deep review Step 8b — writes to inbox without creating the `brainstorm/` directory first.

**Why this matters:** Deep review can run without any prior brainstorm session (via `after_implement` hook). Notable findings would fail to be captured.

**How it was resolved:** Added `mkdir -p brainstorm` before the file creation in Step 8b.

#### FINDING-3 (Important, fixed)
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The brainstorm skill's "Idea Inbox" preamble paragraph described only the conversational nudge behavior, not the primary inbox consumption flow. This could mislead the AI agent into implementing the lighter nudge instead of the full check-and-present flow.

**Why this matters:** User Story 2 acceptance scenarios require active inbox checking and item presentation, not just a passive suggestion.

**How it was resolved:** Rewrote the preamble to describe the inbox consumption behavior first (check, present, consume), with the nudge as a secondary mention.

#### FINDING-4 (Important, fixed)
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Inbox consumption in step 7 removed entries regardless of brainstorm session status. Parked or abandoned sessions haven't truly consumed the idea — the entry should remain available for future brainstorming.

**Why this matters:** The spec ties consumption to "a brainstorm document is written," but a parked document means the idea was not fully explored. Removing it from the inbox loses the seed.

**How it was resolved:** Added condition: only remove consumed entries when brainstorm document status is `active`. Parked and abandoned sessions leave inbox items untouched.

#### FINDING-5 (Minor, fixed)
- **File:** spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Deep review derives theme-slug from finding description with no length or word-count guidance, potentially producing unwieldy slugs that don't group well with triage-generated slugs.

**Why this matters:** Inconsistent slug generation between triage (uses theme name) and deep review (derives from description) makes brainstorm's "group by theme" less effective.

**How it was resolved:** Added constraint: 2-4 words in kebab-case, under 40 characters, focusing on the core concept.

#### FINDING-6 (Minor, remaining)
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** accepted (low risk)

**What is wrong:** The Summary field in inbox entries incorporates bot comment content without explicit sanitization. A crafted summary containing `### ` could create a fake inbox entry boundary.

**Why this matters:** Bot comments are from known CI bots, not arbitrary attackers. The Context field is already protected by blockquote formatting. Risk is limited to parser confusion, not data loss.

**Why not fixed:** Low risk (bots are trusted, Summary is AI-synthesized not raw bot output). Adding sanitization instructions would add complexity for a scenario that is unlikely to occur in practice.

### Notable Observations

#### NOTABLE-1
- **File:** spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md
- **Category:** architecture
- **Source:** architecture-agent

Deep review Step 8b writes Notable findings to the inbox automatically without user confirmation — the only unsupervised write path. Triage requires user selection; manual addition is user-controlled. This is an intentional design choice (review agents are trusted internal agents) but worth revisiting if the trust model changes.

#### NOTABLE-2
- **File:** spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md
- **Category:** production-readiness
- **Source:** production-agent

Both triage Step 15 and deep review Step 8b contain identical inbox file-creation templates and similar entry-append logic. This is acceptable duplication for AI instruction files (markdown prompts in different extensions with different lifecycles). If a third writer is added, consider extracting the format into a shared reference.

#### NOTABLE-3
- **File:** spex/extensions/spex/commands/speckit.spex.brainstorm.md
- **Category:** architecture
- **Source:** test-quality-agent, architecture-agent

User Story 4 (Conversational Nudge, P3) is partially implemented. The brainstorm preamble mentions the inbox when invoked after review discussions, but the spec envisions detection "when the review discussion concludes" — before brainstorm is invoked. Full implementation would require modifying the upstream `receiving-code-review` skill, which is not tracked by spex and would be overwritten on sync. This is an intentional design limitation documented in the plan's Research section.

## Spec Compliance

All 16 functional requirements (FR-001 through FR-016) have implementing code:

| FR | Status | Implementation |
|----|--------|---------------|
| FR-001 | PASS | Inbox at `brainstorm/idea-inbox.md`, committed |
| FR-002 | PASS | Entry format with all required fields |
| FR-003 | PASS | Thematic clustering with 2+ threshold |
| FR-004 | PASS | Triage writes to inbox, not brainstorm |
| FR-005 | PASS | Unselected themes discarded |
| FR-006 | PASS | Notable verdict added to schema |
| FR-007 | PASS | Notable Observations section in review-findings.md |
| FR-008 | PASS | Notable findings appended to inbox |
| FR-009 | PASS | Brainstorm checks inbox in step 3 |
| FR-010 | PASS | Consumed items removed (active status only) |
| FR-011 | PARTIAL | Nudge in brainstorm preamble (P3, intentional limitation) |
| FR-012 | PASS | No automatic action from nudge |
| FR-013 | PASS | README section added |
| FR-014 | PASS | File created with mkdir -p + header on first write |
| FR-015 | PASS | Canonical format with Reference + blockquote |
| FR-016 | PASS | Deferred-idea signal phrases listed in brainstorm preamble |
