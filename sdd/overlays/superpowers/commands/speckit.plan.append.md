
<!-- SDD-TRAIT:superpowers -->
## SDD Quality Gates for Planning

**Before generating the plan:**
1. Invoke {Skill: sdd:review-spec} to validate the spec is sound
2. If review finds critical issues, stop and fix before planning

**After the plan is generated:**
1. Run `/speckit.tasks` to generate the task breakdown
2. Invoke {Skill: sdd:review-plan} to validate coverage, task quality, and generate REVIEW.md

**Pre-PR Quality Gate (mandatory):**

Before creating a spec PR, verify that ALL three quality checks have been completed:
1. `/sdd:review-spec` (spec soundness, completeness, implementability)
2. `/sdd:review-plan` (coverage matrix, task quality, REVIEW.md generation)
3. `/speckit.clarify` (clarification questions resolved, answers encoded in spec)

If any of these have NOT been run during this planning session, run them now before proceeding. Do NOT skip any of these steps. The REVIEW.md file MUST exist in the spec directory.

**Commit and PR:**
1. Commit spec artifacts (spec.md, plan.md, tasks.md, REVIEW.md) to the feature branch
2. **Ask the user** before creating a spec PR. Do NOT create a PR automatically.
   - If approved, proceed with:
   - Target remote: `upstream` if configured, otherwise `origin`
   - PR title: feature name from spec
   - PR body: summarize the feature, then direct reviewers to REVIEW.md
     in the spec directory for detailed review guidance
