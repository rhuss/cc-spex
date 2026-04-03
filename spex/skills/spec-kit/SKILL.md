---
name: spec-kit
description: Technical integration layer for the `specify` CLI (not speckit, not spec-kit) - handles automatic initialization, installation validation, project setup, and ensures proper file/directory layout. Called by all spex workflow skills.
user-invocable: false
---

# Spec-Kit Technical Integration

## CRITICAL NAMING - READ THIS FIRST

| What | Correct Name | WRONG Names |
|------|--------------|-------------|
| CLI command | `specify` | ~~speckit~~, ~~spec-kit~~ |
| Package name | `specify-cli` | ~~spec-kit~~, ~~speckit~~ |
| Slash commands | `/speckit.*` | (these are correct) |

**Installation:** `uv pip install specify-cli` or `pip install specify-cli`

## Purpose

This skill is the **single source of truth** for all spec-kit technical integration:
- Automatic initialization and setup
- Installation validation
- Project structure management
- Slash command availability
- Layout and file path enforcement

**This is a low-level technical skill.** Workflow skills (brainstorm, implement, etc.) call this skill for setup, then proceed with their specific workflows.

## CRITICAL: Understanding the Tool Architecture

**The `specify` CLI is a setup tool only.** It has three commands:
- `specify init` - Initialize a project with spec-kit templates and commands
- `specify check` - Check that required tools are installed
- `specify version` - Display version information

**All spec operations are done via `/speckit.*` slash commands**, which are installed by `specify init`:
- `/speckit.specify` - Create specifications
- `/speckit.plan` - Generate implementation plans
- `/speckit.tasks` - Generate task lists
- `/speckit.clarify` - Find underspecified areas
- `/speckit.analyze` - Cross-artifact consistency check
- `/speckit.checklist` - Generate quality checklists
- `/speckit.implement` - Execute implementation
- `/speckit.constitution` - Create project constitution

**NEVER call `specify validate`, `specify plan`, etc. - these commands don't exist!**

## Automatic Initialization

**IMPORTANT: This runs automatically when called by any workflow skill.**

Check `<spex-initialized>` in the `<spex-context>` system reminder:
- If `true`: Skip initialization entirely. The project is already set up.
- If `false` or missing: Run `{Skill: spex:init}` to initialize. If init prompts for restart, pause this workflow and resume after restart.

After initialization succeeds (or was skipped), this skill provides reference material below.

## Available Slash Commands

After `specify init`, these `/speckit.*` commands are available:

| Command | Purpose | Creates |
|---------|---------|---------|
| `/speckit.specify` | Create specification interactively | `specs/[NNNN]-[name]/spec.md` |
| `/speckit.plan` | Generate implementation plan | `specs/[name]/plan.md` |
| `/speckit.tasks` | Generate task list | `specs/[name]/tasks.md` |
| `/speckit.clarify` | Find underspecified areas | (analysis output) |
| `/speckit.analyze` | Cross-artifact consistency | (analysis output) |
| `/speckit.checklist` | Generate quality checklist | checklist file |
| `/speckit.implement` | Execute implementation | code files |
| `/speckit.constitution` | Create project constitution | `.specify/memory/constitution.md` |

**Usage in skills:**

When a skill needs to create a spec, plan, or tasks, it should:
1. Check that `/speckit.*` commands are available
2. Invoke the appropriate slash command
3. If commands not available, fall back to manual creation following templates

**Example:**
```
To create a spec, invoke: /speckit.specify

If /speckit.specify is not available (not initialized),
create the spec manually following .specify/templates/spec-template.md
```

## Branch Naming Convention

**Spec-kit requires feature branches named `NNN-feature-name`** where `NNN` is a three-digit numeric prefix matching the spec directory number.

| Pattern | Valid | Example |
|---------|-------|---------|
| `NNN-feature-name` | Yes | `002-operator-config` |
| `feature/name` | No | Fails branch validation |
| `spec/NNN-name` | No | Fails branch validation |
| `fix/NNN-name` | No | Fails branch validation |

The validation regex is `^[0-9]{3}-` (must start with exactly three digits followed by a hyphen).

**Why this matters:** Spec-kit uses the branch name to locate the corresponding spec directory under `specs/`. The numeric prefix links branch `002-operator-config` to `specs/002-operator-config/`.

**Validation helper:**

```bash
check_branch_for_speckit() {
  local branch=$(git branch --show-current)
  if [[ "$branch" =~ ^[0-9]{3}- ]]; then
    echo "valid: $branch"
  else
    echo "invalid: $branch (must match NNN-feature-name pattern)"
  fi
}
```

**If the branch name is wrong**, create or switch to a properly named branch before running any `/speckit.*` commands:

```bash
# Example: for spec in specs/002-operator-config/
git checkout -b 002-operator-config
```

## Layout Validation

Use these helpers to validate spec-kit file structure:

### Check Constitution

The constitution is stored at `.specify/memory/constitution.md` (the canonical location, matching upstream spec-kit).

```bash
# Check constitution location
if [ -f ".specify/memory/constitution.md" ]; then
  CONSTITUTION=".specify/memory/constitution.md"
  echo "constitution-exists: $CONSTITUTION"
else
  echo "no-constitution"
fi
```

### Get Feature Spec Path

```bash
# Validate feature spec path follows spec-kit layout
# Expected: specs/NNNN-feature-name/spec.md
# Or: specs/features/feature-name.md

validate_spec_path() {
  local spec_path=$1

  # Check if follows spec-kit conventions
  if [[ $spec_path =~ ^specs/[0-9]+-[a-z-]+/spec\.md$ ]] || \
     [[ $spec_path =~ ^specs/features/[a-z-]+\.md$ ]]; then
    echo "valid"
  else
    echo "invalid: spec must be in specs/ directory with proper naming"
  fi
}
```

### Get Plan Path

```bash
# Plan location (per spec-kit convention)
# Expected: specs/NNNN-feature-name/plan.md

get_plan_path() {
  local feature_dir=$1  # e.g., "specs/0001-user-auth"
  echo "$feature_dir/plan.md"
}
```

### Ensure Directory Structure

```bash
# Create spec-kit compliant feature structure
ensure_feature_structure() {
  local feature_dir=$1  # e.g., "specs/0001-user-auth"

  mkdir -p "$feature_dir/docs"
  mkdir -p "$feature_dir/checklists"
  mkdir -p "$feature_dir/contracts"

  echo "created: $feature_dir structure"
}
```

## Spec Discovery

When a workflow skill requires a spec file and none is specified, use this discovery protocol.

### List Available Specs

```bash
# Find all spec.md files in specs/ directory
fd -t f "spec.md" specs/ 2>/dev/null || find specs/ -name "spec.md" -type f 2>/dev/null

# Also check for direct .md files in specs/features/
ls specs/features/*.md 2>/dev/null
```

### Present Options to User

**If multiple specs found:**
Use AskUserQuestion to let user select which spec to use.

**If single spec found:**
Confirm with user before proceeding: "Found specs/0001-auth/spec.md. Use this spec?"

**If no specs found:**
Inform user and suggest creating one:
```
No specs found in specs/ directory.

To create a spec:
- Use `spex:brainstorm` to refine ideas into a spec
- Use `/speckit.specify` to create a spec from clear requirements
```

### Path Resolution Priority

When resolving a spec path:

1. **Exact path if provided** (e.g., `specs/0001-auth/spec.md`)
2. **Match by feature name in numbered directory** (e.g., `auth` -> `specs/0001-auth/spec.md`)
3. **Match by feature name in features directory** (e.g., `auth` -> `specs/features/auth.md`)

```bash
# Resolve feature name to spec path
resolve_spec_path() {
  local feature_name=$1

  # Check numbered directory pattern first
  local numbered=$(fd -t f "spec.md" specs/ 2>/dev/null | grep -i "$feature_name" | head -1)
  if [ -n "$numbered" ]; then
    echo "$numbered"
    return
  fi

  # Check features directory
  local features="specs/features/${feature_name}.md"
  if [ -f "$features" ]; then
    echo "$features"
    return
  fi

  # Not found
  echo ""
}
```

## Error Handling

### specify CLI Errors

**Command not found:**
- Provide installation instructions
- Suggest uv or pip installation

**Init fails:**
- Check write permissions
- Check disk space
- Suggest manual troubleshooting

### Slash Command Errors

**Commands not available:**
- Check if `specify init` was run
- Check if restart is needed
- Suggest re-initialization

**Command execution fails:**
- Display error message
- Suggest checking spec format
- Reference spec template

### File System Errors

**Permission denied:**
```
Cannot write to project directory.

Please ensure you have write permissions:
  chmod +w .
```

**Path not found:**
```
Expected file not found: <path>

This suggests incomplete initialization.
Run: specify init --force
```

## Integration Points

**Called by these workflow skills:**
- spex:brainstorm (at start)
- spex:evolve (at start)
- spex:review-spec (at start)
- spex:review-plan (at start)
- `/speckit.implement` via superpowers trait overlay (at start)
- All workflow skills that need spec-kit

**Calls:**
- `{Skill: spex:init}` (for initialization)
- `specify` CLI (for init only, via spex:init)
- `/speckit.*` slash commands (for all operations)
- File system operations

## Session Management

**First call in session:**
- Run full initialization protocol
- Check installation, project, commands
- Prompt restart if needed
- Set session flag

**Subsequent calls in session:**
- Check session flag
- Skip initialization if already done
- Optionally re-verify critical paths
- Return success immediately

**Session reset:**
- New conversation = new session
- Re-run initialization protocol
- Ensures project state is current

## CLI vs Slash Commands Summary

| Task | Tool | Command |
|------|------|---------|
| Initialize project | CLI | `specify init` |
| Check tools | CLI | `specify check` |
| Show version | CLI | `specify version` |
| Create spec | Slash | `/speckit.specify` |
| Generate plan | Slash | `/speckit.plan` |
| Generate tasks | Slash | `/speckit.tasks` |
| Find gaps | Slash | `/speckit.clarify` |
| Check consistency | Slash | `/speckit.analyze` |
| Generate checklist | Slash | `/speckit.checklist` |
| Execute implementation | Slash | `/speckit.implement` |
| Create constitution | Slash | `/speckit.constitution` |

## Remember

**This skill is infrastructure, not workflow.**

- Don't make decisions about WHAT to build
- Don't route to other workflow skills
- Just ensure spec-kit is ready to use
- Validate paths and structure
- Handle technical errors

**Workflow skills handle:**
- What to create (specs, plans, code)
- When to use which tool
- Process discipline and quality gates

**This skill handles:**
- Is specify CLI installed?
- Is project initialized?
- Are /speckit.* commands available?
- Do files exist in correct locations?

**The goal: Zero-config, automatic, invisible setup.**
