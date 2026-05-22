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
           │     │                         │  FINISH  │
           │     │                         └──────────┘
           │     │                        /speckit-spex-finish
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
                       TIP: Run /clear after tasks before implementing
                       to free context for the implementation phase
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
                        Fix loop runs project test suite after each round
                        (auto-detected or configured via test_command).
                        Correctness agent detects swallowed errors.
                        Test-quality agent cross-refs spec acceptance
                        scenarios against test verification methods.
                        Project hints via .specify/review-hints.md.
                        Combines with spex-teams for parallel execution.
                        Optionally includes CodeRabbit + Copilot CLIs.
                        Flags: --no-external, --no-coderabbit, --no-copilot
                               --external, --coderabbit, --copilot

  spex-worktrees extension:
    /speckit-specify  → creates git worktree for feature branch,
                        restores main (also auto-created by ship)
    /speckit-spex-worktrees-manage → list, create, finish, or cleanup worktrees

  spex-collab extension:
    /speckit-tasks    → auto-generates REVIEWERS.md, offers [Spec] PR
    /speckit-implement → presents phase split proposal (before hook)
    /speckit-spex-collab-phase-manager → PR creation + REVIEWERS.md updates per phase
    /speckit-spex-collab-revise   → revise spec from PR feedback, cascade plan/tasks
    /speckit-spex-collab-reconcile → scan code against revised tasks, produce delta


spex COMMANDS (helpers and configuration)

  /spex:init                  Initialize spec-kit + configure extensions and permissions
                                --refresh: update templates without reconfiguring
                                --update: upgrade specify CLI and refresh
                                --clear: reset status line state
  /speckit-spex-worktrees-manage  List active worktrees, finish, or cleanup merged ones
  /speckit-spex-brainstorm    Rough idea into formal spec (interactive dialogue)
  /speckit-spex-ship          Autonomous full-cycle pipeline (brainstorm to finish)
                                Requires: spex-gates + spex-deep-review extensions
                                Flags: --ask always|smart|never, --create-pr,
                                       --resume, --start-from <stage>
                                Worktree: auto-creates if spex-worktrees enabled
  /speckit-spex-finish        Verify + merge/PR/keep (all-in-one feature completion)
  /speckit-spex-review-spec   Check spec quality and completeness
  /speckit-spex-review-plan   Validate plan coverage, task quality, red flags
  /speckit-spex-review-code   Check code compliance against spec
  /speckit-spex-stamp         Verification only (use /speckit-spex-finish for full flow)
  /speckit-spex-evolve        Reconcile spec/code drift
  /speckit-spex-help          This quick reference

CLOSING OUT A FEATURE (after review passes)

  After /speckit-spex-review-code (or deep-review) passes:

    1. /clear                    Free context for final verification
    2. /speckit-spex-finish       Verify + merge/PR (all-in-one)

  /speckit-spex-finish runs all verification gates (tests, spec compliance,
  drift check), then offers merge/PR/keep options with automatic worktree
  cleanup. One command to close out a feature.

  Extensions are managed via the specify CLI:
    specify extension enable <name>    Enable an extension
    specify extension disable <name>   Disable an extension


PR TITLE CONVENTIONS

  Feature Name [Spec]              Spec-only PR for review
  Feature Name [Spec + Impl]       Spec + implementation (single phase)
  Feature Name [Spec + Impl (1/3)] Multi-phase implementation

  Labels (auto-applied, configurable in collab-config.yml):
    spex/spec           Spec under review
    spex/spec-approved  Spec approved, ready for implementation
    spex/implement      Implementation in progress
    Set labels.enabled: false to disable


COMMON MISTAKES (do NOT use these)

  /spex:specify   ✗  Does not exist → use /speckit-specify
  /spex:plan      ✗  Does not exist → use /speckit-plan
  /spex:tasks     ✗  Does not exist → use /speckit-tasks
  /spex:implement ✗  Does not exist → use /speckit-implement
  /speckit-spex-brainstorm ✗  Old name → use /speckit-spex-brainstorm
  /spex:ship      ✗  Old name → use /speckit-spex-ship
  /speckit-spex-evolve    ✗  Old name → use /speckit-spex-evolve
  /spex:traits    ✗  Removed → use `specify extension enable/disable`

  Rule: spex commands use /speckit-spex-* prefix (brainstorm, review, evolve).
        Spec-kit commands use /speckit-* prefix (specify, plan, implement).
