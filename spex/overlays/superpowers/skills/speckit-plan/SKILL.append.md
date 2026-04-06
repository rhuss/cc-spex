
<!-- SPEX-TRAIT:superpowers -->
## Protect User-Maintained Agent Files

After Phase 1 runs `update-agent-context.sh`, immediately restore CLAUDE.md (and any other user-maintained agent file) to its pre-script state:

```bash
git checkout -- CLAUDE.md 2>/dev/null || true
```

The `update-agent-context.sh` script (from spec-kit) auto-generates "Active Technologies" and "Recent Changes" sections that overwrite user-curated content. CLAUDE.md is a user-maintained file, not an auto-generated one.

## Spex Quality Gates for Planning

**Before generating the plan:**
1. Invoke {Skill: spex:review-spec} to validate the spec is sound
2. If review finds critical issues, stop and fix before planning

**After the plan is generated:**
1. Run `/speckit-tasks` to generate the task breakdown
2. Invoke {Skill: spex:review-plan} to validate coverage, task quality, and generate REVIEWERS.md

**Pre-PR Quality Gate (mandatory):**

Before creating a spec PR, verify that ALL three quality checks have been completed:
1. `/spex:review-spec` (spec soundness, completeness, implementability)
2. `/spex:review-plan` (coverage matrix, task quality, REVIEWERS.md generation)
3. `/speckit-clarify` (clarification questions resolved, answers encoded in spec)

If any of these have NOT been run during this planning session, run them now before proceeding. Do NOT skip any of these steps. The REVIEWERS.md file MUST exist in the spec directory.

**Commit and PR:**
1. Commit spec artifacts (spec.md, plan.md, tasks.md, REVIEWERS.md) to the feature branch
2. **Ask the user** before creating a spec PR. Do NOT create a PR automatically.
   - If approved, proceed with:
   - Target remote: `upstream` if configured, otherwise `origin`
   - PR title: feature name from spec
   - PR body: summarize the feature, then direct reviewers to REVIEWERS.md
     in the spec directory for detailed review guidance
