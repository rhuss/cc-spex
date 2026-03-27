<!-- DEPRECATED: Replaced by sdd/overlays/teams/commands/speckit.implement.append.md -->
<!-- Use the consolidated 'teams' trait instead of 'teams-vanilla'. -->

<!-- SDD-TRAIT:teams-vanilla -->
## Agent Teams: Parallel Implementation

When this trait is active, orchestrate implementation using Claude Code Agent Teams
for parallel task execution instead of sequential single-session work.

**Pre-flight**: Check if `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled.
If not, set it in `.claude/settings.local.json` under `env` and inform the user
that a restart is needed.

**Execution**: Delegate to {Skill: sdd:teams-orchestrate} for task graph analysis,
teammate spawning, and completion coordination.
