# Brainstorm: Configurable implementation model for ship

**Date:** 2026-11-11
**Status:** active

## Problem Framing

`speckit-spex-ship` runs every stage on the session model, including Stage 6 (implement), which is usually the most token-heavy stage. By the time implementation starts, the expensive thinking is done: spec, plan, and tasks.md are written and reviewed, and they constrain the implementer tightly. Implementation should therefore run on a cheaper model with minimal quality risk.

The main driver is cost. Cheaper models include the harness's own smaller models (Sonnet/Haiku on Claude Code, a smaller GPT on Codex) and third-party models such as GLM and DeepSeek served behind an Anthropic- or OpenAI-compatible facade. The user routes these through Praxis, an AI router used from Claude Code.

Success: a project can name a cheaper implementer model per harness, ship uses it for implementation only, and the rest of the pipeline is unchanged. With no configuration, behavior is identical to today.

Anti-goals:
- Silent quality loss: review-code (Stage 7) and its fix loop must stay on the session model as the quality backstop.
- Hijacking model aliases session-wide (for example pointing `haiku` at GLM, which also redirects Claude Code's own background Haiku calls).
- spex owning provider configuration (base URLs, keys). Routing stays in the harness or router.

## Harness Capabilities (verified 2026-11-11)

- **Claude Code 2.1.319**: The Agent tool `model` parameter accepts only aliases (`sonnet`, `opus`, `haiku`, `fable`), plus an `effort` parameter. Custom agent definitions (`.claude/agents/*.md` frontmatter) accept "an alias or model ID, or 'inherit'". A subagent shares the parent's API endpoint, so third-party models need a router that dispatches by model name (Praxis does).
- **Codex 0.167.0**: `spawn_agent` accepts optional `model` and `reasoning_effort`, validated against the available models list ("Unknown model X for spawn_agent. Available models: ..."). Its tool description says not to set `model` unless the user explicitly asks, so ship's instructions must state the override explicitly. Codex also supports agent role files (TOML with `name`, `description`, `developer_instructions`, `nickname_candidates`, optional `config_file` layer) and global `default_subagent_model` / `default_subagent_reasoning_effort` settings.

## Approaches Considered

### A: Per-spawn model parameter
Ship reads `implement.model` / `implement.effort` from spex-config and passes them on the spawn call (Agent `model`/`effort`, `spawn_agent` `model`/`reasoning_effort`).
- Pros: smallest change, no generated files, everything else unchanged.
- Cons: Claude Code limits this to aliases, so GLM/DeepSeek require remapping an alias at the router or via `ANTHROPIC_DEFAULT_*_MODEL`, which affects every use of that alias in the session.

### B: Generated implementer agent definition (chosen)
spex-init generates `.claude/agents/spex-implementer.md` (with `model: <any ID>`) and a Codex agent role from the config. Ship spawns that agent by name.
- Pros: arbitrary model IDs (whatever Praxis serves), no alias hijacking, stays an in-session subagent so state file, status line, worktree CWD, hooks, and progress reporting work unchanged. The agent definition can carry implementer-specific instructions tuned for weaker models.
- Cons: init must generate the files and regenerate them on config change. Two capabilities still need verification (see Open Questions).

### C: Out-of-process implementer
Ship runs `claude -p --model X` or `codex exec -m X` with its own endpoint configuration.
- Pros: any model, any endpoint, even a cross-harness implementer.
- Cons: loses subagent integration (permissions, hooks, progress, state), harder error and timeout handling. Only worth it when the router cannot route by model name, which is not the case with Praxis.

## Decision

Approach B, with approach A as the fallback when no generated agent file exists (for example an alias-only config, or init not yet re-run).

## Key Requirements

- New `implement` block in spex-config (`.specify/extensions/spex/spex-config.yml`, which already holds `implement.test_between_tasks` and `implement.review_checkpoints`) with a model per harness (`claude`, `codex`) and an optional effort level. Unset means today's behavior (inherit the session model).
- `spex-init` generates `.claude/agents/spex-implementer.md` and a Codex agent role from that config; `--refresh` regenerates them. When the config is unset, no implementer files are generated (or existing generated ones are removed).
- Ship Stage 6 spawns `spex-implementer` by name when available; otherwise passes the configured model/effort on the spawn call.
- The spawn instructions state the model override explicitly, so Codex's "do not set model unless asked" guidance does not suppress it.
- Mid-implementation correctness checkpoint reviewers (spawned inside implement) use the cheaper model. *(Proposed by Claude: they check correctness against the spec, a bounded task.)*
- spex-teams implementers use the same configured model. *(Proposed by Claude: same role as the single implementer.)*
- Stage 7 review-code and its fix loop stay on the session model.
- Documentation: README, `spex/docs/help.md`, and a note that this is an explicit, config-driven exception to the "do not pass `model` to subagents" convention.

**Out of scope:**
- Out-of-process implementer (approach C).
- Automatic escalation to a stronger model when the cheaper one fails. *(Proposed by Claude: add later if quality turns out to be a problem.)*
- Managing Praxis or provider configuration (base URLs, credentials).

## Open Questions

- Does Claude Code pass a non-Claude model ID in agent frontmatter through to the router (Praxis) unchanged, or does it validate or rewrite it?
- Can a Codex agent role select a model or provider outside the default available-models list (via `config_file`), and does `spawn_agent` accept a Praxis-served model?
- Should the standalone `/speckit-implement` (outside ship) also use the implementer model, or only ship?
- Exact config schema: one model per harness, or a shared default plus per-harness overrides?
- Should the generated implementer agent definition carry extra guardrail instructions for weaker models (e.g. strict task-by-task adherence, no scope expansion)?
