# Contract: The Line and Vehicle Content Fields

Spec FR-042–FR-044. Research R9. Schema changes are free: `content/source/pack.json` doesn't exist,
so `schema-diff` doesn't apply and `content/schemas/schema-set.json` stays at `1.0`.

## Schemas

| File | Property | Definition | Required |
| --- | --- | --- | --- |
| `content/schemas/line.schema.json` | `whats_new` | `{"$ref": "common.schema.json#/$defs/LocalizedText"}` | yes |
| `content/schemas/line.schema.json` | `display_fare_piasters` | `{"$ref": "common.schema.json#/$defs/PositivePiasters"}` (integer, ≥ 50, multiple of 50) | yes |
| `content/schemas/vehicle.schema.json` | `short_name` | `{"$ref": "common.schema.json#/$defs/LocalizedText"}` | yes |

- **Meaning.**
  - `whats_new` is the player text a line card shows after its name: what the line brings that is new.
  - `display_fare_piasters` is the fare the card's chip shows. It is for display only: trips keep
    their own `fare_piasters`, and neither engine reads it (FR-043).
  - `short_name` is the vehicle's name on its tile («قديم · عربيتك»). The sheet and every label keep
    `name`.
- **Validation.** No new rule: content-kit's V-X1 already covers every `LocalizedText` of lines and
  vehicles (no digits, no edge spaces), and `PositivePiasters` covers the fare.

## Generated code (committed)

- `tools/content_kit`: `uv run wassal-content codegen`. This writes `src/wassal_content/schemas/
  {line,vehicle}.schema.json` and `models/_generated.py` (`Line`, `Vehicle`).
- `packages/content_models`: `fvm dart run build_runner build -d`. This writes
  `lib/src/generated/{line,vehicle}.dart` with `Line.whatsNew` (`LocalizedText`),
  `Line.displayFarePiasters` (`int`) and `Vehicle.shortName` (`LocalizedText`), read as `.arEg`.

## Examples and the sample

| Path | Change |
| --- | --- |
| `content/examples/valid/line/{line_hay,line_gamaa}.json`, `valid/vehicle/micro_old.json`, `valid/pack/core.json` | gain the fields |
| `content/examples/invalid/line/*.json`, `invalid/vehicle/*.json` | gain the fields, so each still reports only its own error |
| `content/examples/invalid/line/display_fare_475.json` | new → `$.display_fare_piasters` |
| `content/examples/invalid/vehicle/no_short_name.json` | new → `$.short_name` |
| `content/examples/invalid/expected.json` | the two above, plus a V-X1 case `$.whats_new.ar-EG` (a digit in the text) |
| `content/examples/sample/lines/line_hay.json` | `display_fare_piasters: 700`; `whats_new` «تعلّم اللمّ والباقي، الحاجة، النايم، المستعجل» |
| `content/examples/sample/lines/line_gamaa.json` | `display_fare_piasters: 850`; `whats_new` «نص الأجرة، الدفع الجماعي، "أنا دافع!"، أبو سمّاعة» |
| `content/examples/sample/vehicles/tuktuk.json`, `micro_old.json` | `short_name` «توكتوك», «قديم» |
| `content/examples/sample.golden.json` | `uv run wassal-content golden --update`, reviewed |
| `apps/mobile/assets/content/dev/{core-1.json.gz,bundled.json}` | `uv run wassal-content bundle dev --out ../../apps/mobile/assets/content/dev`, after the golden |

The sample files keep the export format: sorted keys, 2-space indent, a trailing newline.

## Backend (B04's content app)

| Path | Change |
| --- | --- |
| `backend/apps/content/models/lines.py` | `Line`: `whats_new_ar_eg` (`TextField`), `whats_new_ar` (`TextField(blank=True)`), and `display_fare_piasters` (`PositiveIntegerField`), with a `CheckConstraint` (≥ 50, multiple of 50) and the same check in `clean()`. `Vehicle`: `short_name_ar_eg`, `short_name_ar`. The 50-piaster helpers move from `models/trips.py` to `models/base.py`, since `trips.py` imports `lines.py`. |
| `backend/apps/content/migrations/0010_line_vehicle_display_fields.py` | `AddField` ×5, with `default` and `db_default` for existing rows (a fare of 50, empty texts that a later import or authoring fills), as `0006_trip_no_fights_required.py` did. A build refuses an empty `ar-EG` text, so a pack can't ship with the defaults. |
| `backend/apps/content/services/importer.py` | `vehicle()` and `line()` read the fields |
| `backend/apps/content/services/snapshot.py` | `line_part()` and `vehicle_part()` write them; export, build and the import diff follow |
| `backend/apps/content/admin/authoring.py` | `LineAdmin.fields`, plus the fare in `list_display`; `VehicleAdmin.fields` |
| `backend/apps/content/tests/` | `factories.py`, `test_admin_authoring.py`, `test_history.py`, `test_import_export.py` |

After the content_kit change, run `uv sync --reinstall-package wassal-content` in `backend/` and in
`tools/solver`. The solver reads neither field, and `solver_fingerprint` doesn't change.

## Mobile fixtures

- `apps/mobile/test/core/economy/domain/wire_test.dart`: the literal `Vehicle.fromJson` gains
  `short_name`.
- `apps/mobile/test/fixtures/tutorial/lines/line_hay.json`: gains the fields; its README's
  provenance note says so.

## The release draft

In the `content-core-r1` worktree (`content/drafts/core-r1/pack/lines/*.json`, `pack/vehicles/*.json`),
uncommitted like the rest of the draft: the same three fields, with the product spec's texts for
both lines (the owner may rewrite them).

## Deployment

A pack built before this change has no fields. The new app refuses it as unreadable and falls back
to the bundled pack (M04), and production's promote would refuse it against the new schema. No pack
is promoted yet. After the deploy, staging rebuilds and publishes a fresh pack
(`docs/runbooks/content-publishing.md`, owner action).

The required fields make this an expand-only schema change with four operational consequences
(constitution "migrations expand/contract"; T110):

- **Production must carry M09 before the first M09 pack is promoted.** `promote.py` validates the
  incoming pack with production's own schemas, so an earlier production refuses the new properties.
  Tag and deploy production first, then promote.
- **Packs built before `content.0010` can't be rolled back to.** A rollback rebuilds the old pack's
  parts and validates them against today's schema (`build.py`), so it fails on the missing fields.
  Only post-deploy packs are rollback targets.
- **A draft built before the deploy must not be published.** `publish.py` doesn't re-run the schema
  stage, so the pack would go out and every M09 app would refuse it. Rebuild first.
- **Exports of pre-M09 versions don't import**, for the same reason: they lack the required fields.

The admin rows the migration created hold a fare of 50 (a valid fare) and empty texts (refused by a
build). Every line's fare must be set by hand; a build warning when a fare still equals 50 would
make a missed one visible, but isn't implemented.
