<!-- DEPRECATED: Replaced by spex/overlays/teams/commands/speckit.implement.append.md -->
<!-- Use the consolidated 'teams' trait instead of 'teams-spec'. -->

<!-- SDD-TRAIT:teams-spec -->
## Spec Guardian: Lead Reviews, Teammates Implement

When this trait is active, the lead acts as a **spec compliance guardian**.
The lead MUST NOT implement tasks itself. Instead, it spawns teammates in
git worktrees, reviews their completed work against spec.md, and only
merges compliant changes.

**This overrides teams-vanilla behavior** when both traits are active.

**Execution**: Delegate to {Skill: spex:teams-spec-guardian} for worktree
spawning, spec compliance review, and merge protocol.
