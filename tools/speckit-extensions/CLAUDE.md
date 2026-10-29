# tools/speckit-extensions/CLAUDE.md

The source of the project's own Spec Kit extensions: `feature-branch` (checks out the active feature's branch before every step after specify) and `review` (`/speckit-review-implementation`). The project-wide rules are in the root `CLAUDE.md`.

- Edit an extension here, then reinstall it from the repo root with `specify extension add --dev tools/speckit-extensions/<name> --force`. Never edit the installed copy under `.specify/extensions/`, or the skill and command files the Specify CLI generates and hash-tracks (`.specify/integrations/*.manifest.json`).
- `specify extension add` writes commands for the default integration only. To give opencode an extension's commands as well, run `specify integration use opencode`, then `specify integration use claude`, then `chmod +x .specify/scripts/bash/*.sh` (the switch drops the bit).
