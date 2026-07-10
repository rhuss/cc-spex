# Review Guide: Neutral Command Vocabulary with Per-Harness Adaptation

**Generated**: 2026-07-09 | **Spec**: [spec.md](spec.md)

## Why This Change

Spex extension commands currently hardcode Claude Code-specific tool references (AskUserQuestion, Agent tool, subagent_type, EnterWorktree, settings.json, Agent Teams, CLAUDE_CODE_EXPERIMENTAL). This creates an upstream dependency: every command file must be maintained per-harness, and supporting Codex, OpenCode, or future harnesses means duplicating or branching all 30 command files. Brainstorm #28 identified this as the key blocker for multi-harness support.

## What Changes

All 8 command files containing CC-specific tool references are rewritten to use harness-neutral vocabulary with capability markers (`<!-- harness:X -->`) that identify sections needing harness-specific adaptation. A new `spex-adapt-commands.sh` script reads per-harness JSON mapping tables and transforms neutral commands into harness-optimized versions at setup time. The setup workflow gains an `adapt-commands` step that runs after extension installation. Claude Code users see zero behavioral change because the Claude mapping table restores all existing tool references.

## How It Works

The system has three layers:

1. **Neutral command files** (source of truth): Command markdown files use natural language for behavioral instructions ("present the user with a structured choice" instead of "use the AskUserQuestion tool"). Multi-line harness-specific blocks are wrapped in capability markers with neutral default text between them.

2. **Mapping tables** (`spex/scripts/adapters/<harness>/command-map.json`): Each harness has a JSON file defining inline text substitutions and section-level replacements keyed by capability marker name. Six capabilities are defined: `interactive-choice`, `subagent-dispatch`, `parallel-dispatch`, `agent-teams`, `worktree-isolation`, `harness-settings`.

3. **Adaptation script** (`spex/scripts/spex-adapt-commands.sh`): POSIX shell script that loads a mapping table, applies inline substitutions, replaces capability-marked sections, and writes results atomically (temp dir, then move). Supports `--dry-run` for diff preview. Exits cleanly if no mapping table exists (neutral passthrough). Integrates into `setup.yml` between `select-extensions` and `adapt-harness` steps.

Idempotency is by construction: setup reinstalls extensions from neutral source, then adapts. No reverse-adaptation logic needed.

## When It Applies

**Applies when**:
- Writing or modifying spex extension commands that reference harness-specific tools
- Running the setup workflow on a new project (`specify workflow run setup.yml`)
- Adding support for a new AI harness (create a mapping table, add a setup.yml case)

**Does not apply when**:
- Commands that already use neutral vocabulary (22 of 30 files are untouched)
- Upstream spec-kit CLI changes (no PRs to spec-kit core)
- Packaging the Claude Code mapping table as a separate installable preset (Phase 3, future)
- Creating community-maintained mapping tables for other harnesses (Phase 4, future)

## Key Decisions

1. **Neutral-first approach**: Commands are written neutral, with all harnesses (including Claude Code) receiving adaptation. More principled than writing for CC and de-specializing. Alternative: CC-first with stripping for other harnesses. Rejected because it makes CC the privileged default and complicates the data model.

2. **JSON mapping tables over YAML/TOML**: The project already requires `jq`. JSON avoids adding `yq` as a dependency and is natively parseable in shell. YAML was considered (more readable) but rejected to minimize dependencies.

3. **Capability markers via HTML comments**: `<!-- harness:X -->` syntax is invisible in rendered markdown, serves as machine-readable delimiters, and is familiar HTML comment syntax. Alternative: YAML frontmatter blocks. Rejected because commands aren't processed as frontmatter.

4. **Fallback notes over silent removal (FR-009)**: When a harness lacks a capability, the section is replaced with a plain-text note explaining the limitation rather than silently deleted. This gives users actionable context instead of mysterious gaps.

5. **Atomic writes via temp directory**: All files transform to a temp dir first, then move on success. Prevents partially transformed files on failure. Simple and shell-native.

6. **8 files in scope (not the full 30)**: Detailed grep audit confirmed only 8 of 30 command files contain CC-specific tool references. The remaining 22 are already neutral and untouched.

## Areas Needing Attention

- **Behavioral equivalence of neutral rewrites**: The neutral text between capability markers must convey the same behavioral intent as the CC-specific instructions. Subtle differences in wording could change how an LLM interprets the command on non-Claude harnesses. Review each rewrite carefully.

- **Mapping table completeness**: The Claude mapping table must restore every tool reference present in the pre-rewrite commands. Missing entries mean silent behavioral regressions for the primary user base. The pre-rewrite snapshot comparison (T015-T016) is the critical verification step.

- **Inline vs section-level boundary**: The heuristic (single tool name mention = inline, 2+ line blocks with parameters = section) is reasonable but requires judgment during the rewrite. Edge cases may need revisiting.

- **Capability marker naming**: Six markers are defined. Future commands may need new markers. The naming convention (`[a-z][a-z0-9-]*`) should be documented for contributors.

## Open Questions

No open questions identified. All ambiguities were resolved during the clarification session (canonical term: "capability marker", default fallback: replace with note, dry-run mode: yes).

## Review Checklist

- [ ] Key decisions are justified
- [ ] Breaking changes are documented with migration guidance
- [ ] Scope matches the stated boundaries (8 files, 6 capabilities, 3 mapping tables)
- [ ] Success criteria are achievable and measurable (SC-001 through SC-005)
- [ ] No unstated assumptions
- [ ] Capability marker syntax is consistent across all rewritten files
- [ ] Claude mapping table entries cover all pre-rewrite tool references
- [ ] spex-adapt-commands.sh handles edge cases (missing mapping table, malformed JSON, unmatched markers)
- [ ] setup.yml integration is positioned correctly in the step sequence

## Revision History

### Rev 1 (2026-07-09) - Address CodeRabbit/Devin bot review feedback

**Trigger**: PR review feedback from [#31](https://github.com/rhuss/cc-spex/pull/31) (CodeRabbit + Devin automated reviews)

**Spec changes**:
- Fixed file count "7" to "8" in assumptions section
- Aligned edge case fallback wording with FR-009 (plain-text note, not removal)
- Standardized FR-002 to use HTML-comment capability markers (was "design decision")
- Updated Capability Marker entity definition to match
- Renamed script from `adapt-commands.sh` to `spex-adapt-commands.sh` (naming convention)

**Quality gates**:
- review-spec: skipped (bot feedback, focused fixes)
- review-plan: skipped (bot feedback, focused fixes)

**Cascade impact**:
- plan.md: Fixed ship.md R1 count (7->8, total 44->45), renamed script, fixed constitution check, explicit step ordering, consistent snapshot path, version example "1.0" -> "1.0.0"
- tasks.md: Renamed script, T023 changed from delete to archive
- research.md: Fixed ship.md entry (added Agent Teams), total 44->45
- data-model.md: Renamed script, fixed version validation example
- REVIEWERS.md: Renamed script references, added revision history

### Rev 2 (2026-07-09) - Fix Rev 1 regressions and new bot findings

**Trigger**: PR review feedback from [#31](https://github.com/rhuss/cc-spex/pull/31) (Devin round 2, CodeRabbit round 2, Copilot)

**Spec changes**:
- Fixed smoke test wording: "skill files" to "command files" (spec.md:114)

**Quality gates**:
- review-spec: skipped (bot feedback, focused fixes)
- review-plan: skipped (bot feedback, focused fixes)

**Cascade impact**:
- plan.md: Fixed doubled script name `spex-spex-adapt-commands.sh` to `spex-adapt-commands.sh`, fixed "JSON/YAML" to "JSON" in storage description, fixed version "1.0" to "1.0.0" in cross-task interfaces
- tasks.md: unchanged
- REVIEWERS.md: revision history appended

---

<!-- Code phase sections are appended below this line by the phase-manager command -->
