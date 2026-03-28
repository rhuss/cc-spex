# spex Plugin Design

**Date**: 2025-11-10
**Status**: Design Complete, Ready for Implementation

## Overview

A Claude Code plugin that merges superpowers' process discipline with specification-driven development (SDD), using specs as the single source of truth while maintaining workflow flexibility.

## Core Principles

- **Specs as source of truth** - Everything flows from specifications
- **Process discipline preserved** - All superpowers quality gates and workflow enforcement remain
- **Evolving specs** - Specs can evolve based on implementation reality with AI guidance
- **Intent before implementation** - "What" and "why" before "how"
- **Hybrid tooling** - Spec-kit CLI handles spec operations; spex adds workflow discipline
- **Flexible entry points** - Phase-specific skills for different starting contexts

## Architecture

```
User Request
     ↓
Phase-Specific Entry Point (/spex:brainstorm, /spex:spec, /spex:implement, /spex:evolve)
     ↓
Superpowers-spex Skill (workflow + validation + checklists)
     ↓
Spec-Kit CLI (for spec CRUD/validation) ← → Spec Files (specs/)
     ↓
Implementation (with TDD, code review, verification gates)
```

## Workflow Phases

### 1. Brainstorm Phase (`spex:brainstorm`)
- Starting point: Rough idea
- Process: Collaborative dialogue to refine concept
- Output: Formal spec created via `specify specify`
- Recommendation: Suggests constitution if none exists

### 2. Spec Phase (`spex:spec`)
- Starting point: Clear idea, need formal spec
- Process: Interactive spec creation with validation
- Output: Spec file with soundness validation
- Validation: Auto-validates against constitution if present

### 3. Implementation Phase (`spex:implement`)
- Starting point: Spec exists and validated
- Process: Plan → TDD → Code Review → Verify
- Key difference: Plans generated FROM spec, not from scratch
- Verification: Includes spec compliance checking

### 4. Evolution Phase (`spex:evolve`)
- Starting point: Code/spec mismatch detected
- Process: AI analyzes, recommends, user decides
- Options: Update spec, fix code, or clarify spec
- Automation: Configurable auto-updates for minor changes

## Skills Structure

### Phase Entry Points

**`spex:brainstorm`** - Modified `superpowers:brainstorming`
- Guides collaborative refinement
- Outputs spec instead of design doc
- Recommends constitution creation

**`spex:spec`** - Direct spec creation
- Bypasses brainstorming for clear requirements
- Interactive spec authoring
- Calls spec-kit CLI validation

**`spex:implement`** - Spec-to-code workflow
- Generates plan from spec
- Applies TDD during implementation
- Validates code-to-spec compliance

**`spex:evolve`** - Spec/code reconciliation
- Detects divergence
- AI-recommended resolution
- Configurable automation

### Modified Core Skills

**`spex:writing-plans`** - Plan generation from specs
- Input: Spec file (not blank slate)
- Output: Implementation tasks with file paths
- Validation: Plan completeness against spec

**`spex:review-code`** - Code-to-spec review
- Checks spec compliance
- Reports: compliance score + mismatches
- Triggers evolution workflow if needed

**`spex:verification-before-completion`** - Extended verification
- Step 1: Run tests (existing)
- Step 2: Validate spec compliance (new)
- Step 3: Check for spec drift (new)
- Blocks completion on failures

### New spex-specific Skills

**`spex:review-spec`** - Spec soundness review
- Validates structure and clarity
- Checks implementability
- Identifies ambiguities and gaps

**`spex:spec-refactoring`** - Spec consolidation
- For organically grown specs
- Identifies inconsistencies
- Maintains feature coverage

**`spex:spec-kit`** - CLI wrapper
- Intelligent delegation to spec-kit
- TodoWrite integration
- Error handling with context

**`spex:using-superpowers`** - Entry skill
- Mandatory workflow establishment
- Skill discovery and usage
- Process enforcement

### Preserved Skills (From Superpowers)

These work as-is, referenced by spex skills:
- `test-driven-development`
- `systematic-debugging`
- `using-git-worktrees`
- `dispatching-parallel-agents`
- Other non-conflicting skills

## Spec Evolution & Compliance

### Detection Points
- During code review
- During verification
- Explicit user invocation

### Decision Framework
1. AI analyzes mismatch (type, severity, impact)
2. AI recommends with reasoning:
   - Update spec (better approach discovered)
   - Fix code (deviation from design)
   - Clarify spec (ambiguity resolved)
3. User decides (or auto-update if configured)

### Configuration
```json
{
  "spex": {
    "auto_update_spec": {
      "enabled": true,
      "threshold": "minor",
      "notify": true
    }
  }
}
```

### Change Classification
- **Minor** (auto-update eligible): Naming, organization, implementation details
- **Major** (always manual): Architecture, behavior, requirements

### Versioning
- Git-based spec versioning
- Spec changelog auto-updated
- Links between spec versions and commits

## Repository Structure

```
cc-spex/
├── README.md                          # In-depth guide with examples
├── Makefile                           # Build and install targets
├── spex/                               # Nested plugin directory
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── skills/
│   │   ├── brainstorm/
│   │   ├── spec/
│   │   ├── implement/
│   │   ├── evolve/
│   │   ├── writing-plans/
│   │   ├── review-code/
│   │   ├── verification-before-completion/
│   │   ├── review-spec/
│   │   ├── spec-refactoring/
│   │   ├── spec-kit/
│   │   ├── constitution/
│   │   └── using-superpowers/
│   ├── commands/                      # Slash command implementations
│   └── scripts/                       # Maintenance scripts
├── .claude-plugin/
│   └── marketplace.json               # Local marketplace definition
├── examples/
│   └── todo-app/                      # Complete workflow example
│       ├── specs/
│       ├── docs/
│       └── src/
└── docs/
    ├── workflow-guide.md
    └── migration-from-superpowers.md
```

## Design Decisions

### Constitution: Optional but Recommended
- Not required for spec work
- Provides project-wide consistency
- User educated on benefits during first use

### Spec-Kit as Means, Not End
- Leverage spec-kit CLI where beneficial
- Replace/bypass if it creates friction
- Focus on spex goals, not tool compliance

### User Control on Automation
- AI makes recommendations with reasoning
- User configures automation threshold
- Transparency on all spec changes

### Phase Flexibility
- Entry points for different contexts
- No forced linear progression
- Spec always remains anchor point

## Impedance Resolutions

### Brainstorming → Spec Creation
- Brainstorming feeds into spec writing
- Output is spec, not design doc
- Skill modified accordingly

### Plans from Specs
- `writing-plans` reads spec as input
- No longer creates plans from scratch
- Validates plan against spec

### TDD Integration
- Spec first, then TDD during implementation
- Spec guides test structure
- Tests validate spec compliance

### Dual Review Types
- Code review: code-to-spec compliance
- Spec review: soundness and completeness
- Different skills for each

### Extended Verification
- Tests must pass (existing)
- Spec compliance must pass (new)
- Both required for completion

## Acknowledgements

- **Superpowers**: https://github.com/obra/superpowers by Jesse Vincent
- **Spec-Kit**: https://github.com/github/spec-kit by GitHub

## Next Steps

1. Create GitHub repository: `rhuss/cc-spex`
2. Implement all skill files
3. Create comprehensive README with practical examples
4. Build example todo-app demonstrating full workflow
5. Create plugin.json manifest
6. Add supporting documentation
