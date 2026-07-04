# Brainstorm: Fix plugin discovery for marketplace installs

**Date:** 2026-07-04
**Status:** parked
**Issue:** [#7](https://github.com/rhuss/cc-spex/issues/7)

## Problem Framing

Claude Code can't find spex skills/hooks when installed from the public marketplace (`cc-rhuss-marketplace`). The plugin files are nested under `spex/` subdirectory, but Claude Code installs the entire repo root and doesn't follow the `source: "./spex"` field in the local marketplace.json.

## Investigation Findings

### What works
- **Local dev marketplace** (`make install`): The local marketplace at cc-spex root has `source: "./spex"`. Claude Code correctly follows this and installs only the `spex/` subdirectory content. All skills, hooks, and commands are found.
- **cc-copyedit**: Uses the same nested pattern (`copyedit/` subdir) and works from cc-rhuss-marketplace. However, cc-copyedit was installed when the marketplace was misconfigured (pointing directly to cc-copyedit directory, not to cc-rhuss-marketplace repo). So it was essentially a local directory install, not a GitHub-sourced one.

### What doesn't work
- **cc-rhuss-marketplace with GitHub source**: The marketplace entry uses `source: {source: "github", repo: "rhuss/cc-spex"}`. Claude Code clones the repo, finds `.claude-plugin/marketplace.json` at root, but doesn't follow `source: "./spex"` to the nested plugin directory. It installs the repo root instead.

### Root cause
Claude Code's plugin installer handles local directory sources differently from GitHub-cloned repos. For local directories, it follows the `source:` field in marketplace.json. For GitHub clones, it appears to use the repo root as the plugin root without resolving nested source references.

All cc-* plugins use the same structure: development repo with the actual plugin in a subdirectory (to separate dev artifacts like specs, tests, brainstorms from the distributed plugin content). This works for local dev but breaks for GitHub-sourced marketplace installs.

## Approaches Considered

### A: Add root-level discovery files
Add `plugin.json`, `skills/` symlink, and `hooks.json` at the repo root level. Claude Code finds the plugin at root without needing to follow `source:`.

- Pros: Works for both local and GitHub installs. No structural change needed.
- Cons: Symlinks may not work on Windows. Maintaining duplicate `plugin.json` is error-prone. Root level becomes cluttered with both dev files AND plugin files.

### B: Change marketplace to use local path
Change the cc-rhuss-marketplace entry to `source: "../cc-spex/spex"` (relative local path). 

- Pros: Follows existing working pattern. 
- Cons: Only works on your machine. Remote users can't install from GitHub marketplace.

### C: Restructure repo (move plugin to root)
Move `spex/` contents (skills, hooks, extensions, scripts) to the repo root. Dev files (specs, brainstorm, tests) stay where they are.

- Pros: Flat structure, no symlinks, works everywhere.
- Cons: Large structural change. Mixes plugin and dev files at root. Breaks existing scripts and paths.

### D: Separate distribution repo
Create a separate repo (cc-spex-dist) that contains only the plugin files. The marketplace references this clean repo. A release script copies from cc-spex/spex/ to cc-spex-dist/.

- Pros: Clean separation. GitHub install works on any machine.
- Cons: Two repos to maintain. Release process becomes more complex.

### E: Claude Code bug report
File a bug with Claude Code that GitHub-sourced marketplace installs don't follow the nested `source:` field. If fixed upstream, the current structure would work.

## Decision

**Parked.** Need to investigate whether this is a Claude Code bug (GitHub source not following nested marketplace source field) or intended behavior. If it's a bug, option E is the right path. If intended, option A or D is the likely fix. Should also check how superpowers and other official plugins handle this, since they work from GitHub sources.

## Open Questions

- Is the `source: "./subdir"` field in a cloned repo's marketplace.json supposed to be followed by Claude Code's installer?
- Does Claude Code have documentation on how nested plugin sources are resolved?
- Would symlinks in option A survive GitHub clone on all platforms (macOS, Linux, Windows)?
