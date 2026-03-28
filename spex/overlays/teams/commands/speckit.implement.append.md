
<!-- SPEX-TRAIT:teams -->
## Agent Teams: MANDATORY for Multi-Task Implementation

**ENFORCEMENT**: This section is NON-NEGOTIABLE when implementing 2+ independent tasks.

### Phase Marker (FIRST action)

Before any implementation logic, set the phase marker so the teams enforcement hook
is active for this session:

```bash
echo "implement" > .specify/.spex-phase
```

When implementation completes (success or failure), clean it up:

```bash
rm -f .specify/.spex-phase
```

### Decision Gate (BEFORE any implementation)

When the implement skill is invoked with multiple tasks:

1. **CHECK**: Is `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` set?
   - If not: Set it in `.claude/settings.local.json`, inform user restart needed, STOP.
   - If yes: proceed.

2. **DELEGATE**: Call `{Skill: spex:teams-orchestrate}` for task graph analysis,
   teammate spawning in worktrees, spec compliance review, and merge coordination.
   Do NOT proceed with direct implementation.

### When teams are NOT needed
- Single sequential task with no parallelism opportunity
- Pure verification/validation work (clippy, test runs)
- Fixing a single compile error or merge conflict

### Anti-patterns (NEVER do these)
- Using `Agent` tool with `run_in_background` instead of Agent Teams
- Implementing tasks directly when 2+ independent tasks exist
- Skipping the pre-flight check
