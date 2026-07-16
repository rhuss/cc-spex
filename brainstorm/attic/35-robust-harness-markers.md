# Brainstorm: Robust Harness Markers

**Date:** 2026-07-12
**Status:** active

## Problem Framing

Feature 038 (neutral command vocabulary) introduced a two-mechanism adaptation system: HTML-comment capability markers (`<!-- harness:X -->`) for section-level blocks and exact prose-matching inline substitutions for single phrases. The inline substitutions are fragile: any rewording in the command file silently breaks the match, there is no validation that entries actually matched, and 15 entries must stay perfectly synchronized with exact wording across 8 command files. The HTML-comment markers are structurally sound but invisible in rendered markdown, hiding unadapted content when adaptation fails or is incomplete.

## Approaches Considered

### A: Placeholder tokens for inline, keep HTML comment markers for sections

Replace the 15 inline prose-matching entries with `{harness:key}` placeholder tokens. Keep `<!-- harness:X -->...<!-- /harness:X -->` for section-level blocks.

- Pros: Minimal change, section markers already working
- Cons: Two syntaxes to document and grep for, HTML comments hide unadapted blocks

### B: Unified `{harness:X}` syntax for both inline and block

Replace all markers with a single `{harness:key}` syntax. Inline tokens are bare `{harness:key}`, block markers use `{harness:key}...{/harness:key}` with a closer. Markers are stripped completely after adaptation.

- Pros: One syntax, one grep pattern, one code path, all markers visible in raw markdown, unadapted content is immediately obvious, trivial validation (`grep '{harness:' file` = 0 matches means fully adapted)
- Cons: Slightly more visible noise in source files (but these are consumed by agents, not humans)

### C: Jinja-style template variables

Use `{{ harness.key }}` for inline, `{% block harness.key %}...{% endblock %}` for sections. Leverage existing template engine conventions.

- Pros: Familiar syntax for anyone who knows Jinja/Django
- Cons: Heavier syntax, curly-brace doubling could confuse markdown parsers, introduces a naming convention from a specific template engine

## Decision

**Approach B: Unified `{harness:X}` syntax.** One pattern for everything, markers always visible, trivially validatable.

### Design Details

**Inline tokens** (replace a phrase within a sentence):
```markdown
In pipeline mode, {harness:no-interactive-prompts} for this step.
```
Adapted for Claude Code:
```markdown
In pipeline mode, do NOT use AskUserQuestion for this step.
```

**Block markers** (replace a multi-line section):
```markdown
{harness:agent-teams}
The parallel agent teams feature must be enabled.
Use the agent's team mechanism to spawn teammates.
{/harness:agent-teams}
```
Adapted for Claude Code:
```markdown
Enable Claude Code Agent Teams by setting the feature flag:
...full Claude-specific instructions...
```

**After adaptation**: All markers are stripped. Only the replacement content remains. No tracing markers in production files (agents consume these, leftover markers waste context and could confuse them).

**Mapping table changes**: Replace `"inline"` array (prose-matching pairs) with `"tokens"` object (key-to-replacement map). Remove `"sections"` HTML-comment handling. Both tokens and blocks use the same `"tokens"` namespace in the mapping table:

```json
{
  "harness": "claude",
  "version": "2.0.0",
  "tokens": {
    "no-interactive-prompts": "do NOT use AskUserQuestion",
    "interactive-choice": "use `AskUserQuestion` with structured options",
    "agent-teams": "Enable Claude Code Agent Teams by setting...\n(multi-line content for block replacement)"
  },
  "fallback_note": "> **Note:** This capability is not available on {harness}. {fallback_text}"
}
```

**Script changes**: `spex-adapt-commands.sh` gets a single processing pass:
1. Find `{harness:key}` inline tokens, replace with value from `tokens[key]`
2. Find `{harness:key}...{/harness:key}` blocks, replace entire block (including markers) with value from `tokens[key]`
3. If key not in tokens, apply `fallback_note` template

**Debug mode**: Add `--debug` flag that logs which markers matched and what they were replaced with (stdout only, never written to files). Complements existing `--dry-run` (diff preview).

**Validation**: After adaptation, `grep '{harness:' file` should return 0 matches. The script can optionally verify this and warn on leftover markers.

## Key Requirements

- Replace all 15 inline prose-matching substitutions with `{harness:key}` tokens
- Replace all `<!-- harness:X -->...<!-- /harness:X -->` section markers with `{harness:X}...{/harness:X}` blocks
- Update `spex-adapt-commands.sh` to handle the unified syntax
- Update `command-map.json` to use `"tokens"` instead of `"inline"` + `"sections"`
- Update all 8 command files that use current markers
- Add `--debug` flag to adaptation script
- Add post-adaptation validation (warn on leftover `{harness:` markers)
- Maintain idempotency, atomicity, and dry-run support

## Open Questions

- Should the mapping table support multi-line token values via JSON string with `\n`, or should large blocks reference external files?
- Should `--debug` output go to stderr (not polluting stdout in dry-run mode)?
