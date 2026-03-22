                          SDD Quick Reference

WORKFLOW

     ┌──────────┐      ┌──────────┐      ┌──────────┐
     │   IDEA   │─────▶│   SPEC   │─────▶│   PLAN   │
     └──────────┘      └──────────┘      └──────────┘
           │                │                   │
           │  /sdd:brainstorm  /speckit.specify    /speckit.plan
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
           │                            │   EVOLVE   │ /sdd:evolve
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
  SDD adds:                     Spec-first enforcement, compliance
                                scoring, drift detection, evolution


SDD TRAITS (quality gates for spec-kit commands)

  Traits inject automated quality gates into the spec-kit workflow.
  Enable them with /sdd:init or /sdd:traits enable <trait>.

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
                        restores main, writes context handoff file
    /sdd:worktree     → list active worktrees, cleanup merged ones


SDD COMMANDS (helpers and configuration)

  /sdd:init           Initialize spec-kit + configure traits and permissions
  /sdd:traits         Enable/disable traits (superpowers, teams, worktrees)
  /sdd:worktree       List active worktrees or cleanup merged ones
  /sdd:brainstorm     Rough idea into formal spec (interactive dialogue)
  /sdd:review-spec    Check spec quality and completeness
  /sdd:review-plan    Validate plan coverage, task quality, red flags
  /sdd:review-code    Check code compliance against spec
  /sdd:verify         Run verification (tests, hygiene, spec compliance)
  /sdd:evolve         Reconcile spec/code drift
  /sdd:help           This quick reference


COMMON MISTAKES (do NOT use these)

  /sdd:specify   ✗  Does not exist → use /speckit.specify
  /sdd:plan      ✗  Does not exist → use /speckit.plan
  /sdd:tasks     ✗  Does not exist → use /speckit.tasks
  /sdd:implement ✗  Does not exist → use /speckit.implement

  Rule: SDD commands are helpers (brainstorm, review, evolve).
        Spec-kit commands are the workflow (specify, plan, implement).
