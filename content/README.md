# content

Content is data, not code (constitution VII). This folder holds the definition of that data and
the content itself.

| Folder | What | Who writes it |
| --- | --- | --- |
| `schemas/` | JSON Schema 2020-12, one file per pack part, plus `schema-set.json` (the set's version and the minimum app version per major). The only definition of content shared by the app, the backend and the solver. | Developers, by pull request |
| `examples/valid/<part>/` | At least one valid document per part, including the backend §9.3 trip made self-contained | Developers |
| `examples/invalid/<part>/` | Deliberately broken documents. `invalid/expected.json` names the field each one gets wrong: its schema path, or, for a document only a rule beyond shape refuses, the rule's `code` and `path` (checked in place of the sample's element). | Developers |
| `examples/sample/` | A small sample pack in the `content/source` layout that uses every part. `sample.golden.json` holds its checksums as version 1. | Developers |
| `examples/canonical-vectors.json` | Input and canonical-JSON pairs that the Python and Dart canonical forms must both reproduce | Developers |
| `source/` | Exports of the packs promoted to production, and nothing else (FR-040) | The publisher, by pull request |

- **Generated copies.** `wassal-content codegen` (in `tools/content_kit`) writes the server models
  (`tools/content_kit/src/wassal_content/models/_generated.py`), the app models
  (`packages/content_models/lib/src/generated/`) and a copy of `schemas/` inside the Python
  package. CI regenerates all three and fails on any difference.
- **Checks** (from `tools/content_kit`; the full table is in the root `CLAUDE.md`, "Content
  commands"):
  - `uv run wassal-content validate <file>` validates one document, and
    `uv run wassal-content validate-source <dir>` a whole layout;
  - `uv run wassal-content schema-diff --base <ref>` refuses a breaking schema change without a
    major-version bump, once `source/pack.json` exists;
  - `uv run wassal-content golden` checks the sample's checksums in `examples/sample.golden.json`.
    A change to the sample or to the pack format needs `golden --update` and a reviewed diff.
- **Changing a schema.** Edit `schemas/`, run `uv run wassal-content codegen`, rebuild
  `packages/content_models` with `build_runner`, and commit everything together. Add or adjust an
  example in `examples/valid/` or `examples/invalid/` (with its `expected.json` entry) for the
  change.
- **Contracts.** The shapes and rules are in `specs/003-b04-content-pipeline/contracts/`
  (`content-schemas.md`, `content-source.md`).
- **No real brands, government bodies or clubs, and no digits in player text** (R14): numbers go
  through placeholders, so the player's digit setting applies.

## Scenes

A chapter's scenes are comics of 3 to 5 panels (`schemas/chapter.schema.json`). Two conventions
tell the app how to play them (M07, `specs/012-m07-onboarding/contracts/scenes.md`):

- **`plays`** makes the app play a scene by itself:
  - `{"kind": "opening"}`: at the first open, before the Name card. Only in the chapter with
    `order` 1, at most once in the pack, and with no `trip_id` (`V-C3`).
  - `{"kind": "after_trip", "trip_id": "<trip_id>"}`: after that trip's first finish. The trip is
    in the pack, and each trip has at most one such scene (`V-C4`).
  - Without `plays`, a scene waits for M10's rules (album, chapter end).
- **`narrator`.** A panel line whose `speaker` is `narrator` is the panel's caption, drawn in its
  caption chip, not in a bubble. A panel has at most one, and it is the panel's first line
  (`V-C5`).
- The sample's chapter 1 uses both: `opening` plays first, and `the_stand` plays after
  `line_hay.03`.
