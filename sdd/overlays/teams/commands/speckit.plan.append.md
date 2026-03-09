
<!-- SDD-TRAIT:teams -->
## Agent Teams: Parallel Codebase Research for Planning

When this trait is active, orchestrate the research phase of planning using
Claude Code Agent Teams for parallel codebase exploration before the lead
generates the plan.

**Pre-flight**: Check if `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled.
If not, set it in `.claude/settings.local.json` under `env` and inform the user
that a restart is needed.

**Execution**: Delegate to {Skill: sdd:teams-research} for research topic
identification, agent spawning, findings consolidation, and plan generation.
