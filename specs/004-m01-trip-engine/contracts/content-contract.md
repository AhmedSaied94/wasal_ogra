# Contract: Trip Schema Change, Engine Capabilities and Content Validation

What this feature changes in B04's content contract (spec FR-064 to FR-066 and FR-073; research
R13 to R15). B04's own contract is `specs/003-b04-content-pipeline/contracts/content-schemas.md`, and
everything there still holds.

## 1. The trip schema change

`content/schemas/trip.schema.json`, `$defs.TripRules`, gains one required property:

```json
"no_fights_required": { "type": "boolean" }
```

It is added to `TripRules.required` too. Meaning: when `true`, the first fight fails the trip, and it
can't be revived (rules.md §9.3, §10.2). Every trip states it, and only story trips such as
«أبو العروسة راكب» set it to `true`.

- **Allowed now.** `content/source/pack.json` doesn't exist, so no pack has been promoted, and B04
  FR-010 lets schemas change freely. `schema-set.json` stays at `1.0`. `schema-diff` is run and
  reviewed anyway.
- **In the same change:**
  - `uv run wassal-content codegen` regenerates `_generated.py`,
    `src/wassal_content/schemas/*.json` and `packages/content_models/lib/src/generated/trip.dart`;
  - the field is added to every trip in the examples:
    - the sample trips (`content/examples/sample/trips/**`);
    - `content/examples/valid/trip/*.json` and the trips inside `content/examples/valid/pack/core.json`;
    - all 13 existing `content/examples/invalid/trip/*.json`, because `test_examples.py` requires
      each invalid example to fail at its named field only;
  - an invalid example without it is added;
  - `uv run wassal-content golden --update` rewrites `content/examples/sample.golden.json`, and the
    diff is reviewed;
  - the backend authoring app gets the changes in §5.

## 2. `content/engine/capabilities.json`

The one machine-readable list of what the engine supports and says. The engine checks it in
`capabilities_test.dart`, `wassal-content` reads it for rules V-T8 to V-T10 from its packaged copy
(`src/wassal_content/engine/capabilities.json`, written by `codegen` and covered by
`codegen --check`), and B05 reads it later.

```json
{
  "version": 1,
  "archetypes": [
    "regular", "honest", "hajja", "sleeper", "hurry", "big_note", "student",
    "headphones", "false_claimer", "group_payer", "chatty", "regular_customer"
  ],
  "events": {
    "bump":            {},
    "traffic":         { "seconds": { "use": "required", "min": 1, "max": 60 } },
    "open_road":       { "seconds": { "use": "required", "min": 1, "max": 60 } },
    "fare_increase":   { "amount_piasters": { "use": "required", "min": 50 },
                         "passenger_ids":   { "use": "optional", "min_items": 1, "max_items": 6 } },
    "drop_me_here":    { "passenger_ids":   { "use": "required", "min_items": 1, "max_items": 1 },
                         "seconds":         { "use": "optional", "min": 1, "max": 60 } },
    "payment_dispute": { "passenger_ids":   { "use": "required", "min_items": 2, "max_items": 2,
                                              "no_group_members": true } },
    "change_request":  { "passenger_ids":   { "use": "required", "min_items": 1, "max_items": 1 },
                         "amount_piasters": { "use": "required", "one_of": [1000, 2000, 5000, 10000, 20000] } },
    "roadside_pickup": { "passenger_ids":   { "use": "required", "min_items": 1, "max_items": 6 } }
  },
  "speech_slots": [
    { "slot": "pays",                    "placeholders": ["amount"] },
    { "slot": "pays_group",              "placeholders": ["amount"] },
    { "slot": "pays_old_fare",           "placeholders": ["amount"] },
    { "slot": "pays_rest",               "placeholders": ["amount"] },
    { "slot": "wants_change",            "placeholders": ["amount"] },
    { "slot": "impatient",               "placeholders": [] },
    { "slot": "thanks",                  "placeholders": [] },
    { "slot": "short_change",            "placeholders": ["amount"] },
    { "slot": "returns_excess",          "placeholders": ["amount"] },
    { "slot": "stop_near",               "placeholders": ["station"] },
    { "slot": "fight",                   "placeholders": ["amount"] },
    { "slot": "missed_stop",             "placeholders": ["station"] },
    { "slot": "claims_paid",             "placeholders": [] },
    { "slot": "caught",                  "placeholders": [] },
    { "slot": "accused",                 "placeholders": [] },
    { "slot": "woke",                    "placeholders": [] },
    { "slot": "attentive",               "placeholders": [] },
    { "slot": "drop_me_here",            "placeholders": [] },
    { "slot": "dispute",                 "placeholders": [] },
    { "slot": "change_request",          "placeholders": ["amount"] },
    { "slot": "change_request_declined", "placeholders": [] },
    { "slot": "boards",                  "placeholders": [] },
    { "slot": "tip",                     "placeholders": ["amount"] }
  ]
}
```

The rules for this file:

- **Event parameters.** Any parameter an event doesn't list is forbidden. `use: optional` may be
  absent. `min` and `max` bound integers, and `min_items` and `max_items` bound list lengths.
  `no_group_members` forbids listing a passenger who has a `group_id`.
- **Speech slots.**
  - A slot's default key is `passenger.<slot>`.
  - A placeholder `amount` is filled from `PassengerSpeaks.amount_piasters`, and `station` from
    `station_id` (rules.md §12).
  - A speech line in a pool may use only the placeholders its slot lists, and may use none at all.
- **Changing the file.** Adding an archetype, event or slot is a change to the engine, so it ships
  with its rules, fixtures and a version bump in the same PR (constitution III).

## 3. New content validation rules

These live in `tools/content_kit/src/wassal_content/rules/engine.py`, and every finding is an error.
They run wherever B04's rules run: `validate`, `validate-source` and the admin's builds.

| Code | Scope | Rule |
| --- | --- | --- |
| V-T8 | trip | Every event's parameters follow its row in `events`: required ones are present, forbidden ones absent, bounds respected, and `no_group_members` honoured. |
| V-T9 | trip | Every passenger's archetype is in `archetypes`, and every event in `events`. |
| V-T10 | pack | For every slot, the pack has a speech pool whose key is the slot's default key. |
| V-T11 | pack | A pool reached through a slot uses only that slot's placeholders. That covers default keys and passenger overrides, so B04's general `{amount}`/`{station}` rule is narrowed per slot. Every key of a passenger's `speech_keys` must be a slot: B04 left the names open ("role slug"), and an override under any other name would never be used. |

B04's V-T6 already checks that a passenger's `speech_keys` overrides point to existing pools.
`wassal-content validate <file> --part trip` runs V-T8 and V-T9 on a lone trip, so fixtures and
daily challenges are checked too.

## 4. The sample pack and examples

- **The sample trips** gain `"no_fights_required": false`.
  - They may also be adjusted where the rules make a trip impossible to play to 3 stars, for example
    `line_gamaa.01`'s student with a 0% discount. Each needs a `sample__…` fixture that does play it
    to 3 stars (spec FR-062).
  - `line_hay.03`, already `kind: story`, gets `"no_fights_required": true`, so the field is used
    for real.
  - `line_hay.01`'s student discount becomes 50%, so a sample trip exercises it.
  - `line_hay.02`'s `payment_dispute` named one passenger, and a dispute needs two who aren't in a
    group. A fourth passenger, `p4`, boards at forn into the seat `p1` frees, and the dispute is
    between `p3` and `p4` at 70 s.
  - `line_gamaa.02`'s `mother_kids` (phase 3) becomes `honest`.
  - The `speech_keys` overrides named B04's placeholder slugs (`pay`, `stop`, `change`). They use
    the engine's slots (`pays`, `pays_group`, `stop_near`, `wants_change`).
- **Speech pools.** `content/examples/sample/speech/` gains a pool for each of the 20 slots it lacks,
  one or two short Egyptian Arabic lines each, under B04's text rules (no digits, only the slot's
  placeholders). The three existing pools (`passenger.pays`, `passenger.stop_near`,
  `passenger.wants_change`) keep their keys.
- **Examples.** `content/examples/invalid/` gains a trip missing `no_fights_required`. The tests of
  V-T8 to V-T11 use their own fixtures in `tools/content_kit/tests/`.

## 5. The backend ripple (B04's authoring app)

| File | Change |
| --- | --- |
| `backend/apps/content/models/trips.py` | `Trip.no_fights_required = BooleanField(default=False, db_default=False)`. The database default keeps inserts by the previous release working during a deploy and after a rollback. |
| `backend/apps/content/migrations/000N_trip_no_fights_required.py` | `AddField` with `default=False`. It is expand-only: the previous release ignores the column. |
| `backend/apps/content/services/importer.py` | Reads `rules.no_fights_required`. |
| `backend/apps/content/services/snapshot.py` | Writes it into `rules`. |
| `backend/apps/content/admin/authoring.py` | Adds the field to the trip's rules fieldset. |
| `backend/apps/content/tests/factories.py`, `conftest.py` | Trips carry the field, and a helper adds a pool for every engine slot to the packs tests build. |
| backend tests | Import, export, snapshot and admin round-trips cover the field. Packs missing an engine pool fail V-T10. |

`contracts/openapi.yaml` doesn't change: the manifest doesn't expose trip fields.
