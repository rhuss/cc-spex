
<!-- SPEX-TRAIT:superpowers -->
## Spex Quality Gates for Implementation

**Before implementation begins:**
1. Verify spec package exists: spec.md, plan.md, and tasks.md must all be present
2. If any are missing, stop and instruct the user to generate them first

**During implementation:**
- **NEVER modify CLAUDE.md automatically.** Do not append "Active Technologies", "Recent Changes", or any tracking sections. CLAUDE.md is for stable repo-level instructions maintained by the user. Only touch it when the user explicitly asks.

**After implementation completes:**
1. Invoke {Skill: spex:review-code} to check code compliance against spec
2. Invoke {Skill: spex:verification-before-completion} for the final stamp

## Context Management

**Before running code review**, consider running `/clear` to ensure an unbiased review. The reviewer should evaluate the code independently, without carrying context from the implementation process. An implementation-aware reviewer tends to confirm what was built rather than critically assess it. Spec-kit resolves all artifacts from the branch name automatically, so no context is lost.
