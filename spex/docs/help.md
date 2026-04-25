                          spex Quick Reference

WORKFLOW

     ┌──────────┐      ┌──────────┐      ┌──────────┐
     │   IDEA   │─────▶│   SPEC   │─────▶│   PLAN   │
     └──────────┘      └──────────┘      └──────────┘
           │                │                   │
           │  /speckit-spex-brainstorm  /speckit-specify    /speckit-plan
           │                │                   │
           │    ┌───────────┤                   │
           │    │  OR       │                   │
           │    ▼           ▼                   ▼
           │  ┌──────┐  ┌──────────┐      ┌──────────────┐
           │  │ SHIP │  │  REVIEW  │      │  REVIEW PLAN │
           │  └──┬───┘  └──────────┘      └──────────────┘
           │     │   (auto via spex-gates hooks)    (auto via spex-gates hooks)
           │     │                                 │
           │     │   /speckit-spex-ship                    │
           │     │   (chains all                   ▼
           │     │    stages)              ┌──────────┐
           │     │                         │IMPLEMENT │
           │     │                         └──────────┘
           │     │                                 │  /speckit-implement
           │     │                                 ▼
           │     │                         ┌──────────┐
           │     │                         │  VERIFY  │
           │     │                         └──────────┘
           │     │                     (auto via spex-gates hooks)
           │     │                                 ▼
           │     │                         ╔══════════╗
           │     └────────────────────────▶║ COMPLETE ║
           │                               ╚══════════╝
           │                                   ▲
           │                            ┌──────┴─────┐
           │                            │   EVOLVE   │ /speckit-spex-evolve
           │                            └────────────┘
           │                                   ▲
           └───────────────────────────────────┘
                       (when drift detected)


SPEC-KIT COMMANDS (core workflow)

  /speckit-specify     Create or update feature specification
  /speckit-plan        Generate implementation plan from spec
  /speckit-tasks       Generate dependency-ordered tasks from plan
  /speckit-implement   Execute tasks from the implementation plan
  /speckit-checklist   Generate a custom checklist for the feature
  /speckit-clarify     Identify underspecified areas in the spec
  /speckit-analyze     Cross-artifact consistency and quality analysis
  /speckit-taskstoissues  Convert tasks into GitHub issues
  /speckit-constitution   Create or update project constitution


BUILT ON
  Superpowers (Jesse Vincent): Process discipline, TDD, verification,
                                anti-rationalization patterns
  Spec-Kit (GitHub):            Specification templates, artifacts,
                                `specify` CLI
  spex adds:                    Spec-first enforcement, compliance
                                scoring, drift detection, evolution


spex EXTENSIONS (quality gates for spec-kit commands)

  Extensions inject automated quality gates into the spec-kit workflow
  via lifecycle hooks. Enable them with `specify extension enable <name>`.

  spex-gates extension:
    /speckit-specify  → auto-runs spec review + constitution check
    /speckit-plan     → auto-runs spec review before planning,
                        plan review + task generation after,
                        commits spec artifacts, offers spec PR
    /speckit-implement → verifies spec package before starting,
                         runs code review + verification after

  spex-teams extension (experimental):
    /speckit-implement → parallel task execution via Claude Code
                         Agent Teams with spec guardian review

  spex-deep-review extension:
    /speckit-spex-review-code → runs 5 specialized review agents
                        (correctness, architecture, security,
                        production-readiness, test-quality) after spec
                        compliance passes, auto-fixes Critical/Important
                        findings (up to 3 rounds), writes
                        review-findings.md.
                        Combines with spex-teams for parallel execution.
                        Optionally includes CodeRabbit + Copilot CLIs.
                        Flags: --no-external, --no-coderabbit, --no-copilot
                               --external, --coderabbit, --copilot

  spex-worktrees extension:
    /speckit-specify  → creates git worktree for feature branch,
                        restores main
    /speckit-spex-worktree → list active worktrees, cleanup merged ones


spex COMMANDS (helpers and configuration)

  /spex:init                  Initialize spec-kit + configure extensions and permissions
  /speckit-spex-worktree      List active worktrees or cleanup merged ones
  /speckit-spex-brainstorm    Rough idea into formal spec (interactive dialogue)
  /speckit-spex-ship          Autonomous full-cycle pipeline (brainstorm to stamp)
                                Requires: spex-gates + spex-deep-review extensions
                                Flags: --ask always|smart|never, --create-pr,
                                       --resume, --start-from <stage>
  /speckit-spex-review-spec   Check spec quality and completeness
  /speckit-spex-review-plan   Validate plan coverage, task quality, red flags
  /speckit-spex-review-code   Check code compliance against spec
  /speckit-spex-stamp         Final gate (tests, hygiene, spec compliance)
  /speckit-spex-evolve        Reconcile spec/code drift
  /speckit-spex-help          This quick reference

  Extensions are managed via the specify CLI:
    specify extension enable <name>    Enable an extension
    specify extension disable <name>   Disable an extension


COMMON MISTAKES (do NOT use these)

  /spex:specify   ✗  Does not exist → use /speckit-specify
  /spex:plan      ✗  Does not exist → use /speckit-plan
  /spex:tasks     ✗  Does not exist → use /speckit-tasks
  /spex:implement ✗  Does not exist → use /speckit-implement
  /spex:brainstorm ✗  Old name → use /speckit-spex-brainstorm
  /spex:ship      ✗  Old name → use /speckit-spex-ship
  /spex:evolve    ✗  Old name → use /speckit-spex-evolve
  /spex:traits    ✗  Removed → use `specify extension enable/disable`

  Rule: spex commands use /speckit-spex-* prefix (brainstorm, review, evolve).
        Spec-kit commands use /speckit-* prefix (specify, plan, implement).
