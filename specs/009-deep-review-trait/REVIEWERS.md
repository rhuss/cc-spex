# Review Summary: Deep-Review Trait

**Spec:** specs/009-deep-review-trait/spec.md | **Plan:** specs/009-deep-review-trait/plan.md
**Generated:** 2026-03-28

---

## Executive Summary

The deep-review trait adds automated multi-perspective code review to the spex plugin. Today, when a user completes implementation with the superpowers trait, the `spex:review-code` skill checks whether the code matches the specification. This is valuable but narrow: it catches spec deviations but misses code quality issues like mutation bugs, security gaps, or dead code.

The deep-review trait extends this with a second review stage. After spec compliance passes, five specialized review agents analyze the code independently, each from a different angle: correctness (mutation safety, logic errors), architecture (dead code, duplication), security (injection, secret handling), production readiness (resource leaks, concurrency), and test quality (coverage gaps, weak assertions). Each agent operates in isolation to prevent groupthink, and every finding must include concrete evidence with file and line references.

When agents find Critical or Important issues, an autonomous fix loop applies corrections and re-reviews, running up to three rounds without requiring human intervention. The results are documented in a `review-findings.md` artifact that shows what was found, what was fixed, and what remains. This gives human reviewers a clear picture of what the machine already checked, reducing duplicate review effort.

The trait is designed for flexibility. It works with or without the superpowers trait (when used alone, results are advisory rather than blocking). It supports focus hints so users can steer attention toward specific concerns. When the teams trait is also enabled, all agents run in parallel for faster reviews. Optional integrations with CodeRabbit CLI and GitHub Copilot CLI add external AI perspectives from different models to catch blind spots.

The implementation is entirely in Markdown (a SKILL.md file with embedded agent prompts and orchestration logic) plus a minimal overlay and trait registration. No compiled code, no new dependencies beyond the existing spex infrastructure.

## Review Recipe (30 minutes)

### Step 1: Understand the problem (5 min)
- Read the Executive Summary above
- Skim `spec.md` User Story 1 (the core value proposition)
- Ask: Is multi-perspective review with an autonomous fix loop the right approach for catching code quality issues that spec compliance misses?

### Step 2: Check critical references (10 min)
- Review each item in the **Critical References** table below
- These define the agent prompt design, fix loop mechanics, and gate behavior
- For each: read the referenced section, check the reasoning, flag concerns

### Step 3: Evaluate technical decisions (8 min)
- Review the **Technical Decisions** section below
- Focus on D1 (skill-level trait detection) and D2 (embedded agent prompts)
- Are the rejected alternatives valid? Is the trade-off acceptable?

### Step 4: Validate coverage and risks (5 min)
- Scan the **Risk Areas** table: Are mitigations sufficient?
- Check **Scope Boundaries**: Anything missing from in/out of scope?
- Verify the 5 agent focus areas (FR-020) cover the right concerns

### Step 5: Complete the checklist (2 min)
- Work through the **Reviewer Checklist** below
- Mark items as checked, flag concerns as PR comments

## PR Contents

| Artifact | Description |
|----------|-------------|
| `spec.md` | Feature spec: 5 user stories, 30+ functional requirements, clarifications from review |
| `plan.md` | Implementation plan with 7 design decisions and constitution check |
| `research.md` | Research on agent prompt patterns from Anthropic, AgentCheck, obra/superpowers |
| `data-model.md` | Entity definitions: ReviewAgent, Finding, ReviewRound, ReviewSession with state transitions |
| `quickstart.md` | Usage guide for enabling and using the trait |
| `tasks.md` | 35 tasks across 8 phases (MVP: Phases 1-3) |
| `REVIEWERS.md` | This file |
| `checklists/requirements.md` | Pre-existing spec quality checklist |

## Technical Decisions

### D1: Skill-Level Trait Detection (not overlay-only)
- **Chosen approach:** The review-code skill itself checks for the deep-review trait in `.specify/spex-traits.json` and delegates to the deep-review skill
- **Alternatives considered:**
  - Overlay-only trigger: Rejected because overlays only target command files, not skills. The trait must work when review-code is invoked manually (not through a command overlay)
  - Modifying the overlay system to support skill appends: Rejected as overengineering for one trait
- **Trade-off:** The review-code skill gains one trait-detection branch (minor coupling) but the trait works from every invocation path
- **Reviewer question:** Is the minimal coupling in review-code acceptable, or should a different integration pattern be considered?

### D2: Agent Prompts Embedded in SKILL.md
- **Chosen approach:** All 5 agent prompt templates live inside `deep-review/SKILL.md` as structured sections
- **Alternatives considered:**
  - Separate files per agent: Rejected because the existing pattern is one SKILL.md per skill directory with no auxiliary files
  - Agent prompts in a config file: Rejected as unnecessary indirection for a fixed set of 5 agents
- **Trade-off:** SKILL.md will be large (~500-800 lines) but self-contained and consistent with existing patterns

### D4: Findings Deduplication by File + Line Range + Category
- **Chosen approach:** Match on file path + overlapping line ranges + same issue category, keep the finding with more detail
- **Alternatives considered:**
  - Exact line match only: Rejected because different agents may point to slightly different lines for the same issue
  - Text similarity: Rejected as too complex and fragile
- **Trade-off:** May occasionally fail to deduplicate genuinely different issues at the same location in the same category, but this is safer than false deduplication

### D6: Fix Loop Applies Fixes Without User Approval
- **Chosen approach:** Fully autonomous fixes, user reviews all changes after completion via git diff
- **Alternatives considered:**
  - Per-fix approval: Rejected as defeating the autonomous purpose
  - Batch approval per round: Rejected as slowing the loop significantly
- **Trade-off:** Speed and autonomy over granular control. The 3-round maximum and review-findings.md provide safety bounds

## Critical References

| Reference | Why it needs attention |
|-----------|----------------------|
| `spec.md` FR-020: Five review agents | Defines the core product. Are these the right 5 focus areas? Is anything missing or overlapping? |
| `spec.md` FR-021: Agent prompt requirements | Specifies what every agent prompt must include. This directly determines review quality |
| `spec.md` FR-040 to FR-047: Autonomous fix loop | Complex autonomous behavior. Review the mechanics: fix ordering, staging, re-review scope, conversation context |
| `spec.md` FR-044: Gate behavior by context | Defines blocking vs advisory behavior. Subtle distinction that affects user experience |
| `plan.md` D1: Skill-level trait detection | Integration approach that adds a branch to an existing skill. Architectural trade-off |
| `research.md` R1: Agent prompt patterns | Research from three reference implementations. Patterns chosen will shape review quality |
| `data-model.md` Finding entity | Core data structure for the feature. Verify all fields are necessary and sufficient |

## Reviewer Checklist

### Verify
- [ ] The 5 agent focus areas (FR-020) are distinct with minimal overlap
- [ ] Anti-sycophancy measures (FR-080, FR-081) are sufficient to prevent false positives
- [ ] The fix loop mechanics (FR-040-047) handle edge cases: same-file conflicts, new issues during fixes, round exhaustion
- [ ] Gate behavior (FR-044) is clear for both superpowers and manual contexts
- [ ] The deduplication algorithm (FR-031) handles cross-agent duplicate detection correctly
- [ ] The confidence threshold exception for Critical findings (FR-021: >= 50 vs >= 70) is the right calibration

### Question
- [ ] Is 3 rounds the right maximum for the fix loop? Too many risks thrashing, too few might leave issues
- [ ] Should the Production Readiness agent's Go-specific patterns (goroutine leaks, channels) be generalized for other languages?
- [ ] Is the external tool confidence default of 75 appropriate for both CodeRabbit and Copilot, or should they differ?
- [ ] Given Copilot CLI's 50 premium requests/month free tier (shared pool), should the trait warn users about quota consumption?
- [ ] Are 5 agents the right number? Could correctness and architecture be merged, or does separation improve focus?

### Watch out for
- [ ] SKILL.md file size: at ~500-800 lines, it may hit context limits when loaded as a skill prompt
- [ ] Agent prompt quality: the prompts are the most critical deliverable. Weak prompts produce weak reviews regardless of orchestration
- [ ] Fix loop introducing regressions: fixes applied by the main agent could break working code
- [ ] CodeRabbit CLI output format is undocumented: the `=============` delimiter parsing is based on community observations, not official docs
- [ ] Copilot CLI has no structured output mode: the prompt-engineered format may produce inconsistent results across invocations

## Scope Boundaries
- **In scope:** 5 internal review agents, autonomous fix loop, findings management, teams integration, CodeRabbit + Copilot CLI integration, manual hints, review-findings.md artifact
- **Out of scope:** Custom agent definitions, PR-level review (GitHub comments), runtime/dynamic analysis, non-code artifact review
- **Why these boundaries:** The trait focuses on pre-commit code quality review within the spex workflow. PR integration and custom agents are future enhancements if the core proves valuable

## Naming & Schema Decisions

| Item | Name | Context |
|------|------|---------|
| Trait | `deep-review` | Follows `kebab-case` convention of existing traits |
| Skill | `spex:deep-review` | Follows `spex:` prefix convention |
| Sentinel | `<!-- SPEX-TRAIT:deep-review -->` | Matches existing `SPEX-TRAIT:` pattern |
| Artifact | `review-findings.md` | In spec directory, overwritten per run |
| Severity levels | Critical, Important, Minor | Matches obra/superpowers pattern |
| Agent categories | correctness, architecture, security, production-readiness, test-quality, external | Used for dedup and classification |

## Risk Areas

| Risk | Impact | Mitigation |
|------|--------|------------|
| Agent prompts produce too many false positives | High | Confidence thresholds (70/50), anti-sycophancy instructions, "zero findings = re-read" directive |
| Fix loop introduces new bugs | High | 3-round maximum, re-review after each round, user reviews all changes via git diff |
| SKILL.md too large for context window | Medium | Single file keeps skill self-contained. If too large, agent prompts could be extracted (future) |
| CodeRabbit CLI output format changes | Low | Graceful degradation: errors are logged but don't block internal review |
| Copilot CLI structured output unreliable | Medium | Prompt-engineered format may vary. Parser should handle missing fields gracefully. Falls back to treating entire output as one finding |
| Review takes too long in sequential mode | Medium | SC-003 targets < 10 min for < 2000 LOC. Teams trait provides 2x speedup path |
| Agent scope overlap causes duplicate findings | Medium | Explicit scope gates per agent + deduplication algorithm on file + line range + category |

---
*Share this with reviewers. Full context in linked spec and plan.*
