# Brainstorm: OpenCode adaptation

**Date:** 2026-06-08
**Status:** idea

## Problem framing

cc-spex is built exclusively for Claude Code. Every hook, command, and packaging convention assumes Claude Code's plugin model. OpenCode is gaining traction as an open-source alternative, and it already reads `.claude/skills/` as a compatibility path, which means the speckit skill files install and show up in OpenCode's `<available_skills>` list. But showing up is not the same as working. The skills reference tools that don't exist in OpenCode (`AskUserQuestion`), rely on hooks that have no equivalent (`UserPromptSubmit`), and cross-reference slash commands (`/clear`, `/loop`) that OpenCode doesn't support.

The `specify` CLI already lists `opencode` as a supported agent type and can generate `AGENTS.md` instead of `CLAUDE.md`. So the low-level foundation is there. The problem is the spex layer on top, the one that provides the interactive workflow, process discipline, and quality gates.

The question: can we adapt cc-spex for OpenCode without maintaining two completely separate codebases, and without gutting the enforcement model that makes spex worth using?

## Inventory of Claude Code dependencies

Before considering approaches, here's what actually ties spex to Claude Code:

### Hooks (the hard part)

Two Python scripts run on every interaction:

**context-hook.py (UserPromptSubmit)** fires on every user prompt. It validates `/spex:*` commands against a known list (catches hallucinated commands), injects XML context with plugin root and session state, and writes a marker file that forces the model to call the Skill tool before any other tool. This is the command dispatch brain.

**pretool-gate.py (PreToolUse)** fires before every tool call. It implements four gates: blocks non-Skill tools when a command is pending (forces skill loading first), enforces teams usage when the extension is active, enforces stage ordering during ship pipeline, and reminds about verification before git commit.

OpenCode's `tool.execute.before` plugin event can deny tool calls by throwing an Error, which covers the pretool-gate partially. But there is no `UserPromptSubmit` equivalent at all. The `tui.prompt.append` event is for injecting text into the TUI prompt, not for intercepting prompts before the model sees them.

### AskUserQuestion (66 call sites)

Used for interactive multi-choice prompts: "Fix all / Let me pick / Skip", "Merge / Create PR / Keep branch", extension enable/disable confirmations, init questionnaire. OpenCode has a `question` tool that maps to the same concept, though the structured multi-select with headers may need simplification. The ship pipeline's autonomous mode (`ask: never`) suppresses these prompts, which is a pattern within command markdown, not an API difference, so it transfers as-is.

### Slash command references (267 cross-references)

Commands reference each other constantly. The ship pipeline invokes a dozen commands in sequence. Review commands suggest next steps. Help lists all commands by category. OpenCode supports both `.opencode/commands/*.md` and `.opencode/skills/*/SKILL.md`, so the references work if the files are in the right place. The `specify` CLI handles this path difference already when initialized with `--ai opencode`.

### Agent Teams (optional, 157 references)

The spex-teams extension uses Claude Code's experimental `Agent` tool with background execution and worktree isolation. OpenCode's Task tool can invoke subagents and supports parallel calls in a single message, but it lacks background execution, worktree isolation, and team naming. The teams extension is optional and can be disabled.

### Other Claude Code-isms

- `/clear` for context isolation (no OpenCode equivalent)
- `/loop` for timed repeated command execution (no OpenCode equivalent)
- Status line integration via `.spex-status-line.sh` (no OpenCode equivalent)
- `${CLAUDE_PLUGIN_ROOT}` environment variable in hook scripts
- `.claude-plugin/plugin.json` manifest and `marketplace.json`
- `settings.local.json` for permissions (different format in OpenCode)

## Approaches considered

### A: Dual-agent abstraction layer

Build an abstraction layer into spex that detects the running agent (Claude Code vs OpenCode) and dispatches to the right implementation. Hook scripts would have OpenCode equivalents as TS plugins. Command files would be generated for both `.claude/skills/` and `.opencode/skills/` paths. The `specify` CLI already has the `--ai` flag for this.

- Pros: Single codebase. Correct behavior on both platforms. The `specify` CLI's multi-agent architecture already supports this pattern.
- Cons: Every feature needs two implementations. Testing doubles. The abstraction layer itself becomes a maintenance burden. Hook parity may not be achievable since OpenCode lacks `UserPromptSubmit`.

### B: OpenCode plugin + relaxed enforcement

Accept that OpenCode cannot enforce process discipline at the hook level. Write an OpenCode plugin (TS module) that handles what it can via `tool.execute.before` (pretool gates, teams enforcement). Move command validation and context injection into the skill files themselves, duplicating it per-command. Accept that enforcement becomes advisory rather than mandatory.

- Pros: Simpler than full parity. Works within OpenCode's actual capabilities. The core workflow (specify, plan, tasks, implement, review) still works. Skills already load correctly.
- Cons: Process discipline degrades. The model can skip stages without the hook catching it. Each skill file grows larger with duplicated context setup. The spex value proposition weakens.

### C: OpenCode-native fork (chosen direction for exploration)

Fork the command/skill content into an OpenCode-native variant. Instead of wrapping Claude Code conventions, design directly for OpenCode's model: commands as `.opencode/commands/*.md`, skills as `.opencode/skills/*/SKILL.md`, enforcement via a TS plugin in `.opencode/plugins/`, and OpenCode's `question` tool for interactive prompts.

Share the `specify` CLI and spec-kit core between both variants. The CLI generates the right files for the target agent. The markdown content is maintained separately per agent, but the underlying SDD methodology, spec format, and plan/task templates remain identical.

- Pros: Each variant is idiomatic for its platform. No abstraction layer overhead. OpenCode users get a first-class experience, not a compatibility shim. Can adopt OpenCode-specific features as they mature (custom agents, custom tools).
- Cons: Content duplication across two sets of command files. Drift risk between variants. More maintenance work.

### D: Wait for OpenCode to add hook support

OpenCode is actively developed. The plugin system already supports `tool.execute.before` and `tool.execute.after`. A `prompt.before` or `session.prompt.submitted` event would close the biggest gap. Monitor OpenCode's roadmap and revisit when hook parity improves.

- Pros: Zero effort now. Full parity possible later.
- Cons: Unknown timeline. OpenCode may never add this. Misses the adoption window.

## Decision

**Lean toward C (OpenCode-native fork) with elements of B (relaxed enforcement).**

Full hook parity isn't achievable today. Waiting (D) is passive. The dual abstraction (A) adds complexity without solving the fundamental gap. A native fork lets OpenCode users get a working spex experience, even if enforcement is softer than the Claude Code version.

The `specify` CLI already handles multi-agent generation. The fork is in the spex layer (command markdown and the plugin), not in spec-kit core.

## Key requirements

### Phase 1: Skills and commands (the easy part)

The `specify` CLI's `--ai opencode` path needs to:
- Install skill files into `.opencode/skills/speckit-*/SKILL.md` instead of `.claude/skills/`
- Generate `AGENTS.md` with spex context (already supported)
- Replace `AskUserQuestion` references with `question` tool in all skill content
- Remove `/clear` and `/loop` references, replace with OpenCode-appropriate alternatives or remove entirely

Estimated scope: 28 command files need `AskUserQuestion` rewrites and path updates. Straightforward text replacement.

### Phase 2: OpenCode plugin for enforcement

Write `.opencode/plugins/spex-discipline.ts`:

```
tool.execute.before:
  - If a spex command is pending (marker file exists), block non-Skill tools
  - If ship pipeline is active, enforce stage ordering
  - If teams extension is enabled, redirect raw Task calls to orchestration skill
```

This covers what `pretool-gate.py` does today, minus the `additionalContext` injection (OpenCode's `tool.execute.before` can deny but can't add context). The context injection would move into each skill's preamble instead.

The `context-hook.py` logic (command validation, context injection) has no plugin equivalent. It would be embedded directly in each command file's template, or handled via a custom OpenCode command that wraps the skill invocation.

### Phase 3: Teams adaptation (optional, deferred)

OpenCode's Task tool can invoke multiple subagents in parallel. The worktree isolation would need to be manual (the skill instructs the subagent to create/use a worktree) rather than built into the tool invocation. This works but is less robust.

### Phase 4: Missing features (tracked, not blocked)

| Feature | Claude Code | OpenCode | Workaround |
|---|---|---|---|
| Context clearing | `/clear` | None | Suggest starting a new session |
| Timed polling | `/loop 5m /command` | None | Manual re-invocation |
| Status line | Custom script | None | Skip or use todo tracking |
| Background agents | `run_in_background` | None | Sequential task execution |
| Prompt interception | `UserPromptSubmit` | None | Embed logic in command templates |

## Open threads

- Should the OpenCode variant be a separate npm package or a `--ai opencode` flag on the existing `specify init`?
- How much enforcement degradation is acceptable? If the model can skip stages, is spex still useful or just a spec template generator?
- OpenCode's plugin system is young. Worth opening a feature request for `prompt.before` or `session.prompt.submitted` events?
- The `question` tool's capabilities need testing. Can it handle multi-select with grouped options, or does it only support simple lists?
- Can OpenCode custom tools (via plugins) replace some hook functionality? A `spex-context` custom tool that the model calls for context injection could work around the lack of `UserPromptSubmit`.

## Risk: enforcement without hooks

This is the elephant in the room. Spex's value is process discipline: you can't skip the spec, you can't skip the review, you can't implement without a plan. The hooks enforce this mechanically. Without hooks, enforcement relies on instructions in the skill files, which the model can ignore.

Possible mitigations:
- Make enforcement instructions very prominent in AGENTS.md (top-level, bold, repeated)
- Use the `tool.execute.before` plugin to block `bash` and `write` tools until the skill gate is satisfied
- Accept that OpenCode spex is "discipline by convention" rather than "discipline by enforcement" and market it accordingly
- Track compliance and report deviations rather than blocking them

None of these are as strong as mechanical enforcement. But they may be good enough for users who want the SDD methodology without the Claude Code lock-in.
