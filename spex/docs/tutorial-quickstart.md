# Quick Start Guide

## What is spex?

**Specification-Driven Development** = Specs are your single source of truth.

Traditional development: Code first, document later (if ever). Docs drift. Intent gets lost.

spex: Spec first, code validates against spec. Specs evolve with reality. Intent is preserved.

**The core loop:**
```
Idea → Spec → Code → Verify → (Drift? → Evolve)
```

## What's Inside

spex combines two foundations:

- **Superpowers** (by Jesse Vincent) provides process discipline: TDD, verification gates, anti-rationalization patterns, and skills like systematic debugging and parallel agent dispatch.
- **Spec-Kit** (by GitHub) provides the specification workflow: templates, structured artifacts, and the `specify` CLI for project setup.

spex adds the glue: specs as single source of truth, spec-first enforcement, compliance scoring, spec/code drift detection, and the evolution workflow. Several upstream superpowers skills are extended with spec-awareness (verification, code review, brainstorming), while others are used unchanged (TDD, debugging, git worktrees).

## The Three Phases

### 1. Specification Phase

**Turn ideas into specs before writing code.**

| Starting Point | Command | What Happens |
|----------------|---------|--------------|
| Rough idea | `/spex:brainstorm` | Collaborative dialogue refines idea into formal spec |
| Clear requirements | `/speckit.specify` | Create spec directly using spec-kit |

**Output:** A specification file in `specs/features/[name]/spec.md`

### 2. Implementation Phase

**Build from specs with TDD and compliance checking.**

| Command | What Happens |
|---------|--------------|
| `/speckit.implement` | Generates plan from spec, uses TDD, validates compliance |

**Output:** Working code that matches the spec

### 3. Evolution Phase

**When code and spec diverge (it happens), reconcile them.**

| Situation | Command | What Happens |
|-----------|---------|--------------|
| Spec/code mismatch | `/spex:evolve` | AI analyzes, recommends update spec vs fix code |

**Output:** Restored alignment between spec and code

## Command Decision Table

Use this to pick the right command:

| You Have | You Want | Use |
|----------|----------|-----|
| Vague idea | Clear spec | `/spex:brainstorm` |
| Clear requirements | Formal spec | `/speckit.specify` |
| Validated spec | Working code | `/speckit.implement` |
| Spec + code mismatch | Alignment | `/spex:evolve` |
| Draft spec | Validation | `/spex:review-spec` |
| Code changes | Compliance check | `/spex:review-code` |
| New project | Standards | `/speckit.constitution` |

## Quick Reference Card

```
SPEC CREATION
  /spex:brainstorm    Rough idea → spec (interactive)
  /speckit.specify          Clear reqs → spec (direct)
  /speckit.constitution  Project-wide principles

VALIDATION
  /spex:review-spec   Check spec quality
  /spex:review-code   Check code-to-spec compliance

IMPLEMENTATION
  /speckit.implement     Spec → code with TDD

EVOLUTION
  /spex:evolve        Fix spec/code drift
```

## Key Principles

1. **Spec-first, always** - No code without spec. Period.
2. **WHAT, not HOW** - Specs define requirements, not implementation details
3. **Evolution is normal** - Specs change as you learn. That's healthy.
4. **Quality gates** - Verification checks both tests AND spec compliance

## Enabling Traits

Traits are quality gates that automate reviews and validation at each workflow step. They inject checks into spec-kit commands so you don't have to remember to run them manually.

**Available traits:**

| Trait | Purpose |
|-------|---------|
| `superpowers` | Automated spec reviews, plan reviews, spec PR creation |
| `teams` | Parallel implementation via Claude Code Agent Teams (experimental) |

**How to enable:**

```
/spex:traits enable superpowers       # Enable quality gates
```

You can also enable traits during `/spex:init`.

**What changes with traits enabled:**

Without traits, you run each step manually:
```
/speckit.specify  →  /spex:review-spec  →  /speckit.plan  →  /spex:review-plan
```

With the superpowers trait, reviews happen automatically:
```
/speckit.specify  →  (review runs automatically)
/speckit.plan     →  (spec review before, plan review + tasks + spec PR after)
```

Traits are optional. Start without them to learn the workflow, then enable them when you want automated discipline.

## Common Mistakes to Avoid

**Don't:**
- Skip specs for "simple" features (they still need spec context)
- Put implementation details in specs (that's for code)
- Ignore drift warnings (use `/spex:evolve`)
- Write code then spec afterward (that's documentation, not Specification-Driven Development)

**Do:**
- Start every feature with a spec
- Keep specs focused on WHAT and WHY
- Use `/spex:evolve` when reality differs from plan
- Review specs before implementing

## Try It Now

Best way to learn: try it on a real feature.

1. Think of a feature you want to build
2. Run `/spex:brainstorm` to turn it into a spec
3. Run `/speckit.implement` to build it
4. See how the workflow feels

That's it. Specs first, code validates, evolve when needed.
