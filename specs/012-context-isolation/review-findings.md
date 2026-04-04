# Deep Review Findings

**Date:** 2026-04-04
**Branch:** 012-context-isolation
**Rounds:** 0
**Gate Outcome:** PASS
**Invocation:** superpowers

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 4 | - | 4 |
| **Total** | **4** | **0** | **4** |

**Agents completed:** 5/5 (+ 1 external tool)
**Agents failed:** none
**External tools:** CodeRabbit completed (findings in specs/ only, excluded from scope), Copilot not installed

## Findings

### FINDING-1
- **Severity:** Minor
- **Confidence:** 90
- **File:** spex/skills/deep-review/SKILL.md (vs review-code, review-spec, verification-before-completion)
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (by design)

**What is wrong:**
The section header is "Spec Resolution" in deep-review but "Spec Selection" in the other three skills. Functionally identical sections have different names, which hurts searchability.

**Why this matters:**
A developer grepping for "Spec Selection" across skills won't find deep-review's version, and vice versa. Minor discoverability issue.

**How it was resolved:**
Accepted as-is. Deep-review has a different caller context (invoked by review-code or ship, not directly by users), so a slightly different name is reasonable. Can be standardized in a future cleanup pass.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 85
- **File:** spex/skills/deep-review/SKILL.md:25-34
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (by design)

**What is wrong:**
The deep-review Spec Resolution preamble says "If the caller does not provide a spec path" but doesn't mention the "argument" pattern used by the other three skills ("If a spec path is provided as an argument, use it directly").

**Why this matters:**
Minor wording inconsistency. Deep-review is typically invoked by review-code (not directly), so the "argument" framing is less relevant, but the inconsistency could confuse readers.

**How it was resolved:**
Accepted as-is. The difference reflects the actual invocation pattern: deep-review receives spec path from its caller, not from CLI arguments.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 80
- **File:** spex/skills/ship/SKILL.md:456-520
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (harmless redundancy)

**What is wrong:**
The ship skill pre-resolves FEATURE_DIR via `check-prerequisites.sh` before spawning subagents, but the subagents will re-resolve it when they invoke their respective skills. This is redundant.

**Why this matters:**
No functional impact (second resolution returns the same value). The pre-resolution provides clear context in the subagent prompt, which is useful for traceability. If the first resolution fails, the pipeline should handle it gracefully.

**How it was resolved:**
Accepted as-is. The redundancy is benign and improves prompt clarity for the subagent.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/overlays/superpowers/commands/speckit.plan.append.md, speckit.implement.append.md
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (out of spec scope)

**What is wrong:**
Context clear warnings exist after plan review and after implementation, but not after specify (before review-spec). The architecture agent flagged this as an asymmetry in workflow guidance.

**Why this matters:**
The spec explicitly scopes warnings to two transition points (FR-001 and FR-002). Adding a warning after specify would be scope creep. The specify-to-review-spec transition is less critical because the review-spec stage is lightweight and benefits from having the specification context.

**How it was resolved:**
Not a deviation. The spec intentionally omits this transition point. No action needed.
