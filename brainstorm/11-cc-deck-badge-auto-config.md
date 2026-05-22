# Brainstorm: cc-deck Badge Auto-Configuration

**Date:** 2026-05-19
**Status:** active

## Problem Framing

The spex plugin uses cc-deck's sidebar badges to show workflow state (ship/flow mode, current phase). These badges require configuration in `~/.config/cc-deck/config.yaml` with specific badge rules, monochrome icons, and color prefixes. Currently, users must manually add this configuration. The `spex-init.sh` script (which runs at session start) should detect cc-deck and auto-configure the badge rules if they are not already present.

## Current State

- `spex-init.sh` at `spex/scripts/spex-init.sh` handles spec-kit initialization (CLI check, template refresh, project setup) but has no awareness of cc-deck
- Badge configuration lives in `~/.config/cc-deck/config.yaml` under the `badges:` key
- Three badge rules are needed:
  - `spex-mode`: shows `▶` (ship, amber #FFB43C) or `◆` (flow, teal #64C8BE)
  - `spex-ship-phase`: shows phase icon during ship pipeline (✎ ? ☑ ▦ ☰ ⚙ ◉ ✓)
  - `spex-flow-phase`: shows phase icon during step-by-step flow (same icons)
- All badges read from `.specify/.spex-state` (JSON file with `mode`, `stage`, `running` fields)

## Approaches Considered

### A: Patch config.yaml in spex-init.sh (Recommended)

During `spex-init.sh`, check if `~/.config/cc-deck/config.yaml` exists. If it does, check whether badge rules named `spex-mode`, `spex-ship-phase`, and `spex-flow-phase` already exist. If any are missing, append the default badge block using `yq` or a heredoc-based YAML append.

- Pros: Runs automatically at session start, idempotent, no user action needed
- Cons: Modifying another tool's config file requires care (preserve existing content, handle edge cases like missing `badges:` key)

### B: Separate setup command

Add a `/spex:setup-cc-deck` command that users run once to configure badges.

- Pros: Explicit, user controls when it runs
- Cons: Users forget to run it, one more manual step

### C: Ship a config fragment file

Install a `~/.config/cc-deck/conf.d/spex-badges.yaml` fragment (if cc-deck supports config fragments).

- Pros: Clean separation, no patching
- Cons: cc-deck does not support config fragments today

## Decision

**Approach A: Patch config.yaml in spex-init.sh.**

The init script already runs every session start and is idempotent. Adding a cc-deck detection step fits naturally. The badges are additive (they don't modify existing rules) and the check is simple (grep for rule names).

## Key Requirements

1. `spex-init.sh` MUST check if `~/.config/cc-deck/config.yaml` exists. If not, skip silently (cc-deck not installed).
2. If the config exists, check whether badge rules named `spex-mode`, `spex-ship-phase`, and `spex-flow-phase` are present (grep for the name strings).
3. If ALL three are present, skip (already configured).
4. If ANY are missing, append the full badge block to the config file. Use a heredoc for the YAML content.
5. The badge block MUST include the monochrome icons and color prefixes:
   - Mode badges: `"#FFB43C:▶"` (ship), `"#64C8BE:◆"` (flow)
   - Phase badges: `✎` (specify), `?` (clarify), `☑` (review), `▦` (plan), `☰` (tasks), `⚙` (implement), `◉` (stamp/finish), `✓` (done)
6. If the config file has no `badges:` key yet, add it. If it already has `badges:`, append the new rules to the existing list.
7. The script MUST NOT overwrite or modify existing badge rules (only append missing ones).
8. Print a one-line message when badges are configured: `[spex] cc-deck badges configured for workflow status`

## Implementation Notes

The badge YAML block to inject:

```yaml
  # Spex mode indicator (managed by spex-init)
  - name: spex-mode
    file: .specify/.spex-state
    format: json
    extract: .mode
    values:
      ship: "#FFB43C:▶"
      flow: "#64C8BE:◆"

  # Spex ship phase (managed by spex-init)
  - name: spex-ship-phase
    file: .specify/.spex-state
    format: json
    extract: .stage
    values:
      specify: "✎"
      clarify: "?"
      review-spec: "☑"
      plan: "▦"
      tasks: "☰"
      review-plan: "☑"
      implement: "⚙"
      review-code: "☑"
      stamp: "◉"
      finish: "◉"
      done: "✓"

  # Spex flow phase (managed by spex-init)
  - name: spex-flow-phase
    file: .specify/.spex-state
    format: json
    extract: .running
    values:
      specify: "✎"
      clarify: "?"
      review-spec: "☑"
      plan: "▦"
      tasks: "☰"
      review-plan: "☑"
      implement: "⚙"
      review-code: "☑"
```

Detection logic (pseudocode):
```bash
CC_DECK_CONFIG="$HOME/.config/cc-deck/config.yaml"
if [ -f "$CC_DECK_CONFIG" ]; then
  if ! grep -q "spex-mode" "$CC_DECK_CONFIG"; then
    # Check if badges: key exists
    if grep -q "^badges:" "$CC_DECK_CONFIG"; then
      # Append rules under existing badges key
      cat >> "$CC_DECK_CONFIG" << 'BADGES'
      ...
BADGES
    else
      # Add badges key and rules
      cat >> "$CC_DECK_CONFIG" << 'BADGES'
badges:
      ...
BADGES
    fi
    echo "[spex] cc-deck badges configured for workflow status"
  fi
fi
```

## Open Questions

- Should the script also handle updates (e.g., if the icon set changes in a future version)? A version comment in the YAML block could enable this: `# spex-badges-v1`. If the version changes, replace the block.
- Should the detection also check for the cc-deck CLI binary (`which cc-deck`) in addition to the config file?
- Should there be a `--no-cc-deck` flag on `spex-init.sh` to skip badge configuration?
