# Contract: Onboarding Scenes, from Schema to Screen

When a scene plays, how a caption is written, what B04 stores, what the sample holds, and how the app
plays a scene. Spec FR-006–FR-010, FR-031, FR-046; research R5, R6, R13, R15, R20.

## Schema (`content/schemas/chapter.schema.json`)

Added to `$defs`, and `Scene` gains one optional property:

```json
"Scene": { "...": "...", "properties": { "scene_id": {}, "panels": {},
           "plays": { "$ref": "#/$defs/ScenePlays" } } },
"ScenePlays": {
  "description": "When the app plays the scene by itself. Absent: M10's rules (album, chapter end).",
  "type": "object", "additionalProperties": false,
  "required": ["kind"],
  "properties": {
    "kind": { "$ref": "#/$defs/ScenePlaysKind" },
    "trip_id": { "$ref": "common.schema.json#/$defs/TripId" }
  }
},
"ScenePlaysKind": { "type": "string", "enum": ["opening", "after_trip"],
  "description": "opening: at the first open, before the Name card. after_trip: right after the trip's first finish." }
```

- Then `uv run wassal-content codegen` (Python models and the schema copies), and `build_runner` in
  `packages/content_models`. The generated Dart: `ScenePlays`, `ScenePlaysKind`, `Scene.plays`.
- An example: `content/examples/valid/chapter_with_plays.json`, plus two invalid cases with their
  `expected.json` entries.

## Validator rules (content kit, `rules/references.py`)

| Code | Rule |
| --- | --- |
| V-C3 | `plays.kind == opening` only in the chapter with `order` 1, at most once in the pack, and with no `trip_id` |
| V-C4 | `plays.kind == after_trip` needs a `trip_id` naming a trip in the pack; at most one scene per trip |
| V-C5 | A panel's `narrator` line, if any, is its first line; at most one per panel |

The codes follow the existing V-C1–V-C2. The table in `tools/content_kit` docs lists them.

## Captions: the `narrator` speaker

- A `PanelLine` with `speaker: "narrator"` is the panel's caption: `ComicPanel`'s caption chip
  (`Intro` block 2a), never a bubble.
- It is documented in `content/README.md` ("Scenes") and B04's authoring notes. B04's admin shows it
  like any line.

## Backend B04 (`backend/apps/content/`)

| Where | Change |
| --- | --- |
| `models/story.py` `Scene` | `plays_kind = CharField(max_length=16, choices=[opening, after_trip], blank=True)`; `plays_trip = ForeignKey(Trip, null=True, blank=True, on_delete=PROTECT, related_name="+")`; a check constraint: `plays_trip` is set exactly when `plays_kind == "after_trip"` |
| `migrations/0009_scene_plays.py` | adds both fields and the constraint (expand-only) |
| `services/importer.py` `chapter()` | reads `plays` (resolving `trip_id` like `story_trip_id`) |
| `services/snapshot.py` `scene_part()` | writes `plays` when `plays_kind` is set, in schema key order |
| `admin/authoring.py` `SceneInline` | shows `plays_kind` and `plays_trip` |
| `services/lookups.py` `rules_document()` | unchanged: it lists scene ids only, and the server's rules don't use `plays` |
| `services/validation.py` (the pipeline) | runs the kit's rules (no change needed beyond the kit) |
| tests | the sample round trip (byte for byte), the record count, `test_lookups_rules.py`'s chapter 1 scenes, an import with each invalid `plays` |

`uv sync --reinstall-package wassal-content` in `backend/` picks up the regenerated kit.

## The sample pack (`content/examples/sample/chapters/ch1_first_job.json`)

- **A new first scene,** `opening`, with `plays: {kind: opening}`. Its text is the `Intro` artboard's,
  plus panels 2–3:

  | Panel `art` | Lines |
  | --- | --- |
  | `opening_key` | narrator: «الموقف، الصبح بدري» · moallem: «خد مفتاح التوكتوك. لمّ الأجرة صح، والباقي يرجع لصاحبه.» |
  | `opening_stand` | moallem: «الركاب بيدفعوا، والفلوس بتيجي لحد الدرج.» · usta: «وأنا أرجّع الباقي لكل واحد.» |
  | `opening_go` | belya: «وأنا معاك أول كام مشوار يا أسطى» · moallem: «يلا، على الله.» |

- `the_stand` gains `plays: {kind: after_trip, trip_id: line_hay.03}`.
- Then `uv run wassal-content golden --update` (review the diff) and
  `uv run wassal-content bundle dev --out ../../apps/mobile/assets/content/dev`.
- The trips don't change, so no parity fixture changes.
- V-X1 forbids digits in `LocalizedText`; none of these lines has one.

## The release draft (handed over, `content-core-r1`)

The draft's `ch1_first_job` gains `opening` first (the same three panels, or the owner's), `plays:
after_trip line_hay.03` on `first_sight`, and `plays: after_trip line_hay.20` on `moallem_verdict`.

## Panel art (`lib/core/art/panel_art.dart`)

- `PanelArt.assetFor(slug)` → `String?`, a const map from slug to `assets/illustrations/panels/<slug>.svg`.
- Today, the sample's six panels. `tool/design/sync_assets.dart` copies each drawing from
  `docs/design/illustrations/screens/`, and `design_assets_test` follows the mapping:

  | Slug | Copied from |
  | --- | --- |
  | `opening_key` | `Intro_01.svg` |
  | `opening_stand` | `PanelOpeningStand_01.svg` |
  | `opening_go` | `PanelOpeningGo_01.svg` |
  | `stand_morning` | `PanelStandMorning_01.svg` |
  | `salma_waiting` | `PanelSalmaWaiting_01.svg` |
  | `usta_decides` | `PanelUstaDecides_01.svg` |

- **`PanelFallback(speakers:, current:)`:** the panel's sky (`ColorTokens.sceneSky`), a street strip
  along the bottom, and each speaker (not `narrator`) as a `CharacterAvatar` at 1.6×, side by side,
  the current speaker in front. Used for every slug without a drawing.
- New drawings (owner step): one entry in the map and the asset, and the goldens change.

## The player (`ScenePlayer`, `lib/features/onboarding/presentation/scene_player.dart`)

Built to the `Intro` artboard:

| Block | Component |
| --- | --- |
| Background | `dashboard.bg` |
| Header | the chapter's title (`display.s`, `sun`) at the start; «تخطّى» pill 44 high at the end |
| Panel | `ComicPanel(art:, caption:, lines:)` 358×540, r `scene`, lip `lip.dark`. 008.5's `ComicPanel` takes one speaker and line; it is extended to a list of lines, so a panel can hold up to two bubbles, stacked |
| Dots | `PageDots(count, index)` (new, `core/theme/components/story.dart`) |
| CTA | `AppButton.primary(xl)` «يلا» |

- «يلا» advances; on the last panel it finishes.
- «تخطّى» and back finish.
- Finishing writes the flag (opening done, or the scene seen), then goes to the route's `then` (the
  opening: `/onboarding/name`).
- Semantics read order: title → caption → speaker and line → «اللوحة {n} من {total}» → «يلا» → «تخطّى».
- Strings: `introSkip` «تخطّى», `introNext` «يلا», `introPageOf` «اللوحة {n} من {total}».
- Motion: panel change ≤ 280 ms (`sheetIn`), bubble `bubblePop`; reduced motion: 150 ms fade.

## Routes

- `/onboarding/intro`: the pack's `opening` scene (redirected to `/onboarding/name` when none).
- `/onboarding/scene/:sceneId?then=…`: an `after_trip` scene by id; an unknown id goes to `then`.
