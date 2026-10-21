# Contract: Content Schemas (schema set 1.0)

This contract describes the content schemas, which live in `content/schemas/` (FR-001).

- **The shapes**: each `*.schema.json` file is JSON Schema 2020-12 within the profile of research
  R3, and is the authority.
- **Rules beyond shape**: this document defines what the schemas can't express, enforced by the
  validator (FR-021).
- **Changes**: the schemas may change freely until the first production promotion. After that,
  FR-010 and R3 apply.

## Files

| File | Root type | `$id` |
| --- | --- | --- |
| `common.schema.json` | none; `$defs` only | `https://wassal.invalid/content/1/common.schema.json` |
| `pack.schema.json` | `Pack` | `…/pack.schema.json` |
| `trip.schema.json` | `TripDefinition` | `…/trip.schema.json` |
| `line.schema.json` | `Line` | `…/line.schema.json` |
| `vehicle.schema.json` | `Vehicle` | `…/vehicle.schema.json` |
| `chapter.schema.json` | `Chapter` | `…/chapter.schema.json` |
| `room.schema.json` | `Room` | `…/room.schema.json` |
| `item.schema.json` | `Item` | `…/item.schema.json` |
| `family_request.schema.json` | `FamilyRequest` | `…/family_request.schema.json` |
| `speech_pool.schema.json` | `SpeechPool` | `…/speech_pool.schema.json` |
| `catalog.schema.json` | `Catalog` | `…/catalog.schema.json` |
| `daily_reward.schema.json` | `DailyRewardDay` | `…/daily_reward.schema.json` |
| `task.schema.json` | `TaskTemplate` | `…/task.schema.json` |
| `manifest.schema.json` | `Manifest` | `…/manifest.schema.json` |
| `schema-set.json` | not a schema | `{"version": "1.0", "min_client_version_by_major": {"1": "1.0.0"}}` |

- **`$id`s** use the reserved `.invalid` top-level domain, so nothing ever tries to fetch them.
  Validators load every file into one registry (R2).
- **The `/1/` in the path** is the schema set's major version. A breaking change moves every
  `$id` to `/2/`.

## Profile rules that hold everywhere

- Every object is `"additionalProperties": false`, except maps, which pair a value schema with
  `propertyNames`.
- No `null` and no default values. An optional field is left out, never set to `null`. Canonical
  documents therefore never contain `null`.
- Numbers are `integer` only (FR-003). Loaders refuse any number token with a `.` or an exponent
  (R2).
- Arrays that list things with an identifier are kept in authored order. The canonical form sorts
  object keys, never array items.

## `common.schema.json` `$defs`

| Name | Shape |
| --- | --- |
| `Piasters` | integer, `minimum: 0`, `multipleOf: 50` |
| `PositivePiasters` | `Piasters` with `minimum: 50` |
| `Denomination` | integer `enum: [50, 100, 500, 1000, 2000, 5000, 10000, 20000]` (glossary §3.2) |
| `DenominationKey` | string `enum: ["50", "100", "500", "1000", "2000", "5000", "10000", "20000"]`, used as a map key |
| `Amount` | integer `minimum: 0`, for JENEHAT and BONAT |
| `LocalizedText` | object `{ "ar-EG": string (minLength 1, required), "ar": string (minLength 1, optional) }` |
| `Slug` | string `^[a-z][a-z0-9_]{1,47}$` |
| `LineId` | `enum: ["line_hay", "line_gamaa", "line_souq", "line_masyaf", "line_safar"]` |
| `VehicleId` | `enum: ["tuktuk", "micro_old", "micro_new", "micro_safar"]` |
| `ChapterId` | `enum: ["ch1_first_job", "ch2_her_father", "ch3_shabka", "ch4_salon", "ch5_kitchen", "ch6_bedroom", "ch7_wedding"]` |
| `RoomId` | `enum: ["salon", "kitchen", "bedroom"]` |
| `Archetype` | the 18 glossary archetypes |
| `EventId` | the 8 glossary in-trip events |
| `BoosterId` | `enum: ["change_bag", "wake_all", "ledger_peek", "traffic_jam", "revive", "refuel_full", "fuel_unlimited_1h"]` |
| `Currency` | `enum: ["JENEHAT", "BONAT"]` |
| `TripId` | string `^line_[a-z]+\.[0-9]{2}$`. It must start with its own `line_id` (rule V-T1). |
| `StationId` | string `^[a-z][a-z0-9_]{1,31}$` |
| `SeatId` | string `^(front\|[A-D])_(r\|m\|l)$` |
| `ItemId` | string `^(salon\|kitchen\|bedroom)\.[a-z][a-z0-9_]{1,31}$` |
| `SpeechKey` | string `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$`, maxLength 64 |
| `ClientVersion` | string `^[0-9]+\.[0-9]+\.[0-9]+$` |
| `Sha256` | string `^[0-9a-f]{64}$` |

## `TripDefinition` (`trip.schema.json`, FR-004)

This is the self-contained trip the engine runs (mobile §7.2). Fields marked "opt." are optional.

| Field | Type | Notes |
| --- | --- | --- |
| `trip_id` | `TripId` | — |
| `rev` | integer ≥ 1 | — |
| `kind` | `enum: ["regular", "story"]` | — |
| `line_id` | `LineId` | — |
| `vehicle_id` | `VehicleId` | — |
| `seed` | integer 1–4294967295 | The `xorshift32` seed (mobile §7.10) |
| `seats` | array of `Seat` (1–20) | The vehicle's layout, copied in at build time |
| `stations` | array of `TripStation` (1–4) | In line order |
| `initial_tray` | map `DenominationKey` → integer ≥ 1 | Zero counts are left out |
| `rules` | `TripRules` | — |
| `passengers` | array of `PassengerSpec` (1–30) | — |
| `events` | array of `TripEvent` (0–10) | — |
| `star_rules` | `{ two: enum ["no_fights"], three: enum ["no_fights_no_mistakes"] }` | — |
| `max_earnings_jenehat` | `Amount` | — |

| `$defs` type | Fields |
| --- | --- |
| `Seat` | `seat_id` (`SeatId`), `row` (`enum front A B C D`), `col` (`enum r m l`), `reachable_by_driver` (boolean) |
| `TripStation` | `station_id`, `at_seconds` (integer 1–600), `fare_piasters` (`PositivePiasters`) |
| `TripRules` | `student_discount_pct` (0–100), `bag_fare_piasters` (`Piasters`), `child_free_age` (0–18), `max_break_requests` (0–2) |
| `PassengerSpec` | `passenger_id` (`^p[0-9]{1,3}$`), `archetype`, `skin` (`Slug`), `seat_id`, `dest_station_id`, `payment` (array of `Denomination`, 1–10); opt. `board_station_id`, `pays_at_seconds` (0–600), `group_id` (`^g[0-9]{1,2}$`), `group_size` (2–12), `speech_keys` (map `Slug` → `SpeechKey`) |
| `TripEvent` | `event_id`, `at_seconds` (0–600); opt. `passenger_ids` (array of passenger ids, 1–6), `station_id`, `amount_piasters` (`Piasters`), `seconds` (integer −60–60) |

The §9.3 example becomes `content/examples/valid/trip/line_gamaa.12.json`, with five changes:

- `seats` is added;
- `kind` and `seed` are added;
- the explicit `"board_station_id": null` is dropped;
- `initial_tray` keeps only non-zero counts;
- the trip gains a `rules.max_break_requests`.

## The other parts

| Type | Fields |
| --- | --- |
| `Line` | `line_id`, `name` (`LocalizedText`), `order` (≥ 1), `stations` (array of `{ station_id, name }`, 2–30), `unlock` (`{ kind: enum start\|vehicle\|line_complete, vehicle_id?: VehicleId, line_id?: LineId }`), `difficulty_band` (`{ min: 0–100, max: 0–100 }`) |
| `Vehicle` | `vehicle_id`, `name`, `order`, `starter` (boolean), `seats` (array of `Seat`, 1–20) |
| `Chapter` | `chapter_id`, `order`, `title`, `goal` (`{ kind: enum complete_line\|own_vehicle\|purchase\|complete_room, line_id?, vehicle_id?, room_id? }`), opt. `story_trip_id`, `completion_bonat` (`Amount`), `scenes` (array of `Scene`, 0–10) |
| `Scene` | `scene_id` (`StationId` pattern), `panels` (array of `Panel`, 3–5) |
| `Panel` | `art` (`Slug`), `lines` (array of `{ speaker: Slug, text: LocalizedText }`, 0–8) |
| `Room` | `room_id`, `name`, `order`, `chapter_id`, `completion_bonat` |
| `Item` | `item_id`, `room_id`, `name`, `order`, `variants` (array of `{ variant_id: StationId pattern, name, art: Slug }`, 1–3) |
| `FamilyRequest` | `request_id` (`^req_[a-z0-9_]{1,40}$`), `room_id`, `item_id`, opt. `variant_id`, `text`, `reward_bonat` (≥ 1) |
| `SpeechPool` | `speech_key`, `lines` (array of `{ text: LocalizedText }`, 1–50) |
| `Catalog` | `prices` (array of `{ sku_kind: enum item\|vehicle\|chapter\|booster\|fuel\|revive\|fuel_unlimited, sku_id: string, currency, amount: integer ≥ 1 }`) |
| `DailyRewardDay` | `day_index` (1–7), `jenehat` (`Amount`), `bonat` (`Amount`) |
| `TaskTemplate` | `task_id`, `metric` (`Slug`), `target` (≥ 1), `text`, `reward_jenehat`, `reward_bonat` |
| `Pack` | `pack_id` (`const "core"`), `version` (≥ 1), `schema_version` (`^[0-9]+\.[0-9]+$`), `lines`, `vehicles`, `trips`, `chapters`, `rooms`, `items`, `family_requests`, `speech_pools`, `catalog`, `daily_rewards`, `tasks`. Each is an array of the matching type, except `catalog`, which is one `Catalog`. |
| `Manifest` | `version` (≥ 0), `packs` (array of `{ pack_id, version, url (string, ^https?://), sha256 (Sha256), size (≥ 1), min_client_version (ClientVersion) }`, 0–5) |

## Rules beyond shape (stages 2 and 3 of FR-021)

The validator in `wassal_content.validate` reports each finding as `{stage, code, severity, entity,
id, path, message}`. Codes are stable, so tests can name them.

- **Where a finding points.** `entity` and `id` name the record: a part element by its identifier,
  a catalog price as `catalog_price` with id `<sku_kind>:<sku_id>`, and anything else in the pack
  as `pack` `core`. `path` is a JSON path inside that record, such as `$.passengers[2].seat_id`.
  Schema findings (`V-SC`) on a pack use the same form.
- **Order of stages.** The rules assume the schema's shapes, so when the schema stage fails,
  `references` and `content_rules` report `not_available` instead of running.

| Code | Severity | Rule |
| --- | --- | --- |
| **References** | | |
| `V-T1` | error | `trip_id` starts with `line_id + "."` |
| `V-T2` | error | Every trip station is a station of its line, in line order, with strictly increasing `at_seconds` |
| `V-T3` | error | `seats` equals the layout of `vehicle_id` in this pack, row and column derived from `seat_id`, `reachable_by_driver` = row ∈ {front, A} |
| `V-T4` | error | Every passenger's `seat_id` is in `seats`. `dest_station_id` is a trip station. `board_station_id`, if present, is an earlier trip station. |
| `V-T5` | error | `group_id` and `group_size` are set together. The members listed in a group share `group_size`, and there are at most `group_size` of them: backend §9.3 lists only the group's payer. |
| `V-T6` | error | Every `speech_keys` value and every event `passenger_ids`/`station_id` resolves |
| `V-T7` | error | `trip_id`s are unique, and each line's trip numbers start at 01 with no gaps |
| `V-L1` | error | `unlock.kind` has exactly its field (`vehicle` → `vehicle_id`, `line_complete` → `line_id`, `start` → none), and the reference resolves |
| `V-L2` | error | `difficulty_band.min ≤ max`. Station ids are unique within a line. |
| `V-C1` | error | `goal.kind` has exactly its field, and the reference resolves. `purchase` needs a catalog price `(chapter, chapter_id)`. |
| `V-C2` | error | `story_trip_id`, if present, is a `story` trip |
| `V-R1` | error | Every room's `chapter_id` and every item's `room_id` exist, `item_id` starts with `room_id + "."`, and variant ids are unique per item |
| `V-R2` | error | A family request's `item_id` is in its `room_id`, and its `variant_id` is a variant of that item |
| `V-K1` | error | Catalog prices and purchasable products match one to one. Each item, each non-starter vehicle, each `purchase` chapter, and each BONAT SKU listed in data-model.md `CatalogPrice` has exactly one price. Nothing else has a price. |
| `V-D1` | error | `daily_rewards` has exactly day 1 to 7. Every day and every task grants something. |
| `V-U1` | error | Every identifier is unique within its kind, and so are passenger, seat and scene ids within their trip, layout or chapter. Trip ids are `V-T7`'s, station ids `V-L2`'s and variant ids `V-R1`'s. |
| **Content rules** | | |
| `V-M1` | error | The currency follows the SKU kind: JENEHAT for item, vehicle and chapter, BONAT for the rest |
| `V-X1` | error | Every `LocalizedText` value is trimmed and contains no `Nd` digit (R14) |
| `V-X2` | error | Placeholders are well-formed and allowed for the text kind: speech `{amount}` and `{station}`, task `{target}`, everything else none |
| `V-S1` | warning | The pack file is over 2,097,152 bytes compressed (mobile §19) |

**Stages that need authoring data**, which run only on `source` (apps/content):

| Code | Severity | Rule |
| --- | --- | --- |
| `V-V1` | error | Every speech line is reviewed (FR-017) |
| `V-Z1` | error/n.a. | The solver stage (B05). Until it exists it reports `not_available`, which blocks publishing on staging and promotion on production (FR-022). (B05) The real stage's codes, `V-Z1` to `V-Z5`, are in specs/005-b05-solver-parity/contracts/content-pipeline.md. |

No rule converts BONAT into JENEHAT, because nothing in the schema can express it. No SKU kind
grants JENEHAT, and a pack has no real-money field. `V-M1` and the closed `sku_kind` enum keep it
that way (constitution IV).

## Canonical form and pack file (FR-011, research R4)

- **Canonical JSON**: UTF-8, object keys sorted by UTF-16 code unit, no insignificant whitespace,
  minimal escaping (only `"`, `\` and U+0000–U+001F, using `\b \f \n \r \t` or `\u00xx`), integers
  in shortest decimal form, no `null`.
- **The pack file** is gzip of the canonical JSON at level 9, header `mtime = 0`, no file name, OS
  byte 255 (Python's `gzip.compress`).
- **`sha256`** is over the gzip file. **`canonical_sha256`** is over the canonical JSON, for
  diagnostics only.
- **The golden test**: the sample content (`content/examples/sample/`) built as version 1 must give
  the checksums in `content/examples/sample.golden.json`, on every machine. An intended change to
  the sample or the schemas regenerates the golden file in the same PR.
