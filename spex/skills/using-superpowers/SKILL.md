---
name: using-superpowers
description: Establishes spex methodology - workflow routing, process discipline, spec-first principle, and skill discovery. Use when starting any spex conversation to determine which workflow skill to invoke.
---

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a skill might apply to what you are doing, you ABSOLUTELY MUST read the skill.

IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. This is not optional. You cannot rationalize your way out of this.
</EXTREMELY-IMPORTANT>

# Getting Started with spex

## What is spex?

**SDD = Specification-Driven Development.** spex is the Claude Code plugin that implements it.

SDD is a development methodology where specifications are the single source of truth:
- Specs created before code
- Code validated against specs
- Specs evolve with implementation reality
- Quality gates enforce spec compliance

This plugin combines two upstream projects:
- **Superpowers** (by Jesse Vincent): Process discipline, TDD enforcement, verification gates, anti-rationalization patterns, and foundational skills (debugging, git worktrees, parallel agents)
- **Spec-Kit** (by GitHub): Specification templates, artifact management, and the `specify` CLI

spex extends these with spec-first enforcement, compliance scoring, drift detection, and evolution. Several upstream superpowers skills are modified with spec-awareness (verification, code review, brainstorming, plan review), while others are used unchanged.

## Technical Prerequisites

**All technical setup is automatic.** Every spex workflow skill calls `{Skill: spec-kit}` first, which handles initialization, installation, and validation internally. Do not check for or search for any CLI tools. Focus on choosing the right workflow.

## MANDATORY FIRST RESPONSE PROTOCOL

Before responding to ANY user message, you MUST complete this checklist:

1. ☐ List available spex skills in your mind
2. ☐ Ask yourself: "Does ANY spex skill match this request?"
3. ☐ If yes → Use the Skill tool to read and run the skill file
4. ☐ Announce which skill you're using
5. ☐ Follow the skill exactly

**Responding WITHOUT completing this checklist = automatic failure.**

## The Specification-First Principle

**CRITICAL RULE: Specs are the source of truth. Everything flows from and validates against specs.**

Before ANY implementation work:
- Spec must exist OR be created first
- Spec must be reviewed for soundness
- Implementation must validate against spec
- Spec/code mismatches trigger evolution workflow

**You CANNOT write code without a spec. Period.**

## Critical Rules

1. **Spec-first, always.** No code without spec. No exceptions.
2. **Follow mandatory workflows.** Brainstorm → Spec → Plan → TDD → Verify.
3. **Check for relevant skills before ANY task.** spex has skills for each phase.
4. **Validate spec compliance.** Code review and verification check specs.
5. **Handle spec/code drift.** Use spex:evolve when mismatches detected.

## Available spex Skills

### Primary Workflow (via spec-kit commands)
- `/speckit.specify` - Create specifications (superpowers trait adds review gate)
- `/speckit.plan` - Generate plan and tasks (superpowers trait adds spec review + plan review)
- `/speckit.implement` - Execute implementation (superpowers trait adds pre/post quality gates)

**NAMESPACE WARNING:** `/spex:specify`, `/spex:plan`, `/spex:tasks`, `/spex:implement` DO NOT EXIST. Always use the `/speckit.*` names above. The `spex:` namespace only contains helper skills (brainstorm, review-*, evolve, traits, init, help).

### spex Helper Skills
- **spex:brainstorm** - Rough idea → spec through collaborative dialogue
- **spex:review-spec** - Validate spec soundness and completeness
- **spex:review-plan** - Post-planning quality validation (coverage, red flags, task quality)
- **spex:review-code** - Review code-to-spec compliance
- **spex:evolve** - Handle spec/code mismatches with AI guidance
- **spex:verification-before-completion** - Tests + spec compliance validation
- **spex:spec-refactoring** - Consolidate and improve evolved specs

### Configuration
- **spex:traits** - Enable/disable spex discipline overlays (superpowers, teams)
- **spex:init** - Initialize project with spec-kit and spex configuration

### Compatible Superpowers Skills
These work as-is with spec context:
- **test-driven-development** - Use AFTER spec, during implementation
- **systematic-debugging** - Use spec as reference during debugging
- **using-git-worktrees** - For isolated feature development
- **dispatching-parallel-agents** - For independent parallel work

## Workflow Decision Tree

```
User request arrives
    ↓
Is this a new feature/project?
    Yes → Is it a rough idea?
            Yes → spex:brainstorm
            No → Create spec using /speckit.specify
    No → Does spec exist for this area?
            Yes → Is there spec/code mismatch?
                    Yes → spex:evolve
                    No → Need plan/tasks?
                            Yes → /speckit.plan
                            No → /speckit.implement
            No → Create spec first using /speckit.specify
```

## Creating Specifications

### Rough Idea → Use Brainstorm

```
User: "I want to add authentication to my app"
→ Use spex:brainstorm
```

**Brainstorm will:**
- Explore the idea through questions
- Propose approaches with trade-offs
- Refine requirements collaboratively
- Create formal spec using spec-kit

### Clear Requirements → Direct Spec Creation

```
User: "Add a POST /api/users endpoint that validates email and returns 422 on invalid format"
→ Create spec directly using /speckit.specify
```

**Direct spec creation:**
- Requirements are already clear
- No exploratory dialogue needed
- Use `/speckit.specify` to create the spec
- Follow spec-kit layout conventions

**WHAT vs HOW principle:**
Specs define WHAT and WHY, not HOW.
- ✅ WHAT: Requirements, behaviors, contracts, success criteria
- ❌ HOW: Algorithms, code, technology choices, architecture

## Common Rationalizations That Mean You're About To Fail

If you catch yourself thinking ANY of these thoughts, STOP. You are rationalizing. Check for and use the skill.

**Spec-avoidance rationalizations:**
- "This is too simple for a spec" → WRONG. Simple changes still need spec context.
- "I'll just write the code quickly" → WRONG. Code without spec creates drift.
- "The spec is obvious from the description" → WRONG. Make it explicit.
- "We can spec it after implementation" → WRONG. That's documentation, not spex.

**Skill-avoidance rationalizations:**
- "This is just a quick fix" → WRONG. Quick fixes need spec validation.
- "I can check the spec manually" → WRONG. Use spex:verification-before-completion.
- "The spec is good enough" → WRONG. Use spex:review-spec before implementing.
- "I remember this workflow" → WRONG. Skills evolve. Run the current version.

**Why:** Specs prevent drift. Skills enforce discipline. Both save time by preventing mistakes.

If a skill for your task exists, you must use it or you will fail at your task.

## Skills with Checklists

If a skill has a checklist, YOU MUST create TodoWrite todos for EACH item.

**Don't:**
- Work through checklist mentally
- Skip creating todos "to save time"
- Batch multiple items into one todo
- Mark complete without doing them

**Why:** Checklists without TodoWrite tracking = steps get skipped. Every time.

## Announcing Skill Usage

Before using a skill, announce that you are using it.

"I'm using [Skill Name] to [what you're doing]."

**Examples:**
- "I'm using spex:brainstorm to refine your idea into a spec."
- "I'm using /speckit.implement to build this feature from the spec."
- "I'm using spex:evolve to reconcile the spec/code mismatch."

**Why:** Transparency helps your human partner understand your process and catch errors early.

## Spec Evolution is Normal

Specs WILL diverge from code. This is expected and healthy.

**When mismatch detected:**
1. DON'T panic or force-fit code to wrong spec
2. DO use spex:evolve
3. AI analyzes: update spec vs. fix code
4. User decides (or auto-update if configured)

**Remember:** Specs are source of truth, but truth can evolve based on reality.

## Constitution: Optional but Powerful

Consider creating a constitution for your project:

**What is it?**
- Project-wide principles and standards
- Referenced during spec validation
- Ensures consistency across features

**When to create:**
- New projects: Early, after first feature spec
- Existing projects: When patterns emerge
- Team projects: Always (defines shared understanding)

**How to create:**
Use `/speckit.constitution`.

## Instructions ≠ Permission to Skip Workflows

Your human partner's specific instructions describe WHAT to do, not HOW.

"Add X", "Fix Y" = the goal, NOT permission to skip spec-first or verification.

**Red flags:** "Instruction was specific" • "Seems simple" • "Workflow is overkill"

**Why:** Specific instructions mean clear requirements, which is when specs matter MOST.

## Summary

**Starting any task:**
1. Check this skill first for routing
2. Determine: brainstorm vs. direct spec vs. implement vs. evolve
3. Invoke the appropriate workflow skill
4. That skill will call spec-kit for setup automatically
5. Follow the workflow discipline exactly

**The methodology is:**
- Specs first, always
- Code validates against specs
- Specs evolve when reality teaches us
- Quality gates prevent shortcuts
- Process discipline ensures quality

**The tools are:**
- spec-kit (technical integration)
- Workflow skills (brainstorm, implement, evolve)
- Verification and validation skills
- TDD and debugging skills

**The goal is:**
High-quality software with specs that remain the living source of truth.

## Workflow Patterns

### Pattern 1: New Feature from Rough Idea

```
User: "I want to add notifications to my app"

1. Recognize: Rough idea
2. Route to: spex:brainstorm
3. Brainstorm will:
   - Call spec-kit (auto-setup)
   - Explore idea collaboratively
   - Create formal spec
   - Hand off to /speckit.implement
```

### Pattern 2: New Feature from Clear Requirements

```
User: "Add GET /api/stats endpoint returning JSON with user_count and post_count"

1. Recognize: Clear requirements
2. Create spec using /speckit.specify
3. Route to: /speckit.implement
4. Implementation will:
   - Quality gates from superpowers trait overlay
   - Use TDD
   - Verify spec compliance
```

### Pattern 3: Code Exists, Spec Missing

```
User: "Document what this auth module does"

1. Recognize: Code without spec
2. Create spec by analyzing code
3. Route to: spex:evolve (to reconcile)
```

### Pattern 4: Code and Spec Diverged

```
User: "The login endpoint returns different errors than the spec says"

1. Recognize: Spec/code mismatch
2. Route to: spex:evolve
3. Evolve will:
   - Call spec-kit (auto-setup)
   - Analyze mismatch
   - Recommend update spec vs. fix code
   - User decides or auto-update
```

## Remember

**You are the methodology enforcer.**

- Route to correct workflow skill
- Enforce spec-first principle
- Catch rationalizations
- Ensure quality gates run

**You are NOT:**
- The technical setup manager (that's spec-kit)
- The implementer (that's workflow skills)
- The spec creator (that's spec-kit + brainstorm)

**Your job:**
Ensure the right skill gets used for the right task, and that spex principles are followed.

**The goal:**
Specs that stay current. Code that matches intent. Quality through discipline.
