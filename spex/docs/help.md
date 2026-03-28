                          spex Quick Reference

WORKFLOW

     ┌──────────┐      ┌──────────┐      ┌──────────┐
     │   IDEA   │─────▶│   SPEC   │─────▶│   PLAN   │
     └──────────┘      └──────────┘      └──────────┘
           │                │                   │
           │  /spex:brainstorm  /speckit.specify    /speckit.plan
           │                │                   │
           │                ▼                   ▼
           │         ┌──────────┐      ┌──────────────┐
           │         │  REVIEW  │      │  REVIEW PLAN │
           │         └──────────┘      └──────────────┘
           │      (auto with superpowers trait) (auto with superpowers trait)
           │                                   │
           │                                   ▼
           │                            ┌──────────┐
           │                            │IMPLEMENT │
           │                            └──────────┘
           │                                   │  /speckit.implement
           │                                   ▼
           │                            ┌──────────┐
           │                            │  VERIFY  │
           │                            └──────────┘
           │                        (auto with superpowers trait)
           │                                   ▼
           │                            ╔══════════╗
           │                            ║ COMPLETE ║
           │                            ╚══════════╝
           │                                   ▲
           │                            ┌──────┴─────┐
           │                            │   EVOLVE   │ /spex:evolve
           │                            └────────────┘
           │                                   ▲
           └───────────────────────────────────┘
                       (when drift detected)


SPEC-KIT COMMANDS (core workflow)

  /speckit.specify     Create or update feature specification
  /speckit.plan        Generate implementation plan from spec
  /speckit.tasks       Generate dependency-ordered tasks from plan
  /speckit.implement   Execute tasks from the implementation plan
  /speckit.checklist   Generate a custom checklist for the feature
  /speckit.clarify     Identify underspecified areas in the spec
  /speckit.analyze     Cross-artifact consistency and quality analysis
  /speckit.taskstoissues  Convert tasks into GitHub issues
  /speckit.constitution   Create or update project constitution


BUILT ON
  Superpowers (Jesse Vincent): Process discipline, TDD, verification,
                                anti-rationalization patterns
  Spec-Kit (GitHub):            Specification templates, artifacts,
                                `specify` CLI
  spex adds:                    Spec-first enforcement, compliance
                                scoring, drift detection, evolution


SPEX TRAITS (quality gates for spec-kit commands)

  Traits inject automated quality gates into the spec-kit workflow.
  Enable them with /spex:init or /spex:traits enable <trait>.

  superpowers trait:
    /speckit.specify  → auto-runs spec review + constitution check
    /speckit.plan     → auto-runs spec review before planning,
                        plan review + task generation after,
                        commits spec artifacts, offers spec PR
    /speckit.implement → verifies spec package before starting,
                         runs code review + verification after

  teams trait (experimental):
    /speckit.implement → parallel task execution via Claude Code
                         Agent Teams with spec guardian review

  worktrees trait:
    /speckit.specify  → creates git worktree for feature branch,
                        restores main
    /spex:worktree     → list active worktrees, cleanup merged ones


SPEX COMMANDS (helpers and configuration)

  /spex:init           Initialize spec-kit + configure traits and permissions
  /spex:traits         Enable/disable traits (superpowers, teams, worktrees)
  /spex:worktree       List active worktrees or cleanup merged ones
  /spex:brainstorm     Rough idea into formal spec (interactive dialogue)
  /spex:review-spec    Check spec quality and completeness
  /spex:review-plan    Validate plan coverage, task quality, red flags
  /spex:review-code    Check code compliance against spec
  /spex:verify         Run verification (tests, hygiene, spec compliance)
  /spex:evolve         Reconcile spec/code drift
  /spex:help           This quick reference


COMMON MISTAKES (do NOT use these)

  /spex:specify   ✗  Does not exist → use /speckit.specify
  /spex:plan      ✗  Does not exist → use /speckit.plan
  /spex:tasks     ✗  Does not exist → use /speckit.tasks
  /spex:implement ✗  Does not exist → use /speckit.implement

  Rule: SPEX commands are helpers (brainstorm, review, evolve).
        Spec-kit commands are the workflow (specify, plan, implement).
