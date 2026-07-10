---
description: "Parallel implementation via Agent Teams for independent tasks"
---

# Teams Implement

Standalone parallel implementation command. The ship pipeline routes to this command
(instead of standard implement) when spex-teams is enabled and 2+ independent tasks exist.

## Prerequisites

- CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS must be set
- tasks.md must exist with task breakdown
- spex-gates extension must be enabled

## Execution

1. Read tasks.md and parse the task list
2. Count tasks marked with [P] (parallel-eligible)
3. If 2+ independent tasks: invoke speckit.spex-teams.orchestrate for parallel agent spawning
4. If <2 independent tasks: fall back to standard implement (inform user)
5. Check .spex-state for autonomous mode; suppress prompts if in ship pipeline

## Ship Pipeline Integration

The ship command routes here when spex-teams is enabled and tasks.md has 2+ independent tasks.
This command is NOT invoked via a hook - it is called directly by ship or the user.
