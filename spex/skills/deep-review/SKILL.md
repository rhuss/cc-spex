---
name: deep-review
description: Multi-perspective code review with autonomous fix loop - dispatches 5 specialized review agents, merges findings, auto-fixes Critical/Important issues
---

# Deep Review: Multi-Perspective Code Review

## Overview

This skill orchestrates a multi-perspective code review using five specialized review agents. Each agent analyzes code from a distinct angle (correctness, architecture, security, production readiness, test quality). Findings are merged, deduplicated, and classified by severity. Critical and Important findings trigger an autonomous fix loop (up to 3 rounds). Results are documented in `review-findings.md`.

**This skill is invoked by `spex:review-code` when the `deep-review` trait is enabled.**

## Prerequisites

The caller (review-code or ship) may provide these values. When not provided, the deep-review skill resolves them itself:

1. **Stage 1 result**: spec compliance score (or null if no spec)
2. **Invocation context**: `superpowers` or `manual`
3. **Hint text**: optional focus area from user (or null)
4. **External tool settings**: `{coderabbit: true/false, copilot: true/false}` (see resolution below)
5. **Spec path**: path to spec.md (or null)
6. **Feature directory**: path to the spec directory for artifact output

### External Tool Settings Resolution

If external tool settings are provided by the caller, use them directly. If not (e.g., when invoked directly by `spex:ship` or manually), resolve from config:

```bash
# Read config defaults (all default to true if key is missing)
DEFAULT_ENABLED=$(jq -r '.external_tools.enabled // true' .specify/spex-traits.json 2>/dev/null)
DEFAULT_CODERABBIT=$(jq -r '.external_tools.coderabbit // true' .specify/spex-traits.json 2>/dev/null)
DEFAULT_COPILOT=$(jq -r '.external_tools.copilot // true' .specify/spex-traits.json 2>/dev/null)
```

```
Resolution:
  coderabbit = DEFAULT_ENABLED && DEFAULT_CODERABBIT
  copilot    = DEFAULT_ENABLED && DEFAULT_COPILOT
```

This ensures CodeRabbit and Copilot are enabled by default regardless of how deep-review is invoked.

## Orchestration Flow

### Step 1: Determine Changed Files

Identify the files to review:

```bash
# Get the main branch name
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

# Files changed between main branch and HEAD
git diff --name-only "${MAIN_BRANCH}...HEAD" 2>/dev/null

# Uncommitted changes (staged + unstaged)
git diff --name-only HEAD 2>/dev/null
git diff --name-only --cached 2>/dev/null
```

Combine all results into a deduplicated list. Filter to only source code files (exclude binary, images, lock files). **Exclude files under `specs/` and `brainstorm/`** as these are spec artifacts, not implementation code.

**For re-review rounds (fix loop):** narrow scope to only files modified by the most recent fix round:
```bash
# Files changed since last staging
git diff --name-only --cached 2>/dev/null
```

### Step 2: Detect External Tools

Check for optional external review CLIs, respecting the external tool settings from the caller:

```bash
# Only check if the tool is enabled in settings
# CodeRabbit (skip if coderabbit setting is false)
which coderabbit >/dev/null 2>&1 && echo "CODERABBIT_AVAILABLE=true"

# GitHub Copilot CLI (skip if copilot setting is false)
which copilot >/dev/null 2>&1 && echo "COPILOT_AVAILABLE=true"
```

**External tool resolution:**
1. Use the external tool settings from Prerequisites (either caller-provided or self-resolved from config)
2. If `coderabbit` is `false`, skip CodeRabbit detection entirely
3. If `copilot` is `false`, skip Copilot detection entirely
4. If a tool is enabled in settings but not installed, proceed silently without it

No error or warning if tools are not found or disabled. Proceed with internal agents only.

### Step 3: Dispatch Review Agents

**Check for teams trait:**

Read `.specify/spex-traits.json` and check if `teams` is enabled.

**Sequential mode** (teams NOT enabled):
- Dispatch each agent one at a time using the Agent tool
- Each agent gets a fresh, isolated context (no session history)
- Report progress after each agent completes:
  ```
  Agent 1/5: Correctness... done, N findings
  Agent 2/5: Architecture & Idioms... done, N findings
  ...
  ```

**Parallel mode** (teams IS enabled):
- Dispatch all 5 agents in a single message using multiple Agent tool calls
- Each agent runs in isolated context
- Report progress as each agent completes:
  ```
  Agent completed: Security... 2 findings
  Agent completed: Test Quality... 0 findings
  ...
  ```

**For each agent dispatch**, use the Agent tool with:
- `subagent_type: "general-purpose"`
- The full agent prompt (from the Agent Prompts section below)
- Include the list of changed files and their contents
- **Include the spec text** (spec.md content, if available). Agents need the spec to check code behavior against requirements. Without it, they can only find code-level issues, not spec compliance gaps.
- Include the hint text (if provided) as additional review focus

### Step 4: Dispatch External Tools (if available)

**CodeRabbit** (if available):
```bash
# Initial review (Stage 2): review all changes (committed branch diff + uncommitted work)
coderabbit review --agent --type all --no-color 2>&1

# Fix loop re-review rounds: review only uncommitted fixes
coderabbit review --agent --type uncommitted --no-color 2>&1
```
The `--agent` flag produces structured, detailed findings with rationale (preferred over `--prompt-only` which only shows prompts).

Parse output:
1. Check for "Review completed" (no issues found)
2. Split on `=============` delimiters
3. For each block: extract file, line, severity keyword, description, and **rationale/explanation**
4. **Discard findings for files under `specs/`** (spec artifacts are not code to review)
5. Map severity: critical -> Critical, major -> Important, minor -> Minor
6. Set category = "external", source_agent = "coderabbit", confidence = 75
7. **Preserve the full rationale** from CodeRabbit output for inclusion in review-findings.md

**Copilot CLI** (if available):
```bash
copilot -s -p "Review the following git diff for bugs, security issues, and code quality problems. Output ONLY a structured list of findings. For each finding use this exact format:

### FINDING
- Severity: Critical|Important|Minor
- File: <relative path>
- Line: <number>
- Description: <what is wrong and how to fix it>

End each finding with ---

$(git diff HEAD)" 2>&1
```
Parse output:
1. Split on "### FINDING" markers
2. For each block: extract Severity, File, Line, Description fields
3. **Discard findings for files under `specs/`** (spec artifacts are not code to review)
4. Set category = "external", source_agent = "copilot", confidence = 75

**Error handling for external tools:**
If a tool times out, crashes, or returns an error:
- Log the failure (tool name, error reason) for inclusion in review-findings.md
- Continue with findings from internal agents and any other working tools
- Do NOT block the review

### Step 5: Merge and Deduplicate Findings

1. Collect all findings from internal agents and external tools
2. Normalize to common schema:
   ```
   {
     id: "FINDING-N",
     severity: Critical|Important|Minor,
     confidence: 0-100,
     file: "relative/path",
     line_start: N,
     line_end: N,
     category: correctness|architecture|security|production-readiness|test-quality|external,
     description: "what is wrong",
     rationale: "why it matters",
     fix: "how to fix it",
     source_agent: "agent-name",
     also_reported_by: [],
     external_rationale: "full rationale from external tool (CodeRabbit/Copilot), or null",
     resolution: "pending",
     round_found: N
   }
   ```
3. Sort by file path, then line number
4. Deduplicate: for each pair of findings where:
   - Same file path AND
   - Overlapping line ranges (A.line_start <= B.line_end AND B.line_start <= A.line_end) AND
   - Same category
   Then: keep the finding with the longer description, add the other's source_agent to `also_reported_by`, use the higher severity and confidence
5. Assign sequential IDs to merged findings

### Step 6: Gate Check

Count findings by severity:
- **Critical count**: findings with severity = Critical
- **Important count**: findings with severity = Important
- **Minor count**: findings with severity = Minor

**Gate logic:**
- If Critical + Important = 0: **GATE PASS**
- If Critical + Important > 0: proceed to fix loop (or fail if max rounds reached)

### Step 7: Autonomous Fix Loop

**Maximum 3 rounds.**

For each round:
1. Report: `Fix round N/3: N Critical + N Important findings to address`
2. Collect all Critical and Important findings, sorted by file
3. For each file with findings, sort findings by line number **descending** (reverse order to prevent line shifts)
4. Apply each fix:
   - Read the file
   - Apply the fix suggestion at the specified location
   - The main conversation agent performs fixes (not review agents)
5. Stage all changes: `git add <modified files>`
6. Report: `Fix round N/3: applied N fixes, re-reviewing...`
7. Re-dispatch review agents on **only the modified files** (narrowed scope)
8. Merge new findings with existing Minor findings
9. Gate check:
   - If Critical + Important = 0: **GATE PASS**, exit loop
   - If round < 3: continue to next round
   - If round = 3: **GATE FAIL**, exit loop

**No user approval needed.** Fixes are applied autonomously. The user reviews all accumulated changes after the loop completes via `git diff`.

### Step 8: Write review-findings.md

Write `specs/<feature>/review-findings.md` (overwrite if exists):

```markdown
# Deep Review Findings

**Date:** YYYY-MM-DD
**Branch:** branch-name
**Rounds:** N
**Gate Outcome:** PASS|FAIL
**Invocation:** superpowers|manual

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | N | N | N |
| Important | N | N | N |
| Minor | N | - | N |
| **Total** | **N** | **N** | **N** |

**Agents completed:** 5/5 (+ N external tools)
**Agents failed:** [list if any]

## Findings

### FINDING-1
- **Severity:** Critical
- **Confidence:** 85
- **File:** path/to/file.go:142-148
- **Category:** correctness
- **Source:** correctness-agent (also reported by: coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
[Describe the issue clearly. What specific code pattern, logic error, or
vulnerability was found? Include the relevant code snippet if it helps
understanding.]

**Why this matters:**
[Explain the impact. What could go wrong if this is not fixed? Is it a
runtime error, data corruption risk, security exposure, or maintenance
burden? Be specific about the failure scenario.]

**How it was resolved:**
[If fixed: explain what was changed and why this fix is correct.
If remaining: explain what needs to happen to resolve it.]

[If CodeRabbit or Copilot reported this finding, include their analysis:]

**External tool analysis (CodeRabbit):**
> [Preserve the full rationale from CodeRabbit's output. This gives
> reviewers the external AI's perspective, which may differ from or
> complement the internal agent's analysis.]

### FINDING-2
[Same structure. Every finding gets the full treatment.]

...

## Remaining Findings

[If gate failed, list unresolved findings here with the same detailed
format. Explain why they could not be auto-fixed and what human action
is needed.]
```

### Step 9: Append Deep Review Report to REVIEWERS.md

After writing `review-findings.md`, append a **Deep Review Report** section to `REVIEWERS.md`. This gives human reviewers a quick summary of what the automated review covered, what it found and fixed, and where human attention is still needed.

**If REVIEWERS.md does not exist**, create it with just this section.

**Append the following to REVIEWERS.md:**

```markdown

---

## Deep Review Report

> Automated multi-perspective code review results. This section summarizes
> what was checked, what was found, and what remains for human review.

**Date:** YYYY-MM-DD | **Rounds:** N/3 | **Gate:** PASS|FAIL

### Review Agents

| Agent | Findings | Status |
|-------|----------|--------|
| Correctness | N | completed |
| Architecture & Idioms | N | completed |
| Security | N | completed |
| Production Readiness | N | completed |
| Test Quality | N | completed |
| CodeRabbit (external) | N | completed/skipped/failed |
| Copilot (external) | N | completed/skipped/failed |

### Findings Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | N | N | N |
| Important | N | N | N |
| Minor | N | - | N |

### What was fixed automatically

[Brief summary of the most significant fixes applied during the fix loop.
Group by theme rather than listing every finding. E.g., "Fixed 3 resource
cleanup issues in the HTTP handler (correctness agent) and removed 2 unused
imports (architecture agent)."]

### What still needs human attention

[If gate PASSED with zero remaining: "All Critical and Important findings
were resolved. N Minor findings remain (see [review-findings.md](review-findings.md)
for details). No further review action needed, but reviewers may want to check
the Minor findings during code review."]

[If gate FAILED or Minor findings remain, list what needs attention as
questions:]

- [Finding or area framed as question, e.g. "The security agent flagged
  input validation at `handler.go:42`. Is the current sanitization
  sufficient for production use?"]
- [Another area needing human judgment]

[If all findings were resolved:]
"No unresolved findings. The automated review covered correctness, architecture,
security, production readiness, and test quality across N changed files."

### Recommendation

[One of:]
- "All findings addressed. Code is ready for human review with no known blockers."
- "N Minor findings remain. Consider reviewing them during code review but they
  are not blocking."
- "N Critical/Important findings could not be auto-fixed. Human review and manual
  fixes are recommended before merging. See [review-findings.md](review-findings.md)
  for details."
```

**Constraints:**
- Keep this section factual and concise (200-400 words max)
- The "What was fixed" section should summarize, not list every finding
- The "What still needs human attention" section should frame remaining items as questions where possible
- Do NOT repeat the full findings here (that's what [review-findings.md](review-findings.md) is for)
- Include external tools in the agent table even if skipped (mark as "skipped" with reason)
- **Hyperlink all references.** Link to [review-findings.md](review-findings.md), [spec.md](spec.md), and [plan.md](plan.md) using relative paths. Reference specific code files with backtick paths.

### Step 10: Report Gate Outcome

**Superpowers context (gate is blocking):**
- **PASS**: "Deep review passed. N findings found, N fixed. Proceeding to verification."
- **FAIL**: "Deep review failed after N rounds. N Critical/Important findings remain. Review `review-findings.md` for details. Implementation cannot proceed to verification."

**Manual context (gate is advisory):**
- **PASS**: "Deep review passed. N findings found, N fixed. See `review-findings.md` for details."
- **FAIL**: "Deep review completed with N remaining Critical/Important findings after N rounds. See `review-findings.md` for details. You may proceed at your discretion."

---

## Finding Output Schema

Each review agent MUST return findings in this exact format:

```markdown
## Findings

### FINDING-1
- **Severity**: Critical|Important|Minor
- **Confidence**: 0-100
- **File**: relative/path/to/file.ext
- **Lines**: start-end
- **Category**: [agent's category]
- **Description**: [what is wrong]
- **Rationale**: [why it matters, with evidence from the code]
- **Fix**: [concrete fix suggestion with code if applicable]

### FINDING-2
...

## Self-Verification
- [ ] Each finding has file:line evidence from actual code I read
- [ ] No findings invented for code that is actually clean
- [ ] No duplicate findings (same issue reported twice)
- [ ] Confidence scores reflect my actual certainty, not padding
- [ ] If I found zero issues, I re-read the code a second time to confirm
- [ ] Every finding includes a concrete, implementable fix
- [ ] If a spec was provided, I checked my findings against specific FR/NFR requirements
- [ ] I checked boundary/last-iteration behavior in all loops and retry logic
```

If an agent finds no issues after careful review, it MUST return:

```markdown
## Findings

No issues found. Code was reviewed twice to confirm.

## Self-Verification
- [x] Re-read code a second time after initial zero-finding pass
- [x] Confirmed no issues in my focus area
```

---

## Agent Prompts

### Common Preamble (included in every agent prompt)

The following instructions are prepended to every agent's prompt:

```
IMPORTANT INSTRUCTIONS - READ BEFORE REVIEWING:

1. ANTI-SYCOPHANCY: Do NOT start with praise. Do NOT say "Great implementation!",
   "Nice work!", or any positive affirmation. Start directly with your findings.
   Zero findings is a red flag - if you find nothing, re-read the entire codebase
   a second time before confirming zero findings.

2. DISTRUST: Do NOT trust the implementer's report, comments, or commit messages.
   Verify EVERYTHING by reading the actual code. Comments may be wrong. Variable
   names may be misleading. Test names may not match what they test.

   ISOLATION: Do NOT read git log, commit messages, brainstorm documents, or
   plan.md/tasks.md. These reveal implementation intent and bias your review.
   Review the CODE and the SPEC only. Judge what was built, not what was intended.

3. DO NOT trust test results as proof of correctness. Read the actual assertions.
   A passing test with weak assertions proves nothing. Verify what is actually
   being tested, not what the test name claims.

4. FAILURE MODES - You MUST NOT:
   - Inflate nits to fill a quota. If the code is clean in your area, say so.
   - Invent issues that don't exist. Every finding must cite specific code.
   - Repeat the same finding in different words.
   - Report issues outside your designated scope (see your role gate below).

5. CONFIDENCE SCORING: Rate every finding 0-100.
   - Only report findings with confidence >= 70
   - EXCEPTION: Critical findings may be reported at confidence >= 50
   - Be honest about uncertainty. 60% confidence on a real issue is better
     than 95% confidence on a manufactured one.

6. EVERY FINDING MUST INCLUDE:
   - File path and line number(s)
   - What is wrong (specific, not vague)
   - Why it matters (impact if not fixed)
   - How to fix it (concrete suggestion, not "consider improving")

7. LANGUAGE AWARENESS: Adapt your checklist based on the programming languages
   detected in the changed files. For mixed-language changes, apply language-specific
   checks for each language present.

8. OUTPUT FORMAT: Use the Finding Output Schema exactly as specified. Do not
   deviate from the format. Your output will be parsed programmatically.

9. SPEC AWARENESS: If a spec (spec.md) is provided, cross-check the code
   against specific requirements. For each functional requirement (FR-NNN),
   verify the code implements exactly what the spec says, not more, not less.
   Flag mismatches as findings. Common spec compliance gaps:
   - Code handles a broader or narrower set of cases than the spec defines
   - Metrics or observability the spec requires but code doesn't expose
   - Error codes or status codes that differ from the spec
   - Behavioral differences on edge cases (last iteration, empty input, etc.)
```

### Agent 1: Correctness

```
You are the CORRECTNESS REVIEW AGENT.

YOUR ROLE: You ARE responsible for finding bugs, logic errors, and correctness issues.
YOUR SCOPE: Mutation safety, shared references, logic errors, resource cleanup,
error path correctness, off-by-one errors, null/nil handling, type confusion.

YOU ARE NOT RESPONSIBLE FOR: Code style, naming conventions, documentation quality,
performance optimization, test coverage, security vulnerabilities, or architecture
decisions. Those belong to other agents. Stay in your lane.

CHECKLIST - Check each item against the code:

For all languages:
- [ ] Shared mutable state: Are references copied before mutation? Are slices/arrays
      cloned before passing to goroutines/threads/async functions?
- [ ] Error paths: Do all error returns clean up resources (close files, release locks,
      cancel contexts)? Are errors propagated correctly (not silently swallowed)?
- [ ] Logic errors: Are conditions correct (not inverted)? Are loops bounded?
      Are edge cases handled (empty input, single element, max values)?
- [ ] Null/nil safety: Can any dereference panic? Are optional values checked
      before use? Are map lookups verified?
- [ ] Resource lifecycle: Are all opened resources (files, connections, channels)
      properly closed? In the right order? In defer/finally blocks?
- [ ] Concurrency: Are shared variables protected? Can race conditions occur?
      Are channels properly drained on cancellation?
- [ ] Last-iteration behavior: In loops with retries, attempts, or pagination,
      does the final iteration behave correctly? Common bugs: sleeping after the
      last attempt, returning a generic error instead of the original, off-by-one
      in attempt counting, unnecessary work on the last pass.
- [ ] Boundary correctness: Does the code match the spec's exact boundaries?
      If the spec says "retry on 502/503/504", does the code retry exactly
      those, not all 5xx? If the spec says "max 3 attempts", is it 3 not 4?

For Go specifically:
- [ ] Slice append in loops: Does `append` modify a shared backing array?
- [ ] Goroutine variable capture: Are loop variables captured by value, not reference?
- [ ] Context cancellation: Is context.Cancel() called in defer?
- [ ] Error wrapping: Are errors wrapped with %w for proper unwrapping?

For Python specifically:
- [ ] Mutable default arguments: Are lists/dicts used as default parameters?
- [ ] Iterator exhaustion: Are generators consumed only once when multiple reads needed?
- [ ] Exception handling: Are bare `except:` clauses catching too broadly?

For JavaScript/TypeScript specifically:
- [ ] Async/await: Are promises properly awaited? Can unhandled rejections occur?
- [ ] Closure variable capture: Are `var` variables captured in closures inside loops?
- [ ] Type narrowing: After type guards, is the narrowed type used correctly?

For Bash specifically:
- [ ] Unquoted variables: Can word splitting cause unexpected behavior?
- [ ] Exit codes: Are command failures checked? Is `set -e` or explicit checks used?
- [ ] Subshell variable scope: Are variables set in subshells expected in parent?
```

### Agent 2: Architecture & Idioms

```
You are the ARCHITECTURE & IDIOMS REVIEW AGENT.

YOUR ROLE: You ARE responsible for finding structural issues, code smells, and
maintainability problems.
YOUR SCOPE: Dead code, unnecessary complexity, duplication that will diverge,
misleading naming, comment accuracy, abstraction problems, YAGNI violations.

YOU ARE NOT RESPONSIBLE FOR: Bug detection, security analysis, performance profiling,
test coverage, or production operations concerns. Those belong to other agents.

CHECKLIST - Check each item against the code:

- [ ] Dead code: Are there functions, methods, variables, imports, or branches
      that are never called/used? Are there commented-out code blocks that should
      be deleted (git history preserves them)?
- [ ] Unnecessary complexity: Are there abstractions with only one implementation?
      Interfaces with one implementor? Factories that construct one type?
      Wrapper functions that add no value?
- [ ] Duplication: Is there copy-pasted code that will diverge as the codebase
      evolves? (Three similar lines are fine; three similar 20-line blocks are not.)
      Note: intentional duplication for clarity is acceptable. Flag only duplication
      that will become a maintenance burden.
- [ ] Misleading naming: Do function/variable names accurately describe what they
      do? Are there names that suggest one behavior but implement another?
      Are boolean variables named as questions (isReady, hasPermission)?
- [ ] Comment accuracy: Do comments match the code they describe? Are there
      TODO/FIXME comments that should be addressed or tracked? Are there comments
      that explain "what" (redundant) instead of "why" (valuable)?
- [ ] Abstraction level: Are functions doing work at mixed abstraction levels
      (high-level orchestration mixed with low-level byte manipulation)?
- [ ] YAGNI: Is there code written for hypothetical future requirements that
      are not in the current spec? Speculative generality?
- [ ] Convention adherence: Does the new code follow the patterns established
      in the existing codebase? Or does it introduce a new pattern where one
      already exists?
- [ ] State machine completeness: For any state machine (circuit breaker,
      retry state, connection lifecycle, etc.), are ALL transitions covered?
      Check both success and failure paths. Every transition should be
      observable (logged, metriced, or tested). Missing transitions on the
      success path are a common blind spot.
- [ ] Observability completeness: If the spec requires specific metrics,
      counters, or log entries, verify they are actually exposed. Check that
      every metric the spec names has a corresponding implementation, not
      just the ones on the error path.
```

### Agent 3: Security

```
You are the SECURITY REVIEW AGENT.

YOUR ROLE: You ARE responsible for finding security vulnerabilities and unsafe patterns.
YOUR SCOPE: Input validation, injection risks, secret handling, authentication/
authorization patterns, RBAC scope, CRD/CEL validation gaps, cryptographic misuse.

YOU ARE NOT RESPONSIBLE FOR: Code correctness, architecture decisions, performance,
test quality, or code style. Those belong to other agents.

CHECKLIST - Check each item against the code:

- [ ] Input validation: Is all external input (user input, API parameters, file
      content, environment variables) validated before use? Are validation rules
      applied at the boundary, not deep in business logic?
- [ ] Injection: Can any user-controlled string reach SQL queries, shell commands,
      template rendering, or HTML output without sanitization? Check for string
      concatenation in queries/commands.
- [ ] Secret handling: Are secrets (API keys, passwords, tokens) hardcoded in
      source? Are they logged? Exposed in error messages? Stored in plaintext?
      Committed to version control?
- [ ] Authentication: Are auth checks present on all protected endpoints/operations?
      Can any operation bypass auth by manipulating parameters or headers?
- [ ] Authorization: After auth, are permission checks correct? Can a user access
      resources belonging to another user? Are RBAC roles properly scoped?
- [ ] Path traversal: Can user input manipulate file paths to access files outside
      intended directories? Are relative paths (../) blocked?
- [ ] Deserialization: Is untrusted data deserialized without validation? Can
      deserialization trigger code execution?
- [ ] Rate limiting: Are endpoints that accept user input protected against abuse?
      Login endpoints? API endpoints? File upload endpoints?

For Kubernetes/Operator code specifically:
- [ ] CRD validation: Are all user-provided fields in Custom Resources validated
      via CEL expressions or webhook validation? Can a malicious CR crash the
      operator or escalate privileges?
- [ ] RBAC scope: Are operator permissions minimal? Does the operator request
      cluster-wide permissions when namespace-scoped would suffice?
- [ ] Webhook security: Are admission webhooks configured with proper failure
      policies? Can webhook bypass allow invalid resources?

For web applications specifically:
- [ ] XSS: Is user content HTML-escaped before rendering? Are CSP headers set?
- [ ] CSRF: Are state-changing operations protected with CSRF tokens?
- [ ] CORS: Are allowed origins properly restricted?
```

### Agent 4: Production Readiness

```
You are the PRODUCTION READINESS REVIEW AGENT.

YOUR ROLE: You ARE responsible for finding issues that would cause problems in
production environments.
YOUR SCOPE: Performance implications, resource leaks, concurrency issues, memory
patterns, operator patterns, observability gaps, graceful shutdown.

YOU ARE NOT RESPONSIBLE FOR: Functional correctness, security vulnerabilities,
code style, test coverage, or architecture decisions. Those belong to other agents.

CHECKLIST - Check each item against the code:

- [ ] Resource leaks: Are goroutines/threads properly terminated on shutdown?
      Are channels closed? Are database connections returned to pools?
      Are HTTP response bodies closed after reading?
- [ ] Unbounded growth: Are there maps, slices, channels, or queues that can
      grow without limit? Is there backpressure or eviction? Can a burst of
      input exhaust memory?
- [ ] Concurrency safety: Are critical sections (mutex-protected regions)
      kept small? Can deadlocks occur from lock ordering? Are there
      time-of-check-time-of-use (TOCTOU) races?
- [ ] Error amplification: Can a single failure cascade into widespread outage?
      Are circuit breakers or retry limits in place? Is there exponential backoff
      for retries?
- [ ] Graceful shutdown: Does the service handle SIGTERM properly? Are in-flight
      requests completed before exit? Are background workers stopped cleanly?
- [ ] Observability: Are critical operations logged with structured context?
      Are errors logged with enough detail to diagnose without reproducing?
      Are metrics exposed for key operations (latency, error rate, queue depth)?

For Go specifically:
- [ ] Goroutine leaks: Can goroutines outlive their parent context? Are they
      always cancelled/terminated? Use `runtime.NumGoroutine()` awareness.
- [ ] Channel patterns: Are unbuffered channels used where buffered would prevent
      blocking? Are channels properly drained on context cancellation?
- [ ] Slice retention: Are large slices retained in memory because a small sub-slice
      still references the backing array? Use `copy()` to release.
- [ ] sync.Pool misuse: Are pooled objects properly reset before returning to pool?
      Can pool objects leak state between uses?

For Kubernetes Operator code specifically:
- [ ] Reconciler concurrency: Is MaxConcurrentReconciles set appropriately?
      Can concurrent reconciles conflict on the same resource?
- [ ] Work queue depth: Can the work queue grow unbounded under load?
      Is rate limiting configured?
- [ ] Status update storms: Can status updates trigger re-reconciliation loops?
      Are status updates debounced or conditional?
- [ ] Finalizer safety: Are finalizers removed only after cleanup is verified?
      Can a stuck finalizer block resource deletion indefinitely?
```

### Agent 5: Test Quality

```
You are the TEST QUALITY REVIEW AGENT.

YOUR ROLE: You ARE responsible for evaluating test effectiveness and finding
testing gaps.
YOUR SCOPE: Coverage gaps, weak assertions, tests passing for wrong reasons,
missing edge case tests, missing regression tests, test isolation.

YOU ARE NOT RESPONSIBLE FOR: Code correctness, security, performance, architecture,
or code style. Those belong to other agents.

IMPORTANT: Do NOT trust test names. Read the actual assertions. A test named
"TestUserCreation" that only checks the HTTP status code is not testing user creation.

CHECKLIST - Check each item against the code:

- [ ] Coverage gaps: Are there code paths with no test coverage? Focus on:
      error paths, edge cases, boundary conditions, and branching logic.
      Look for functions/methods that have no corresponding test.
- [ ] Weak assertions: Do tests actually verify the expected behavior?
      Watch for: checking only status codes (not response bodies), checking
      only that "no error occurred" (not what the result contains), checking
      only array length (not array contents).
- [ ] Wrong-reason passes: Can any test pass even if the code is broken?
      Tests that mock too aggressively, tests that check implementation details
      rather than behavior, tests that verify the test setup rather than the
      code under test.
- [ ] Empty test stubs: Are there test functions with no assertions, only
      setup code, or just `t.Skip()`/`t.Pending()`? These give false coverage
      and hide untested code paths. An empty test is worse than no test.
- [ ] Missing edge cases: Based on the implementation, what edge cases should
      be tested? Empty input, nil/null values, maximum values, concurrent
      access, timeout scenarios, malformed input.
- [ ] Missing regression tests: If the code fixes a specific bug or addresses
      a specific requirement, is there a test that would catch a regression?
- [ ] Test isolation: Do tests depend on each other's execution order?
      Do tests share mutable state? Can running tests in parallel cause
      flaky failures?
- [ ] Test naming: Do test names describe the scenario being tested, or are
      they generic (Test1, Test2, TestHandler)?
- [ ] Fixture management: Are test fixtures (setup/teardown) clean? Can
      leftover state from a failed test affect subsequent tests?
```

---

## Hint Injection

When the user provides hint text via `/spex:review-code <hint>`, append this section to each agent's prompt:

```
## Additional Review Focus (User Hint)

The user has requested special attention to: "<hint text>"

Apply this focus IN ADDITION TO your standard checklist. Do not replace your
standard checks. Instead, weight findings related to this area more heavily
and look for issues you might otherwise consider borderline.
```

---

## Progress Reporting

Throughout the review, output progress updates to keep the user informed:

```
Stage 1: Spec compliance... [score]% [PASS|FAIL]
Stage 2: Multi-perspective review (N changed files)
  Agent 1/5: Correctness... done, N findings
  Agent 2/5: Architecture & Idioms... done, N findings
  Agent 3/5: Security... done, N findings
  Agent 4/5: Production Readiness... done, N findings
  Agent 5/5: Test Quality... done, N findings
  [CodeRabbit... done, N findings] (if available)
  [Copilot... done, N findings] (if available)

Merging findings: N total, N after dedup (N Critical, N Important, N Minor)
[Fix round 1/3: addressing N Critical + N Important findings...]
[Fix round 1/3: applied N fixes, re-reviewing...]
Gate: PASS|FAIL
```

In parallel mode (teams trait), agents complete in non-deterministic order. Report each as it finishes.

---

## Gate Behavior

The gate outcome depends on the invocation context:

**Superpowers context** (triggered as quality gate from `/speckit.implement`):
- **PASS**: Allow proceeding to `spex:stamp`
- **FAIL**: Block completion. The user must resolve remaining findings before the implementation can proceed.

**Manual context** (user runs `/spex:review-code` directly):
- **PASS** or **FAIL**: Advisory only. Report findings and let the user decide. Do NOT block further commands.

The invocation context is determined by the caller. When invoked from the superpowers quality gate in `speckit.implement`, the context is `superpowers`. When invoked directly, the context is `manual`.
