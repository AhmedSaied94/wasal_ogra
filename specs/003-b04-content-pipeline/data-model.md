# Data Model: Content Pipeline (B04)

B04 adds the Django app `apps/content`. It holds authored content, which mirrors the pack schemas
(backend §12 "content"), plus the pack records, the version lookups and the audit log. It also adds
files in the repository (schemas, examples, `content/source`) and on each host (pack files). Field
shapes inside packs are in [contracts/content-schemas.md](./contracts/content-schemas.md). This
document covers how they are stored and the rules that apply.

Conventions for every table below:

- `id` is a UUIDv7 primary key from `common.ids.uuid7()`, as B01's key check requires.
- Tables have `created_at`, and mutable ones also have `updated_at`.
- Arabic text is stored as two columns: `<name>_ar_eg`, a non-empty varchar or text, and
  `<name>_ar`, which may be empty. In the pack they become a `LocalizedText`. The text rules (no
  digits, placeholders) are checked at build time (R14).
- "Permanent" means the identifier can't be changed or the row deleted once its identifier is in
  `PublishedIdentifier` (FR-016). The guard lives in `save()` and in a `pre_delete` receiver, so it
  also covers queryset deletes. Services never use `QuerySet.update()` on identifier fields.

## Authored content (editable when `CONTENT_ROLE=source`, read-only when `target`)

### `content.Line` (FR-012)

| Field | Type | Rules |
| --- | --- | --- |
| `line_id` | varchar, unique | Glossary §3.6 closed set (`line_hay`, …). Permanent. |
| `name_ar_eg`, `name_ar` | text | Display name |
| `order` | smallint, unique | Order on the lines map |
| `unlock_kind` | enum `start`, `vehicle`, `line_complete` | product-spec «الخطوط» "يفتح بـ" |
| `unlock_vehicle` | FK `Vehicle`, null, PROTECT | Required if and only if `unlock_kind=vehicle` (form + build check) |
| `unlock_after_line` | FK `Line`, null, PROTECT | Required if and only if `unlock_kind=line_complete`. Not itself. |
| `difficulty_min`, `difficulty_max` | smallint 0–100 | `min ≤ max`. B05 defines the score. |
| `whats_new_ar_eg`, `whats_new_ar` | text | What Lines shows the line brings (M09, migration `0010`; `''` for rows from before it, which a build refuses) |
| `display_fare_piasters` | positive int | The card's fare chip, display only: ≥ 50 and a multiple of 50 (database check and `clean()`; M09, `0010`, default 50) |

### `content.Station`

| Field | Type | Rules |
| --- | --- | --- |
| `line` | FK `Line`, CASCADE | — |
| `station_id` | varchar | `^[a-z][a-z0-9_]{1,31}$`, unique per line. Permanent. |
| `name_ar_eg`, `name_ar` | text | — |
| `order` | smallint | Unique per line. Defines the station order on the line. |

### `content.Vehicle` and `content.Seat`

| `Vehicle` field | Type | Rules |
| --- | --- | --- |
| `vehicle_id` | varchar, unique | Glossary closed set. Permanent. |
| `name_ar_eg`, `name_ar` | text | — |
| `short_name_ar_eg`, `short_name_ar` | text | Its name on the Lines tile (M09, `0010`) |
| `starter` | bool | `true` for `tuktuk` (not owned, not sold). Starter vehicles have no catalog price, and every other vehicle has exactly one. |
| `order` | smallint, unique | — |

| `Seat` field | Type | Rules |
| --- | --- | --- |
| `vehicle` | FK `Vehicle`, CASCADE | — |
| `seat_id` | varchar | `^(front\|[A-D])_(r\|m\|l)$`, unique per vehicle. Permanent once the vehicle is published. |

A seat's row and column come from its `seat_id`. `reachable_by_driver` is true exactly for rows
`front` and `A` (mobile §7.7). Both are derived at build time, not authored. A vehicle's capacity is
its seat count.

### `content.Trip`, `TripStation`, `TripPassenger`, `TripEvent` (FR-004, FR-012, FR-023)

| `Trip` field | Type | Rules |
| --- | --- | --- |
| `line` | FK `Line`, PROTECT | — |
| `number` | smallint 1–99 | Unique per line. `trip_id = f"{line_id}.{number:02d}"`. Permanent: line and number together. |
| `vehicle` | FK `Vehicle`, PROTECT | — |
| `kind` | enum `regular`, `story` | — |
| `seed` | bigint 1–4,294,967,295 | Random on create. 0 is invalid for `xorshift32`. |
| `rev` | int ≥ 1, default 1 | The `rev` in the latest published pack. Written at publish (FR-023). Not editable in forms. |
| `max_earnings_jenehat` | int ≥ 0 | — |
| `star_two`, `star_three` | enum | `no_fights`; `no_fights_no_mistakes` (the only values in schema 1.0) |
| `student_discount_pct` | smallint 0–100 | — |
| `bag_fare_piasters` | int ≥ 0, multiple of 50 | — |
| `child_free_age` | smallint 0–18 | — |
| `max_break_requests` | smallint 0–2 | — |
| `tray_50` … `tray_20000` | 8 × smallint ≥ 0 | One per §3.2 denomination. They become `initial_tray`, and zero counts are omitted. |
| `author_notes` | text | Authoring only. Never in a pack. |

| `TripStation` field | Type | Rules |
| --- | --- | --- |
| `trip` | FK `Trip`, CASCADE | — |
| `station` | FK `Station`, PROTECT | Must be on the trip's line |
| `at_seconds` | smallint ≥ 1 | Strictly increasing in station order |
| `fare_piasters` | int ≥ 50, multiple of 50 | — |

A trip has 1 to 4 `TripStation`s (ux-spec «الألوان»), ordered by the line's station order.

| `TripPassenger` field | Type | Rules |
| --- | --- | --- |
| `trip` | FK `Trip`, CASCADE | — |
| `passenger_id` | varchar | `^p[0-9]{1,3}$`, unique per trip |
| `archetype` | enum | Glossary closed set |
| `skin` | varchar | `^[a-z][a-z0-9_]{1,47}$` |
| `seat` | FK `Seat`, PROTECT | Must belong to the trip's vehicle |
| `board_station` | FK `Station`, null | Null means the passenger is on board at the start. Otherwise it is a trip station before the destination. |
| `dest_station` | FK `Station` | Must be one of the trip's stations |
| `pays_at_seconds` | smallint ≥ 0, null | — |
| `payment` | int[] (PostgreSQL array) | 1 to 10 values, each a §3.2 denomination |
| `group_id` | varchar, empty when none | `^g[0-9]{1,2}$` |
| `group_size` | smallint 2–12, null | Set exactly when `group_id` is set. Members of a group agree on size, and at most that many members are listed (build check, V-T5). |
| `speech_keys` | jsonb, default `{}` | A map from role slug to `speech_key`. Each key must exist in a `SpeechPool` (build check). |
| `order` | smallint | Order in the trip |

| `TripEvent` field | Type | Rules |
| --- | --- | --- |
| `trip` | FK `Trip`, CASCADE | — |
| `event_id` | enum | Glossary closed set |
| `at_seconds` | smallint ≥ 0 | — |
| `passenger_ids` | varchar[] | Each one a passenger of the trip |
| `station_id` | varchar, empty when none | A station of the trip |
| `amount_piasters` | int, null | A multiple of 50 |
| `seconds` | smallint, null | — |
| `order` | smallint | — |

The event fields are a first cut for M01 (research, "Handed to later features").

### `content.Chapter`, `Scene`, `SceneLine` (FR-012, R15)

| `Chapter` field | Type | Rules |
| --- | --- | --- |
| `chapter_id` | varchar, unique | Glossary closed set. Permanent. |
| `order` | smallint, unique | — |
| `title_ar_eg`, `title_ar` | text | — |
| `goal_kind` | enum `complete_line`, `own_vehicle`, `purchase`, `complete_room` | Exactly the matching goal field below is set. `purchase` needs a catalog price `(chapter, chapter_id)`. |
| `goal_line` / `goal_vehicle` / `goal_room` | FK, null, PROTECT | — |
| `story_trip` | FK `Trip`, null, PROTECT | If set, its `kind` must be `story` |
| `completion_bonat` | int ≥ 0 | — |
| `goal_art` | varchar, blank | M10 (migration `0011`): the slug of a drawing the app ships |
| `goal_line_speaker`, `goal_line_ar_eg`, `goal_line_ar` | choices (`StoryCharacter`), text, blank | M10: a character's line on the goal card; the speaker is set exactly when the text is (database check) |
| `ready_line_*`, `tagline_*` | text, blank | M10 |
| `story_title_*`, `story_condition_*`, `story_fail_reason_*` | text, blank | M10: the pack's `story_trip_info` (`title`, `condition`, `fail_reason`). Only with `story_trip` (database check and `clean()`) |

| `StoryRider` field (M10, `0011`) | Type | Rules |
| --- | --- | --- |
| `chapter` | FK, CASCADE, `related_name="riders"` | The chapter's `story_trip_info.riders`, in order |
| `order` | smallint | 1 or 2; unique per chapter |
| `character` | choices (`StoryCharacter`) | `usta`, `salma`, `bride_father`, `bride_mother`, `moallem`, `belya` |
| `seat_id` | varchar | A seat of the story trip that no passenger sits in (V-C7); unique per chapter |
| `comment_short_change`, `comment_false_accusation`, `comment_fight`, `comment_missed_stop`, `comment_impatient` | varchar, blank | Speech keys of the pools the rider draws from (V-C8) |

| `Scene` field | Type | Rules |
| --- | --- | --- |
| `chapter` | FK, CASCADE | — |
| `scene_id` | varchar | `^[a-z][a-z0-9_]{1,31}$`, unique per chapter |
| `order` | smallint | — |
| `panel_art` | varchar[] | 3 to 5 art slugs, one per panel (product-spec «المشاهد») |
| `title_ar_eg`, `title_ar` | text | M10 (`0011`): the album's and the timeline's name for the scene; required by the schema, `''` for rows from before the migration, which a build refuses |

| `SceneLine` field | Type | Rules |
| --- | --- | --- |
| `scene` | FK, CASCADE | — |
| `panel` | smallint ≥ 1 | At most the number of panels |
| `order` | smallint | Order within the panel |
| `speaker` | varchar | `^[a-z][a-z0-9_]{1,31}$` (a character slug) |
| `text_ar_eg`, `text_ar` | text | Player-visible, so the text rules apply |

### `content.Room`, `Item`, `ItemVariant`, `FamilyRequest` (FR-012)

| Model | Fields and rules |
| --- | --- |
| `Room` | `room_id`: glossary closed set, unique, permanent. `name_*`. `chapter` (FK, PROTECT): the chapter that opens it. `order`. `completion_bonat` ≥ 0. M10 (`0011`): `art` (slug, blank), `done_line_*` (text, blank). |
| `Item` | `room` (FK, PROTECT). `slug`: `^[a-z][a-z0-9_]{1,31}$`, unique per room. `item_id = f"{room_id}.{slug}"`: permanent. `name_*`. `order`. Price: catalog `(item, item_id)` in JENEHAT. M10 (`0011`): `slot_x`, `slot_y`, `slot_w`, `slot_h` (small positive integers, a database check for each bound of the schema's `ItemSlot`; `0` in rows from before the migration, which `0011` lets pass and a build refuses), `comment_*` (text, blank). |
| `ItemVariant` | `item` (FK, CASCADE). `variant_id`: slug, unique per item, permanent. `name_*`. `art` slug. `order`. 1 to 3 per item, all at the item's price. M10: `comment_*` (text, blank). |
| `FamilyRequest` | `request_id`: `^req_[a-z0-9_]{1,40}$`, unique, permanent. `room` (FK). `item` (FK, in that room). `variant` (FK, null, of that item). `text_*`. `reward_bonat` > 0. M10 (`0011`): `character` (choices, `StoryCharacter`; blank in rows from before the migration, which a build refuses). |

### `content.SpeechPool` and `content.SpeechLine` (FR-017)

| Model | Fields and rules |
| --- | --- |
| `SpeechPool` | `speech_key`: `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$`, unique, permanent. `author_notes` (authoring only). |
| `SpeechLine` | `pool` (FK, CASCADE). `order` (smallint, unique per pool; the deterministic pick uses this order). `text_ar_eg`, `text_ar`. `reviewed_by` (staff username, varchar, empty when unreviewed). `reviewed_at` (timestamptz, null). |

**Review rule.** `save()` clears `reviewed_by` and `reviewed_at` whenever either text changes.
Setting a review requires `content.review_speech`, and only the service `review_lines(lines,
actor)` sets it. The writer may review their own lines. Usernames are stored as text, not as a
foreign key, so the content tables restore without the staff table (R8).

### `content.CatalogPrice` (FR-021, R15)

| Field | Type | Rules |
| --- | --- | --- |
| `sku_kind` | enum `item`, `vehicle`, `chapter`, `booster`, `fuel`, `revive`, `fuel_unlimited` | Phase 2 adds `upgrade` and `cosmetic` |
| `sku_id` | varchar | Unique together with `sku_kind`. It must resolve: an `item_id`, a non-starter `vehicle_id` or a `chapter_id` with a `purchase` goal. For the BONAT kinds it is a glossary `booster_id`: `change_bag`, `wake_all`, `ledger_peek` and `traffic_jam` for `booster`, `refuel_full` for `fuel`, `revive` for `revive`, and `fuel_unlimited_1h` for `fuel_unlimited`. |
| `currency` | enum `JENEHAT`, `BONAT` | Fixed by kind: JENEHAT for item, vehicle and chapter, BONAT for the rest (form + build check) |
| `amount` | int > 0 | — |

### `content.DailyRewardDay` and `content.TaskTemplate`

| Model | Fields and rules |
| --- | --- |
| `DailyRewardDay` | `day_index` 1–7, unique. `jenehat` ≥ 0. `bonat` ≥ 0. At least one of them > 0. All 7 days must exist (build check). |
| `TaskTemplate` | `task_id` (`^task_[a-z0-9_]{1,40}$`, unique, permanent). `metric` (`^[a-z][a-z0-9_]{1,40}$`; B08 will close the set). `target` (int ≥ 1). `text_ar_eg`, `text_ar` (may use `{target}`). `reward_jenehat` ≥ 0, `reward_bonat` ≥ 0, at least one > 0. `active` (bool; inactive templates stay out of packs). |

## Packs and their records

### `content.ContentChannel` (one row per `pack_id`; only `core` in the MVP, FR-034)

| Field | Type | Rules |
| --- | --- | --- |
| `pack_id` | varchar, unique | `core` |
| `last_assigned_version` | int ≥ 0 | Raised under `SELECT … FOR UPDATE` at each build on `source`. Starts from the R7 floor. |
| `current` | FK `ContentPack`, null | The pack the manifest offers by default. Changed only by publish or promote. |

### `content.ContentPack` (FR-020, FR-024–FR-032, FR-039a)

| Field | Type | Rules |
| --- | --- | --- |
| `pack_id` | varchar | `core` |
| `version` | int ≥ 1, null while queued | Unique together with `pack_id`. A built pack gets it when its build runs (R7); a promoted one has it from the start. |
| `origin` | enum `built`, `promoted` | `built` on `source`, `promoted` on `target` |
| `status` | enum `draft`, `validated`, `published`, `retired` | Transitions below |
| `build_state` | enum `queued`, `running`, `finished`, `failed` | For `built` packs only |
| `schema_version` | varchar | `MAJOR.MINOR` from `schema-set.json` at build time |
| `snapshot_at` | timestamptz | When the content was read (US3-7) |
| `canonical_sha256` | char(64) | Of the canonical JSON. Diagnostic only. |
| `sha256` | char(64) | Of the gzip file (R4). Immutable once `validated`. |
| `size` | int | Gzip byte length |
| `file` | bytea | The gzip bytes. Immutable once `validated`. |
| `validation_report` | jsonb | contracts/admin.md "Validation report". Immutable once `validated`. |
| `min_client_version` | varchar `^\d+\.\d+\.\d+$` | Mutable (FR-032), never below `min_client_version_by_major[major]` |
| `rollback_of` | FK `ContentPack`, null | Set when built by a rollback (FR-028) |
| `built_by`, `published_by`, `promoted_by` | varchar | Staff username, or empty |
| `built_at`, `published_at`, `promoted_at` | timestamptz, null | — |
| `release_sha256` | char(64), empty on drafts | Hash of the release record, which is the promotion code (R6) |
| `release_file` | bytea, empty until the first publish attempt | The release record's bytes, made once, so a retried publish and `content_files sync` write exactly the same file |
| `failure_reason` | text | Last failed build or publish reason (short, no secrets) |

**State transitions** (any other change is refused in `save()` and in the services):

```text
built:    (build requested) draft/queued → draft/running → draft/finished ─┬─ report green → validated
                                                     └ draft/failed      └─ report red   → draft (kept for its report)
          validated ──publish (source)──▶ published ──6th newer published──▶ retired
promoted: (promotion succeeds) ─────────▶ published ──6th newer published──▶ retired
```

- A `validated` pack whose version isn't higher than `ContentChannel.current.version` can't be
  published (US4-4).
- Once a pack is `published` or `retired`, only `min_client_version` (and the bookkeeping columns
  that move with status) may change (FR-027). Retiring deletes the pack's index rows (R12) but
  never its file or record.
- `draft` packs that failed or were never published are pruned after 30 days. Their version numbers
  are never reused (FR-039b).

### `content.PublishedIdentifier` (FR-016)

| Field | Type | Rules |
| --- | --- | --- |
| `kind` | enum `line`, `station`, `vehicle`, `seat`, `trip`, `chapter`, `scene`, `room`, `item`, `variant`, `request`, `speech_key`, `task` | — |
| `identifier` | varchar | The full identifier. Stations, seats, scenes and variants are qualified (`line_hay/kobri`, `micro_old/A_l`, `salon.nish/crystal`). |
| `first_version` | int | The first published pack that contained it |

Unique on `(kind, identifier)`. Rows are written on `source` when a pack is published there.
Promotion adds none: production authors nothing.

### `content.PackTripIndex` and `content.PackPriceIndex` (FR-035, R12)

| Table | Fields | Key |
| --- | --- | --- |
| `PackTripIndex` | `pack` (FK), `version`, `trip_id`, `rev`, `definition` (jsonb, the trip exactly as in the pack), `max_earnings_jenehat`, `last_station_at_s` | unique (`version`, `trip_id`) |
| `PackPriceIndex` | `pack` (FK), `version`, `sku_kind`, `sku_id`, `currency`, `amount` | unique (`version`, `sku_kind`, `sku_id`) |

Rows exist only for the last 5 published versions.

### `content.ContentAuditRecord` (FR-038)

| Field | Type | Rules |
| --- | --- | --- |
| `action` | enum `publish`, `promote`, `rollback`, `min_client_version_change` | — |
| `outcome` | enum `succeeded`, `failed` | — |
| `actor` | varchar | Staff username |
| `at` | timestamptz | — |
| `pack_id`, `version`, `sha256` | — | The pack acted on |
| `details` | jsonb | The validation report, or for a promotion the release record. Old and new values for a minimum-version change. The failure reason if it failed. |

Append-only: `save()` refuses updates, `delete()` refuses always, a database trigger (migration
`0005_audit_append_only`) refuses any `UPDATE` or `DELETE` that bypasses the model, and the admin
has no add, change or delete permission for any role, superuser included.

## Framework tables used

| Table | Use |
| --- | --- |
| `django_admin_log` | The change history of authored content (FR-018), shown on every content object's "History" page |
| `auth_group`, `auth_permission` | The `content_author` and `content_publisher` groups, created by a data migration with the custom permissions of research R9 |
| `django_celery_beat_periodictask` | Data migration rows for `content.sweep_stuck_builds` (every 10 min) and `content.sync_files` (daily, `--verify`) |

## Files

### In the repository

| Path | What | Owner |
| --- | --- | --- |
| `content/schemas/*.schema.json` | The schema set (contracts/content-schemas.md) | Hand-written |
| `content/schemas/schema-set.json` | `version` and `min_client_version_by_major` (R3) | Hand-written |
| `content/examples/valid/<part>/*.json`, `content/examples/invalid/<part>/*.json`, `content/examples/invalid/expected.json` | The example set (FR-009). `expected.json` maps each invalid file to the JSON path that must fail. | Hand-written |
| `content/examples/sample/` | The sample content in `content/source` layout, using every part of every schema | Hand-written |
| `content/examples/sample.golden.json` | Golden `canonical_sha256` and `sha256` of the sample pack built as version 1 (R4) | Generated by a test helper and reviewed |
| `content/source/` | Exports of packs promoted to production (FR-040). Empty with a README until the first promotion. | Exported |
| `tools/content_kit/src/wassal_content/models/_generated.py`, `…/schemas/*.json` | The server models and the packaged schema copy (R1, R13) | Generated, drift-checked |
| `packages/content_models/lib/src/generated/*.dart` | The app models (R1) | Generated, drift-checked |

### On each host

| Path | What | Who writes |
| --- | --- | --- |
| `/var/lib/wassal/packs/core-<v>.json.gz` | A published pack | The worker, create-only (R5) |
| `/var/lib/wassal/packs/core-<v>.release.json` | Its release record (R6) | The worker, create-only |
| `/var/lib/wassal/packs/core.floor.json` | Production only: the highest version it has stored (R7) | Production's worker, by atomic replace, never lowered |

Mode `0755` for the directory, owned by uid 10001 (the image's `app` user). Files are `0644`. The
floor file is the only one that is ever rewritten (contracts/pack-delivery.md "The floor file"). The
edge mounts the directory read-only at `/srv/packs`. Only the worker mounts it read-write. On dev it
is the `packs` volume at the same path, served by the API under `DEBUG`.

## Invariants

| Name | Checked by | Statement |
| --- | --- | --- |
| `content.published_packs_intact` | The restore drill (B01 registry), and the daily `sync_files --verify` | For every `published` or `retired` pack, `sha256(file) == sha256` and `len(file) == size` |
| One current pack | DB check at commit (migration 0002) + tests | `ContentChannel.current` is `published`, and has the highest `version` of all published packs for that `pack_id`. With nothing published it is empty. |
| Index matches pack | Tests | Index rows of version *v* equal what parsing pack *v*'s file gives |
| Versions never reused | Tests (R7) | No two `ContentPack` rows share `(pack_id, version)` in one environment. Staging never builds a version that production's pack files already have. |
