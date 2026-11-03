# Feature Specification: Modernize Generated Permission Rules

**Feature Branch**: `061-permission-rule-modernize`

**Created**: 2026-11-03

**Status**: Draft

**Input**: Brainstorm `brainstorm/55-permission-rule-modernize.md`: current Claude Code releases warn about the `Read(*)`, `Edit(*)` and `Write(*)` allow rules that spex writes for the YOLO permission level. New init must write the bare tool names, and `init --refresh` must repair existing projects.

## Clarifications

### Session 2026-11-03

- Q: Does a full init (not only refresh) also run the rule migration, for every permission level including Standard and None? → A: Yes. Every init entry point (interactive, workflow, refresh, update) runs it; it preserves meaning and is a no-op without legacy rules.
- Q: What exact format does the `Migrated:` line use? → A: `Migrated: <file> permissions: <old> -> <new>[, <old> -> <new>...]`, one line per changed file, rules in list order.
- Q: May the rewrite normalize the JSON formatting of a migrated file? → A: Yes. Values are preserved; layout is rewritten with 2-space indentation, as the existing init writes do. Files that need no change keep their exact bytes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fresh YOLO init produces warning-free rules (Priority: P1)

A developer runs `/spex:init` (interactive or through the workflow setup) and picks the YOLO permission level. When Claude Code restarts, it shows no warnings about the rules spex wrote, and the agent can read, edit and write files in every path, including sibling worktrees outside the working directory.

**Why this priority**: Every new YOLO project hits the warnings today. Fixing the generators stops the problem from spreading.

**Independent Test**: Run init with YOLO in an empty project and inspect `.claude/settings.json`: the allow list contains `Bash`, `Read`, `Edit`, `Write` and none of `Bash(*)`, `Read(*)`, `Edit(*)`, `Write(*)`.

**Acceptance Scenarios**:

1. **Given** a project without `.claude/settings.json`, **When** the user runs interactive init with YOLO, **Then** the written allow list contains bare `Bash`, `Read`, `Edit` and `Write` and no `Tool(*)` form of these four tools.
2. **Given** a project without `.claude/settings.json`, **When** the workflow setup runs with `security: yolo` for Claude, **Then** the written allow list contains bare `Bash`, `Read`, `Edit` and `Write` and no `Tool(*)` form of these four tools.
3. **Given** a project with an existing `.claude/settings.json` that holds the legacy rules, **When** the user runs init with YOLO, **Then** the resulting allow list holds only the bare forms of the four tools, each exactly once.

---

### User Story 2 - Refresh repairs existing projects (Priority: P1)

A developer whose project was initialized with an older spex version runs `/spex:init --refresh` (or `--update`). The legacy rules in the project's Claude settings are rewritten to the bare form, and refresh reports what changed. The next Claude Code start shows no warnings.

**Why this priority**: Existing projects never re-run full init. Without this, they keep the warnings indefinitely.

**Independent Test**: Put a settings file with `Read(*)`, `Edit(*)`, `Write(*)`, `Bash(*)` and an unrelated user rule into a project, run refresh, and compare: the four rules are bare, the user rule and all other keys are unchanged, and the output names the changes.

**Acceptance Scenarios**:

1. **Given** `.claude/settings.json` with `Read(*)`, `Edit(*)`, `Write(*)` and `Bash(*)` in `permissions.allow`, **When** refresh runs, **Then** those entries become `Read`, `Edit`, `Write` and `Bash`, and refresh prints a `Migrated:` line naming the file and the rewritten rules.
2. **Given** `.claude/settings.local.json` with any of the four legacy rules, **When** refresh runs, **Then** that file is migrated the same way and gets its own `Migrated:` line.
3. **Given** an allow list that holds both `Read` and `Read(*)`, **When** refresh runs, **Then** the result holds `Read` exactly once.
4. **Given** an allow list with user rules such as `Bash(npm test)`, `Read(~/notes/**)` or `Agent(*)`, **When** refresh runs, **Then** those rules are unchanged and keep their relative order.
5. **Given** a settings file that refresh already migrated, **When** refresh runs again, **Then** the file is not modified and no `Migrated:` line is printed for it.
6. **Given** a settings file with `defaultMode`, `hooks`, `statusLine` or other keys, **When** refresh migrates it, **Then** those keys and their values are unchanged.

---

### User Story 3 - Refresh never damages settings it cannot handle (Priority: P2)

A developer has a missing, partial or broken settings file. Refresh leaves it alone and, for broken JSON, says so.

**Why this priority**: Settings files also hold hooks from other tools (memory sync, cc-deck). A failed migration must never cost the user those entries.

**Independent Test**: Run refresh against an invalid JSON settings file and against a file without `permissions.allow`; both files are byte-identical afterwards, and only the invalid file produces a warning.

**Acceptance Scenarios**:

1. **Given** no `.claude/settings.json` and no `.claude/settings.local.json`, **When** refresh runs, **Then** no settings file is created and no migration output is printed.
2. **Given** a settings file without `permissions` or without `permissions.allow`, **When** refresh runs, **Then** the file is unchanged.
3. **Given** a settings file with invalid JSON, **When** refresh runs, **Then** the file is unchanged, a warning names the file, and refresh still completes.
4. **Given** a settings file whose `permissions.allow` is not a list, **When** refresh runs, **Then** the file is unchanged.

### Edge Cases

- An allow list with duplicate non-legacy rules (for example `Skill` twice) and no legacy rules is left unchanged.
- A legacy rule appears more than once in the same list: all copies collapse into one bare entry at the position of the first occurrence.
- Rules that only resemble the legacy forms (`Read(./*)`, `Bash(* )`, `bash(*)`, `Read(**)`) are not touched. Only exact string matches count.
- The legacy rules sit in `permissions.deny` or `permissions.ask`: these lists are not touched (spex never writes them).
- The settings file is a symlink: the migration updates the target content without replacing the link with a regular file. (Symlink handling in the init permission merge write is out of scope.)
- Refresh runs for a non-Claude harness (Codex, OpenCode): the Claude settings migration still applies when `.claude/` settings files exist, and does nothing otherwise.
- Standard and None permission levels: they write none of the four legacy rules, but init still migrates legacy rules already present (for example, a project that once used YOLO and is re-initialized as Standard).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Interactive init with the YOLO level MUST write `Bash`, `Read`, `Edit` and `Write` to `permissions.allow` instead of `Bash(*)`, `Read(*)`, `Edit(*)` and `Write(*)`.
- **FR-002**: Workflow setup with `security: yolo` for Claude MUST write `Bash`, `Read`, `Edit` and `Write` instead of the four legacy forms.
- **FR-003**: When init merges YOLO rules into an existing allow list, it MUST also rewrite any of the four legacy forms already present, so the result holds each bare form exactly once.
- **FR-004**: Every init entry point (interactive init, workflow setup, `init --refresh`, `init --update`) MUST migrate `.claude/settings.json` and `.claude/settings.local.json` of the current project when they exist, regardless of the chosen permission level (including Standard and None).
- **FR-005**: The migration MUST rewrite only the exact strings `Bash(*)`, `Read(*)`, `Edit(*)` and `Write(*)` in `permissions.allow`, each to its bare tool name.
- **FR-006**: When at least one legacy rule was rewritten, the migration MUST remove duplicate occurrences of the four bare names (`Bash`, `Read`, `Edit`, `Write`), keeping the first occurrence. All other entries, including their duplicates, MUST stay unchanged and in place.
- **FR-007**: The migration MUST leave every other key and value in the settings file unchanged, including `permissions.defaultMode`, `permissions.deny`, `permissions.ask`, `hooks` and `statusLine`.
- **FR-008**: The migration MUST NOT write a file whose content would not change.
- **FR-009**: For each file it changed, the migration MUST print exactly one line in the form `Migrated: <file> permissions: <old> -> <new>[, <old> -> <new>...]` (for example `Migrated: .claude/settings.json permissions: Read(*) -> Read, Edit(*) -> Edit`), listing each rewritten rule once, in list order. `<file>` is the path relative to the project root.
- **FR-009a**: A migrated file MAY have its JSON layout normalized to 2-space indentation; all values MUST be preserved. A file that needs no change MUST keep its exact bytes.
- **FR-010**: On every entry point in FR-004, the `Migrated:` lines and migration warnings MUST be visible to the user. For workflow setup, the setup report MUST include them. The init skill's report step MUST relay them for full init as well as refresh and update.
- **FR-011**: The migration MUST leave a settings file unchanged and MUST NOT fail the run when the file is missing, is not valid JSON, has a top-level value that is not an object, has a `permissions` value that is not an object, lacks `permissions.allow`, or has a non-list `permissions.allow`. For invalid JSON it MUST print a warning naming the file. Non-string entries inside `permissions.allow` MUST be kept as they are.
- **FR-011a**: If writing a migrated file fails, the original file MUST stay intact, a warning naming the file MUST be printed, and the run MUST NOT fail.
- **FR-012**: The migration MUST be limited to the project's settings files. It MUST NOT read or modify user-level settings (`~/.claude/settings.json`).
- **FR-013**: The init skill text MUST no longer state that refresh leaves permissions entirely unchanged; it MUST describe the rule migration.
- **FR-014**: The YOLO permission description in the init skill MUST explain that the bare tool names allow every path, so readers do not reintroduce the `(*)` forms.
- **FR-016**: The migration MUST be implemented once, in a script, and invoked by every entry point in FR-004. The init skill MUST NOT perform the rewrite in prose.
- **FR-017**: When init merges permission rules into an existing allow list, it MUST keep existing entries in their relative order and append only new entries (no alphabetical re-sorting of the user's list).
- **FR-015**: `spex/docs/help.md` (the `--refresh`/`--update` entry) and the README's refresh description MUST state that refresh rewrites the legacy `Bash(*)`, `Read(*)`, `Edit(*)` and `Write(*)` rules to bare names.

### Key Entities

- **Settings file**: `.claude/settings.json` (usually committed) or `.claude/settings.local.json` (personal). JSON object with an optional `permissions.allow` list of rule strings plus unrelated keys owned by the user or other tools.
- **Legacy rule**: one of the exact strings `Bash(*)`, `Read(*)`, `Edit(*)`, `Write(*)`, written by earlier spex versions.
- **Bare rule**: the tool name alone (`Bash`, `Read`, `Edit`, `Write`), which allows the tool for every path or command in all supported Claude Code versions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a fresh YOLO init, no `Bash(*)`, `Read(*)`, `Edit(*)` or `Write(*)` remains in `permissions.allow` of either project settings file (automated check), and Claude Code 2.1.317 shows zero permission-rule warnings for rules spex wrote (manual check).
- **SC-002**: After one refresh on a project with the legacy rules, none of the four legacy rules remains in either project settings file (automated check), and Claude Code 2.1.317 shows zero warnings for those rules without any manual edit (manual check).
- **SC-003**: Running refresh twice in a row produces no file changes and no `Migrated:` output on the second run.
- **SC-004**: In all migration test cases, 100% of non-legacy rules and non-permission keys survive unchanged.
- **SC-005**: No refresh run against a broken or partial settings file modifies that file.

## Assumptions

- Bare `Bash`, `Read`, `Edit` and `Write` grant the tool for all paths and commands in every Claude Code version spex supports, so the change needs no version check.
- `Read` stays in the YOLO list: it adds nothing inside the working directories but still matters for paths outside them, such as sibling worktrees and the sibling specs repository.
- `Agent(*)` and other `Tool(*)` rules are out of scope: the harness does not warn about them, and they are not file-path rules.
- Moving YOLO permissions into `settings.local.json` is handled separately (brainstorm #52, GitHub issue #62). This feature migrates rules in whichever file holds them.
- Anchoring `Bash(*spex-init.sh*)` and `Bash(*spex-ship-statusline.sh*)` is out of scope.
- Codex and OpenCode permission formats are out of scope.
- `jq` is available, as for the existing permission merge.
