---
name: spex:traits
description: Manage spex trait overlays - enable, disable, or list active traits
argument-hint: "[list | enable <superpowers|teams|worktrees> | disable <superpowers|teams|worktrees>]"
---

# Spex Traits Management

Manage which spex traits are active. Traits inject discipline overlays into spec-kit command and template files.

**Valid traits**: `superpowers`, `teams`, `worktrees`

### Step 0: Resolve Script Path

Use `<spex-traits-command>` from the `<spex-context>` system reminder injected by the hook. This is the fully resolved path to `spex-traits.sh`.

If `<spex-context>` is not present, the hook may not have fired. Instruct the user to verify the plugin is installed correctly.

---

## Parse Arguments

Parse `$ARGUMENTS` for the subcommand and optional trait name:

- No arguments or `list` -> **List**
- `enable <trait-name>` -> **Enable**
- `disable <trait-name>` -> **Disable**

## Subcommand: List (default)

Run via Bash:

```bash
"<value from spex-traits-command>" list
```

Display the output to the user.

## Subcommand: Enable

Run via Bash:

```bash
"<value from spex-traits-command>" enable <trait-name>
```

Report the result to the user.

## Subcommand: Disable

1. Run `"<value from spex-traits-command>" list` and check if the trait is already disabled. If so, report that and STOP.
2. **Warn the user**: Disabling a trait requires regenerating all spec-kit files, which resets any manual customizations to `.claude/commands/speckit.*.md` and `.specify/templates/*.md` files.
3. Use `AskUserQuestion` to confirm:
   - **Question**: "Disabling a trait will reset all spec-kit files to defaults (losing any manual customizations). Proceed?"
   - **Header**: "Confirm"
   - **Options**:
     - Label: "Yes, disable", Description: "Reset spec-kit files and remove this trait's overlays"
     - Label: "Cancel", Description: "Keep current trait configuration unchanged"
4. If cancelled: report "Trait disable cancelled." and STOP.
5. If confirmed, run these commands sequentially via Bash:
   ```bash
   "<value from spex-traits-command>" disable <trait-name>
   specify init --here --ai claude --force
   "<value from spex-traits-command>" apply
   ```
6. Report which traits are still active.
