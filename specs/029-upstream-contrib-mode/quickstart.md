# Quickstart: spex-detach Extension

## Setup

1. Run `specify init` in your fork's worktree and enable the `spex-detach` extension when prompted.

2. Configure the archive path (optional) in `.specify/extensions/spex-detach/spex-detach-config.yml`:
   ```yaml
   archive:
     path: "/path/to/your/project-specs-repo"
     auto_commit: true
   ```

## Workflow

1. **Specify, plan, implement** as usual (no changes to the standard SDD workflow).

2. **Finish**: Run `/speckit-spex-finish`. When `spex-detach` is enabled:
   - Specs are archived to the project-specs repo (if configured)
   - A clean PR branch `pr/<your-branch>` is created with only code changes
   - You're offered the option to push the clean branch for an upstream PR

3. **Iterate**: If the upstream PR needs revisions, make changes on the feature branch and re-run finish. The clean PR branch is regenerated.

## Manual detach

Run `/speckit-spex-detach-detach` to create the clean PR branch without going through the full finish flow.

## Verification

After finish, verify the clean branch:
```bash
git log --oneline pr/<your-branch>   # Should show single commit
git diff main...pr/<your-branch> --stat   # Should show only code files
```
