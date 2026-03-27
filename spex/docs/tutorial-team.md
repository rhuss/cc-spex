# Team Collaboration with SDD

## The Core Principle

**Share specs via PR before implementation for significant features.**

This lets the team align on WHAT before debating HOW.

Traditional approach: Write code, create PR, debate implementation details, realize requirements were misunderstood, rewrite.

SDD team approach: Create spec, get team alignment, then implement. The PR reviews the contract, not the code.

## When to Create Spec PRs

### Always Create Separate Spec PRs

**Major new features:**
- New user-facing functionality
- New API endpoints or services
- New integrations with external systems

**Architecture changes:**
- New patterns or conventions
- Changes to data models
- Infrastructure modifications

**Why:** These decisions affect everyone. Get alignment before investing in implementation.

### Judgment Call (Often Same PR is Fine)

**Minor features:**
- Small enhancements to existing features
- Bug fixes with clear solutions
- Internal refactoring

**Quick fixes:**
- Typo corrections
- Configuration changes
- Dependency updates

**Guideline:** If it takes longer to discuss than implement, just do it. If implementation is non-trivial, spec first.

## Team Feature Development Workflow

### Example: Adding User Authentication

```
1. CREATE BRANCH AND SPEC
   Developer creates feature branch
   Runs /sdd:brainstorm to create spec
   Spec lives at specs/features/authentication/spec.md

2. CREATE SPEC-ONLY PR
   gh pr create --title "RFC: User Authentication Spec"
   PR contains only the spec file
   No implementation code yet

3. TEAM REVIEWS SPEC
   Team reviews requirements, not code
   Discussion focuses on WHAT, not HOW
   "Do we need OAuth or is magic links enough?"
   "What error messages for failed login?"

4. SPEC APPROVED
   Team aligns on requirements
   Spec is merged to main
   Developer now has approved contract

5. IMPLEMENT IN SEPARATE PR
   Developer runs /speckit.implement
   Creates implementation PR
   Code review is faster: "Does this match the spec?"

6. MERGE AND SHIP
   Implementation matches approved spec
   No surprises at code review
   Feature ships with aligned expectations
```

## Spec as Contract

Think of specs as contracts between team members:

**The spec author promises:**
- Clear requirements
- Defined success criteria
- Considered edge cases
- Documented dependencies

**The reviewer promises:**
- Thorough review of requirements
- Raise concerns before implementation
- Approve = "I agree this is what we should build"

**The implementer promises:**
- Build exactly what's specified
- Use `/sdd:evolve` if reality differs
- Don't silently deviate from spec

## Traits for Team Workflows

For teams, enabling the **superpowers trait** is strongly recommended. It automates the review steps that catch issues early and integrates spec PRs directly into the workflow.

### Automated Spec PRs

With the superpowers trait enabled, `/speckit.plan` handles spec PR creation automatically:

1. Spec review runs before planning begins
2. Plan, tasks, and review summary are generated
3. All spec artifacts are committed to the feature branch
4. A spec PR is offered, targeting `upstream` if configured (for fork-based workflows) or `origin` otherwise

This fits naturally with the "Spec PRs before implementation" pattern described above. Instead of manually creating spec PRs, the trait handles it as part of the planning step.

## Multi-Developer Patterns

### Pattern 1: Spec Author != Implementer

```
Alice creates spec for authentication
Team reviews and approves spec
Bob implements from Alice's spec

Benefits:
- Fresh eyes catch spec gaps during implementation
- Knowledge sharing across team
- Reduces bus factor
```

### Pattern 2: Parallel Specs, Sequential Implementation

```
Sprint planning:
- Alice specs Feature A
- Bob specs Feature B
- Carol specs Feature C

After spec review:
- Implementation can happen in parallel
- Dependencies are clear from specs
- Integration points defined upfront
```

### Pattern 3: Spec Pairing

```
For complex features:
- Two developers brainstorm together
- One drives, one reviews in real-time
- Shared ownership of the spec

When to use:
- Features touching multiple systems
- High-risk or high-complexity work
- Onboarding new team members
```

## Code Review with Specs

With SDD, code review becomes simpler:

**Traditional code review questions:**
- "What is this trying to do?"
- "Why did you do it this way?"
- "Should this handle X edge case?"

**SDD code review questions:**
- "Does this match the spec?"
- "Any deviations to discuss?"
- "Tests cover the success criteria?"

**The spec answers the "what" and "why." Code review focuses on "how well."**

## Handling Disagreements

### During Spec Review

```
Reviewer: "I don't think we need OAuth, magic links are simpler"
Author: "Good point. Let me update the spec to explore both options"
[Spec is updated with comparison]
Team: "Let's go with magic links for v1, OAuth as future enhancement"
[Spec reflects decision]
```

**Key:** Decisions are captured in the spec. Future developers know WHY.

### During Implementation

```
Implementer: "The spec says X, but I discovered Y is better"
→ Don't silently change. Use /sdd:evolve
→ Create PR updating spec with reasoning
→ Team reviews the change
→ Spec and code stay aligned
```

## Onboarding New Team Members

SDD makes onboarding easier:

**New developer can:**
1. Read constitution to understand project standards
2. Read existing specs to understand features
3. See the "why" behind code decisions
4. Follow the same process as everyone else

**Onboarding workflow:**
```
1. /sdd:tutorial - Learn the methodology
2. Review constitution - Understand project standards
3. Review 2-3 feature specs - See examples
4. Pair on spec creation - Practice with support
5. Solo spec + review - Demonstrate understanding
```

## Team Adoption Tips

### Starting with SDD

**Week 1-2: Pilot**
- Pick one feature
- One developer creates spec
- Team reviews together
- Discuss what worked, what didn't

**Week 3-4: Expand**
- All new features get specs
- Create project constitution
- Refine process based on learnings

**Month 2+: Normal**
- SDD is default process
- Spec PRs are routine
- New members onboarded to process

### Common Adoption Challenges

**"This slows us down"**
- Front-loaded thinking reduces rework
- Code reviews are faster with spec context
- Fewer "I thought it meant X" moments

**"Specs become outdated"**
- That's what `/sdd:evolve` is for
- Deliberate evolution > silent drift
- Constitution defines update expectations

**"We don't have time for process"**
- Process prevents the bugs that steal time
- Clear specs reduce back-and-forth
- Aligned teams ship faster

## Summary

**For teams, SDD provides:**
- Shared understanding before implementation
- Clear contracts between team members
- Faster code reviews
- Easier onboarding
- Decisions captured with context

**Key practices:**
1. Spec PRs for significant features
2. Review specs before implementation
3. Use `/sdd:evolve` for any deviations
4. Constitution for shared standards
5. Treat specs as team contracts

**The goal:** Aligned teams shipping quality software with specs that remain the source of truth.
