---

description: "Task list for B04 Content Pipeline"
---

# Tasks: Content Pipeline (B04)

**Input**: Design documents from `specs/003-b04-content-pipeline/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Tests are required (constitution XIII). Every phase writes its tests
  first, and they must fail before the implementation tasks start.
- **Real services.** Backend tests run against real PostgreSQL and Valkey. Pack files go to a
  temporary directory. "Staging" and "production" pack URLs are a local `http.server` thread
  fixture, not mocks.
- **Coverage.** At least 80% lines in each of `tools/content_kit`, `packages/content_models` and
  the backend (FR-041).

**Organization**:

- **Paths** are from the repository root.
  - Run `uv` in `tools/content_kit/` or `backend/` as the task says.
  - Run Dart commands with `fvm` in `packages/content_models/`.
- **Two PRs** (plan "Delivery slices"):
  - **PR 1** is Phases 1–3 (US1), so M01 can start.
  - **PR 2** is Phases 4–9.
- **Owner tasks** need the owner's accounts or hosts. An agent can't do them alone.
- **After-B05 tasks** wait for B05, because staging can't publish before it (spec Clarifications).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US5 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the shared Python package, the Dart package and the `content/` tree
(plan "Project Structure").

- [X] T001 Create the uv project `tools/content_kit/` (research R1, R2, R13):
  - **`pyproject.toml`:**
    - `[project]`: `name = "wassal-content"`, `version = "0.1.0"`, `requires-python = "==3.13.*"`,
      and `dependencies = ["jsonschema==4.26.0", "referencing==0.37.0", "pydantic==2.13.5"]`;
    - `[project.scripts] wassal-content = "wassal_content.cli:main"`;
    - build backend `hatchling`, with `[tool.hatch.build.targets.wheel] packages =
      ["src/wassal_content"]` and package data `src/wassal_content/schemas/*.json`;
    - `[dependency-groups] dev`: `ruff==0.17.1`, `mypy==1.19.1`, `pytest==9.1.1`,
      `pytest-cov==7.1.0` and `hypothesis==6.170.1`;
    - `[tool.ruff]` as in `backend/pyproject.toml` (line length 100, the same `select`), with
      `extend-exclude = ["src/wassal_content/models/_generated.py"]`;
    - `[tool.mypy] strict = true` with `plugins = ["pydantic.mypy"]`;
    - `[tool.pytest.ini_options] testpaths = ["tests"]`, and `[tool.coverage.run] source =
      ["wassal_content"]`.
  - **Other files:** `.python-version` (`3.13`), `src/wassal_content/__init__.py`,
    `src/wassal_content/py.typed` and `tests/__init__.py`.
  - **Lock:** run `uv lock` and commit `uv.lock`.
- [X] T002 [P] Create the Dart package `packages/content_models/` (research R1):
  - **`pubspec.yaml`:**
    - `name: content_models`, `publish_to: none`, `environment: sdk: ^3.13.0`;
    - dependencies `freezed_annotation: ^3.1.0` and `json_annotation: ^4.12.0`;
    - dev dependencies `build_runner: ^2.16.2`, `freezed: ^4.0.2`, `json_serializable: ^6.14.1`,
      `test`, `coverage` and `lints`.
  - **`analysis_options.yaml`:** includes `package:lints/recommended.yaml`, and excludes
    `**/*.g.dart` and `**/*.freezed.dart`.
  - **`build.yaml`:** `json_serializable` options `include_if_null: false`,
    `explicit_to_json: true` and `checked: false`.
  - **`lib/content_models.dart`:** an exports-only library.
  - **`.gitignore`:** `*.g.dart`, `*.freezed.dart`, `.dart_tool/`, `coverage/`.
  - **`README.md`:** says the files under `lib/src/generated/` come from `wassal-content codegen`
    and are never edited by hand.
- [X] T003 [P] Create the `content/` tree:
  - `content/schemas/`, `content/examples/valid/`, `content/examples/invalid/` and
    `content/examples/sample/`;
  - `content/README.md`, explaining each folder, that `content/source/` holds only exports of
    promoted packs (FR-040), and where the generated copies live.

  Append `backend/var/` to the root `.gitignore`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The strict loader, the canonical form and the pack file, which every later phase uses
(research R2, R4; contracts/content-schemas.md "Canonical form").

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 [P] Write `tools/content_kit/tests/test_loader.py` (R2). It checks that loading:
  - **refuses** `1.0`, `1e3`, `-0.5`, `NaN`, `Infinity` and duplicate keys at any depth, invalid
    UTF-8 and a UTF-8 BOM, each with an error naming the line and column;
  - **accepts** integers up to `4294967295`, booleans, nested arrays and objects.
- [X] T005 [P] Create `content/examples/canonical-vectors.json`, an array of `{input, canonical}`
  pairs:
  - key order by UTF-16 code unit;
  - `"`, `\` and U+0000–U+001F escaped as `\b \f \n \r \t` or `\u00xx` (lowercase hex);
  - Arabic left unescaped;
  - empty objects and arrays;
  - large integers.

  Then write `tools/content_kit/tests/test_canonical.py` over the file, plus:
  - `null` and floats are refused (`ValueError`);
  - a `hypothesis` property: `canonical(loads(canonical(x))) == canonical(x)` for generated
    integer, bool, string, list and dict trees.
- [X] T006 [P] Write `tools/content_kit/tests/test_packfile.py`:
  - the gzip header has `mtime` 0, no file name and OS byte 255;
  - the same input gives the same bytes;
  - `sha256_hex` is over the gzip bytes;
  - `decompress_capped(data, max_bytes)` raises `PackTooLarge` past the cap, and on a crafted
    gzip bomb.
- [X] T007 Implement `tools/content_kit/src/wassal_content/loader.py`:
  - `load_json_bytes(data: bytes)` and `load_json_file(path)`, using `json.loads` with
    `parse_float` and `parse_constant` that raise `ContentLoadError`, an `object_pairs_hook` that
    refuses duplicate keys, strict UTF-8 decoding, and BOM refusal;
  - `ContentLoadError` carries the line, column and message.
- [X] T008 Implement `tools/content_kit/src/wassal_content/canonical.py`. `canonical_bytes(obj) ->
  bytes` is `json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)` encoded
  as UTF-8, after a recursive check that refuses `None`, `float` and non-`str` keys.
- [X] T009 Implement `tools/content_kit/src/wassal_content/packfile.py`:
  - `build_pack_file(canonical: bytes) -> bytes`, which is `gzip.compress(data, compresslevel=9,
    mtime=0)`;
  - `sha256_hex(data)`;
  - `decompress_capped(data, max_bytes)`, which streams with `zlib.decompressobj(16 + MAX_WBITS)`
    and stops at the cap.

**Checkpoint**: `uv run pytest` in `tools/content_kit/` is green for T004–T006.

---

## Phase 3: User Story 1 - One set of content schemas, with models generated from it (Priority: P1) 🎯 MVP, PR 1

**Goal**: `content/schemas/` (schema set 1.0), examples, the sample pack, one generator that
writes the Pydantic server models and the freezed app models, and the CI checks (FR-001–FR-011).

**Independent Test**: quickstart §1. The §9.3 trip validates, and round-trips identically through
both model sets. A fare of 475 is refused at `$.stations[0].fare_piasters`. A hand edit to a
generated file fails `codegen --check`.

### Tests for User Story 1 (write first, they must fail)

- [X] T010 [P] [US1] Write `tools/content_kit/tests/test_profile.py`:
  - one fixture schema per forbidden construct in research R3 (`null`, `number`, `default`,
    `oneOf`, `anyOf`, `allOf`, `if`, `not`, `additionalProperties` missing on an object, an
    unknown keyword), each refused with its file and JSON pointer;
  - every file in `content/schemas/` passes.
- [X] T011 [P] [US1] Write `tools/content_kit/tests/test_examples.py`:
  - every file in `content/examples/valid/<part>/` passes its part's schema (the folder name is
    the part);
  - every file in `content/examples/invalid/<part>/` fails, and its first finding's `json_path`
    equals the one in `content/examples/invalid/expected.json`;
  - every invalid file is listed in `expected.json`, and every entry has a file.
- [X] T012 [P] [US1] Write `tools/content_kit/tests/test_round_trip.py`:
  - each valid example, parsed with its root model from `wassal_content.models.ROOT_MODELS` and
    dumped with `to_json_dict` (alias, no `None`), is `canonical_bytes`-equal to the input;
  - adding `"future_field": 1` at the top and in a nested object still parses (FR-008, US1-5);
  - a `hypothesis` property built from mutations of the valid trip (integer fields within their
    schema bounds, payments from `Denomination`): parse, dump, parse gives an equal model.
- [X] T013 [P] [US1] Write `tools/content_kit/tests/test_codegen.py`, with
  `tests/fixtures/codegen/schemas/`: a small set using every profile construct, with expected
  outputs in `tests/fixtures/codegen/expected/{models.py,parts/*.dart}`. It checks that:
  - generation is byte-identical to the expected output, and identical across two runs;
  - `codegen --check` exits 1 and names the file when any output differs, or a generated file has
    been edited;
  - a schema outside the profile is refused.
- [X] T014 [P] [US1] Write `tools/content_kit/tests/test_schema_diff.py`, each case a mutation of
  one base schema:
  - **breaking**, each reported with a reason:
    - a property removed or renamed, or its `type` changed;
    - an `enum` value removed;
    - `minimum` raised, `maximum` lowered, `pattern` changed or `maxLength` lowered;
    - a property newly `required`;
    - `additionalProperties` changed from a schema to `false`;
  - **not breaking**: a new optional property, an added `enum` value, a `description` change;
  - a breaking change passes when `schema-set.json` `version`'s major went up;
  - the command passes without checking when the target tree has no `content/source/pack.json`.
- [X] T015 [P] [US1] Write `tools/content_kit/tests/test_source.py`:
  - `read_layout(content/examples/sample)` assembles a `Pack` whose arrays are sorted by
    identifier;
  - a file whose name isn't its identifier is refused with that path;
  - an unknown folder or file is refused;
  - `write_layout(pack, tmp)` then `read_layout` round-trips, and the written files use sorted
    keys, 2-space indentation, UTF-8 without escapes and a trailing newline
    (contracts/content-source.md).
- [X] T016 [P] [US1] Write `tools/content_kit/tests/test_golden.py`. Assembling
  `content/examples/sample` as version 1 must give the `canonical_sha256` and `sha256` stored in
  `content/examples/sample.golden.json` (R4, SC-004).

### Implementation for User Story 1

- [X] T017 [US1] Write `content/schemas/common.schema.json`:
  - every `$defs` entry in contracts/content-schemas.md "common.schema.json $defs", with exactly
    the patterns and enums listed;
  - `$schema` `https://json-schema.org/draft/2020-12/schema`;
  - `$id` `https://wassal.invalid/content/1/common.schema.json`.
- [X] T018 [P] [US1] Write `content/schemas/trip.schema.json`. Root `TripDefinition` and the
  `$defs` `Seat`, `TripStation`, `TripRules`, `PassengerSpec` and `TripEvent`, with every bound in
  contracts/content-schemas.md "TripDefinition":
  - `seats` 1–20, `stations` 1–4, `passengers` 1–30 and `events` 0–10;
  - `seed` 1–4294967295, `at_seconds` 1–600, `pays_at_seconds` 0–600;
  - `payment` 1–10 `Denomination`s, `group_size` 2–12;
  - `seconds` −60–60, `max_break_requests` 0–2;
  - `initial_tray` as a map from `DenominationKey` to integers ≥ 1.

  Every object has `additionalProperties: false`.
- [X] T019 [P] [US1] Write `content/schemas/line.schema.json` and `vehicle.schema.json`, per the
  "The other parts" table:
  - `Line`: `stations` 2–30, `unlock.kind` `start`, `vehicle` or `line_complete`,
    `difficulty_band` 0–100;
  - `Vehicle`: `seats` 1–20, using `trip.schema.json#/$defs/Seat`.
- [X] T020 [P] [US1] Write `content/schemas/chapter.schema.json` (with `$defs` `Scene` with 3–5
  panels, and `Panel` with 0–8 lines), `room.schema.json`, `item.schema.json` (1–3 variants) and
  `family_request.schema.json` (`request_id` `^req_[a-z0-9_]{1,40}$`, `reward_bonat` ≥ 1).
- [X] T021 [P] [US1] Write `content/schemas/speech_pool.schema.json` (1–50 lines),
  `catalog.schema.json` (`sku_kind` `item`, `vehicle`, `chapter`, `booster`, `fuel`, `revive` or
  `fuel_unlimited`; `amount` ≥ 1), `daily_reward.schema.json` (`day_index` 1–7) and
  `task.schema.json` (`target` ≥ 1).
- [X] T022 [US1] Write `content/schemas/pack.schema.json`:
  - `pack_id` `const "core"`;
  - `version` ≥ 1;
  - `schema_version` `^[0-9]+\.[0-9]+$`;
  - the eleven part arrays, and the single `catalog`.

  Also write `manifest.schema.json` (0–5 packs; fields per contracts/api.md) and
  `content/schemas/schema-set.json` `{"version": "1.0", "min_client_version_by_major": {"1":
  "1.0.0"}}`.
- [X] T023 [US1] Implement `tools/content_kit/src/wassal_content/profile.py` (the R3 keyword
  allow-list check) and `tools/content_kit/src/wassal_content/schemas.py`:
  - load every `*.schema.json` into a `referencing.Registry` keyed by `$id`;
  - `validator_for(part)` returns a `Draft202012Validator`;
  - `validate_document(part, doc) -> list[Finding]` returns `Finding(stage="schema", code="V-SC",
    severity="error", path=error.json_path, message)`;
  - the schemas come from package data, or from the directory in `WASSAL_CONTENT_SCHEMAS_DIR`
    during codegen.
- [X] T024 [US1] Create the valid examples, at least one per part, in
  `content/examples/valid/<part>/`:
  - `trip/line_gamaa.12.json`: the backend §9.3 trip, with the five changes in
    contracts/content-schemas.md (adds `seats` from `micro_old`'s layout, `kind`, `seed`,
    `rules.max_break_requests`; drops the null `board_station_id`; keeps only non-zero tray
    counts);
  - a second trip with a group, a boarding station and two events;
  - one file per other part;
  - a manifest with one pack.
- [X] T025 [US1] Create `content/examples/invalid/<part>/*.json` (at least 3 per part) and
  `content/examples/invalid/expected.json`. The cases include:
  - a fare of 475, a payment denomination of 300, and `seed` 0;
  - 5 stations, and an unknown archetype;
  - the `seat_id` `E_r`;
  - a `LocalizedText` missing `ar-EG`, and an unknown property `"amout"`;
  - `catalog` `sku_kind` `"gift"`;
  - a manifest `sha256` of the wrong length.

  The float case (`"fare_piasters": 450.0`) goes in `tests/fixtures/loader/`, because the loader
  refuses it before the schema sees it.
- [X] T026 [US1] Create the sample content `content/examples/sample/` in the contracts/content-source.md
  layout, using every part. All Arabic text is Egyptian Arabic and follows R14 (no digits). It has
  no real brands, bodies or clubs (constitution content limits). It contains:
  - **Lines:** `line_hay` (start, 4 stations) and `line_gamaa` (`unlock` vehicle `micro_old`, 5
    stations).
  - **Vehicles:** `tuktuk` (`starter: true`, 3 seats) and `micro_old` (10 seats, rows `front` and
    A–C).
  - **Trips:** `line_hay.01` and `line_hay.02` (tuktuk), `line_gamaa.01`, and `line_gamaa.02` (the
    §9.3 trip, kind `regular`, renumbered because V-T7 wants each line's trips numbered from 01
    with no gaps). Plus a `story` trip, `line_hay.03`.
  - **Chapters:** ch1 (`complete_line` `line_hay`, `story_trip_id` `line_hay.03`, one scene with
    3 panels), ch2 (`own_vehicle` `micro_old`), ch3 (`purchase`) and ch4 (`complete_room`
    `salon`).
  - **Room and items:** room `salon` (chapter ch4); items `salon.nish` (3 variants) and
    `salon.sitara` (1 variant); one family request on `salon.nish` variant `crystal`.
  - **Speech:** pools `passenger.pays`, `passenger.wants_change` (with `{amount}`) and
    `passenger.stop_near` (with `{station}`).
  - **Catalog:** both items, `micro_old`, `ch3_shabka` (`chapter`), and every BONAT SKU at the
    glossary §3.3 prices: `change_bag` 10, `wake_all` 8, `ledger_peek` 12, `traffic_jam` 8,
    `revive` 20, `refuel_full` 30, `fuel_unlimited_1h` 80.
  - **Daily rewards and tasks:** daily rewards for days 1–7, and 3 tasks with `{target}`.
  - **`pack.json`:** `{"pack_id": "core", "schema_version": "1.0", "version": 0}`.
- [X] T027 [US1] Implement `tools/content_kit/src/wassal_content/source.py`:
  - `read_layout(root) -> SourceTree`, which validates each file against its part schema, and
    checks names against identifiers and the known folders;
  - `assemble_pack(tree, version) -> dict`, with arrays sorted by identifier, `pack_id` and
    `schema_version` from `pack.json`, and the given `version`;
  - `write_layout(pack, root, version)`, in the export format (sorted keys, `indent=2`,
    `ensure_ascii=False`, `\n`, trailing newline).
- [X] T028 [US1] Implement the generator's intermediate description in
  `tools/content_kit/src/wassal_content/codegen/ir.py`:
  - kinds: object, string enum, integer enum, map, list, reference, string, integer, boolean;
  - class names from `$defs` keys and root `title`;
  - field names converted to `snake_case` (Python) and `camelCase` (Dart), with the original name
    kept as an alias when it isn't a valid identifier (`ar-EG` → `ar_eg` / `arEg`);
  - deterministic ordering: types in dependency order then by name, fields in schema order.
- [X] T029 [US1] Implement `tools/content_kit/src/wassal_content/codegen/python.py`, which writes
  `src/wassal_content/models/_generated.py`:
  - a header "Generated by wassal-content codegen from content/schemas. Do not edit.";
  - `BaseModel` subclasses with `model_config = ConfigDict(extra="ignore", frozen=True,
    populate_by_name=True)`;
  - `StrictInt` and `StrictBool`, `StrEnum` and `IntEnum`, `tuple[T, ...]`, `dict[str, T]`, and
    `Field(alias=...)`;
  - `ROOT_MODELS: dict[str, type[BaseModel]]` mapping part name to class.

  Add the hand-written `src/wassal_content/models/__init__.py`, which re-exports and defines
  `to_json_dict(model) = model.model_dump(mode="json", by_alias=True, exclude_none=True)`.
- [X] T030 [US1] Implement `tools/content_kit/src/wassal_content/codegen/dart.py`, which writes
  `packages/content_models/lib/src/generated/<part>.dart`:
  - the same header, plus `// dart format off`;
  - `part '<part>.freezed.dart'; part '<part>.g.dart';`;
  - classes annotated `@Freezed(copyWith: false, toStringOverride: false, map:
    FreezedMapOptions.none, when: FreezedWhenOptions.none)`, with `const factory`
    constructors, `required` for required fields and nullable types for optional ones;
  - `@JsonKey(name: 'ar-EG')` for aliases, enums with `@JsonValue`, `Map<String, int>` for the
    tray, `List<T>` for arrays;
  - a `fromJson` factory for every class.
- [X] T031 [US1] Implement `tools/content_kit/src/wassal_content/cli.py`, with these subcommands:
  - `codegen [--check]`: writes the Python models, the Dart files and a copy of `content/schemas/*`
    into `src/wassal_content/schemas/`. With `--check`, it compares, prints each differing path
    and exits 1;
  - `validate <file> [--part P]`;
  - `validate-source <dir>`: stage 1 in this phase; T046 extends it to stages 1–3;
  - `schema-diff --base <git-ref>`: reads the base tree with `git show`;
  - `golden [--update]`.

  The repository root is found by walking up to `.fvmrc`. Exit codes are 0 for clean, 1 for
  findings and 2 for usage errors.
- [X] T032 [US1] Implement `tools/content_kit/src/wassal_content/schema_diff.py`. It walks
  matching `$defs` and `properties`, reports each breaking kind of research R3 with the schema file
  and JSON pointer, and decides pass or fail from `schema-set.json` majors and the presence of
  `content/source/pack.json`.
- [X] T033 [US1] Run `uv run wassal-content codegen` and commit the outputs:
  - `tools/content_kit/src/wassal_content/models/_generated.py` and
    `tools/content_kit/src/wassal_content/schemas/*.json`;
  - `packages/content_models/lib/src/generated/*.dart`.

  Write the hand-written files `packages/content_models/lib/src/canonical_json.dart`
  (`canonicalJson(Object? value) -> String`: recursively sorted keys by `String.compareTo`, which
  compares UTF-16 code units, then `jsonEncode`) and `packages/content_models/lib/content_models.dart`
  (exports every generated part and `canonical_json.dart`).
- [X] T034 [P] [US1] Write `packages/content_models/test/round_trip_test.dart`:
  - for every file under `../../content/examples/valid/**`, pick the root `fromJson` from the
    folder name, then check `canonicalJson(x.toJson()) == canonicalJson(input)` and
    `fromJson(x.toJson()) == x`;
  - the unknown-field case;
  - `canonicalJson` against every pair in `../../content/examples/canonical-vectors.json`.
- [X] T035 [US1] Generate `content/examples/sample.golden.json` with `uv run wassal-content golden
  --update`, review it, and commit it.
- [X] T036 [US1] Update `.github/workflows/backend.yml`, per contracts/ci-checks.md:
  - the `changes` path rule gains `content/`, `tools/content_kit/`, `packages/content_models/` and
    `.dockerignore`;
  - add the `content-kit` job (lint, types, tests with ≥ 80% coverage, `codegen --check`,
    `validate-source` on `content/source` and `content/examples/sample`, and `schema-diff` against
    the merge base, with `fetch-depth: 0`);
  - add `content-kit` to the `needs` of the `backend` aggregate job and of `image-manifest`.
- [X] T037 [US1] Update `.github/workflows/mobile.yml`:
  - the path rule gains `content/`;
  - add the `content_models` steps at the end of the required `check` job, since `mobile.yml` has
    no aggregate job (`dart pub get`, `build_runner build -d`, format check, `dart analyze
    --fatal-infos`, `dart test --coverage=coverage`, `coverage:format_coverage --lcov
    --report-on=lib`, and `../../apps/mobile/tool/check_coverage.dart --min 80 --lcov
    coverage/lcov.info`);
  - `apps/mobile/tool/check_coverage.dart` excludes `*.freezed.dart` like `*.g.dart` (research R1),
    with a fixture in `apps/mobile/test/tool/` and the M03 contracts/ci-checks.md list updated.
- [X] T038 [US1] Update the docs for PR 1:
  - backend §9.2: the 14 schema files, `schema-set.json` and a pointer to the profile;
  - mobile §5 (`packages/content_models` is generated) and mobile §14.1 (the gzip sha256 is
    checked before decompressing);
  - `CLAUDE.md`: a "Content commands" table (`wassal-content codegen`, `codegen --check`,
    `validate-source`, `schema-diff`, `golden --update`, and the `content_models` build and test)
    and an overview line;
  - `content/README.md`.
- [X] T039 [US1] Run quickstart §1 end to end, then open **PR 1**. Its body points M01 at
  `trip.schema.json` and `package:content_models`. After it merges, tick the delivery-plan step 2
  note in `docs/delivery-plan.md`.

**Checkpoint**: PR 1 is green and merged. M01 can be specified.

---

## Phase 4: Pipeline Foundation (Blocking Prerequisites for US2–US5, PR 2)

**Purpose**: The validator rules, the backend dependency and build context, settings, the content
models and migrations, and the shared services and test fixtures (research R7, R9, R12, R13;
data-model.md).

**⚠️ CRITICAL**: No US2–US5 work can begin until this phase is complete.

### Tests (write first)

- [X] T040 [P] Write `tools/content_kit/tests/test_rules.py`:
  - one deliberately broken copy of the sample pack per rule code in contracts/content-schemas.md
    (`V-T1` to `V-T7`, `V-L1`, `V-L2`, `V-C1`, `V-C2`, `V-R1`, `V-R2`, `V-K1`, `V-D1`, `V-U1`,
    `V-M1`, `V-X1`, `V-X2`), each with its expected code, entity, id and path;
  - `V-S1` as a warning that doesn't fail;
  - `V-X1` covers ASCII, Arabic-Indic and Extended Arabic-Indic digits, and leading or trailing
    whitespace;
  - `V-X2` covers `{amout}`, an unbalanced `{amount`, `{target}` in a speech line, and `{amount}`
    in an item name;
  - the sample pack has no findings (SC-005).
- [X] T041 [P] Add to `backend/tests/test_settings_guards.py`, using B01's subprocess pattern
  (contracts/environment.md). Each of these refuses to start, naming the variable:
  - `CONTENT_ROLE=source` with `WASSAL_ENV=prod`, and `target` with `staging`;
  - `CONTENT_SOLVER_STAGE=stand_in` on staging or prod;
  - an `http://` `CONTENT_PACKS_PUBLIC_URL` on staging;
  - a missing `CONTENT_PACKS_PUBLIC_URL`, or one without a trailing `/`;
  - `CONTENT_PROMOTION_SOURCE_URL` empty on prod, or set on staging;
  - `CONTENT_VERSION_FLOOR_URL` set on prod;
  - `CONTENT_MANIFEST_CACHE_SECONDS=61`.
- [X] T042 [P] Write `backend/apps/content/tests/test_models.py`:
  - **Permanence** (FR-016): with a `PublishedIdentifier` row present, renaming or deleting the
    identifier is refused, through `save()`, the instance's `delete()`, `QuerySet.delete()`, and a
    nested row (station, seat, variant). An identifier with no row can be renamed.
  - **Reviews:** a `SpeechLine` text change clears `reviewed_by` and `reviewed_at`.
  - **Packs:** once `validated`, `ContentPack.file`, `sha256` and `validation_report` can't change.
    Once `published`, only `min_client_version` (and the bookkeeping columns that move with
    status) can.
  - **The audit log:** `ContentAuditRecord` update and delete are refused.
  - **One current pack:** the `ContentChannel.current` constraint.
  - **Keys:** every content model has a UUIDv7 key (B01's check).

### Implementation

- [X] T043 Implement `tools/content_kit/src/wassal_content/rules/references.py`,
  `rules/content_rules.py` and `rules/size.py`, plus `tools/content_kit/src/wassal_content/validate.py`:
  - `validate_pack(pack: dict, *, file_size: int | None) -> Report`. It runs the stages `schema`,
    `references`, `content_rules` and `size`, each with `passed`, `warning` or `failed`, and
    collects findings `{stage, code, severity, entity, id, path, message}` (contracts/admin.md
    "Validation report").
  - Rule texts and severities are exactly those of contracts/content-schemas.md "Rules beyond
    shape".
  - The placeholder sets per text kind come from R14.
- [X] T044 Move the backend image's build context to the repository root (research R13):
  - **`/.dockerignore`:** at the root, deny everything, then allow `backend/`,
    `tools/content_kit/` and `content/schemas/`, and repeat every exclusion of
    `backend/.dockerignore` with `**/` patterns (secrets, caches, `staticfiles`, `.venv`).
  - **`backend/docker/Dockerfile`:**
    - copy `tools/content_kit/` to `/tools/content_kit` in the builder, and keep the backend at
      `/app`, so the `../tools/content_kit` path dependency resolves;
    - `uv sync --locked --no-dev` installs it non-editable into `/opt/venv`;
    - the runtime stage copies only `/opt/venv` and `/app`.
  - **`backend/docker/compose.dev.yml`:** `build.context: ../..` and `dockerfile:
    backend/docker/Dockerfile`.
  - **`.github/workflows/backend.yml`:** the `image` and `smoke` jobs build with `context: .` and
    `file: backend/docker/Dockerfile`.

  As built, `content/schemas/` stays out of the context: the image reads the package's own schema
  copy (contracts/environment.md "Repository files read at runtime"), and `tools/content_kit/tests`
  is excluded too.
- [X] T045 Add `wassal-content` to `backend/pyproject.toml` (`dependencies` plus `[tool.uv.sources]
  wassal-content = { path = "../tools/content_kit" }`). Then run `uv lock`, and confirm `uv run mypy
  .` stays green.
- [X] T046 Make `wassal-content validate-source` (in `tools/content_kit/src/wassal_content/cli.py`)
  run `validate_pack` stages 1–3 on the assembled pack. The CI step from T036 picks this up.
- [X] T047 Add the content settings to `backend/config/env.py` and
  `backend/config/settings/base.py`:
  - `apps.content` in `INSTALLED_APPS`;
  - every variable in contracts/environment.md "Application variables", with its rules;
  - the dev and test values in `backend/config/settings/{dev,test}.py` and
    `backend/.env.example`, and the non-secret staging and production values in
    `backend/docker/env/{staging,prod}.env`;
  - `backend/apps/content/checks.py`: the worker's startup check that `CONTENT_PACKS_DIR` exists
    and is writable.

  Make T041 pass.

  As built:
  - The staging and production values go in each host's `/etc/wassal/<env>.env`, beside
    `API_HOST`, because `docker/env/<env>.env` only feeds compose interpolation and names no
    hostnames. Setting them is an owner action (T104).
  - `dev.py` needs nothing: the packs directory defaults to `backend/var/packs`, and the dev
    worker creates it.
  - The worker check is a `worker_init` receiver. It stops the worker with `SystemExit`, because
    Celery logs and ignores any `Exception` a receiver raises.
- [X] T048 [P] Create `backend/apps/content/{__init__.py,apps.py}` (`label = "content"`, with
  `ready()` importing `signals` and `invariants`) and the models package
  `backend/apps/content/models/__init__.py`. Then create `backend/apps/content/models/lines.py`
  with:
  - **`Line`**:
    - `line_id` unique, choices from the glossary `LineId`;
    - `name_ar_eg` (non-empty) and `name_ar` (blank allowed);
    - `order` smallint, unique;
    - `unlock_kind` `start`, `vehicle` or `line_complete`;
    - `unlock_vehicle` (FK `Vehicle`, null, PROTECT) and `unlock_after_line` (FK self, null,
      PROTECT);
    - `difficulty_min` and `difficulty_max` smallint 0–100, with a `CheckConstraint min ≤ max`.
  - **`Station`**: `line` (FK, CASCADE), `station_id` `^[a-z][a-z0-9_]{1,31}$` unique per line,
    `name_*`, `order` unique per line.
  - **`Vehicle`**: `vehicle_id` unique (glossary), `name_*`, `starter` bool, `order` unique.
  - **`Seat`**: `vehicle` (FK, CASCADE), `seat_id` `^(front|[A-D])_(r|m|l)$` unique per vehicle.
- [X] T049 [P] Create `backend/apps/content/models/trips.py` per data-model "Trip":
  - **`Trip`**:
    - `line` (PROTECT) and `number` smallint 1–99, unique together; the `trip_id` property is
      `f"{line_id}.{number:02d}"`;
    - `vehicle` (PROTECT), and `kind` `regular` or `story`;
    - `seed` bigint 1–4294967295, random on create;
    - `rev` int ≥ 1 default 1, not editable;
    - `max_earnings_jenehat` ≥ 0, and `star_two`/`star_three` choices;
    - `student_discount_pct` 0–100, `bag_fare_piasters` ≥ 0 and a multiple of 50 (CheckConstraint),
      `child_free_age` 0–18, `max_break_requests` 0–2;
    - `tray_50` … `tray_20000` smallint ≥ 0, and `author_notes`.
  - **`TripStation`**: `trip` (CASCADE), `station` (PROTECT), `at_seconds` ≥ 1, `fare_piasters` ≥
    50 and a multiple of 50.
  - **`TripPassenger`**: `passenger_id` `^p[0-9]{1,3}$` unique per trip; `archetype` choices;
    `skin` `^[a-z][a-z0-9_]{1,47}$`; `seat` (PROTECT); `board_station` (null); `dest_station`;
    `pays_at_seconds` (null, ≥ 0); `payment` `ArrayField(IntegerField)` of 1–10 values from
    `Denomination`; `group_id` `^g[0-9]{1,2}$` (null) and `group_size` 2–12 (null), set together;
    `speech_keys` jsonb default `{}`; `order`.
  - **`TripEvent`**: `event_id` choices, `at_seconds` ≥ 0, `passenger_ids` varchar[],
    `station_id` (null), `amount_piasters` (null, a multiple of 50), `seconds` (null), `order`.
- [X] T050 [P] Create `backend/apps/content/models/story.py` per data-model:
  - **`Chapter`**:
    - `chapter_id` unique (glossary), `order` unique, `title_*`;
    - `goal_kind` `complete_line`, `own_vehicle`, `purchase` or `complete_room`, with a
      `CheckConstraint` that exactly the matching goal FK is set, and no FK for `purchase`;
    - `goal_line`, `goal_vehicle`, `goal_room` (null, PROTECT);
    - `story_trip` (null, PROTECT) and `completion_bonat` ≥ 0.
  - **`Scene`**: `chapter`, `scene_id` slug unique per chapter, `order`, `panel_art` varchar[] of
    3–5 values.
  - **`SceneLine`**: `scene`, `panel` ≥ 1, `order`, `speaker` slug, `text_*`.
  - **`Room`**: `room_id` unique (glossary), `name_*`, `chapter` (PROTECT), `order`,
    `completion_bonat` ≥ 0.
  - **`Item`**: `room` (PROTECT), `slug` unique per room, the `item_id` property, `name_*`, `order`.
  - **`ItemVariant`**: `item` (CASCADE), `variant_id` slug unique per item, `name_*`, `art`, `order`,
    at most 3 per item (checked in `clean()`).
  - **`FamilyRequest`**: `request_id` `^req_[a-z0-9_]{1,40}$` unique, `room`, `item`, `variant`
    (null), `text_*`, `reward_bonat` > 0.
- [X] T051 [P] Create `backend/apps/content/models/speech_economy.py`:
  - **`SpeechPool`**: `speech_key` `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$` unique, maxLength 64;
    `author_notes`.
  - **`SpeechLine`**: `pool` (CASCADE), `order` unique per pool, `text_ar_eg`, `text_ar`,
    `reviewed_by` (varchar, blank), `reviewed_at` (null). `save()` clears the review when either
    text changes.
  - **`CatalogPrice`**: `sku_kind` choices (`item`, `vehicle`, `chapter`, `booster`, `fuel`,
    `revive`, `fuel_unlimited`), `sku_id`, `currency` `JENEHAT` or `BONAT`, `amount` > 0; unique
    (`sku_kind`, `sku_id`); a `CheckConstraint` that the currency follows the kind (`V-M1`).
  - **`DailyRewardDay`**: `day_index` 1–7 unique, `jenehat` ≥ 0, `bonat` ≥ 0, a CheckConstraint
    that at least one is > 0.
  - **`TaskTemplate`**: `task_id` `^task_[a-z0-9_]{1,40}$` unique, `metric` slug, `target` ≥ 1,
    `text_*`, `reward_jenehat`, `reward_bonat`, `active`.
- [X] T052 [P] Create `backend/apps/content/models/packs.py` per data-model "Packs and their
  records":
  - **`ContentChannel`**: `pack_id` unique, `last_assigned_version` ≥ 0, `current` (FK `ContentPack`,
    null).
  - **`ContentPack`**:
    - `pack_id`, `version` ≥ 1 (unique together);
    - `origin` `built` or `promoted`; `status` `draft`, `validated`, `published` or `retired`;
      `build_state` `queued`, `running`, `finished` or `failed`;
    - `schema_version`, `snapshot_at`;
    - `canonical_sha256`, `sha256` and `release_sha256` (char 64), `size`, `file` (BinaryField),
      `validation_report` (jsonb);
    - `min_client_version` `^\d+\.\d+\.\d+$`, and `rollback_of` (self, null);
    - `built_by`, `published_by`, `promoted_by`, their `*_at`, and `failure_reason`;
    - `Meta.permissions` = `build_pack`, `publish_pack`, `rollback_pack`, `promote_pack`,
      `change_min_client_version`, `import_content`, `export_content`, `review_speech`.

    `save()` enforces the immutability rules and transitions of data-model "State transitions".
  - **`PublishedIdentifier`**: `kind` choices, `identifier`, `first_version`; unique (`kind`,
    `identifier`).
  - **`PackTripIndex`** and **`PackPriceIndex`**, with the fields and unique keys of data-model.
  - **`ContentAuditRecord`**: `action`, `outcome`, `actor`, `at`, `pack_id`, `version`, `sha256`,
    `details` jsonb. Append-only: `save()` refuses updates, and `delete()` always refuses.
- [X] T053 Create `backend/apps/content/signals.py`: a `pre_delete` receiver for every model that
  has a permanent identifier, which refuses deletion of identifiers present in
  `PublishedIdentifier`. Then run `uv run manage.py makemigrations content`, which creates
  `backend/apps/content/migrations/0001_initial.py`.

  As built, `0002_current_pack_check.py` follows it. It holds the "one current pack" database
  check: deferred constraint triggers on the channel and pack tables. Each check runs at commit and
  requires `current` to be the highest published pack, or empty when nothing is published. The
  data migrations below are therefore `0003` and `0004`.
- [X] T054 Write the data migrations in `backend/apps/content/migrations/`:
  - `0003_groups.py`: the `content_author` group (add, change and delete on every authoring model,
    plus `import_content`, `export_content`, `build_pack` and `review_speech`) and
    `content_publisher`
    (`publish_pack`, `rollback_pack`, `promote_pack` and `change_min_client_version`);
  - `0004_channel_and_schedules.py`: the `ContentChannel(pack_id="core")` row, and the beat
    `PeriodicTask`s `content.sweep_stuck_builds` (every 10 minutes, queue `content`) and
    `content.sync_files` (daily at 02:00 UTC, kwargs `{"verify": true}`, queue `content`).

  Make T042 pass.
- [X] T055 [P] Implement the shared services:
  - `backend/apps/content/services/permissions.py`: `require(actor, perm)`, which raises
    `PermissionDenied` naming the permission, and also refuses an inactive or non-staff actor; and
    `role()` and `require_role(...)` from `CONTENT_ROLE`;
  - `services/audit.py`: `record(action, outcome, actor, pack=None, details=None)`;
  - `services/permanence.py`: `record_published(pack_dict, version)`, and the guard helpers
    `signals.py` uses.
- [X] T056 [P] Add `backend/apps/content/invariants.py`. It registers
  `content.published_packs_intact` with `apps.common.services.invariants.register`: for every
  `published` or `retired` row, the SHA-256 of `file` equals `sha256` and its length equals
  `size`. Add a test in `backend/apps/content/tests/test_invariants.py` covering a passing database
  and a tampered row.
- [X] T057 Add the test fixtures in `backend/apps/content/tests/conftest.py`:
  - `packs_dir` (a `tmp_path` directory, with `CONTENT_PACKS_DIR` overridden);
  - `pack_server` (a `http.server.ThreadingHTTPServer` on 127.0.0.1 serving a temporary directory,
    with switches to answer `500`, delay past the timeout, or drop the connection);
  - `sample_imported` (imports `content/examples/sample` through the importer, as `author1`). Its
    speech lines are unreviewed, because reviews are never exported (contracts/content-source.md);
  - `sample_reviewed` (`sample_imported`, then `review_lines` on every speech line as `author1`).
    Every test that needs a `validated` pack builds from it: build, publish, manifest, rollback,
    lookups and promotion;
  - `author`, `publisher` and `plain_staff` users with the groups, and an `inactive_author`
    (`content_author`, `is_active=False`).

  `pack_server` serves whatever the test puts in its directory, including `core.floor.json`.

  As built:
  - `sample_imported` and `sample_reviewed` arrive with the importer (T064) and the review
    service (T063).
  - `apps/content/tests/factories.py` builds single rows and packs. Its packs keep the channel on
    the highest published pack, because Django's test teardown runs the deferred checks.

**Checkpoint**: migrations apply, and T040–T042 and T056 are green.

---

## Phase 5: User Story 2 - Authors write content in the admin (Priority: P2)

**Goal**: Authoring in the admin with inlines, right-to-left Arabic fields, per-record checks,
roles, permanence, zip import and export in the `content/source` layout, and the change history
(FR-012–FR-019; contracts/admin.md, contracts/content-source.md).

**Independent Test**: quickstart §2. Enter the §9.3 trip by hand and export it, and the export
matches. Import the sample into an empty database, export it again, and the files are identical.

### Tests for User Story 2 (write first)

- [X] T058 [P] [US2] Write `backend/apps/content/tests/test_admin_authoring.py`:
  - **Form errors** (US2-1): saving a trip with a fare of 475, with a passenger whose
    `dest_station` isn't a trip station, or with a seat from another vehicle shows each error on
    its field, and no row is saved.
  - **Arabic fields** (US2-2) render `dir="rtl" lang="ar"`.
  - **Read-only access:** a staff member without `content_author` gets read-only pages (US2-6),
    and so does everyone under `CONTENT_ROLE=target`.
  - **Permanence:** permanent identifier fields are read-only, and a refused delete names the pack
    version (FR-016).
  - **CSP:** B01's admin CSP test still passes with the content pages loaded, with no inline
    script.
- [X] T059 [P] [US2] Write `backend/apps/content/tests/test_import_export.py`:
  - **Round trip** (US2-4): sample import, then export current content, then `diff`, is identical
    apart from `pack.json` `version: 0`.
  - **All or nothing** (US2-3): one invalid file refuses the whole import, the report names the
    file and path, and no row changes.
  - **Zip safety:** these are each refused:
    - an entry with `../`, an absolute path, a backslash path, or a symlink entry;
    - more than 2,000 entries, more than 8 MiB uncompressed, an entry over 1 MiB, or an upload
      over 4 MiB;
    - an unknown folder.
  - **Nested replacement:** a replacement that drops a permanent identifier refuses the import.
  - **Reviews:** unchanged speech lines keep their review, and changed lines lose it.
  - **Access:** `import_content` is required, and `CONTENT_ROLE=target` refuses. Exporting the
    current content requires `export_content`, and `CONTENT_ROLE=target` refuses it. Exporting a
    published pack is open to any active staff member. `inactive_author` is refused everywhere.
  - **Export of a published pack** reads its stored file.
  - **Commands:** `content_import` and `content_export` behave the same way, and without `--actor`
    each stops before reading or writing anything (contracts/admin.md "Management commands").
- [X] T060 [P] [US2] Write `backend/apps/content/tests/test_history.py` (FR-018): an admin save,
  an inline change, a bulk "mark reviewed" and an import each leave `django_admin_log` entries
  naming the user and the changed objects.

### Implementation for User Story 2

- [X] T061 [US2] Implement `backend/apps/content/widgets.py` (`ArabicTextInput` and
  `ArabicTextarea` with `attrs={"dir": "rtl", "lang": "ar"}`) and `backend/apps/content/forms.py`.
  The forms carry:
  - per-kind validation for line unlock fields, chapter goal fields, and catalog currency by
    `sku_kind`;
  - the trip formset `clean()`: stations on the trip's line, in line order, with increasing
    `at_seconds`; passenger seats in the trip's vehicle; destination and boarding stations among
    the trip's stations;
  - a comma-separated `panel_art` field for 3–5 slugs.
- [X] T062 [US2] Implement `backend/apps/content/services/snapshot.py`: `snapshot_pack_parts() ->
  dict`. It reads every authoring table in one `REPEATABLE READ` transaction and returns the
  `Pack` parts:
  - `trip_id` built from line and number;
  - `seats` with `row`/`col` from `seat_id` and `reachable_by_driver = row in {"front", "A"}`;
  - `initial_tray` without zero counts;
  - `LocalizedText` without an empty `ar`;
  - inactive tasks left out, author notes and reviews never included;
  - arrays sorted by identifier.

  Also return `snapshot_at`.
- [X] T063 [US2] Implement `backend/apps/content/services/review.py`: `review_lines(lines, actor)`,
  which requires `content.review_speech` and sets `reviewed_by` to the username and `reviewed_at`
  to now.
- [X] T064 [US2] Implement `backend/apps/content/services/importer.py`: `import_zip(file, actor)`
  and `import_dir(path, actor)`.
  - Apply the zip safety limits of contracts/content-source.md "Import rules".
  - Read through `wassal_content.source.read_layout`, then `validate_pack` stages 1–3.
  - Apply in one transaction: create or update by identifier, replace nested lists, and keep
    reviews only when the text is unchanged.
  - Refuse the whole import on any finding or permanence conflict.
  - Write `LogEntry` rows (`ADDITION` or `CHANGE`) for the changed objects.
  - Require `import_content` and `CONTENT_ROLE=source`.
- [X] T065 [US2] Implement `backend/apps/content/services/exporter.py`:
  - `export_current() -> bytes`, a zip with `pack.json` `version: 0` built from
    `snapshot_pack_parts`;
  - `export_pack(pack) -> bytes`, which decompresses the stored `file` with a 32 MiB cap and runs
    `write_layout`.
- [X] T066 [US2] Implement `backend/apps/content/admin.py` for the authoring models, per
  contracts/admin.md "Authoring pages":
  - inlines (Line → Station, Vehicle → Seat, Trip → TripStation/TripPassenger/TripEvent, Scene →
    SceneLine, Item → ItemVariant, SpeechPool → SpeechLine);
  - list filters and search;
  - `has_add/change/delete_permission` returning `False` under `CONTENT_ROLE=target`;
  - `get_readonly_fields` adding permanent identifiers;
  - the bulk action "Mark reviewed" calling `review_lines`;
  - the extra URLs "Import zip" (an upload form; `import_content`, `source`) and "Export current
    content" (`export_content`, `source`), through `get_urls`, each calling its service, which
    makes the same checks.
- [X] T067 [US2] Add `backend/apps/content/management/commands/content_import.py` (`<dir-or-zip>
  --actor <username>`) and `content_export.py` (`<dir> [--version N] --actor <username>`), both
  calling the same services with the actor resolved from its username. `--actor` is required, and
  an unknown username stops the command. The checks are those of contracts/admin.md "Management
  commands": the current content needs `export_content` and `source`, and a published pack any
  active staff member.
- [X] T068 [US2] Add a repeatable `--group <name>` option to `backend/apps/accounts/management/commands/create_staff.py`,
  refusing unknown groups, with a test in `backend/apps/accounts/tests/test_create_staff.py`.

**Checkpoint**: quickstart §2 passes, and T058–T060 are green.

As built:
- `ContentChannel.imported_version` keeps the highest imported `pack.json` version, input B of
  research R7's version numbering.
- An import validates the pack at version `max(pack.json version, 1)`, as `validate-source` does,
  because an export of unpublished content says `version: 0`.
- A zip of the layout's folder (`sample/pack.json`, …) is accepted, so a folder zipped by hand
  imports.
- Unchanged entities are skipped, so re-importing the same content writes nothing and logs
  nothing.
- `SpeechLine` also has its own changelist with "Mark reviewed". The pool changelist's action
  reviews every line of the selected pools.
- `content_export` and `content_build` replace Django's own `--version` with the pack version.

---

## Phase 6: User Story 3 - The system builds and validates a pack (Priority: P3)

**Goal**: Background builds that snapshot, number, compute `rev`, validate in all stages, compress
and store, and report (FR-020–FR-024; research R7, R10; contracts/pack-delivery.md "Version
numbers").

**Independent Test**: quickstart §3. The sample builds green. The same content and version give the
golden checksums. A broken reference stays `draft`, with `V-T4` naming its path.

### Tests for User Story 3 (write first)

- [X] T069 [P] [US3] Write `backend/apps/content/tests/test_build.py`:
  - **Green build** (US3-1): `sample_reviewed` builds to `validated`, with a version, size and
    `sha256`.
  - **Unreviewed import:** `sample_imported` builds to `draft`, with one `V-V1` per speech line.
  - **Command access** (FR-019): `content_build` without `--actor` stops before building. An actor
    without `build_pack`, or `inactive_author`, is refused, with `--dry-run` too. Under
    `CONTENT_ROLE=target` it is refused.
  - **Reproducible** (US3-2, SC-004): the same content and version build to byte-identical files,
    equal to `content/examples/sample.golden.json`.
  - **Broken references** stay `draft`, with the finding's code, entity, id and path (US3-3).
  - **Rule failures:** an unreviewed line gives `V-V1`, a digit in task text `V-X1`, and a BONAT
    item price `V-M1` (US3-4, US3-5).
  - **`rev`** goes up only for trips whose definition differs from the current published pack's
    (US3-6).
  - **Snapshots:** an edit committed during a running build is absent from the pack (US3-7).
  - **Solver stage:** `CONTENT_SOLVER_STAGE=none` reports `not_available` and leaves the pack
    unpublishable (US3-8, FR-022); `stand_in` passes.
  - **Stuck builds:** a build `running` for over 30 minutes is marked `failed` by the sweeper.
  - **Re-runs:** running the build task twice for the same pack gives the same result.
  - **Size:** the size warning doesn't block (`V-S1`).
- [X] T070 [P] [US3] Write `backend/apps/content/tests/test_versioning.py`:
  - two concurrent builds, in separate threads and connections, get distinct consecutive versions;
  - an imported `content/source/pack.json` version raises the next version;
  - **the floor file** (contracts/pack-delivery.md "Version numbers"), served by `pack_server`:
    - `{"max_version":14,"pack_id":"core"}` with `last_assigned_version` 12 gives 15;
    - a floor below staging's own records changes nothing: `max_version` 3 with
      `last_assigned_version` 12 gives 13;
    - **gaps don't matter**: `pack_server` holds `core-12.json.gz` and `core-14.json.gz` but no 13,
      the floor file says 14, and `last_assigned_version` is 12, so the build gets 15;
    - each of these refuses the build with `version_floor_unavailable`, assigns nothing and leaves
      `last_assigned_version` unchanged: a `404`, a `500`, a timeout, a dropped connection, a body
      over 1 KiB, invalid JSON, a float `max_version`, a negative `max_version`, and a wrong
      `pack_id`;
  - the floor file is read before the row lock: while `pack_server` delays its answer, a second
    connection's `SELECT … FOR UPDATE NOWAIT` on the `ContentChannel` row succeeds;
  - with no floor URL, nothing is fetched.

### Implementation for User Story 3

- [X] T071 [US3] Implement `backend/apps/content/services/stages.py`:
  - `review_stage(parts) -> StageResult` (`V-V1` for every unreviewed `SpeechLine` in the
    snapshot);
  - `SolverStage` (a protocol with `run(pack: dict) -> StageResult`), plus `NoSolver`
    (`not_available`) and `StandInSolver` (passes every trip);
  - `load_solver_stage()`, which resolves `CONTENT_SOLVER_STAGE` (`none`, `stand_in` or a dotted
    path).
- [X] T072 [US3] Implement `backend/apps/content/services/versioning.py`:
  - `read_floor() -> int`: when `CONTENT_VERSION_FLOOR_URL` is set, `GET
    <floor-url>core.floor.json` with `requests`, `CONTENT_HTTP_TIMEOUT_SECONDS`, 3 retries on
    connection errors and `5xx`, streamed with a 1 KiB cap, and parsed with `wassal_content`'s
    strict loader. It returns `max_version` (an integer ≥ 0, with `pack_id` `"core"`), or 0 without
    a floor URL. Anything else raises `VersionFloorUnavailable`, a `404` included;
  - `next_version(channel) -> int`: it calls `read_floor()` **before** taking the lock, then under
    `select_for_update()` on `ContentChannel` assigns `max(last_assigned_version, imported
    content/source version, floor) + 1`.
- [X] T073 [US3] Implement `backend/apps/content/services/build.py`:
  - `request_build(actor) -> ContentPack`: requires `build_pack` and `CONTENT_ROLE=source`, and
    creates a `draft` with `build_state=queued`;
  - `run_build(pack_id)`:
    1. `running`, then snapshot;
    2. assign the version (T072);
    3. compute each trip's `rev` against `ContentChannel.current`'s index rows;
    4. assemble the `Pack` with `schema_version` from `schema-set.json`;
    5. canonical bytes, then the pack file;
    6. `validate_pack`, the review stage, the solver stage and size;
    7. store `file`, `sha256`, `canonical_sha256`, `size` and `validation_report`, with
       `min_client_version` defaulting to the current pack's (or `1.0.0`);
    8. `validated` if every stage passed or warned, otherwise `draft`;
    9. `finished`, or `failed` with `failure_reason`.
- [X] T074 [US3] Implement `backend/apps/content/tasks.py`:
  - `build_pack` (`bind=True`, `acks_late=True`, `reject_on_worker_lost=True`, queue `content`,
    autoretry only on `OperationalError`, `max_retries=3`);
  - `sweep_stuck_builds`, which marks `running` builds older than 30 minutes as `failed`.
- [X] T075 [US3] Extend `backend/apps/content/admin.py` with the `ContentPack` admin:
  - the changelist columns of contracts/admin.md;
  - a "Build a new pack" button calling `request_build`;
  - a detail page with the validation report grouped by stage, errors first, with links to the
    authoring objects;
  - everything read-only.
- [X] T076 [US3] Add `backend/apps/content/management/commands/content_build.py`: `--actor
  <username> [--dry-run] [--version N]` builds synchronously.
  - `--actor` is required, and an unknown username stops the command.
  - It makes `request_build`'s checks (`build_pack`, an active staff actor, `CONTENT_ROLE=source`)
    before doing anything, `--dry-run` included (contracts/admin.md "Management commands").
  - With `--dry-run` it prints `canonical_sha256`, `sha256` and a summary of the findings without
    saving, even when there are findings.

**Checkpoint**: quickstart §3 passes, and T069–T070 are green.

As built:
- `ContentPack.version` is empty while a build is queued. The build assigns it after the snapshot
  and saves it at once, so a job redelivered after a worker loss keeps its number.
- A pack is `validated` when every stage passed or warned. The solver may also be
  `not_available`: such a pack is validated but can't be published (contracts/admin.md).
- `rev` is compared without `rev` itself: a trip equal to the current pack's keeps its `rev`, a
  changed one gets the current `rev` + 1, a new one keeps its authored `rev`. The authored `rev`
  never changes.
- A rollback build uses the stored pack's parts and skips the review stage.
- `content_build --version N` is accepted only with `--dry-run`. A real build that stays `draft`
  or fails exits with an error, after printing the findings.
- An unexpected error fails the build with "internal error, see the logs", never its details.
- Reports are stored as `jsonb`, which reorders keys, so the admin and the command list stages in
  `STAGES` order. Findings are stored grouped by stage, errors first.
- While a build is queued or running, its admin page reloads every 5 seconds with a meta refresh
  (no script, so the admin CSP is unchanged).
- The admin is now a package: `admin/authoring.py`, `admin/packs.py`, `admin/reports.py` and
  `admin/common.py`.

---

## Phase 7: User Story 4 - A publisher publishes a pack, and the app learns about it (Priority: P4)

**Goal**: Publishing on staging into the packs directory with release records, lookups and
retiring, the manifest endpoint, rollback, minimum-app-version changes, the file sync, and the
edge's `/packs/` route (FR-025–FR-036, FR-038; contracts/api.md, contracts/pack-delivery.md).

**Independent Test**: quickstart §4. Publish, and the manifest lists the pack within a minute, with
a file whose `sha256` matches. Raising the minimum app version makes old apps get the older pack. A
read-only packs directory makes the publish fail, and the previous pack stays offered.

### Tests for User Story 4 (write first)

- [X] T077 [P] [US4] Write `backend/apps/content/tests/test_publish.py`:
  - **Happy path:** `core-<v>.json.gz` and `core-<v>.release.json` are written create-only, read
    back and hash-checked. `status` becomes `published`, `ContentChannel.current` is set,
    `PublishedIdentifier` and the index rows are written, the 6th newest is retired (its index
    rows deleted, its file kept), and an audit record `publish`/`succeeded` exists (US4-1, US4-8).
  - **Existing names:** the same bytes at an existing name count as already stored. Different bytes
    are refused with an error-level log, and the file is untouched.
  - **Read-only directory:** the publish fails, `current` is unchanged, a `failed` audit record
    exists, and a retry succeeds after the permission is restored (US4-2, SC-010).
  - **Version not higher:** refused (US4-4).
  - **Solver not passed:** refused.
  - **Access:** without `publish_pack` it is refused (US4-9). Under `CONTENT_ROLE=target` it is
    refused.
  - **The release record** is canonical, has no staff names, and its sha256 equals
    `release_sha256`.
  - **No floor file on staging:** a publish under `CONTENT_ROLE=source` never writes
    `core.floor.json`.
  - **Immutability:** a published pack's record can't change except `min_client_version` (US4-3).
- [X] T078 [P] [US4] Write `backend/apps/content/tests/test_manifest.py`, covering
  contracts/api.md:
  - every row of the response table;
  - `X-Client-Version` given as `1.4.0+57`, missing, and `abc`;
  - the 30 s cache, and its invalidation on publish and on a minimum-version change;
  - the response validating against `manifest.schema.json` (through `wassal_content`), and the
    serializer's field set equal to the schema's;
  - no authentication needed;
  - `POST` gives `405`;
  - the database down gives `503`, and the cache down still answers;
  - URLs built from `CONTENT_PACKS_PUBLIC_URL`.
- [X] T079 [P] [US4] Write `backend/apps/content/tests/test_rollback_minversion.py`:
  - **Rollback** builds the earlier pack's content as a new version with `rollback_of` set,
    re-validates it, and bumps `rev` for trips that differ from the current pack (US4-5, FR-028).
  - **Minimum version:** raising and lowering are audited with old and new values, and are visible
    in the manifest. Values below `min_client_version_by_major` are refused, and so are values that
    don't match the format (US4-11, FR-032).
- [X] T080 [P] [US4] Write `backend/apps/content/tests/test_lookups.py` (FR-035):
  - `catalog_price(version, sku_kind, sku_id)` and `trip_definition(version, trip_id)` return the
    values from that pack for the last 5 versions;
  - a retired version returns `None`;
  - the index rows equal what parsing the pack file gives.
- [X] T081 [P] [US4] Extend `backend/docker/edge/smoke.sh` and the dev edge check
  (contracts/pack-delivery.md "Public files"):
  - `GET /packs/core-1.json.gz` from a fixture file answers `200` with `Content-Type:
    application/gzip`, `Cache-Control: public, max-age=31536000, immutable` and no
    `Content-Encoding`;
  - `GET /packs/core.floor.json` from a fixture file answers `200` with `Content-Type:
    application/json` and `Cache-Control: no-store`;
  - `/packs/`, `/packs/x.txt`, `/packs/core.floor.json.bak` and `/packs/.hidden` answer `404`;
  - a 6 MiB body to the admin hostname passes the edge, and a 9 MiB one gets `413`.

### Implementation for User Story 4

- [X] T082 [US4] Implement `backend/apps/content/services/files.py`:
  - `pack_file_name(v)` and `release_file_name(v)`;
  - `write_create_only(path, data)` (`os.open` with `O_CREAT|O_EXCL|O_WRONLY`, mode `0o644`,
    `fsync` the file and the directory; an existing file with equal bytes is fine, different bytes
    raise `FileConflict`);
  - `read_back_sha256(path)`;
  - `write_floor(version)` (contracts/pack-delivery.md "The floor file"), only under
    `CONTENT_ROLE=target`:
    - it writes `max(value in the file, version)` as canonical JSON, so the value never goes down;
    - the write is a temporary file in the same directory, `fsync`, `os.replace` over
      `core.floor.json`, then `fsync` of the directory, mode `0o644`;
    - a floor file that doesn't parse is logged at error level and replaced only by a higher value
      from the database;
  - `ensure_floor()`, which creates a missing floor file from the highest version in production's
    records, or 0. Call it from the worker's startup check in `backend/apps/content/checks.py` on
    `target`;
  - `sync_files(verify: bool)`, which recreates missing files from the database, logs
    `FileConflict` and mismatches at error level, and on `target` calls `write_floor` with the
    highest stored version.
- [X] T083 [US4] Implement `backend/apps/content/services/release.py`: `release_record(pack) ->
  bytes` (canonical JSON with the fields of contracts/pack-delivery.md "Release record") and
  `promotion_code(pack) -> str` (`core-<v>:<sha256>`).
- [X] T084 [US4] Implement `backend/apps/content/services/lookups.py`:
  - `index_pack(pack, pack_dict)`, which writes the `PackTripIndex` and `PackPriceIndex` rows, with
    `last_station_at_s` the last station's `at_seconds`;
  - `retire_beyond_five(pack_id)`;
  - `catalog_price(...)` and `trip_definition(...)`.
- [X] T085 [US4] Implement `backend/apps/content/services/publish.py`: `publish(pack, actor)`,
  following contracts/pack-delivery.md "Publish on staging" steps 1–5:
  1. check permissions and role, and that the solver stage passed and the version is higher;
  2. write the files create-only;
  3. read them back and compare;
  4. commit in one transaction, with `on_commit` clearing the manifest cache;
  5. on failure, write a `failed` audit record and set `failure_reason`.
- [X] T086 [US4] Implement `backend/apps/content/services/rollback.py`: `request_rollback(pack,
  actor)` (requires `rollback_pack` and `source`; queues a build whose snapshot is the stored file's
  pack parts instead of the authoring tables; sets `rollback_of`) and `audit` entries on queue and
  on publish.
- [X] T087 [US4] Implement `backend/apps/content/services/manifest.py`:
  - `parse_client_version(header) -> tuple[int, int, int] | None`;
  - `select_pack(version_tuple)`, per the api.md rules;
  - `manifest_payload()`, cached in Valkey under `content:manifest:<offered-version>` for
    `CONTENT_MANIFEST_CACHE_SECONDS`, falling back to the database when the cache errors;
  - `invalidate()`;
  - `change_min_client_version(pack, value, actor)`, which checks the floor from `schema-set.json`,
    writes the audit record and invalidates.
- [X] T088 [US4] Implement `backend/apps/content/api/serializers.py` (`ContentManifestPack`,
  `ContentManifest`) and `backend/apps/content/api/views.py` (`ManifestView`:
  `authentication_classes = []`, `permission_classes = [AllowAny]`, B01's default throttle,
  `extend_schema`). Register `v1/content/manifest` in `backend/config/urls.py`. Add a `/packs/`
  route that serves `CONTENT_PACKS_DIR` through `django.views.static.serve` only when
  `settings.DEBUG`.
- [X] T089 [US4] Add the tasks `publish_pack` and `sync_files(verify)` to
  `backend/apps/content/tasks.py`, and `backend/apps/content/management/commands/content_files.py`
  (`sync [--verify]`). It takes no `--actor`: it changes no content, makes nothing current, and
  writes only already-published files and the floor file (contracts/admin.md "Management
  commands"). Extend the `ContentPack` admin with the actions "Publish", "Roll back to
  this", "Change minimum app version" (a form), "Download pack file" and "Export content", plus the
  promotion code on published packs (`source`) and the read-only `ContentAuditRecord` admin.
- [X] T090 [US4] Regenerate `contracts/openapi.yaml` (`uv run manage.py spectacular --file
  ../contracts/openapi.yaml --validate --fail-on-warn`). Then confirm that B01's `schemathesis`
  suite covers `/v1/content/manifest`.
- [X] T091 [US4] Update the edge:
  - `backend/docker/edge/Caddyfile`: the `(api)` snippet gains, before `reverse_proxy`, `@packs
    path_regexp ^/packs/core-[0-9]+\.(json\.gz|release\.json)$`, `handle @packs { root * /srv;
    header Cache-Control "public, max-age=31536000, immutable"; file_server }`, then `@floor path
    /packs/core.floor.json` with `handle @floor { root * /srv; header Cache-Control "no-store";
    file_server }`, and last `handle_path /packs/* { respond 404 }`. The `(admin)` snippet gains
    `request_body { max_size 8MiB }`.
  - `backend/docker/edge/Caddyfile.dev`: the same.
  - `backend/docker/edge/compose.yml`: a `/var/lib/wassal/packs:/srv/packs:ro` volume.

  Make T081 pass.
- [X] T092 [US4] Mount the packs directory:
  - `backend/docker/compose.yml`: the `worker` mounts `${CONTENT_PACKS_HOST_DIR:-/var/lib/wassal/packs}:/var/lib/wassal/packs`.
    The `api`, `admin` and `beat` services don't.
  - `backend/docker/compose.dev.yml`: `worker` and `api` mount `../var/packs:/app/var/packs`.
  - The CI `smoke` job in `.github/workflows/backend.yml` gains `curl` checks that
    `/v1/content/manifest` answers `{"version":0,"packs":[]}` and that a missing pack gives `404`.

**Checkpoint**: quickstart §4 passes, and T077–T081 are green.

As built:
- `ContentPack.release_file` keeps the release record's bytes, so `content_files sync` can rewrite
  a lost record exactly. A publish makes the record once and saves it before writing files, so a
  retry after a failure writes the same bytes and never conflicts. `published_at` is the record's.
- Create-only writes go to a hidden temporary file, synced, then hard-linked to the name. The link
  fails if the name exists, so a crash never leaves a partial file under a pack's name.
- A refused or failed publish returns the pack with `failure_reason` set and a failed audit
  record, instead of raising. Reasons are `file_conflict: …`, `storage_error: …`, or the refusal.
- The manifest cache key is `content:manifest:<generation>:<stated app version>`. Invalidating
  bumps the generation, which retires every cached answer at once. A Valkey error falls back to
  the database.
- Rollback builds need `rollback_pack` instead of `build_pack`, and skip the review stage: their
  content was reviewed when first published.
- The edge sets each pack file's `Content-Type` itself (one matcher per name), so it never depends
  on the image's MIME table. The admin's 8 MiB limit applies as Django reads the body, as on the
  import page; the smoke posts with a valid CSRF cookie so Django reads it.
- In dev, packs live on the `packs` volume at the hosts' path, `/var/lib/wassal/packs`: the image
  creates that directory owned by `app`, so the new volume starts writable for the worker.
  `backend/var/packs` would sit inside the `/app` bind mount, which the container's user can't
  write to (found by the T106 smoke). Under `DEBUG` the API serves `/packs/` with the edge's names
  only.
- The admin is a package (`admin/packs.py` holds the pack pages). Publish and rollback ask for
  confirmation on their own page.
- Tests: `test_publish.py`, `test_manifest.py`, `test_rollback_minversion.py`, `test_lookups.py`,
  plus `test_files.py` (create-only writes, the floor file, sync) and the pack actions in
  `test_admin_packs.py`.

---

## Phase 8: User Story 5 - A pack tested on staging is promoted to production (Priority: P5)

**Goal**: Production pulls the identical file from staging's public URL, anchored by the pasted
code. Staging's version numbering stays above production's, and staging's authoring work is backed
up (FR-039–FR-040; research R6–R8; contracts/pack-delivery.md "Promotion on production").

**Independent Test**: quickstart §5. `pytest apps/content/tests/test_promotion.py` passes the
happy path and every failure case, using a local server as staging.

### Tests for User Story 5 (write first)

- [X] T093 [P] [US5] Write `backend/apps/content/tests/test_promotion.py`, with `CONTENT_ROLE=target`
  and `pack_server` as staging:
  - **Happy path** (US5-1): the pack is promoted byte-identically, with `origin=promoted`,
    `status=published`, `current` set, index rows written and an audit record `promote/succeeded`.
  - **Failures, each leaving `current` unchanged with an audit `failed`** (US5-2, US5-3, US5-4):
    - a malformed code is refused before any fetch;
    - a wrong code gives `release_mismatch`;
    - a tampered pack gives `pack_mismatch`, and a size mismatch too;
    - a version not higher than current;
    - the solver stage `not_available` or a stage failed gives `release_not_passed`;
    - a release record over 64 KiB, a pack over 16 MiB, or a decompressed pack over 32 MiB;
    - a pack that fails schema validation gives `pack_invalid`;
    - a minimum app version below the floor;
    - staging unreachable gives `release_unreachable`, and a later retry succeeds (US5-8).
  - **Existing files:** the same bytes at an existing name count as stored.
  - **The floor file** (contracts/pack-delivery.md "The floor file"):
    - a successful promotion of version 15 leaves `core.floor.json` at 15;
    - it is raised before the commit: with the commit made to fail, the floor is 15 and `current`
      is unchanged;
    - it never goes down: with the file at 20 (production's database restored from an older
      backup), promoting 16 leaves it at 20;
    - a failure before the files are confirmed (`pack_mismatch`) leaves it unchanged;
    - `ensure_floor()` creates a missing file from the highest promoted version, or 0 with none,
      and `content_files sync` raises a file that is behind the database.
  - **Production's admin** offers no authoring, import or build (US5-5).
  - **On `source`**, promotion is refused.
- [X] T094 [P] [US5] Write `backend/apps/content/tests/test_rebuild_floor.py` (US5-6, SC-013):
  - an empty staging database and an imported `content/source` `pack.json` of version 12, with
    `pack_server` holding production's `core-12.json.gz` and `core-14.json.gz` (13 is a gap) and a
    floor file of 14. The next build gets 15;
  - the same setup with the floor file missing (`404`) refuses the build with
    `version_floor_unavailable`, and assigns nothing.

### Implementation for User Story 5

- [X] T095 [US5] Implement `backend/apps/content/services/promote.py`: `promote(code, actor)`,
  following contracts/pack-delivery.md "Promotion on production" steps 1–6, with the failure codes
  listed there:
  - fetches use `requests`, with `CONTENT_HTTP_TIMEOUT_SECONDS`, streaming with byte caps, and 3
    retries on connection errors and `5xx`;
  - it runs `validate_pack` stages 1–3, the minimum-app-version floor check, `write_create_only`
    and read-back. Then `write_floor(version)`, before one commit for `current`, the index,
    retiring and audit;
  - `on_commit` invalidates the manifest cache.
- [X] T096 [US5] Add the `promote_pack` task (`bind=True`, `acks_late`, retries only for network
  errors) to `backend/apps/content/tasks.py`. Add the "Promote from staging" changelist form to
  `backend/apps/content/admin.py`, shown only under `CONTENT_ROLE=target` with `promote_pack`, with
  one field validated as `^core-[0-9]+:[0-9a-f]{64}$`.
- [X] T097 [US5] Staging backups (research R8, FR-039c):
  - `backend/docker/host/provision.sh` enables `wassal-backup@staging.timer` on the staging host
    once `/etc/wassal/staging-backup.env` exists, and creates `/var/lib/wassal/staging/backup`.
  - The staging host monitor (`backend/docker/host/bin/host-monitor`) checks backup age as
    production's does.
  - Add tests to `backend/docker/host/tests/test_provision_identity.py` and
    `backend/docker/host/tests/test_host_monitor.py`.
- [X] T098 [US5] Create the packs directory: `backend/docker/host/provision.sh` creates
  `/var/lib/wassal/packs` on both hosts (owner `10001:10001`, mode `0755`), with a test in
  `backend/docker/host/tests/test_provision_identity.py`.

**Checkpoint**: quickstart §5 passes, and T093–T094 and the host tests are green.

As built:
- A promotion runs on the worker, which holds the packs directory: the admin form checks the code
  and queues `promote_pack`. Every failure is one of the contract's codes in a failed audit
  record, with up to 50 findings for `pack_invalid`, and changes nothing apps see.
- Fetches are capped (release record 64 KiB, pack 16 MiB, decompressed 32 MiB). The URL is always
  `CONTENT_PROMOTION_SOURCE_URL` plus a name built from the code's version, so the pasted code
  never chooses a host.
- A schema major production doesn't know is `pack_invalid`, not an error.
- The promoted pack's page shows staging's stage results from the release record.
- **T097, as production does it.** `wassal-backup@staging.timer` is always enabled on the staging
  host, and `ConditionPathExists=/etc/wassal/staging-backup.env` skips each run until the file
  exists, exactly like production's timer. Production's host monitor has no backup-age check: a
  late or failed backup is its Healthchecks.io check's alert (`backup-prod`, which `backup_db`
  pings). So staging got the `backup-staging` check (an owner action), and its host monitor now
  runs the backup-storage check on its own `last-backup.json`. `bin/backup` accepts the host's
  own environment on both hosts.
- `provision.sh` lists each host's state directories in `host_dirs` (printable with
  `--render-dirs <env>`): `/var/lib/wassal/<env>/backup` (`10001:10001`, `0750`, as `bin/backup`
  already set it) and `/var/lib/wassal/packs` (`10001:10001`, `0755`, T098).
- `backend/tools/b2_setup.py` gained `--env staging`, which creates staging's buckets and only a
  write-only key, `wassal-staging-backup`, on `staging/` (staging is never drilled). It also gained
  `--restore-key`, a list/read key on one environment's buckets and prefix that B2 expires after
  24 h. A staging restore needs it, and the B2 console can't make a key for two buckets.
- The two hosts' monitors split the 8 GB storage alert (6 GB prod, 2 GB staging), because both
  environments' buckets share one B2 account's free 10 GB. The owner confirms the split before
  merge (owner-actions.md).
- Tests: `test_promotion.py`, `test_rebuild_floor.py`; 371 host tests (staging's timer and env
  file, the state-directory table, staging backing itself up and refusing `backup prod`, the
  staging monitor's storage check); 10 more in `tests/test_b2_setup.py`.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Docs, runbooks, owner actions, review, and the final validation of PR 2.

- [X] T099 [P] Update `docs/architecture-backend.md`:
  - §4: the diagram's `OBJ` node and its row become "packs served by each host's edge from
    `/var/lib/wassal/packs`";
  - §7.4: `spend_jenehat` `sku_kind` gains `chapter`;
  - §9.1: the flow gains "publish on staging → promote to production", and the release record;
  - §9.2: the catalog row;
  - §12 "content": the model list from data-model.md;
  - §15: the object storage row (packs self-hosted, B2 now also holds staging backups), the CDN
    row resolved, and the backups row for staging;
  - §22.3: struck through and resolved, pointing to research R5.
- [X] T100 [P] Update `docs/architecture-mobile.md` §14.1: the manifest selection for old apps, and
  that an app bundles a pack production has promoted (research "Handed to later features").
- [X] T101 [P] Write `docs/runbooks/content-publishing.md`:
  - author, then build, publish on staging and test;
  - copy the promotion code and promote on production;
  - export and open the `content/source` PR;
  - roll back;
  - the minimum-version kill switch;
  - what to do with `version_floor_unavailable`, `FileConflict` and `release_mismatch`.

  Update `docs/runbooks/deploy-and-rollback.md` (the edge update for the `/packs/` route) and
  `docs/runbooks/restore.md` (restoring staging from its own buckets, then `content_files sync`).
- [X] T102 [P] Create `content/source/README.md`, which says that only promoted packs land here,
  how to export them, and that its `pack.json` switches on the schema-diff check (FR-040, R3).
- [X] T103 Update `CLAUDE.md` with the backend content commands (`content_import`,
  `content_export`, `content_build --dry-run`, `content_files sync --verify`) and the new
  environment variables. Update `docs/delivery-plan.md`: the step 2 resolve line, which settles
  §22.3, and the Progress entry.
- [X] T104 Add a "003 B04 content pipeline" section to `docs/owner-actions.md`, and a row in its
  "Open now" table:
  - **Before merge:** the security review (T105).
  - **After merge:**
    - deploy the edge update on both hosts;
    - set `CONTENT_*` in `/etc/wassal/{staging,prod}.env` (contracts/environment.md);
    - create the staging B2 buckets, the write-only key and the Healthchecks.io check, then add
      `/etc/wassal/staging-backup.env` and confirm the first backup;
    - give the `content_author` and `content_publisher` groups;
    - add authors' devices to staging's private network.
  - **After B05:** quickstart "After B05" items 3–7.
- [X] T105 Run a security review of the PR 2 diff with the `security-reviewer` agent, and fix every
  CRITICAL and HIGH finding. In scope:
  - zip import (zip slip, zip bombs, entry limits);
  - file writes and the packs directory's permissions;
  - promotion fetches (size caps, the hash anchor, no SSRF from user input);
  - permission checks in services;
  - the audit log being append-only;
  - the public files carrying no personal data.
- [X] T106 Run the full checks:
  - `uv run pytest --cov --cov-fail-under=80` in `tools/content_kit/` and in `backend/`;
  - `fvm dart test` with the coverage gate in `packages/content_models/`;
  - `uv run ruff check`, `ruff format --check` and `mypy` in both Python projects;
  - `codegen --check`;
  - the migration check and the OpenAPI diff;
  - quickstart §§2–5.

  Fix anything red, then open **PR 2**.

  As built (2026-10-19): every check passes:
  - backend: 1022 tests, 95.20% coverage;
  - `content_kit`: 393 tests, 96.24%;
  - `packages/content_models`: 34 tests, 100%;
  - ruff and mypy in both Python projects;
  - `codegen --check` and `golden`;
  - no missing migrations, and the regenerated OpenAPI file is identical to the committed one.

  Quickstart §§2–4 were walked on the dev stack from the command line and through the dev edge:
  - import, review, build and publish;
  - the manifest, including for an app below the minimum;
  - the pack's sha256 and its immutable header;
  - a `no-store` 404.

  §5 is the promotion suite. The admin-only steps (entering a trip by hand, right-to-left input,
  the 15-minute timing) need a browser with TOTP, and are left for the owner's review of PR 2.

  The smoke found that dev's packs directory sat inside the `/app` bind mount, which the image's
  user can't write to, and that the worker's `mkdir` error there was only logged. The fix: dev uses
  a `packs` volume at `/var/lib/wassal/packs`, which the image creates owned by `app`, and the
  check turns that error into the same `SystemExit`.

  PR 2 is open as #4.
- [ ] T107 After B05 (owner and agent): walk quickstart "After B05" items 1–7 on the hosts, record
  the results in `docs/owner-actions.md`, and tick B04 in `docs/delivery-plan.md` Progress once
  they pass.


As built (Phase 9):
- T099–T101 also touched the docs that B04's staging backups made stale:
  - `docs/runbooks/monitoring-setup.md`: the `backup-staging` check, B2 step 8, the storage split;
  - `docs/runbooks/provision-host.md` and `docs/runbooks/README.md`: staging's timers and files;
  - B01's `contracts/operations.md` and `contracts/environment.md`, annotated "since B04".
- `restore.md` gained "Restore staging" (a 24-hour read key from `b2_setup.py --restore-key`,
  then production's steps with staging's names, then `content_files sync --verify`) and the
  fallback from `content/source`. Production's restore and rebuild now end with
  `content_files sync --verify` too.
- T102: `content/source/README.md` already existed from PR 1, with the required content.
- T104: staging's host steps and `CONTENT_*` values are **before merge**, because the merge
  deploys staging and a B04 release won't start without them. Production's come before the tag.
- T105: the `security-reviewer` agent found no CRITICAL or HIGH issues. It fixed two MEDIUM ones:
  - unreadable or duplicate zip entries are refused;
  - the floor file is written under a lock.

  Its three recommendations are done:
  - a database trigger keeps the audit log append-only (migration `0005_audit_append_only`);
  - `/packs/` 404s carry `no-store`;
  - an unknown schema major is `pack_invalid` on promotion.

  Left as LOW: the manifest cache's key count, `Accept-Encoding` on pack downloads, and staff
  downloading drafts.
---

## Dependencies & Execution Order

### Phase dependencies

| Phase | Depends on | Blocks |
| --- | --- | --- |
| 1 Setup | — | everything |
| 2 Foundational | 1 | 3 |
| 3 US1 (PR 1) | 2 | 4, and M01 |
| 4 Pipeline foundation | 3 merged | 5–8 |
| 5 US2 | 4 | 6 (the build reuses `snapshot.py`) |
| 6 US3 | 4, plus T062 from 5 | 7 |
| 7 US4 | 6 | 8 |
| 8 US5 | 7 (publish files, release records, lookups) | 9 |
| 9 Polish | 5–8 | PR 2 |

### Within phases

- **Tests first.** Test tasks come before implementation, and must fail first.
- **Schemas** (T017–T022) come before the examples (T024–T026), which come before codegen output
  (T033) and the golden file (T035).
- **Models** (T048–T052) come before migrations (T053–T054), then services, admin and endpoints.
- **Publish** (T085) comes before rollback (T086) and the manifest's minimum-version flow (T087).

### Parallel opportunities

- **Phase 1:** T002 and T003 alongside T001.
- **Phase 2:** T004, T005 and T006 together.
- **Phase 3:**
  - tests T010–T016 together;
  - schemas T018–T021 together once T017 is done;
  - T034 alongside T035–T037.
- **Phase 4:**
  - tests T040–T042 together;
  - model modules T048–T052 together (one file each);
  - T055 and T056 together.
- **Phases 5–8:** each phase's test tasks are marked [P].
- **Phase 9:** docs T099–T102 together.

---

## Parallel Example: User Story 1

```bash
# Tests first, together:
Task: "T010 [US1] test_profile.py"      Task: "T011 [US1] test_examples.py"
Task: "T012 [US1] test_round_trip.py"   Task: "T013 [US1] test_codegen.py"
Task: "T014 [US1] test_schema_diff.py"  Task: "T015 [US1] test_source.py"
Task: "T016 [US1] test_golden.py"
# Then the part schemas, together, after common.schema.json (T017):
Task: "T018 trip.schema.json"  Task: "T019 line/vehicle"  Task: "T020 chapter/room/item/request"  Task: "T021 speech/catalog/daily/task"
```

## Parallel Example: Pipeline foundation models

```bash
Task: "T048 models/lines.py"   Task: "T049 models/trips.py"   Task: "T050 models/story.py"
Task: "T051 models/speech_economy.py"   Task: "T052 models/packs.py"
```

---

## Implementation Strategy

### MVP first (PR 1: User Story 1 only)

1. Phases 1–2: the package skeletons, loader, canonical form and pack file.
2. Phase 3: schemas, examples, the sample, codegen, the Dart package and CI.
3. **Stop and validate** with quickstart §1. Open PR 1, merge it, and hand M01 the schemas.

### Incremental delivery (PR 2)

1. Phase 4, the foundation. Then US2 (authors can work on staging as soon as PR 2 deploys), then
   US3, US4 and US5.
2. Each story is validated by its quickstart section before the next starts.
3. **Live publishing waits for B05** (T107). Until then, staging and production refuse to publish
   or promote (FR-022).

---

## Notes

- **[P]** tasks touch different files and have no dependency on an incomplete task.
- **Commits** follow Conventional Commits, with one commit per task or per small group.
- **Generated files** (`_generated.py`, `wassal_content/schemas/`, `lib/src/generated/`) only ever
  change through `wassal-content codegen`.
- **Arabic text** belongs only in `content/` JSON files, never in Python or Dart source
  (constitution VII; the mobile guard test scans `apps/mobile/lib/` only).
