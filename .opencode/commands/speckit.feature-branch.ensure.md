---
description: Check out the active feature's git branch, or create it if it does not exist
---


<!-- Extension: feature-branch -->
<!-- Config: .specify/extensions/feature-branch/ -->
# Ensure Feature Branch

Make sure the git branch of the active feature is checked out before the calling Spec Kit command does
any work. The active feature is the one recorded in `.specify/feature.json` (or set with
`SPECIFY_FEATURE_DIRECTORY`), which `/speckit.specify` writes when it creates a spec.

## Execution

Run from the repository root:

```bash
.specify/extensions/feature-branch/scripts/bash/ensure-feature-branch.sh --json
```

The script resolves the feature the same way the core scripts do, then:

- does nothing if the feature branch is already checked out (`ACTION` = `unchanged`);
- checks it out if it exists locally (`checked_out`);
- creates a local tracking branch if it exists only on a remote (`tracked`);
- otherwise creates it from the current HEAD (`created`).

A branch matches when its name equals the feature directory name (for example `001-app-shell`) or
ends with `/<feature directory name>`. If `SPECIFY_FEATURE` is set, that exact branch name is used.
The script never stashes, resets or discards changes.

## Output

On success the script prints one JSON line with `BRANCH_NAME`, `ACTION`, `PREVIOUS_BRANCH` and
`FEATURE_DIR`. Report it to the user in one line, for example:
`Switched to feature branch 001-app-shell (was master).`

## On failure

If the script exits non-zero:

- **Stop the calling command.** Do not continue its work on the wrong branch.
- Show the script's error output to the user.
- Do not stash, reset, check out or discard anything yourself to get past the error. Let the user
  decide.

If Git is not installed or this is not a Git repository, the script prints a warning and exits 0.
Continue normally in that case.