# Full Introduction to SDD

## What is Specification-Driven Development?

**The Problem:** In traditional development, documentation drifts from code. Specs become outdated the moment implementation starts. Intent gets buried in implementation details.

**The Solution:** Make specifications the single source of truth. Code validates against specs. When they diverge, reconcile them through a deliberate process.

**SDD = Specifications that stay current, enforced by process discipline.**

### Building Blocks

SDD is built on two upstream projects:

- **Superpowers** (by Jesse Vincent): Process discipline, quality gates, TDD enforcement, anti-rationalization patterns, and foundational skills for debugging, git worktrees, and parallel agents.
- **Spec-Kit** (by GitHub): Specification templates, structured artifact management, and the `specify` CLI for project scaffolding.

SDD extends these foundations with:
- Specs as the single source of truth for all development
- Spec-first enforcement across the entire workflow
- Compliance scoring that validates code against spec requirements
- Spec/code drift detection with deliberate evolution
- Modified upstream skills (verification, code review, brainstorming) enhanced with spec-awareness

## The SDD Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   IDEA ──→ SPEC ──→ REVIEW ──→ IMPLEMENT ──→ VERIFY        │
│             ↑                                    │          │
│             │                                    ↓          │
│             └────────── EVOLVE ←──── (drift?) ──┘          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Phase 1: Ideation to Specification

Every feature starts as an idea. Before writing code, turn that idea into a formal spec.

**Two paths to specs:**

| Path | When to Use | Command |
|------|-------------|---------|
| Brainstorm | Rough idea, needs exploration | `/sdd:brainstorm` |
| Direct spec | Clear requirements, no ambiguity | `/speckit.specify` |

**Brainstorm workflow:**
1. You describe your rough idea
2. Claude asks clarifying questions (one at a time)
3. You explore 2-3 approaches with trade-offs
4. You refine requirements collaboratively
5. Claude creates a formal spec

**Direct spec workflow:**
1. You provide clear requirements
2. Claude creates spec using spec-kit templates
3. Spec is ready for review

**Spec structure:**
```markdown
# Feature: [Name]

## Purpose
Why this feature exists

## Requirements
### Functional Requirements
What it must do

### Non-Functional Requirements
Performance, security, etc.

## Success Criteria
How we know it works

## Error Handling
What can go wrong

## Edge Cases
Boundary conditions

## Dependencies
What it needs

## Out of Scope
What it explicitly doesn't do
```

### Phase 2: Specification Review

Before implementing, validate your spec.

**Command:** `/sdd:review-spec`

**What it checks:**
- Structure and completeness
- Clarity and lack of ambiguity
- Implementability
- Alignment with constitution (if exists)
- Missing edge cases or error handling

**Output:** Validation report with issues to address

### Phase 3: Implementation

Build from your validated spec using TDD.

**Command:** `/speckit.implement`

**What happens:**
1. Generates implementation plan FROM spec
2. Creates tests first (test-driven development)
3. Implements code to pass tests
4. Continuously validates against spec
5. Commits with spec reference

**Key principle:** The plan comes FROM the spec, not from scratch. The spec is your requirements document.

### Phase 4: Verification

After implementation, verify both tests and spec compliance.

**Automatic verification includes:**
- All tests pass
- Code matches spec requirements
- No unauthorized deviations

**If verification passes:** Feature complete.

**If drift detected:** Move to evolution phase.

### Phase 5: Evolution

Specs will drift from code. This is normal and healthy. The key is handling it deliberately.

**Command:** `/sdd:evolve`

**What happens:**
1. AI analyzes the mismatch
2. Determines: Is the code right (update spec) or is the spec right (fix code)?
3. Provides recommendation with reasoning
4. You decide (or auto-update based on threshold)
5. Alignment is restored

**Common drift causes:**
- Implementation revealed spec was incomplete
- Requirements changed during development
- Edge cases discovered during coding
- Better approach found during implementation

## Quality Gates

SDD enforces quality gates at key points:

| Gate | When | What's Checked |
|------|------|----------------|
| Spec Review | Before implementation | Spec completeness and clarity |
| Implementation | During coding | Tests + spec compliance |
| Verification | After coding | Full compliance check |
| Evolution | On drift | Deliberate reconciliation |

## The Constitution

For projects with multiple features or team members, create a constitution.

**What is it?**
- Project-wide principles and standards
- Referenced during all spec creation and review
- Ensures consistency across features

**Command:** `/sdd:constitution`

**What it defines:**
- Coding standards (naming, structure)
- Architectural patterns (how things fit together)
- Quality requirements (testing, performance)
- Error handling approaches
- Security requirements

**When to create:**
- New projects: After first feature spec
- Existing projects: When patterns emerge
- Team projects: Always (defines shared understanding)

## Traits: Quality Gates and Extensions

Traits are overlay modules that inject automated behavior into spec-kit commands. They add quality gates, reviews, and integrations without changing the core workflow.

### Managing Traits

```
/sdd:traits list              # Show which traits are active
/sdd:traits enable superpowers        # Enable sdd quality gates
/sdd:traits disable superpowers       # Remove sdd quality gates
```

You can also enable traits during `/sdd:init`.

### The Superpowers Trait

Named after the upstream Superpowers plugin whose process discipline it draws from, this trait adds automated quality gates at each workflow step:

| Command | What the superpowers trait adds |
|---------|------------------------|
| `/speckit.specify` | Auto-runs spec review + constitution check after spec creation |
| `/speckit.plan` | Runs spec review before planning. After planning: generates tasks, runs plan review, commits spec artifacts, offers a spec PR |
| `/speckit.implement` | Verifies the spec package before starting. Runs code review + verification after completion |

The spec PR flow is particularly useful for teams. After `/speckit.plan` completes, the trait commits all spec artifacts (spec.md, plan.md, tasks.md, REVIEWERS.md) and offers to create a PR targeting `upstream` if configured, otherwise `origin`.

### How Traits Compose

Traits are independent and can be enabled or disabled individually. Each trait uses sentinel markers (HTML comments like `<!-- SDD-TRAIT:superpowers -->`) in overlay files to prevent double-application. Enabling multiple traits stacks their additions on top of the base commands.

## Skill Lineage

Understanding where each skill comes from helps when troubleshooting or customizing:

**Modified from upstream Superpowers** (spec-awareness added):

| Skill | Upstream Origin | What SDD Adds |
|-------|----------------|---------------|
| `verification-before-completion` | Verification gates, anti-rationalization | Spec compliance validation, drift checking |
| `review-code` | Code review patterns | Compliance scoring against spec requirements |
| `brainstorm` | Design document generation | Output targets formal spec (WHAT/WHY), not design doc |
| `review-plan` | Plan writing patterns | Coverage matrix, red flag scanning, task quality enforcement |

**Used unchanged from upstream Superpowers:**
- `test-driven-development`, `systematic-debugging`, `using-git-worktrees`, `dispatching-parallel-agents`

**SDD-only skills** (no upstream equivalent):
- `using-superpowers`, `evolve`, `review-spec`, `spec-refactoring`, `spec-kit`, `constitution`

## Command Reference

### Spec Creation
| Command | Purpose |
|---------|---------|
| `/sdd:brainstorm` | Rough idea to spec through dialogue |
| `/speckit.specify` | Clear requirements to spec directly |
| `/sdd:constitution` | Project-wide principles |

### Validation
| Command | Purpose |
|---------|---------|
| `/sdd:review-spec` | Validate spec quality |
| `/sdd:review-code` | Check code-to-spec compliance |

### Implementation
| Command | Purpose |
|---------|---------|
| `/speckit.implement` | Spec to code with TDD |

### Evolution
| Command | Purpose |
|---------|---------|
| `/sdd:evolve` | Reconcile spec/code drift |

## FAQ

**Q: What if my feature is too small for a spec?**
A: Even small features benefit from spec context. A minimal spec (Purpose, Requirements, Success Criteria) is fine. The discipline matters more than the length.

**Q: Can I skip straight to code if I know exactly what I'm building?**
A: No. The spec is what you "know exactly." Write it down, then implement. This catches gaps you didn't realize existed.

**Q: What if the spec keeps changing during implementation?**
A: That's normal. Use `/sdd:evolve` to reconcile. The process makes changes deliberate rather than accidental.

**Q: How detailed should specs be?**
A: Detailed enough that implementation is unambiguous. If you're guessing during implementation, the spec needs more detail.

**Q: What about legacy code without specs?**
A: Create specs by analyzing existing code. Use `/sdd:evolve` to reconcile any differences between what the code does and what it should do.

**Q: Can multiple features share a spec?**
A: Generally no. Each feature should have its own spec. Use the constitution for shared patterns and principles.

## Key Principles Summary

1. **Spec-first, always** - No code without spec
2. **WHAT, not HOW** - Specs define requirements, code defines implementation
3. **Living specs** - Specs evolve with implementation reality
4. **Deliberate evolution** - Drift is handled explicitly, not ignored
5. **Process discipline** - Quality gates prevent shortcuts
6. **Single source of truth** - The spec is authoritative

## Getting Started

1. **First feature:** `/sdd:brainstorm` to create your first spec
2. **Review it:** `/sdd:review-spec` to validate
3. **Build it:** `/speckit.implement` with TDD
4. **If drift:** `/sdd:evolve` to reconcile
5. **For consistency:** `/sdd:constitution` to set project standards

The best way to learn SDD is to use it on a real feature. Start small, follow the process, and see how it feels.
