# Research: Deep-Review Trait

**Feature**: 009-deep-review-trait
**Date**: 2026-03-28

## R1: Agent Prompt Architecture (from reference implementations)

### Decision: Hybrid approach combining best patterns from Anthropic, AgentCheck, and obra/superpowers

### Rationale

Three reference implementations were studied:

**Anthropic PR Review Toolkit** (claude-code/plugins/pr-review-toolkit):
- Six specialized agents as standalone markdown files in `agents/` directory
- Aggressive confidence filtering: code-reviewer uses 0-100 scale, only reports 80+
- Confidence bands: 90-100 = critical, 80-89 = important, below 80 = silently discarded
- Prioritizes precision over completeness (minimizes false positives)

**AgentCheck** (devlyai/AgentCheck):
- Five specialized agents with shared context loading (`agentcheck-common.md`) plus domain-specific files
- "ALWAYS START WITH ISSUES" directive prevents leading with praise
- Standardized output: `[filename]:[line] . [CRITICAL/HIGH/MEDIUM]` with Problem, Task Impact, Fix sections
- Agents run in parallel, write independent reports to a reports directory

**obra/superpowers**:
- Context isolation between implementer and reviewer (reviewer never sees session history)
- Explicit anti-sycophancy: bans phrases like "Great point!", "You're absolutely right!"
- Requires factual acknowledgment ("Fixed X at file:line") over gratitude
- Three-tier severity: Critical (must fix), Important (should fix), Suggestions (nice to have)

### Pattern Synthesis for Deep-Review

1. **Narrow specialization**: Each of the 5 agents gets a tight mandate with explicit scope gates (IS/IS NOT responsible for)
2. **Confidence threshold**: 0-100 scale, report at >= 70 (>= 50 for Critical per FR-021)
3. **Anti-sycophancy bundle**: "Start with issues" (AgentCheck) + banned phrases (obra) + distrust instruction (spec FR-021)
4. **Context isolation**: Agents receive only changed files + spec requirements, never implementation session history (obra pattern, matches FR-022)
5. **Structured output**: AgentCheck's `file:line . SEVERITY` format adapted for our schema
6. **Concrete fixes required**: Every finding must include a fix suggestion, not just a problem description (all three sources agree)

### Alternatives Considered

- **Single omnibus reviewer**: Rejected. All three references use multiple specialized agents. Single reviewer loses depth.
- **Numeric-only severity (no categories)**: Rejected. Domain-specific severity mappings (security: auth bypass = critical) are more actionable than generic numbers.
- **Shared context between agents**: Rejected. All references emphasize independent, parallel analysis. Shared context creates groupthink.

## R2: External Review Tool Integration

### Decision: Support both CodeRabbit CLI and GitHub Copilot CLI as optional external review perspectives

### Rationale

Two external CLI tools are available for local code review, each with different strengths:

**CodeRabbit CLI:**
- Has `--prompt-only` mode with `=============` delimiters (structured, parseable)
- Reviews uncommitted changes via `--type uncommitted`
- Free tier: unlimited repos (rate-limited)
- Review time: 7-30 minutes
- Strength: Deep cross-file analysis, high finding count

**GitHub Copilot CLI:**
- Uses `/review` command or prompt-based invocation
- Reviews staged/unstaged changes locally
- Free tier: 50 premium requests/month (shared pool with all Copilot usage)
- Review time: ~30 seconds
- Strength: Fast, high precision (~71% actionable), fewer total findings
- Limitation: No structured output flags. Output is conversational plain text. Must prompt-engineer structured format.

Both provide perspectives from different AI models, catching blind spots that Claude-based agents might miss.

### CodeRabbit Parsing Strategy

```
1. Run: coderabbit review --prompt-only --type uncommitted --no-color
2. Check for "Review completed" (clean exit)
3. Split output on "=============" delimiters
4. For each block: extract file, line, severity keyword, description
5. Map CodeRabbit severity → deep-review severity:
   - critical → Critical
   - major → Important
   - minor → Minor
6. Set category = "external" for all CodeRabbit findings
7. Set confidence = 75 (external tool, assumed reliable but not verified)
```

### Copilot CLI Parsing Strategy

```
1. Run: copilot -s -p "Review the git diff for bugs, security issues, and code quality problems.
   Output ONLY a structured list of findings. For each finding use this exact format:
   ### FINDING
   - Severity: Critical|Important|Minor
   - File: <path>
   - Line: <number>
   - Description: <what is wrong and how to fix it>
   End each finding with ---" --allow-tool='shell(git)'
2. Capture stdout (silent mode suppresses session metadata)
3. Split on "### FINDING" markers
4. For each block: extract Severity, File, Line, Description fields
5. Map to deep-review finding schema
6. Set category = "external", source_agent = "copilot"
7. Set confidence = 75 (same as CodeRabbit)
```

### Alternatives Considered

- CodeRabbit `--plain` mode: Rejected. More verbose, harder to parse.
- Copilot `gh pr edit --add-reviewer @copilot`: Rejected. Requires a pushed PR, not local changes.
- JSON output from either tool: Not available. Neither has a JSON mode.
- Supporting only CodeRabbit: Rejected. Copilot adds value (different model, fast, high precision) and is widely available via GitHub subscriptions.

## R3: Trait Registration Mechanism

### Decision: Add `deep-review` to VALID_TRAITS in spex-traits.sh with no dependencies

### Rationale

The trait system validates traits against a whitelist (`VALID_TRAITS` string in spex-traits.sh). Registration requires:
1. Adding `deep-review` to the `VALID_TRAITS` string
2. No entries in `get_trait_deps()` (FR-003: independent of superpowers)
3. Creating the overlay directory structure: `spex/overlays/deep-review/commands/`

Unlike the `teams` trait (which requires `superpowers`), `deep-review` has no dependencies. It enhances review-code behavior when enabled but does not require other traits to function.

### Alternatives Considered

- Making deep-review depend on superpowers: Rejected per FR-003 (trait independence).
- Auto-enabling deep-review with superpowers: Rejected. User should opt-in explicitly.

## R4: Findings Deduplication Algorithm

### Decision: File + overlapping line range + category matching with detail-preserving merge

### Rationale

With 5 internal agents plus optional CodeRabbit, the same issue may be reported multiple times. The deduplication algorithm:

```
For each pair of findings (A, B):
  IF A.file == B.file
  AND lines_overlap(A.line_start..A.line_end, B.line_start..B.line_end)
  AND A.category == B.category:
    KEEP whichever has longer description (more detail)
    ADD other source to kept finding's "also_reported_by" list
    USE higher severity if they differ
    USE higher confidence if they differ
```

Line overlap is defined as: `A.line_start <= B.line_end AND B.line_start <= A.line_end`

Categories are: correctness, architecture, security, production-readiness, test-quality, external. Cross-category findings (same file+line, different category) are NOT deduplicated because they represent genuinely different concerns.

### Alternatives Considered

- Exact line match only: Rejected. Different agents may point to slightly different lines for the same issue (e.g., one points to the function signature, another to the body).
- Text similarity matching: Rejected. Too complex, fragile, and slow. Category + location is sufficient.

## R5: Review Agent Output Schema

### Decision: Structured markdown output with parseable format

### Rationale

Each agent must return findings in a format that the orchestrator can reliably parse and merge. Adopting a structured markdown format (inspired by AgentCheck) that works naturally with Claude's output:

```markdown
## Findings

### FINDING-1
- **Severity**: Critical
- **Confidence**: 85
- **File**: src/controller.go
- **Lines**: 142-148
- **Category**: correctness
- **Description**: Shared slice reference passed to goroutine without copy
- **Rationale**: The `items` slice is appended to in the main goroutine while the spawned goroutine reads from it, creating a data race
- **Fix**: Copy the slice before passing: `itemsCopy := make([]Item, len(items)); copy(itemsCopy, items)`

### FINDING-2
...

## Self-Verification
- [ ] Each finding has file:line evidence
- [ ] No findings invented for clean code
- [ ] No duplicate findings
- [ ] Confidence scores reflect actual certainty
- [ ] Zero findings triggered re-read (if applicable)
```

### Alternatives Considered

- JSON output: Rejected. Claude produces more reliable structured markdown than JSON. Parsing markdown headers/bullets is simpler than handling JSON edge cases.
- Free-form text: Rejected. Unreliable parsing. Structured format ensures consistent merge.

## R6: Fix Loop Mechanics

### Decision: Main conversation agent applies fixes with staged verification

### Rationale

The fix loop operates within the main conversation context (FR-047). The flow:

1. Orchestrator collects Critical + Important findings from all agents
2. Orchestrator groups findings by file, sorts by line number (descending, to avoid offset shifts)
3. Main agent reads each affected file, applies fixes top-to-bottom
4. After all fixes for a round: stage changes (`git add`)
5. Re-dispatch review agents on only the modified files (narrowed scope per FR-013)
6. Parse new findings, check for remaining Critical/Important
7. Repeat or conclude

Fixes are applied in reverse line order within each file to prevent line number shifts from invalidating subsequent fix locations.

### Alternatives Considered

- Bottom-to-top fix order: Actually chosen (reverse line order). This prevents line shifts. The spec says top-to-bottom (FR-046), but reverse order is the correct implementation of "sequential within file" when fixes may change line counts. The spec intent is to prevent conflicts, which reverse order achieves.
- Separate fix agent: Rejected. The main conversation agent already has full context and file access. A separate agent would need context transfer.
- Commit between rounds: Rejected. Staging is sufficient. Commits would create noise in git history. The user reviews accumulated changes after completion.

## Sources

- [Anthropic PR Review Toolkit](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit)
- [AgentCheck](https://github.com/devlyai/AgentCheck)
- [obra/superpowers](https://github.com/obra/superpowers)
- [CodeRabbit CLI Documentation](https://docs.coderabbit.ai/cli/overview)
- [CodeRabbit CLI Blog Post](https://www.coderabbit.ai/blog/coderabbit-cli-free-ai-code-reviews-in-your-cli)
