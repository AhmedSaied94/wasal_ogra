# Contract: The Story's Content Fields, from Schema to Admin

What the pack gains for M10, the rules that check it, what B04 stores, and what the sample holds.
Research R15, R16; spec FR-053–FR-055. M07's `contracts/scenes.md` and M09's `content-fields.md` are
the precedent; this follows their order of work.

## Schemas (`content/schemas/`)

Every object is closed and named in `$defs` (the restricted profile, B04 research R3). Optional means
left out of `required`.

### `common.schema.json`

```json
"StoryCharacter": {
  "description": "A story character (the design's character ids).",
  "type": "string",
  "enum": ["usta", "salma", "bride_father", "bride_mother", "moallem", "belya"]
}
```

### `chapter.schema.json`

`properties` gains five optional fields, and `Scene` gains a required `title`:

```json
"goal_art":        { "$ref": "common.schema.json#/$defs/Slug" },
"goal_line":       { "$ref": "#/$defs/CharacterLine" },
"ready_line":      { "$ref": "common.schema.json#/$defs/LocalizedText" },
"tagline":         { "$ref": "common.schema.json#/$defs/LocalizedText" },
"story_trip_info": { "$ref": "#/$defs/StoryTripInfo" }
```

```json
"CharacterLine": {
  "description": "A character's line on a screen (the goal card).",
  "type": "object", "additionalProperties": false,
  "required": ["speaker", "text"],
  "properties": {
    "speaker": { "$ref": "common.schema.json#/$defs/StoryCharacter" },
    "text":    { "$ref": "common.schema.json#/$defs/LocalizedText" }
  }
},
"StoryTripInfo": {
  "description": "How the chapter's story trip is presented: who rides, its title and condition (M10).",
  "type": "object", "additionalProperties": false,
  "required": ["title", "riders"],
  "properties": {
    "title":       { "$ref": "common.schema.json#/$defs/LocalizedText" },
    "condition":   { "$ref": "common.schema.json#/$defs/LocalizedText" },
    "fail_reason": { "$ref": "common.schema.json#/$defs/LocalizedText" },
    "riders": { "type": "array", "items": { "$ref": "#/$defs/StoryRider" }, "minItems": 1, "maxItems": 2 }
  }
},
"StoryRider": {
  "description": "A story character riding in a seat the trip leaves empty.",
  "type": "object", "additionalProperties": false,
  "required": ["character", "seat"],
  "properties": {
    "character": { "$ref": "common.schema.json#/$defs/StoryCharacter" },
    "seat":      { "type": "string", "pattern": "^(front|[A-D])_[rml]$" },
    "comments":  { "$ref": "#/$defs/RiderComments" }
  }
},
"RiderComments": {
  "description": "The speech pool a rider draws from, per mistake.",
  "type": "object", "additionalProperties": false,
  "properties": {
    "short_change":     { "$ref": "common.schema.json#/$defs/SpeechKey" },
    "false_accusation": { "$ref": "common.schema.json#/$defs/SpeechKey" },
    "fight":            { "$ref": "common.schema.json#/$defs/SpeechKey" },
    "missed_stop":      { "$ref": "common.schema.json#/$defs/SpeechKey" },
    "impatient":        { "$ref": "common.schema.json#/$defs/SpeechKey" }
  }
}
```

- `Scene.required` becomes `["scene_id", "title", "panels"]`, with
  `"title": { "$ref": "common.schema.json#/$defs/LocalizedText" }`.
- `ScenePlays.description` becomes "When the app plays the scene by itself. Absent: when the chapter's
  goal is met (M10)."
- The seat pattern is the one `trip.schema.json`'s `seat_id` uses. If that one is named in `$defs`, it
  is referenced instead.

### `room.schema.json`

```json
"art":       { "$ref": "common.schema.json#/$defs/Slug" },
"done_line": { "$ref": "common.schema.json#/$defs/LocalizedText" }
```

### `item.schema.json`

`required` gains `slot`; `properties` gains `slot` and `comment`; `ItemVariant` gains `comment`:

```json
"slot":    { "$ref": "#/$defs/ItemSlot" },
"comment": { "$ref": "common.schema.json#/$defs/LocalizedText" }
```

```json
"ItemSlot": {
  "description": "Where the piece sits in its room's drawing, in a 358×300 design space.",
  "type": "object", "additionalProperties": false,
  "required": ["x", "y", "w", "h"],
  "properties": {
    "x": { "type": "integer", "minimum": 0, "maximum": 334 },
    "y": { "type": "integer", "minimum": 0, "maximum": 276 },
    "w": { "type": "integer", "minimum": 24, "maximum": 358 },
    "h": { "type": "integer", "minimum": 24, "maximum": 300 }
  }
}
```

### `family_request.schema.json`

`required` gains `character`: `{ "$ref": "common.schema.json#/$defs/StoryCharacter" }`.

### Then

`uv run wassal-content codegen` (Pydantic, the schema copies), `build_runner` in
`packages/content_models`, and `codegen --check`. The generated Dart gains `StoryCharacter`,
`CharacterLine`, `StoryTripInfo`, `StoryRider`, `RiderComments`, `ItemSlot` and the new fields.

## Rules (`tools/content_kit/src/wassal_content/rules/references.py`)

| Code | Rule | Where |
| --- | --- | --- |
| V-C6 | `story_trip_info` only on a chapter with `story_trip_id` | `_chapter` |
| V-C7 | each rider's `seat` is one of the story trip's `seats[].seat_id`, no passenger of that trip has that `seat_id`, and the riders' seats differ | `_chapter` (after trips are indexed) |
| V-C8 | each `comments` key names a speech pool in the pack, and that pool's lines have no `{amount}` or `{station}` placeholder (a rider comment has neither) | `_chapter` |
| V-C9 | `fail_reason` only when the story trip has `rules.no_fights_required: true` | `_chapter` |
| V-C10 | at most one scene without `plays` per chapter | `_scene_plays` |
| V-C11 | `scene_id`s unique in the pack | `_scene_plays` (or V-U1 if it covers them) |
| V-C12 | at most two lines whose `speaker` isn't `narrator`, per panel | `_narrators` |
| V-R3 | `slot.x + slot.w ≤ 358` and `slot.y + slot.h ≤ 300` | `_item` |
| V-R4 | a request's `variant_id`, when present, is one of its item's `variant_id`s | `_family_request` (if V-R2 doesn't check it already) |

- Every new `LocalizedText` passes V-X1 (no digits) and V-X2 (no placeholders) automatically
  (`content_rules.localized_texts`).
- `specs/003-b04-content-pipeline/contracts/content-schemas.md`'s table lists the new codes.
- **Examples:** one valid file per new part shape (`valid/chapter/chapter_with_story_trip_info.json`,
  `valid/item/item_with_slot.json`), and one invalid file per rule and per schema refusal (a missing
  `slot`, a missing `title`, a missing `character`, `w` 10, an unknown `StoryCharacter`), each with
  its `expected.json` entry.

## B04 (`backend/apps/content/`)

| Where | Change |
| --- | --- |
| `models/story.py` `Chapter` | `goal_art` (slug, blank), `goal_line_speaker` (choices, blank), `goal_line_ar_eg`/`_ar`, `ready_line_*`, `tagline_*`, `story_title_*`, `story_condition_*`, `story_fail_reason_*` (text, blank); a check: `goal_line_speaker` set exactly when `goal_line_ar_eg` is; the story fields only with `story_trip` |
| `models/story.py` `StoryRider` (new) | `chapter` FK (`related_name="riders"`), `order` (1–2), `character` (choices), `seat_id` (slug), `comment_short_change`, `comment_false_accusation`, `comment_fight`, `comment_missed_stop`, `comment_impatient` (speech-key strings, blank); unique `(chapter, order)` and `(chapter, seat_id)` |
| `models/story.py` `Scene` | `title_ar_eg`/`_ar` |
| `models/story.py` `Room` | `art` (blank), `done_line_*` |
| `models/story.py` `Item` | `slot_x`, `slot_y`, `slot_w`, `slot_h` (positive small integers, checks for the bounds), `comment_*` |
| `models/story.py` `ItemVariant` | `comment_*` |
| `models/story.py` `FamilyRequest` | `character` (choices) |
| `migrations/0011_m10_story_fields.py` | adds every column with `db_default` (`""`, or `0` for the slot), and the `StoryRider` table; expand-only |
| `services/importer.py` | `chapter()` reads the five fields and recreates the riders; `room()`, `item()` (slot, comments, variants' comments), `request()` (character) |
| `services/snapshot.py` | `chapter_part`, `scene_part` (title after `scene_id`, in schema key order), `room_part`, `item_part`, `request_part` write the fields only when set, required ones always |
| `admin/authoring.py` | the fields on `ChapterAdmin`, `SceneInline`, `RoomAdmin`, `ItemAdmin`, `ItemVariantInline` and `FamilyRequestAdmin`; a `StoryRiderInline` (`max_num=2`) on `ChapterAdmin` |
| `services/lookups.py` | unchanged: `rules_document` reads none of these |
| tests | the sample round trip byte for byte (row count updated for the riders); `test_admin_authoring.py`; new `test_story_fields.py` (imports each new invalid example and expects the kit's refusal; the riders' order survives a round trip) |

`uv sync --reinstall-package wassal-content` in `backend/` picks up the regenerated kit. Rebuild the
dev stack's image after the schema change (`tools/content_kit/CLAUDE.md`).

## The sample pack (`content/examples/sample/`)

| File | Gains |
| --- | --- |
| `chapters/ch1_first_job.json` | `goal_art`, `goal_line` (moallem), `tagline`; titles on `opening` and `the_stand`; `story_trip_info` for `line_hay.03`: title, condition, `fail_reason`, one rider `moallem` in `A_l` with `comments.short_change` and `comments.fight` |
| `chapters/ch2_her_father.json` | a goal scene (three panels, `title`) and `goal_line`, `ready_line` |
| `chapters/ch3_shabka.json` | `goal_art`, `goal_line` (bride_mother), `ready_line` |
| `chapters/ch4_salon.json` | `tagline`; a goal scene (three panels, `title`) |
| `rooms/salon.json` | `art`, `done_line` |
| `items/salon.nish.json`, `items/salon.sitara.json` | `slot`; each variant's `comment`; `sitara` (one variant) its `comment` |
| `family_requests/req_nish_crystal.json` | `character: bride_mother` |
| `speech/story.moallem.short_change.json`, `speech/story.moallem.fight.json` | new pools, one or two lines each |

- No trip definition changes; `line_hay.03`'s passengers don't use `A_l`. The parity fixtures and
  `solver_fingerprint` stay as they are.
- Then `uv run wassal-content golden --update` (review the diff) and `bundle dev --out
  ../../apps/mobile/assets/content/dev`.
- The texts are drafts in the characters' voice, with no digits (V-X1).

## The release draft (handed over, `content-core-r1`)

The draft adds every field on its own branch (research R23). It also adds `plays: after_trip
line_gamaa.18` on `the_fatha`, and `story_trip_info` for its three story trips:

- `line_hay.20`: moallem in `A_m`;
- `line_gamaa.01`: bride_father in `front_r`, with a `fail_reason`;
- `line_gamaa.18`: bride_mother in `front_r` and salma in `A_r`.

The owner may rewrite every text.

## After merge

Packs built before the required fields (`Scene.title`, `Item.slot`, `FamilyRequest.character`) no
longer read. After the deploy, staging builds and publishes a fresh pack
(`docs/runbooks/content-publishing.md`, M09's note).
