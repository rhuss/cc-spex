---
name: init
description: Initialize or update the project using the `specify` CLI (--refresh for templates, --update to upgrade CLI). Do NOT search for speckit or spec-kit binaries.
---

# SDD Init

**Note:** The init workflow is defined in `spex/commands/init.md` directly (not via skill reference) for higher compliance. This skill file exists as documentation only.

The init command:
1. Runs `spex-init.sh` (path from `<spex-init-command>` in hook context)
2. Asks user about trait selection and permissions
3. Runs `spex-traits.sh init` and `spex-traits.sh permissions`
4. Reports status and restart requirements

See `spex/commands/init.md` for the authoritative implementation.
