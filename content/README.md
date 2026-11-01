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
- **Checks** (from `tools/content_kit`; the full table is in
  `tools/content_kit/CLAUDE.md`):
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
  - Without `plays`, a scene plays when its chapter's goal is met (M10). A chapter has at most one
    such scene (`V-C10`), and `scene_id`s are unique across the pack (`V-C11`).
- **`narrator`.** A panel line whose `speaker` is `narrator` is the panel's caption, drawn in its
  caption chip, not in a bubble. A panel has at most one, and it is the panel's first line
  (`V-C5`). A panel has at most two lines from other speakers (`V-C12`).
- **`title`** (M10, required): the scene's name in the album and the timeline.
- The sample's chapter 1 uses both `plays` kinds: `opening` plays first, and `the_stand` plays
  after `line_hay.03`. Its chapters 2 and 4 each have a goal scene.

## What Lines shows (M09)

- A line's **`whats_new`** is the player text its card shows after its name: what the line brings
  that is new («نص الأجرة، الدفع الجماعي، …»). No digits and no edge spaces (`V-X1`).
- A line's **`display_fare_piasters`** is the fare on its card's chip: an integer, at least 50 and a
  multiple of 50. Display only: trips keep their own `fare_piasters`.
- A vehicle's **`short_name`** is its name on its tile («قديم · عربيتك»). The sheet and every label
  keep `name`.
- All three are required, so a pack built before them no longer reads
  (`specs/014-m09-lines-vehicles/contracts/content-fields.md`).

## What the apartment shows (M10)

Display only: no trip, engine rule or fixture reads these. Every text is a `LocalizedText`, so it
has no digits and no placeholders (`V-X1`, `V-X2`). Contract:
`specs/015-m10-apartment-story/contracts/content-fields.md`.

- **A chapter**'s goal card: `goal_art` (a slug of a drawing the app ships; a slug it has none for
  draws a plain fallback), `goal_line` (`{speaker, text}`, one of the six `StoryCharacter`s),
  `ready_line` (shown once the goal is met) and `tagline` (the timeline's line).
- **A chapter's story trip**, `story_trip_info`, only on a chapter that has `story_trip_id`
  (`V-C6`):
  - `title` and `condition` (the strip over the trip), and `fail_reason` (the failure card's line),
    which only a trip with `no_fights_required` may have (`V-C9`);
  - one or two `riders`, each a character in a seat the trip leaves empty (`V-C7`: one of the
    trip's seats, and no passenger's), with a speech pool per mistake in `comments`. A pool's lines
    hold no `{amount}` or `{station}` (`V-C8`), because a rider knows neither.
- **A room**: `art` (its drawing's slug) and `done_line` (what is said when it is complete).
- **An item**: `slot`, its place in the room's 358 × 300 drawing (`V-R3`: `x + w ≤ 358` and
  `y + h ≤ 300`), `comment` (the family's remark when it is bought) and a `comment` per style.
- **A family request**: `character`, who asks, and `variant_id` (when present, one of its item's
  styles, `V-R2`).
- The required ones, `Scene.title`, `Item.slot` and `FamilyRequest.character`, mean a pack built
  before them no longer reads: staging builds and publishes a fresh one after the deploy
  (`docs/runbooks/content-publishing.md`).
- The sample's chapter 1 has a rider, المعلم in seat `A_l` on `line_hay.03`, with two pools,
  `story.moallem.short_change` and `story.moallem.fight`.
