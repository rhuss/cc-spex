---
name: teams-research
description: "Parallel codebase research for planning via Claude Code Agent Teams"
---

# Teams Research: Parallel Codebase Exploration for Planning

## Overview

This skill orchestrates parallel codebase research using Claude Code Agent Teams during the plan phase. The lead session analyzes the spec to identify research topics, spawns research agents to explore different parts of the codebase simultaneously, collects their findings, and then generates the plan with comprehensive codebase knowledge.

## Prerequisites

### CC Teams Feature Flag

Check if Agent Teams is enabled:

```bash
# Check settings.local.json for the feature flag
FLAG=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // ""' .claude/settings.local.json 2>/dev/null)
```

**If the flag is not set (`""` or missing):**

1. Set it in `.claude/settings.local.json`:
   ```bash
   jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"' .claude/settings.local.json > /tmp/settings.json && mv /tmp/settings.json .claude/settings.local.json
   ```
2. Inform the user: "Agent Teams feature flag has been enabled. Please restart Claude Code for teams to activate."
3. **Fall back to single-session research** for this session (teams will work on next run).

**If the flag is set:** Proceed with team research.

## Phase 1: Research Topic Identification

Read the spec.md and identify what codebase knowledge is needed to create a solid plan.

### Identify Research Areas

From the spec, extract:

1. **Existing code to modify**: Which files, modules, or packages does the spec reference or affect?
2. **Patterns to follow**: What existing patterns in the codebase should the plan adopt?
3. **Integration points**: Where does the new feature connect to existing code?
4. **Technology questions**: What libraries, frameworks, or tools are already in use that are relevant?

### Group into Independent Research Topics

Organize the areas into independent research topics that can be explored in parallel. Each topic should be:

- **Self-contained**: An agent can research it without needing results from other topics
- **Focused**: Specific enough to produce actionable findings (not "explore the whole codebase")
- **Relevant**: Directly needed for plan creation

**Examples of good research topics:**
- "Explore the authentication module: middleware chain, session handling, token validation patterns"
- "Map the database schema and migration patterns for the user-related tables"
- "Analyze the existing API endpoint structure: routing, validation, error handling conventions"
- "Review the test infrastructure: test helpers, fixtures, integration test patterns"

### Parallelism Assessment

- **If 0-1 research topics exist** (spec is simple or self-contained): Skip team creation, research directly in the current session. Report: "Single research area, no parallelism benefit. Researching directly."
- **If 2+ independent research topics exist**: Proceed with agent spawning.

## Phase 2: Research Agent Spawning

### Spawn Rules

- Spawn **one agent per research topic**
- **Maximum 4 research agents** (research is read-only, so less coordination overhead than implementation, but keep it bounded)
- If more than 4 topics, merge the least complex ones together
- **All agents are read-only**: They explore and report, they do not modify files

### Agent Prompt Template

Each research agent receives:

```
You are a codebase research agent for the [feature-name] feature planning phase.

## Your Research Topic

[Description of what to research]

## Spec Context

[Relevant sections of spec.md that motivate this research]

## Research Instructions

1. Explore the relevant code thoroughly using Read, Grep, and Glob tools
2. Document your findings in a structured format:
   - **Files examined**: List the key files you looked at
   - **Patterns found**: Describe coding patterns, conventions, and structures
   - **Integration points**: Where new code would connect to existing code
   - **Constraints discovered**: Anything that limits or shapes the implementation approach
   - **Recommendations**: Suggest how the plan should handle this area
3. Be specific: include file paths, function names, and line references
4. Do NOT modify any files. This is a read-only research mission.
5. When done, send your findings back to the lead.
```

### Spawning Process

Create an agent team for parallel research:

```
Create an agent team for codebase research on [feature-name].

Spawn [N] research agents:
- Agent 1: [research topic description]
- Agent 2: [research topic description]
...

Each agent should explore the codebase and report findings. Read-only, no file modifications.
Wait for all agents to complete before proceeding.
```

## Phase 3: Findings Consolidation

After all research agents report back:

1. **Collect all findings** from teammate messages
2. **Synthesize**: Identify common patterns across findings, resolve contradictions, note gaps
3. **Build a research summary**: Organize findings by relevance to plan sections
4. **Identify any remaining unknowns**: If research revealed new questions, note them for the plan's assumptions section

## Phase 4: Plan Generation

With research findings in hand, generate the plan:

1. Use the consolidated research as input alongside the spec
2. Reference specific files, patterns, and integration points discovered by agents
3. The plan should reflect the actual codebase state, not assumptions
4. Include a brief "Research Basis" note in the plan acknowledging what was explored

Then proceed with normal plan-phase flow (review-spec if superpowers trait is active, etc.).

## Sequential Fallback

When teams cannot be used (feature flag not active, single research topic, simple spec):

Research the codebase directly in the current session, then generate the plan. This is the normal behavior when the teams-vanilla trait is not active.

## Key Principles

- **Research is read-only**: Agents explore, they never modify files
- **Lead consolidates and plans**: Research agents gather data, the lead makes design decisions
- **Breadth over depth**: Better to have a broad understanding than deep knowledge of one area
- **Graceful degradation**: Always fall back to single-session research if teams can't help
- **Keep research focused**: Every research topic must tie back to a plan need from the spec
