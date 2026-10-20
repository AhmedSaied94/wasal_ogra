---

description: "Task list for M01 Trip Engine"
---

# Tasks: Trip Engine (M01)

**Input**: Design documents from `specs/004-m01-trip-engine/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Tests are required (constitution XIII). Every phase writes its tests
  first, and they must fail before the implementation tasks start. Engine rules are red, then green,
  then refactor.
- **Coverage.** At least 90% of lines in `packages/trip_engine/lib/`, and at least 80% in
  `tools/content_kit` and the backend.
- **Real services.** Backend tests run against the local stack's PostgreSQL and Valkey.

**Organization**:

- **Paths** are from the repository root.
  - Dart commands run with `fvm` in `packages/trip_engine/` (or `apps/mobile/`,
    `packages/content_models/`).
  - `uv` commands run in `tools/content_kit/` or `backend/`.
- **Exactness.** The rules are [contracts/rules.md](./contracts/rules.md) (copied to
  `packages/trip_engine/RULES.md` in T004). "§n" below means a section of that file. Every number
  comes from `TripParams`, so never write a balancing literal in `lib/`.
- **Shared engine files.** `lib/src/rules/step.dart`, `lib/src/rules/command_handlers.dart` and
  `lib/src/rules/stations.dart` grow story by story, so tasks touching them are sequential across
  stories.
- **Fixtures.**
  - From US2 on, every fixture is written by hand (definition, seed, params, log), then
    `fvm dart run tool/fixtures.dart update <file>`. Its rule goes into
    `test/fixtures/fixture_expectations_test.dart`. Read the `show` output before committing.
  - **Earlier fixtures can change.** A story that adds a rule for every passenger changes the
    fixtures written before it; patience in US3 is the main one. So from US3 on, each story's
    fixture task starts with `check` on the existing fixtures. Every difference must be explained
    by the new rule. Only then `update` those files, re-read their `show` output and fix their
    expectations. Never `update` a fixture to make a red suite green without that review
    (constitution III).
- **One PR.** This feature merges as one PR. B05 starts once it is on `master`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US7 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the engine package, the shared contract files and CI (plan "Project
Structure").

- [x] T001 Create the pure Dart package `packages/trip_engine/` (research R1):
  - **`pubspec.yaml`:**
    - `name: trip_engine`, `publish_to: none`, `environment: sdk: ^3.13.0`;
    - dependencies `content_models: {path: ../content_models}` and `crypto: ^3.0.7`;
    - dev dependencies `test: ^1.33.0`, `coverage: ^1.16.0` and `lints: ^6.1.0`;
    - no Flutter SDK dependency.
  - **`analysis_options.yaml`:** includes `package:lints/recommended.yaml`, with
    `analyzer.language` `strict-casts`, `strict-inference` and `strict-raw-types` all `true`.
  - **`.gitignore`:** `.dart_tool/` and `coverage/`. Commit `pubspec.lock`, as `content_models`
    does.
  - **Skeleton:**
    - `lib/trip_engine.dart`, a library doc comment with no exports yet;
    - `lib/src/{model,rules}/` and `test/`;
    - `tool/`;
    - a `README.md` that says what the package is, how to run it (quickstart), and links
      `RULES.md`.
  - **Resolve:** run `fvm dart pub get` (after `content_models`' `build_runner`, quickstart "Set
    up").
- [x] T002 [P] Create `content/engine/capabilities.json` exactly as in
  [contracts/content-contract.md](./contracts/content-contract.md) §2:
  - `version: 1`;
  - the 12 archetypes;
  - the 8 events with their parameter rules;
  - the 23 speech slots with placeholders, in that order.
- [x] T003 [P] Create `fixtures/parity/README.md`:
  - the five-key form;
  - `<area>__<case>.json` naming, with the area table of contracts/replay-and-fixtures.md §5;
  - how to run `tool/fixtures.dart` check, update and show;
  - "never type `expected_result` by hand";
  - the rule that every rule change updates fixtures in the same PR (constitution III).
- [x] T004 [P] Copy [contracts/rules.md](./contracts/rules.md) to `packages/trip_engine/RULES.md`
  (research R18):
  - Change its header to say it is the living rules reference that B05 mirrors.
  - At the top of `specs/004-m01-trip-engine/contracts/rules.md`, add one line saying the living
    copy is `packages/trip_engine/RULES.md`.
- [x] T005 [P] Update `.github/workflows/mobile.yml` per
  [contracts/ci-checks.md](./contracts/ci-checks.md):
  - add `fixtures/` to the `changes` regex;
  - add the four `trip_engine` steps (pub get, format check, `analyze --fatal-infos`, then test with
    coverage, format to lcov and run `check_coverage.dart --min 90 --lcov coverage/lcov.info`) to the
    `check` job, after the `content_models` steps, with `working-directory: packages/trip_engine`.
- [x] T006 [P] Update `.github/workflows/backend.yml`: add `fixtures/` to the `changes` regex
  (contracts/ci-checks.md).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The changes everything else builds on:

- the schema field and its ripple;
- the packaged capabilities file and the new content rules;
- the sample pack the fixtures will play;
- the app's tunables, which are the source of params;
- the engine's types, codecs, validation and step shell.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Content contract: tests first

- [x] T007 [P] Add `content/examples/invalid/trip/no_fights_required_missing.json` (a valid trip
  with `rules.no_fights_required` removed). Register it in `content/examples/invalid/expected.json`
  as `"trip/no_fights_required_missing.json": "$.rules.no_fights_required"`. `uv run pytest
  tests/test_examples.py` must fail until T009.
- [x] T008 [P] Write `tools/content_kit/tests/test_engine_rules.py`, with one case per finding, each
  failing until T012 (contracts/content-contract.md §3):
  - **V-T8:**
    - `bump` with `seconds`;
    - `traffic` without `seconds`, or with `seconds: 0` or `61`;
    - `fare_increase` without `amount_piasters`;
    - `drop_me_here` with 2 passengers;
    - `payment_dispute` with 1 passenger, or naming a group member;
    - `change_request` with `amount_piasters: 500`;
    - `roadside_pickup` with 7 passengers;
    - any event with `station_id`.
  - **V-T9:** a `bags_lady` passenger, and an event id outside capabilities (built directly,
    bypassing the schema).
  - **V-T10:** a pack missing `passenger.tip`.
  - **V-T11:** a `passenger.pays` line using `{station}`, and an override pool used for slot
    `stop_near` that uses `{amount}`.
  - **Clean cases:** the sample pack and every `content/examples/valid/trip/*.json` produce no
    finding.
  - **Lone trips:** `validate <file> --part trip` reports V-T8 and V-T9 on a lone trip.
- [x] T009 Add `"no_fights_required": {"type": "boolean"}` to `$defs.TripRules.properties` and to
  its `required` list in `content/schemas/trip.schema.json`. Then:
  - run `uv run wassal-content codegen` in `tools/content_kit`;
  - run `fvm dart pub get && fvm dart run build_runner build -d` in `packages/content_models`;
  - add `"no_fights_required": false` to every trip in the examples:
    - both `content/examples/valid/trip/*.json`, and the trips inside
      `content/examples/valid/pack/core.json`;
    - all 13 existing `content/examples/invalid/trip/*.json`. `test_examples.py` requires each
      invalid example to fail at its named field only, so without the field each would also fail
      at `$.rules.no_fights_required`;
  - run `uv run wassal-content schema-diff --base origin/master` and confirm it reports only this
    addition;
  - `uv run pytest` and `fvm dart test` in `packages/content_models` pass (T007 now passes).
- [x] T010 Package the capabilities file (research R13):
  - **Codegen:** `wassal_content.codegen` copies `content/engine/capabilities.json` byte for byte to
    `tools/content_kit/src/wassal_content/engine/capabilities.json`, and `codegen --check` fails on
    any difference. Add a test for both in `tools/content_kit/tests/test_codegen.py`.
  - **Packaging:** ship the file as package data in `tools/content_kit/pyproject.toml`.
  - **Loader:** add `src/wassal_content/engine/__init__.py` with a typed loader,
    `capabilities() -> Capabilities`, a frozen dataclass of archetypes, event parameter rules,
    slots and placeholders, and change-request notes.
  - **Commit** the generated copy.
- [x] T011 [P] Update `content/examples/sample/` (contracts/content-contract.md §4). Keep each trip
  3-star playable under rules.md:
  - **Every trip** under `trips/**` gets `"no_fights_required": false`.
  - **`trips/line_hay/line_hay.03.json`** stays `kind: story`, with `no_fights_required: true`.
  - **`trips/line_gamaa/line_gamaa.02.json`:** replace the `mother_kids` passenger, a phase 3 type,
    with archetype `honest` (same seat, destination and payment, skin `effendi_suit`).
  - **`trips/line_hay/line_hay.01.json`:** set `rules.student_discount_pct` to 50.
  - **Speech pools:** add one file per missing slot under `speech/`, named `passenger.<slot>.json`,
    for these 20 slots: `pays_group`, `pays_old_fare`, `pays_rest`, `impatient`, `thanks`,
    `short_change`, `returns_excess`, `fight`, `missed_stop`, `claims_paid`, `caught`, `accused`,
    `woke`, `attentive`, `drop_me_here`, `dispute`, `change_request`, `change_request_declined`,
    `boards` and `tip`.
    - Each has 1–2 short Egyptian Arabic lines, with no digits and only the slot's placeholders.
    - Examples: `thanks` «تسلم يا أسطى»; `claims_paid` «أنا دافع!»; `short_change` «لسه ليا
      {amount} يا أسطى»; `missed_stop` «يا نهار! فاتتني {station}»; `tip` «خلّي {amount} عشانك».
- [x] T012 Implement `tools/content_kit/src/wassal_content/rules/engine.py`, with V-T8 to V-T11 read
  from `wassal_content.engine.capabilities()`, all `severity="error"`:
  - export `engine_findings` from `rules/__init__.py`;
  - call it from `validate.validate_pack`, which covers trips and the pack;
  - call it from single-document `validate --part trip`, with V-T8 and V-T9 only;
  - T008 passes;
  - `uv run wassal-content validate-source ../../content/examples/sample` reports nothing;
  - run `uv run wassal-content golden --update` and review the checksum diff of
    `content/examples/sample.golden.json`;
  - ruff, mypy and `pytest --cov --cov-fail-under=80` pass.
- [x] T013 [P] Write the backend tests for the new field, in `backend/apps/content/tests/`. They fail
  until T014.
  - The `content_import` → `content_export` round trip keeps `rules.no_fights_required` (true and
    false).
  - The snapshot and build output carry it.
  - The admin trip form shows and saves it.
  - Add `engine_speech_pools()` to `backend/apps/content/tests/factories.py`. It creates a
    `SpeechPool` with one line for every capabilities slot. Use it in `conftest.py`'s pack fixtures,
    so builds pass V-T10.
  - A build missing one pool fails with V-T10.
- [x] T014 Implement the backend ripple (contracts/content-contract.md §5):
  - `no_fights_required = models.BooleanField(default=False)` on `Trip` in
    `backend/apps/content/models/trips.py`;
  - `uv run manage.py makemigrations content -n trip_no_fights_required`, an `AddField` only;
  - read it in `services/importer.py` (next to `max_break_requests`);
  - write it in `services/snapshot.py` `rules`;
  - add it to the trip rules fieldset in `admin/authoring.py`;
  - `uv run pytest --cov --cov-fail-under=80`, `uv run mypy .`, `uv run ruff check .` and
    `uv run manage.py makemigrations --check --dry-run` pass.
  - `contracts/openapi.yaml` is unchanged (`spectacular --validate --fail-on-warn` diff empty).

### App tunables: tests first

- [x] T015 [P] Update `apps/mobile/test/core/config/tunables_defaults_test.dart` and
  `apps/mobile/test/core/config/config_source_test.dart` to
  [contracts/tunables.md](./contracts/tunables.md). They fail until T016.
  - The expected table has 50 keys:
    - the five `trip_hints_enabled_*` become `trip_hints_mode_*` with `always`, `first_time`, `off`,
      `off`, `off`;
    - the 20 new `int` keys have their defaults, including `booster_traffic_jam_max_per_trip` 3.
  - `Tunable.tripHintsMode(line).parse('first_time')` is `TripHintsMode.firstTime`, while `'on'`
    and `true` are `null`.
  - The per-line test checks the modes.
- [x] T016 Implement in `apps/mobile/lib/core/config/tunable.dart` and
  `apps/mobile/assets/config/tunables.json`:
  - `enum TripHintsMode { off('off'), firstTime('first_time'), always('always') }`, with `wire`, as
    `PreTripCardMode` has;
  - replace `tripHintsEnabled` with `tripHintsMode(LineId)`;
  - the 20 named `Tunable<int>` constants;
  - `all` lists 50 keys;
  - `tunables.json` gets the same 50 entries;
  - T015 passes, and `fvm flutter analyze --fatal-infos` and `fvm flutter test` pass in
    `apps/mobile`.

### Engine foundation: tests first

- [x] T017 [P] Create the test support in `packages/trip_engine/test/support/`:
  - **`builders.dart`:** a fluent `TripBuilder` that produces valid `TripDefinition`s:
    - vehicle layouts `tuktuk` (A_r, A_m, A_l) and `micro_old` (front_r + A–C × r, m, l);
    - stations with times and fares, passengers, events, a tray and rules
      (`no_fights_required` default false);
    - seed 1.
  - **`default_params.dart`:** `defaultParams(LineId)`. It reads
    `../../apps/mobile/assets/config/tunables.json` from disk and calls
    `TripParams.fromTunables`.
  - **`scripts.dart`:** helpers to step to a time and to apply a command and expect `Accepted` or
    `Rejected(code)`.
- [x] T018 [P] Write the guard tests in `packages/trip_engine/test/guards/` (research R16). Each
  scans `lib/**/*.dart` with comments and string literals stripped:
  - `imports_test.dart`: imports are limited to `dart:core`, `dart:convert`, `dart:collection`,
    `package:content_models/` and `package:crypto/`, and `pubspec.yaml` has no `flutter` key;
  - `integer_money_test.dart`: no `double`, `num`, `.toDouble(` or a `/` operator that isn't `~/`;
  - `no_clock_test.dart`: no `DateTime`, `Stopwatch`, `Random`, `dart:io`, `dart:async` or
    `Future`;
  - `no_arabic_test.dart`: no characters in U+0600–U+06FF or U+0750–U+077F.
- [x] T019 [P] Write `packages/trip_engine/test/prng_test.dart`. It fails until T020.
  - xorshift32 (rules.md §13) from seed 1 gives `270369, 67634689, 2647435461, 307599695,
    2398689233`.
  - From seed 521288629 it gives `1425164135, 2680915048, 127437483`.
  - From seed 4294967295 it gives `253983, 4228382207, 1958451267`.
  - Every value stays in 0..2^32−1.
- [x] T020 Implement `packages/trip_engine/lib/src/prng.dart`: `Xorshift32`, immutable, with
  `next() → (int value, Xorshift32 next)`.
- [x] T021 [P] Write `packages/trip_engine/test/money_test.dart`. It fails until T022.
  - `Pieces`: add, remove (rejecting missing pieces), total, ascending order, unmodifiable, and
    canonical `toJson` (`{"100": 2}`).
  - Fewest pieces (rules.md §14.3): 4150 → 2000×2, 100, 50; 50 → 50; 0 → empty.
  - The break-down table (§14.1): every row totals its note, and 500 has no row.
  - The change-request search (§14.4):
    - 1000 from {500:1, 100:5} → 500, 100×5;
    - 1000 from {500:1, 100:4} → none;
    - 5000 from {2000:2, 500:1, 100:5} → 2000×2, 500, 100×5;
    - a case where greedy fails but backtracking succeeds: 1000 from {500:1, 100:3, 50:4} →
      500, 100×3, 50×4.
- [x] T022 Implement `packages/trip_engine/lib/src/money.dart`:
  - `Pieces`;
  - `isDenomination(int)`;
  - `fewestPieces(int)`;
  - `breakDown(int)`, with the table of §14.1 as `const` data;
  - `changeRequestPieces(int note, Pieces tray)`;
  - `changeBag`, which is 50×2, 100×3, 500×2.
- [x] T023 [P] Write `packages/trip_engine/test/params/params_test.dart` and
  `packages/trip_engine/test/params/params_tunables_test.dart`. They fail until T024.
  - `fromJson` and `toJson` round-trip.
  - A missing key or a non-integer value throws `FormatException`, naming the key.
  - `fromTunables(json, LineId.lineGamaa).tripHopMs == 1100`, using the app's `tunables.json`, for
    every line.
  - The validation of data-model.md "TripParams" (`bad_params`):
    - every field is present and is an integer;
    - `trip_hop_ms`, `trip_group_redirect_hop_ms` and `trip_patience_ms` are ≥ 33;
    - every percent is 1–1000;
    - `rep_revive_to` is 1–100;
    - `booster_traffic_jam_ms` is ≤ 60,000 and `booster_traffic_jam_max_per_trip` ≤ 5 (60,001 and
      6 are refused);
    - every other field is ≥ 0.
- [x] T024 Implement `packages/trip_engine/lib/src/params.dart`: the `TripParams` fields of
  data-model.md, `fromJson`, `toJson` (wire keys from contracts/tunables.md), `fromTunables` and
  `problems()`. There are no defaults in code.
- [x] T025 [P] Write `packages/trip_engine/test/capabilities_test.dart`. It fails until T026. It
  reads `../../content/engine/capabilities.json` and asserts that `EngineCapabilities.archetypes`,
  `.events`, the event parameter rules, `SpeechSlot.values` (wire names, order, placeholders,
  `defaultKey == 'passenger.<slot>'`) and the change-request notes equal the file.
- [x] T026 Implement `packages/trip_engine/lib/src/capabilities.dart`: `EngineCapabilities`, the
  `SpeechSlot` enum (23 slots, `wire`, `defaultKey`, `placeholders`) and the event parameter rules,
  as `const` data.
- [x] T027 [P] Write `packages/trip_engine/test/model/model_json_test.dart`. It fails until T028.
  - Every model type's `toJson()` is canonical: keys in snake_case per data-model.md, absent
    optionals omitted, integers only.
  - Collections are unmodifiable.
  - `TripResult.fromJson(toJson())` round-trips.
- [x] T028 Implement the immutable models in `packages/trip_engine/lib/src/model/`, with the fields
  of [data-model.md](./data-model.md):
  - `state.dart`: `TripState`, `TripStatus`, and the getters `ledgerPeekActive`,
    `undoAvailableUntilMs`, `nextStation` and `breaksLeft`;
  - `passenger.dart`: `PassengerState`, `Presence`, `Alertness` and `AlightOutcome`, plus `isAble`,
    `isOwed` and `patiencePermille`;
  - `token.dart`: `MoneyToken`, `TokenKind`, `Holder`, `Hop` and `progressPermille`;
  - `station.dart`: `StationState`;
  - `choices.dart`: `Claim`, `Dispute`, `ChangeRequest`, `PendingBreak` and `LastSend`;
  - `counters.dart`: `Counters`, `Mistake`, `MistakeKind` and `RepCause`;
  - `result.dart`: `TripResult` and `TripOutcome`.

  Each type has private-constructor update helpers internal to the package, and no exported
  `copyWith`.
- [x] T029 [P] Write `packages/trip_engine/test/commands/command_codec_test.dart`. It fails until
  T030.
  - Each of the 13 commands encodes to and decodes from its wire array in
    contracts/replay-and-fixtures.md §1, for example `[330,"PickFromTray",100]`.
  - A malformed array throws `FormatException`: an unknown name, the wrong argument count or type,
    or a negative or non-33-multiple `t_ms`.
  - `RejectionCode` wire names match the table in contracts/engine-api.md.
- [x] T030 Implement `packages/trip_engine/lib/src/commands.dart`: sealed `Command` with the 13
  classes, `LoggedCommand` (`tMs`, `command`, `toJson`, `fromJson`), `Rejection` and the
  `RejectionCode` enum.
- [x] T031 [P] Write `packages/trip_engine/test/events/event_json_test.dart`. It fails until T032.
  For every event in the contracts/engine-api.md table, `name` and the `toJson()` keys match that
  row exactly, with optional `amount_piasters` and `station_id` omitted when null.
- [x] T032 Implement `packages/trip_engine/lib/src/events.dart`: sealed `DomainEvent` (`tMs`,
  `name`, `toJson`), and every event class in the contracts/engine-api.md table.
- [x] T033 [P] Write `packages/trip_engine/test/validation/validation_test.dart`, with one case per
  refusal code in data-model.md "Validation". It fails until T034.
  - The codes: `bad_seed` (0, 2^32), `bad_params`, `duplicate_id`, `unknown_seat`,
    `unknown_station`, `stations_out_of_order`, `board_after_dest`, `seat_taken_at_start`,
    `unknown_passenger`, `group_mismatch` (sizes disagree, too many members, no or two
    `group_payer`), `unsupported_archetype` (`dodger`), `unsupported_event`, `event_param` (each
    capabilities rule) and `pickup_conflict`.
  - Several problems are all reported at once, with paths.
  - Every sample trip and every `content/examples/valid/trip/*.json` is accepted.
- [x] T034 Implement `packages/trip_engine/lib/src/validation.dart`: `validate(definition, params,
  seed) → List<Refusal>`, `Refusal {code, path, message}` and `TripRefused`.
- [x] T035 [P] Write `packages/trip_engine/test/engine/engine_shell_test.dart`. It fails until T036.
  - **Starting:** `TripEngine.start` throws `TripRefused` for an invalid trip. A valid one starts
    `running` at 0 ms, with reputation 100 and the initial tray.
  - **The clock:** `step()` advances 33 ms. `stepTo(330)` takes 10 steps.
  - **Pausing:** `pause()` makes `step()` return `[]` without moving the clock, and `resume()`
    continues. They are never logged.
  - **The log:** a rejected command isn't logged, an accepted one is logged with the current
    `t_ms`.
  - **The cap:** the 1,201st command is rejected with `command_limit`.
  - **Status checks:** `wrong_status` follows the data-model.md "Commands" table.
  - **Failure:** reputation driven to 0 by a test hook fails the trip (§10.2).
- [x] T036 Implement the shell and the shared rules plumbing:
  - **`packages/trip_engine/lib/src/engine.dart`:** `TripEngine.start`, `state`, `status`, `result`,
    `commandLog`, `step`, `stepTo`, `apply`, `pause` and `resume`.
  - **`lib/src/rules/step.dart`:** the step function with the ten phases of rules.md §3, as named
    functions that do nothing yet.
  - **`lib/src/rules/command_handlers.dart`:** dispatch by type, the status and cap checks, and
    logging.
  - **`lib/src/rules/reputation.dart`:** gains capped at 100, losses recorded in
    `reputation_lost`, `ReputationChanged`, and the failure check of §10.2.
  - **`lib/trip_engine.dart`:** export the public surface of contracts/engine-api.md.
  - T017–T035 pass, and `fvm dart analyze --fatal-infos` is clean.

**Checkpoint**: Foundation ready. Content, schema, app tunables and the engine skeleton are all green.

---

## Phase 3: User Story 1 - Play a basic trip from start to finish with commands (Priority: P1) 🎯 MVP

**Goal**: Fares, the tray and the hand, the passing chain, change judging, stations, getting off,
reputation, stars and earnings, with `regular`, `honest` and the student fare (spec US1).

**Independent Test**: A scripted log on sample `line_hay.01` finishes with 3 stars and the expected
earnings. Giving too much change gives 2 stars and one `over` mistake. Withholding change gives a
fight and 1 star.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [x] T037 [P] [US1] Write `packages/trip_engine/test/rules/chain_test.dart` (§5.1–§5.5, §5.8):
  - **Routing:**
    - toward the driver from rows front, A, B, C and D, skipping empty seats;
    - toward a passenger from the driver and from a middle holder;
    - the next holder is recomputed when a seat empties or fills mid-transit.
  - **Hops:** a `trip_hop_ms` 1300 hop takes 40 steps.
  - **Blocking:** an unable holder or next holder blocks, with `TokenBlocked` and `TokenUnblocked`.
    Make a passenger unable by setting alertness through a test builder.
  - **Getting off:** tokens held by a passenger who gets off are handed to the driver, and tokens
    addressed to them go to the tray.
- [x] T038 [P] [US1] Write `packages/trip_engine/test/rules/fares_test.dart` (§6.1–§6.4, §11):
  - the fare is the destination's fare;
  - a student's fare is discounted and rounded up: 850 at 50% → 450, 700 at 50% → 350, 850 at 0% →
    850;
  - paying sends the authored pieces and fixes `balance = total − fare`, positive, zero or negative;
  - a tap on a passenger who owes makes them pay the rest in the fewest pieces;
  - `fares_collected` is the sum of `min(fare, paid_in)`.
- [x] T039 [P] [US1] Write `packages/trip_engine/test/rules/change_test.dart` (§6.5):
  - **exact:** settled, +`rep_exact_change`, capped at 100;
  - **short:** the balance drops and −`rep_short_change` (clarification 2), and a later top-up that
    settles counts as exact;
  - **over:** an `over` mistake with the excess amount. An `honest` passenger returns the fewest
    pieces through the chain into the tray. Anyone else adds it to `overpaid_piasters`;
  - **not owed:** to a passenger with no fare sent, or a balance ≤ 0. An honest passenger returns
    the same pieces;
  - two tokens to the same passenger are judged in arrival order.
- [x] T040 [P] [US1] Write `packages/trip_engine/test/rules/stations_test.dart` (§9.2–§9.5, §11):
  - **The warning:** at `at_ms − trip_station_warning_ms`, with the `alighting` and `owed` lists,
    and the first alighting passenger says `stop_near`;
  - **Getting off:** outcomes thanked, fight (−`rep_fight`, `fights += 1`, an `unreturned` mistake)
    and left unpaid (`lost_fares += 1`), in passenger order;
  - **Boarding:** at a station when the seat is free, otherwise as soon as it is freed;
  - **The end:** settled per §11 (fares in transit arrive, change goes to the tray), and
    `TripFinished` is emitted.
- [x] T041 [P] [US1] Write `packages/trip_engine/test/rules/scoring_test.dart` (§11):
  - stars 1, 2 and 3 by fights and mistakes, and `star_flags`;
  - earnings are `min(max(0, fares − overpaid + tips) ~/ 100, max_earnings_jenehat)`: 2549
    piasters → 25 JENEHAT, negative → 0, cap applied;
  - `duration_ms` and `reputation`;
  - `command_log_hash` is present.
- [x] T042 [P] [US1] Write `packages/trip_engine/test/rules/speech_test.dart` (§12):
  - the key is `passenger.<slot>`, unless the passenger's `speech_keys[slot]` overrides it;
  - `variant` is the next PRNG value in emission order (seed 1 → the first speech is 270369);
  - placeholders are present only where the slot declares them;
  - speech changes no other state.
- [x] T043 [P] [US1] Write `packages/trip_engine/test/commands/hand_commands_test.dart` (§4.1–§4.3):
  - `PickFromTray` moves one piece, or is rejected with `tray_empty` or `bad_argument` (for 300);
  - `ReturnHand` puts the hand back, or is rejected with `hand_empty`;
  - `SendHand` creates a `change` token from the driver and clears the hand, or is rejected with
    `hand_empty` or `not_aboard`;
  - rejected commands are not logged.
- [x] T044 [P] [US1] Write `packages/trip_engine/test/commands/tap_pay_test.dart` (§3 step 4,
  §4.5):
  - a passenger pays at `pays_at_seconds`;
  - a tap before that time pays at once (clarification 4), and no second payment comes at the
    scheduled time;
  - a passenger with no `pays_at_seconds` pays only when tapped;
  - a tap on a passenger who owes pays the rest.
- [x] T045 [P] [US1] Write `packages/trip_engine/test/stories/us1_basic_trip_test.dart`, with the
  spec's US1 Independent Test and acceptance scenarios 1–6 on sample `line_hay.01` and on small
  built trips:
  - the 3-star run with its exact earnings;
  - over-change → 2 stars;
  - withheld change → a fight and 1 star. Assert the fight's penalty through its
    `ReputationChanged{cause: fight}` event, not the final reputation, so the test still holds once
    patience lands in US3;
  - an unpaid passenger → a lost fare not counted in earnings.

### Implementation for User Story 1

- [x] T046 [P] [US1] Implement `packages/trip_engine/lib/src/rules/speech.dart` (§12), the only place
  that draws from the PRNG.
- [x] T047 [P] [US1] Implement `packages/trip_engine/lib/src/rules/fares.dart`: the fare (§6.1,
  without groups or increases yet), paying now (§6.2), paying the rest (§6.4) and fares collected.
- [x] T048 [US1] Implement `packages/trip_engine/lib/src/rules/chain.dart` (§5.1–§5.5, §5.8):
  - the next holder;
  - the blocking check through `PassengerState.isAble`;
  - the base hop duration (no multipliers yet);
  - hop advance and arrival;
  - delivery dispatch;
  - handing over tokens when a passenger gets off.
- [x] T049 [US1] Implement `packages/trip_engine/lib/src/rules/change.dart` (§6.5 steps 2–5), with
  the honest return token and `MistakeMade`.
- [x] T050 [US1] Implement in `packages/trip_engine/lib/src/rules/stations.dart`:
  - the warning (§9.2);
  - getting off (§9.3), with the outcomes thanked, fight and left unpaid, and boarding of freed
    seats;
  - station processing (§9.4);
  - boarding (§9.5);
  - the end-of-trip settlement (§11).
- [x] T051 [US1] Implement `packages/trip_engine/lib/src/rules/scoring.dart`, building `TripResult`
  for every end (§11), and the fingerprint hook. The fingerprint is a placeholder until T059.
- [x] T052 [US1] Add to `packages/trip_engine/lib/src/rules/command_handlers.dart` the handlers for
  `PickFromTray`, `ReturnHand`, `SendHand` and `Tap`:
  - `Tap` covers cases 4 (pay now) and 6 (pay the rest) of §4.5;
  - the claim cases (4 for false claimers, 5 and 7) return `no_effect` until US4.
- [x] T053 [US1] Wire phases 4 (scheduled payments), 5 (tokens), 7 (warning), 8.2 (stations) and 10
  (end) in `packages/trip_engine/lib/src/rules/step.dart`. T037–T045 pass, and coverage of the
  touched files is ≥ 90%.

**Checkpoint**: A basic trip plays end to end through commands (US1).

---

## Phase 4: User Story 2 - Replay a trip exactly and share parity fixtures (Priority: P2)

**Goal**:

- the command log's wire form and fingerprint, and `replay()`;
- pacing invariance;
- the fixture codec and tool;
- the first fixtures, and the Python check of fixture definitions (spec US2).

**Independent Test**: Every fixture replays to its `expected_result`. A thousand replays, at any
pacing, give the same result and fingerprint. Editing one expected number fails the suite, naming
the fixture and field.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [x] T054 [P] [US2] Write `packages/trip_engine/test/replay/fingerprint_test.dart`
  (contracts/replay-and-fixtures.md §3):
  - `commandLogHash([])` is `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945`;
  - the log `[[33,"Tap","p2"],[1089,"PickFromTray",100]]` hashes to
    `2fc7facd65d1ed083cda40c815e6044ed3e58e41fdbaf0d7448bdc8129e45ed7`.
- [x] T055 [P] [US2] Write `packages/trip_engine/test/replay/replay_test.dart`:
  - `replay()` of a live run's log gives the same `TripResult` as the live run;
  - a log entry the engine rejects throws `RebuildRefused` with its index;
  - a log whose `t_ms` decreases is refused;
  - a log that ends with the trip failed returns the failed result.
- [x] T056 [P] [US2] Write `packages/trip_engine/test/replay/pacing_invariance_test.dart`. For every
  fixture, replaying with steps advanced one at a time, seven per call, or by one `stepTo` to each
  command gives an identical result, event sequence (as `toJson`) and fingerprint. The same holds
  over 1,000 repeated replays of one fixture (SC-001). So does pausing before every command that is
  allowed while paused (choices, boosters, `Abandon`) and resuming after it, as M02 does around
  choices (FR-054, rules.md §10.2).
- [x] T057 [P] [US2] Write `packages/trip_engine/test/fixtures/fixtures_test.dart`:
  - it loads every `../../fixtures/parity/*.json` through `ParityFixture.fromJson`;
  - it fails when a fixture has a key other than the five;
  - it asserts that `replay()` equals `expected_result` field by field, and the failure message
    names the file and field.

  Also write the scaffold `test/fixtures/fixture_expectations_test.dart`: one `group` per fixture
  file, asserting the rule that fixture pins.
- [x] T058 [P] [US2] Write `tools/content_kit/tests/test_parity_fixture_definitions.py`. For every
  `fixtures/parity/*.json`, its `definition` passes `trip.schema.json` and V-T8 and V-T9, and the
  file has exactly the five keys.

### Implementation for User Story 2

- [x] T059 [US2] Implement `packages/trip_engine/lib/src/replay.dart`:
  - `commandLogHash` (SHA-256 of the canonical JSON via `content_models`' `canonicalJson`, using
    `package:crypto`, lowercase hex);
  - `replay(definition, params, seed, log)`;
  - `ReplayRecord` with `toJson` and `fromJson`;
  - `RebuildRefused`.

  Wire the real fingerprint into `scoring.dart`.
- [x] T060 [P] [US2] Implement `packages/trip_engine/lib/src/fixture.dart` (`ParityFixture` with the
  five keys, `fromJson`, and a `toJson` that writes keys sorted with two-space indent) and
  `packages/trip_engine/test/support/fixture_io.dart`.
- [x] T061 [US2] Implement `packages/trip_engine/tool/fixtures.dart` (contracts/replay-and-fixtures.md
  §6):
  - `check`, over all files or the named ones, exits 1 on a difference;
  - `update <file>…` rewrites `expected_result`;
  - `show <file>` prints the event sequence, one `name t_ms payload` line each.
- [x] T062 [US2] Author the core fixtures in `fixtures/parity/`, then `update`, review with `show`,
  and add expectations:
  - `core__chain_rows.json`: a fare from row C hops C→B→A→driver; change goes back the same way;
  - `core__empty_seat_skip.json`;
  - `core__exact_change.json`;
  - `core__short_then_topup.json`;
  - `core__over_change_kept.json`;
  - `core__not_owed_kept.json`;
  - `core__fight_at_stop.json`;
  - `core__left_unpaid.json`;
  - `core__boarding_at_station.json`;
  - `archetype__regular.json`;
  - `archetype__honest_returns_excess.json`.
- [x] T063 [US2] Author the remaining US2 fixtures, with `update`, review and expectations:
  - `ending__three_stars.json`, `ending__two_stars.json` and `ending__one_star.json`;
  - `command__pick_return_send.json`, which includes commands rejected for `tray_empty`,
    `hand_empty` and `not_aboard` that are absent from its log;
  - `sample__line_hay_01_three_stars.json`, which plays sample `line_hay.01` to 3 stars.

  T054–T058 pass.

**Checkpoint**: The replay is exact, and the first fixtures are shared (US2). B05 can start reading
the files.

---

## Phase 5: User Story 3 - The line_hay passenger types and patience (Priority: P3)

**Goal**: The hajja, the sleeper, the hurried passenger, and patience for everyone (spec US3,
clarifications 2 and 5).

**Independent Test**:

- A fixture per type.
- The hajja's hops take twice as long.
- A sleeper blocks until woken, falls asleep again 15 s later, and misses his stop.
- A hurried passenger runs out of patience in half the time, and reputation drops once.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [x] T064 [P] [US3] Write `packages/trip_engine/test/archetypes/hajja_test.dart`. A hop she passes
  on lasts `scale(trip_hop_ms, trip_hop_pct_hajja)` (2600 ms at 1300 and 200%), and her coins land
  in the tray.
- [x] T065 [P] [US3] Write `packages/trip_engine/test/archetypes/sleeper_test.dart`:
  - he starts `asleep`;
  - a tap → `waking` → `awake` after `trip_wake_ms`, with `PassengerWoke` and a `woke` speech;
  - he falls asleep again `trip_sleeper_awake_ms` later, even when settled (clarification 5);
  - a tap while waking is `no_effect`;
  - he blocks money both as a middle holder and as the target;
  - asleep at his stop, he misses it: −`rep_missed_stop`, `missed_stops += 1`, an `unreturned`
    mistake if he is owed, a lost fare if unpaid, and a `missed_stop` speech with his station;
  - a missed stop isn't a fight;
  - he pays at the first step he is able, after his `pays_at_seconds`.
- [x] T066 [P] [US3] Write `packages/trip_engine/test/archetypes/patience_test.dart` (§7.3):
  - patience starts when he is first owed (`trip_patience_ms`; `hurry` at
    `scale(…, trip_patience_pct_hurry)` = 10 s);
  - it drains 33 per step only while he is owed and aboard;
  - `wants_change` is said once at half;
  - at zero, −`rep_impatient` once, with `counters.impatient += 1`, `PatienceRanOut` and an
    `impatient` speech;
  - it never refills or repeats;
  - while `traffic_active` (set by a builder hook), it drains `scale(33, 150) = 49` per step.

### Implementation for User Story 3

- [x] T067 [US3] Implement `packages/trip_engine/lib/src/rules/passengers.dart`:
  - the initial alertness (§2.4);
  - the timers of §3 step 2.1 and 2.2, waking and falling asleep;
  - patience (§7.3).

  Add the `asleep` and `waking` cases of `Tap` (§4.5 cases 1–2) to `command_handlers.dart`, and the
  hajja multiplier (§5.4) to `chain.dart`.
- [x] T068 [US3] Wire phases 2.1–2.2 and 6 in `packages/trip_engine/lib/src/rules/step.dart`. Add
  the missed-stop outcome (§9.3), checked before fight, to `stations.dart`. T064–T066 pass.
- [x] T069 [US3] Re-check the earlier fixtures, then author the US3 fixtures.

  **Re-check.** Run `fvm dart run tool/fixtures.dart check`. Patience now applies to every owed
  passenger, so the US2 fixtures change:
  - in their results: `impatient`, `reputation` and `reputation_lost`;
  - in their events: new `PassengerSpeaks{wants_change}` events, which shift every later speech
    `variant`.

  For each changed file, confirm with `show` that patience alone explains the difference. Then
  `update` it and fix its rule in `fixture_expectations_test.dart`. Re-run the US1 and US2 tests
  (T037–T045, T054–T058).

  **New fixtures**, with `update`, review and expectations:
  - `archetype__hajja_slow_hop.json`;
  - `archetype__sleeper_blocks_chain.json`;
  - `archetype__sleeper_missed_stop.json`;
  - `archetype__sleeper_redoze.json`;
  - `archetype__hurry_impatient.json`;
  - `core__patience_runs_out.json`.

**Checkpoint**: The line_hay types work and are pinned in fixtures (US3).

---

## Phase 6: User Story 4 - The line_gamaa passenger types (Priority: P4)

**Goal**: The big note, the student, headphones, the false claimer and the claim system, the group
payer, chatty, and the regular customer's tip (spec US4).

**Independent Test**:

- A fixture per type.
- A student on an 850 fare at 50% owes 450.
- Headphones block until the second tap and stay attentive for 15 s.
- A caught false claimer raises reputation and pays, and a believed one never pays.
- A group's change goes on to the payer.

### Tests for User Story 4 ⚠️ (write first, must fail)

- [x] T070 [P] [US4] Write `packages/trip_engine/test/archetypes/headphones_test.dart`:
  - they start `muted`;
  - the first tap gives `PassengerCalled{taps: 1}`, and the second makes them `attentive` for
    `trip_headphones_attentive_ms` with an `attentive` speech;
  - then they are `muted` again, with taps reset;
  - while muted, a tap never asks for the fare;
  - they block money both ways while muted;
  - their scheduled payment waits until they are attentive.
- [x] T071 [P] [US4] Write `packages/trip_engine/test/archetypes/claims_test.dart` (§4.5–§4.6, §7.4):
  - a false claimer claims at their payment time and when tapped, with `ClaimRaised` and a
    `claims_paid` speech;
  - **insist** gives `LiarCaught`, +`rep_liar_caught`, `caught_liars += 1`, a `caught` speech, and
    they pay;
  - **accept** gives `ClaimAccepted` and `never_pays`. They then leave unpaid at their stop, and
    later taps only make them say `claims_paid`;
  - a truthful claim from a tap on a passenger who has paid, then insist, is a false accusation:
    −`rep_false_accusation` and `fights += 1`;
  - one resolved claim per passenger;
  - a tap while a claim is open is `no_effect`;
  - `ResolveClaim` with no claim is `no_choice`;
  - an open claim at the passenger's stop counts as accepted.
- [x] T072 [P] [US4] Write `packages/trip_engine/test/archetypes/group_test.dart` (§6.1, §6.5, §7.2):
  - the group fare counts listed members' own fares, plus the payer's base fare for each unlisted
    member: 5000 paid for 3 to an 850 stop → owed 2450;
  - a tap on a member acts on the payer;
  - members never pay or claim;
  - change sent to a member is redirected to the payer in one hop of `trip_group_redirect_hop_ms`
    (600);
  - members get off thanked, or with a missed stop if asleep.
- [x] T073 [P] [US4] Write `packages/trip_engine/test/archetypes/chatty_test.dart`:
  - hops out of any seat in the row of an able chatty passenger last
    `scale(…, trip_hop_pct_chatty_row)`;
  - the multiplier stacks after the hajja's;
  - it doesn't apply while the chatty passenger isn't able, or after they get off.
- [x] T074 [P] [US4] Write `packages/trip_engine/test/archetypes/regular_customer_test.dart`, with
  student and big-note checks:
  - a regular customer who gets off thanked and not impatient adds
    `trip_tip_piasters_regular_customer` to tips, with a `tip` speech;
  - an impatient one tips nothing;
  - tips enter the earnings;
  - a `big_note` paying 20000 on a 700 fare is owed 19300;
  - a student's discount applies to their fare.

### Implementation for User Story 4

- [x] T075 [US4] Implement headphones in `packages/trip_engine/lib/src/rules/passengers.dart` and
  `command_handlers.dart`: the `muted` case of `Tap` (§4.5 case 3), and timer §3 step 2.3.
- [x] T076 [US4] Implement claims in `packages/trip_engine/lib/src/rules/command_handlers.dart` and
  `passengers.dart`:
  - `Tap` cases 4 (false claimer), 5 and 7;
  - `ResolveClaim` (§4.6);
  - false claimers at their scheduled time (§3 step 4);
  - `never_pays` (§6.3);
  - closing an open claim when its passenger gets off (§9.3.1).
- [x] T077 [US4] Implement groups:
  - the group fare in `fares.dart`;
  - member taps standing for the payer (§4.5);
  - the `redirect` in `change.dart` (§6.5.1), with its duration in `chain.dart` (§5.4);
  - member outcomes in `stations.dart`.
- [x] T078 [US4] Implement the chatty multiplier in `chain.dart` (§5.4) and the regular customer's
  tip in `stations.dart` (§9.3). T070–T074 pass.
- [x] T079 [US4] Re-check the earlier fixtures, then author the US4 fixtures.

  **Re-check.** Run `check`. No earlier fixture should change: truthful claims come only from taps
  that US1 rejected, and rejected commands are never logged. Treat any difference as a bug until
  it is explained.

  **New fixtures**, with `update`, review and expectations:
  - `archetype__big_note_drains_tray.json`;
  - `archetype__student_half_fare.json`;
  - `archetype__headphones_called_twice.json`;
  - `archetype__false_claimer_caught.json`;
  - `archetype__false_claimer_believed.json`;
  - `core__false_accusation.json`;
  - `archetype__group_payer_redirect.json`;
  - `archetype__chatty_row.json`;
  - `archetype__regular_customer_tip.json`;
  - `sample__line_gamaa_02_three_stars.json`, which plays sample `line_gamaa.02` to 3 stars.

**Checkpoint**: All 12 supported types work (US3 + US4).

---

## Phase 7: User Story 5 - The eight in-trip events (Priority: P5)

**Goal**: `bump`, `traffic`, `open_road`, `fare_increase`, `drop_me_here`, `payment_dispute`,
`change_request` and `roadside_pickup`, with skipping and the open choices that close by themselves
(spec US5).

**Independent Test**: A fixture per event. After a bump, a fare picked up within 3 s reaches the
tray, and one left on the floor is lost while its passenger is still owed.

### Tests for User Story 5 ⚠️ (write first, must fail)

- [x] T080 [P] [US5] Write `packages/trip_engine/test/events/bump_test.dart` (§8, §5.7):
  - only mid-hop tokens drop, and held ones stay;
  - `CollectDropped` within `trip_bump_collect_ms` works per kind: a fare arrives, change goes to
    the tray with the passenger still owed, and a return goes to the tray;
  - after the deadline the token is lost per kind: a lost fare never counts, but its balance
    stands; a lost return adds to overpaid; other money is gone;
  - `CollectDropped` on a token that isn't dropped is `no_effect`;
  - a dropped token at the end of the trip is lost.
- [x] T081 [P] [US5] Write `packages/trip_engine/test/events/schedule_shift_test.dart` (§9.1):
  - `traffic` +10 s moves the next station and every later one, sets `traffic_active` until the
    next station, and patience drains at 49 per step meanwhile;
  - `open_road` −10 s moves them sooner, but the next station is clamped to at least
    `trip_station_warning_ms` from now, and later stations move by the clamped amount;
  - shifts add up;
  - `ScheduleShifted` carries the applied delta;
  - events run on the unshifted trip clock.
- [x] T082 [P] [US5] Write `packages/trip_engine/test/events/fare_increase_test.dart` (§6.1–§6.2):
  - fares not yet sent rise by `amount_piasters`;
  - a listed passenger pays the authored amount, says `pays_old_fare`, and owes the difference,
    paid when tapped (`pays_rest`);
  - an unlisted passenger whose payment is short tops it up in the fewest pieces;
  - fares already sent don't change;
  - the unpaid remainder at the stop is missing from fares collected.
- [x] T083 [P] [US5] Write `packages/trip_engine/test/events/drop_me_here_test.dart`:
  - `deadline_ms` is `t + seconds × 1000`, or `t + trip_station_warning_ms` when `seconds` is absent;
  - everything that happens at a stop happens at the deadline: outcomes, tokens, choices, freed
    seats and boarding;
  - their station's warning no longer lists them.
- [x] T084 [P] [US5] Write `packages/trip_engine/test/events/dispute_test.dart` (§4.7, §8):
  - `DisputeRaised` with both passengers saying `dispute`;
  - the right answer (the named one sent, the other didn't): the other pays, the liar is caught;
  - a wrong answer, or both or neither having paid, is a false accusation;
  - `bad_argument` for a third passenger;
  - `no_choice` once resolved;
  - the dispute is dropped when either passenger gets off;
  - `ResolveDispute` is allowed while paused.
- [x] T085 [P] [US5] Write `packages/trip_engine/test/events/change_request_test.dart` (§4.8, §5.5,
  §14.4):
  - **agree:** the tray's pieces chosen by the search leave in a `break_out` token, the passenger
    sends a `break_in` with the note, and it reaches the tray, with `ChangeRequestCompleted`;
  - `cannot_make_change` leaves the request open;
  - **decline:** −`rep_change_request_declined`, with a `change_request_declined` speech;
  - no answer by their stop counts as declined, with the penalty;
  - a dropped `break_out` cancels the request with no penalty.
- [x] T086 [P] [US5] Write `packages/trip_engine/test/events/roadside_pickup_test.dart`:
  - listed `waiting` passengers board at the event if their seat is free, otherwise the moment it
    is freed (`pickup_due`), with `PassengerBoarded` and a `boards` speech;
  - an event naming a passenger who isn't aboard (or, for a pickup, isn't waiting) emits
    `EventSkipped` and does nothing.

### Implementation for User Story 5

- [x] T087 [US5] Implement `packages/trip_engine/lib/src/rules/authored_events.dart`: firing in
  definition order at `at_seconds × 1000`, `EventStarted`, the skip rule, and a dispatch per event.
  Wire phase 3 in `step.dart`.
- [x] T088 [US5] Implement in `packages/trip_engine/lib/src/rules/stations.dart` and
  `passengers.dart`:
  - `shift(δ)` with the open-road clamp (§9.1);
  - `traffic_active`, cleared at each station (§9.4);
  - the traffic drain of patience (§3 step 6).
- [x] T089 [US5] Implement `bump`, the `CollectDropped` handler, dropped-token deadlines (§3 step
  2.5), and losses per kind (§5.7). Add dropped tokens to the end settlement (§11).
- [x] T090 [US5] Implement `fare_increase` in `fares.dart` (§6.1–§6.2: the current fare,
  `old_fare_payers`, the top-up, `pays_old_fare`) and in `authored_events.dart`.
- [x] T091 [US5] Implement `drop_me_here`: `deadline_ms`, phase 8.1 in `step.dart`, and the warning
  exclusion in `stations.dart`.
- [x] T092 [US5] Implement disputes: the `payment_dispute` event, the `ResolveDispute` handler, and
  closing on getting off.
- [x] T093 [US5] Implement change requests: the `change_request` event, the `ResolveChangeRequest`
  handler, `break_out` and `break_in` delivery in `chain.dart`, and the automatic decline on getting
  off.
- [x] T094 [US5] Implement `roadside_pickup` and `pickup_due` boarding (§9.5). T080–T086 pass.
- [x] T095 [US5] Re-check the earlier fixtures, then author the US5 fixtures.

  **Re-check.** Run `check`. No earlier fixture should change: none of them has an authored event.
  Treat any difference as a bug until it is explained.

  **New fixtures**, with `update`, review and expectations:
  - `event__bump_collect_and_lose.json`;
  - `event__traffic.json`;
  - `event__open_road_clamped.json`;
  - `event__fare_increase.json`;
  - `event__drop_me_here.json`;
  - `event__payment_dispute.json`;
  - `event__change_request.json`;
  - `event__roadside_pickup.json`;
  - `event__skipped.json`;
  - `sample__line_hay_02_three_stars.json` and `sample__line_gamaa_01_three_stars.json`.

**Checkpoint**: All eight events work (US5).

---

## Phase 8: User Story 6 - Player aids, failing and reviving (Priority: P6)

**Goal**: «حد معاه فكة؟», the four boosters, undo, pause rules, failing, reviving once, abandoning,
and the story trip's no-fights rule (spec US6, clarifications 3 and 4).

**Independent Test**:

- A break on a 10000 note takes 1.5 s, keeps the tray total, and a third request is rejected.
- The change bag adds 50×2, 100×3 and 500×2.
- A revived trip goes on at 40, and a second revive is rejected.
- An abandoned trip ends with 0 stars and no earnings.

### Tests for User Story 6 ⚠️ (write first, must fail)

- [x] T096 [P] [US6] Write `packages/trip_engine/test/commands/request_break_test.dart` (§4.9,
  §14.1):
  - every table row arrives `trip_break_delay_ms` later, with `BreakRequested` and `BreakCompleted`;
  - the tray total is unchanged;
  - `tray_empty` for a note the tray lacks;
  - `break_limit` beyond `max_break_requests`, and for a note below `trip_break_min_piasters` or
    with no table row;
  - a break completes even while a choice is open.
- [x] T097 [P] [US6] Write `packages/trip_engine/test/commands/boosters_test.dart` (§4.11):
  - `change_bag` contents;
  - `wake_all` wakes every asleep or waking sleeper at once, awake for `trip_sleeper_awake_ms`;
  - `ledger_peek` sets `ledger_peek_until_ms`, `ledgerPeekActive` holds for
    `booster_ledger_peek_ms`, then `LedgerPeekEnded`;
  - `traffic_jam` shifts by `booster_traffic_jam_ms`. A fourth use is rejected with `booster_limit`
    at the default limit of 3, and a limit of 0 rejects the first;
  - `revive`, `refuel_full` and `fuel_unlimited_1h` are `bad_argument`;
  - every use is in `boosters_used`;
  - boosters are allowed while paused.
- [x] T098 [P] [US6] Write `packages/trip_engine/test/commands/undo_test.dart` (§4.4):
  - an undo within `trip_undo_window_ms` and before the first hop ends puts the pieces back in the
    hand, with `SendUndone`;
  - after the window, after the first hop, for a dropped token, or a second undo is
    `undo_unavailable`;
  - only the last send can be undone.
- [x] T099 [P] [US6] Write `packages/trip_engine/test/rules/fail_revive_test.dart` (§10, §4.12):
  - reputation ≤ 0 fails the trip at once: the clock stops, choices and tokens stay put, and
    `TripFailed` carries the breakdown, including short change;
  - a revive sets `rep_revive_to`, continues from the same point, and is recorded in the result;
  - a second revive is `not_revivable`;
  - a revive while running is `wrong_status`;
  - in a `no_fights_required` trip, the first fight or false accusation fails it with
    `revivable: false`;
  - a reputation failure there with no fight is revivable;
  - **failing while paused:** an answer given while paused that ends the trip (a false accusation in
    a no-fights trip, or a declined change request that takes reputation to 0) moves it from
    `paused` straight to `failed` at that `t_ms`, with no step in between, and `resume()` does
    nothing. Replaying the same log fails at the same `t_ms` with the same result;
  - a failed result has 0 stars and 0 earnings (clarification 3).
- [x] T100 [P] [US6] Write `packages/trip_engine/test/commands/abandon_pause_test.dart` (§4.13,
  FR-054):
  - abandoning works from running, paused and failed, giving `TripAbandoned` with the outcome
    `abandoned`, 0 stars and 0 earnings;
  - commands after the end are `wrong_status`;
  - while paused, only `ResolveClaim`, `ResolveDispute`, `ResolveChangeRequest`, `UseBooster` and
    `Abandon` are accepted.

### Implementation for User Story 6

- [x] T101 [US6] Implement `RequestBreak` (§4.9) and pending-break completion (§3 step 2.6) in
  `command_handlers.dart` and `step.dart`.
- [x] T102 [US6] Implement `UseBooster` (§4.11), with the ledger-peek timer (§3 step 2.4) and the
  `traffic_jam` limit (`booster_limit`, counted from `boosters_used`).
- [x] T103 [US6] Implement `UndoLastSend` (§4.4) and `last_send` upkeep in `SendHand`.
- [x] T104 [US6] Implement `Revive` and `Abandon` (§4.12–§4.13). In `reputation.dart`, the failure
  check (§10.2) gains the no-fights rule and runs while paused too, so a paused trip can go straight
  to `failed`. Then the result for failed and abandoned trips, and the paused allowlist in
  `command_handlers.dart`. T096–T100 pass.
- [x] T105 [US6] Re-check the earlier fixtures, then author the US6 fixtures.

  **Re-check.** Run `check`. No earlier fixture should change: the aids act only through commands
  earlier logs don't contain, no earlier trip requires no fights, and a replay never pauses. Treat
  any difference as a bug until it is explained.

  **New fixtures**, with `update`, review and expectations:
  - `command__request_break.json`, with a third request rejected and absent from the log;
  - `command__undo_last_send.json`;
  - `booster__change_bag.json`, `booster__wake_all.json`, `booster__ledger_peek.json` and
    `booster__traffic_jam.json` (with a fourth `traffic_jam` rejected and absent from the log);
  - `ending__failed.json`, `ending__revived.json`, `ending__abandoned.json` and
    `ending__story_fight_fails.json`;
  - `sample__line_hay_03_three_stars.json`, the story trip played to 3 stars with no fights.

**Checkpoint**: All aids and endings work (US6). Every command now exists.

---

## Phase 9: User Story 7 - Resume a trip after the app is killed (Priority: P7)

**Goal**: Rebuild a trip exactly from its replay record (spec US7, clarification 1, research R10).

**Independent Test**: Cut any recorded run at any step, rebuild it from its record, and continue
with the remaining commands. The result and fingerprint equal the uninterrupted run's. A failed or
paused trip comes back failed or paused.

### Tests for User Story 7 ⚠️ (write first, must fail)

- [x] T106 [P] [US7] Write `packages/trip_engine/test/replay/rebuild_test.dart` (SC-009):
  - for every fixture, at 10 evenly spaced cuts of its duration, `TripEngine.rebuild(record)` gives
    `state.toJson()` identical to the uninterrupted run at that step;
  - a rebuilt running trip is `paused` with no events delivered;
  - continuing with the remaining log gives the same result and fingerprint;
  - a failed trip comes back failed and still revivable if it was;
  - a finished trip comes back finished;
  - `replayRecord` round-trips through JSON;
  - refusals with `RebuildRefused`: a refused definition, decreasing `t_ms`, `t_ms` before the last
    command, and an entry rejected on replay.

### Implementation for User Story 7

- [x] T107 [US7] Implement `TripEngine.rebuild(ReplayRecord)` and the `replayRecord` getter in
  `packages/trip_engine/lib/src/engine.dart`. It replays commands at their times, steps to `t_ms`,
  discards the events, and pauses if running (contracts/replay-and-fixtures.md §4). T106 passes.

**Checkpoint**: A killed trip resumes exactly (US7). All stories are done.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: The cross-story guarantees (SC-002, SC-004, SC-005, SC-007), the documents, and the
final checks.

- [x] T108 [P] Write `packages/trip_engine/test/fuzz/fuzz_test.dart` (research R16):
  - 200 random command logs per sample trip, from a seeded `Xorshift32` (seed 20261020), choosing
    among the commands valid in each state;
  - no exceptions, and every money value is an `int`;
  - conservation after every step: the tray, the hand and money in transit or on the floor, plus
    money lost or kept by passengers, equal the initial tray plus every payment, break and booster;
  - every run replays to an identical result.

  Fix any rule bug it finds, with a new fixture for it.
- [x] T109 Create `packages/trip_engine/tool/stress_fixture.dart`. It writes
  `fixtures/parity/stress__longest_trip.json` deterministically:
  - `micro_old`, all 10 seats used, with boarding stations bringing it to 30 passengers;
  - 4 stations, the last at 600 s;
  - 10 `traffic` events of 60 s, the schema's maximum number of events;
  - params at their upper bounds, the one fixture that changes two: `booster_traffic_jam_ms` 60000
    and `booster_traffic_jam_max_per_trip` 5, with all 5 traffic jams used. The last station is
    then reached at 1,500 s, the longest trip (SC-004);
  - exactly 1,200 accepted commands.

  Then run `tool/fixtures.dart update` on it.
- [x] T110 Write `packages/trip_engine/test/perf/replay_budget_test.dart`:
  - its `duration_ms` is at least 1,500,000, so it really is the longest trip;
  - replaying `stress__longest_trip.json` takes < 1 s (SC-004);
  - rebuilding it at its last step takes < 1 s;
  - its canonical `command_log` is ≤ 65,536 bytes (SC-005);
  - the worst case holds too: 1,200 copies of the longest possible entry,
    `[1500000,"ResolveChangeRequest","p999",false]` (45 bytes), with separators, encode to
    ≤ 65,536 bytes.
- [x] T111 Write `packages/trip_engine/test/fixtures/fixture_coverage_test.dart` (SC-002). Across
  `fixtures/parity/`, assert:
  - every capabilities archetype appears in some definition;
  - every event appears;
  - all 13 commands appear in some log;
  - all four boosters are used;
  - expected results include 3, 2 and 1 stars, `failed`, `revived: true` and `abandoned`;
  - each of the 5 sample trips has a `sample__…` fixture with 3 stars.
- [x] T112 Run the coverage gate in `packages/trip_engine`. Add tests for any uncovered branch until
  `check_coverage.dart --min 90` passes. Don't exclude files.
- [x] T113 [P] Update `docs/architecture-mobile.md` (FR-074, research R18):
  - **§7.2–§7.9:**
    - the types match data-model.md (`TripResult` gains `outcome`, `rev`, `missed_stops`,
      `impatient`, `reputation`, `reputation_lost`, and mistakes use `amount_piasters`);
    - the commands are the 13 of FR-050, and the events follow engine-api.md;
    - money flow and scoring are summarized, with a link to `packages/trip_engine/RULES.md`;
  - **§10:** the checkpoint sentence becomes "the replay record is the checkpoint" (R10);
  - **§14.3:** the 20 keys and `trip_hints_mode_<line_id>`;
  - **§24.4:** marked resolved, with a link to research R10.
- [x] T114 [P] Update `CLAUDE.md`:
  - the "Project status" list adds `packages/trip_engine/` (M01), `fixtures/parity/` and
    `content/engine/capabilities.json`;
  - the "Mobile commands" section gains an engine table (pub get, format, analyze,
    test + coverage gate at 90, `tool/fixtures.dart` check, update and show);
  - the planned-architecture tree no longer calls `trip_engine` planned.
- [x] T115 [P] Add the M01 section to `docs/owner-actions.md`: no owner actions before or after
  merge. Note the approval in T117, already given on 2026-10-20. In `docs/delivery-plan.md`'s Progress, note under
  `004-m01-trip-engine` that mobile §24.4 and the hints hand-over are resolved. Tick it when the PR
  merges.
- [x] T116 Reconcile `packages/trip_engine/RULES.md` with the code. Every rule clarified during
  implementation is written there, with its fixture. `specs/004-m01-trip-engine/contracts/rules.md`
  keeps its pointer to the living copy.
- [x] T117 **Owner:** approve or reject the Complexity Tracking item in `plan.md` (constitution
  VIII: the backend copy of the 20 new tunables waits for B10's `LiveSetting`). Done: approved on
  2026-10-20 and recorded in `plan.md`. The follow-up that removes it is B10's "Handed over from
  M01" item in `docs/delivery-plan.md`.
- [x] T118 Run every check from [quickstart.md](./quickstart.md):
  - the engine's;
  - the scenarios 1–13;
  - `tools/content_kit` (`codegen --check`, `validate-source`, `golden`, ruff, mypy and pytest);
  - `apps/mobile` (`flutter analyze --fatal-infos`, `flutter test`, coverage ≥ 80%);
  - the backend (pytest, mypy, ruff, `makemigrations --check`, an empty OpenAPI diff).

  All pass.
- [x] T119 Review:
  - run the `code-reviewer` agent on the whole diff, and the `python-reviewer` on
    `tools/content_kit` and `backend`;
  - check every changed file against constitution I, II, III, VII, VIII and XIII;
  - fix every CRITICAL and HIGH finding.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies. T001 comes first, and T002–T006 are parallel.
- **Foundational (Phase 2)**: Depends on Setup, and blocks every story.
  - Content: T007 and T008 come first.
    - T009 needs T007.
    - T010 needs T002.
    - T011 needs T009.
    - T012 needs T008, T010 and T011.
    - T013 then T014, after T009 and T011.
  - Tunables: T015 then T016.
  - Engine:
    - T017 needs T016 (it reads the new `tunables.json`) and T009 (the new model field);
    - T018–T035 alternate test then implementation per module;
    - T036 needs T020–T034.
- **US1 (Phase 3)**: After Foundational.
- **US2 (Phase 4)**: After US1. Its fixtures play US1's rules, and the fixture tool serves every
  later story.
- **US3 (Phase 5)**: After US2 (fixture tool).
- **US4 (Phase 6)**: After US3, because `line_gamaa.02` has a sleeper and a hurried passenger, and
  claims build on taps.
- **US5 (Phase 7)**: After US4, because its sample fixtures use a hajja, a group and a sleeper.
- **US6 (Phase 8)**: After US5, because `traffic_jam` uses `shift` and `line_hay.03` has a chatty
  passenger.
- **US7 (Phase 9)**: After US2 at the earliest, but its SC-009 test runs over every fixture, so it
  is done after US6.
- **Polish (Phase 10)**: After every story. T111 needs all fixtures. T117 is done (approved on 2026-10-20).

### Within Each User Story

- Tests are written first and must fail, then implementation, then fixtures.
- `step.dart`, `command_handlers.dart` and `stations.dart` are edited by one task at a time.
- A story's fixtures come last, after its tests pass. From US3 on, that task first re-checks the
  earlier fixtures (Organization, "Earlier fixtures can change").

### Parallel Opportunities

- Setup: T002–T006.
- Foundational:
  - the content track (T007–T014), the tunables track (T015–T016) and the engine track
    (T017–T036, after T016 and T009) can run side by side;
  - within the engine track, every `[P]` test task is parallel, and so are T020, T022, T024 and
    T026 once their tests exist.
- Each story: all of its test tasks are `[P]`. In US1, T046 and T047 are parallel.
- Polish: T108, T113, T114 and T115.

---

## Parallel Example: User Story 1

```bash
# Write the US1 tests together (all different files):
Task: "Write packages/trip_engine/test/rules/chain_test.dart (§5.1–§5.5, §5.8)"
Task: "Write packages/trip_engine/test/rules/fares_test.dart (§6.1–§6.4, §11)"
Task: "Write packages/trip_engine/test/rules/change_test.dart (§6.5)"
Task: "Write packages/trip_engine/test/rules/stations_test.dart (§9.2–§9.5, §11)"
Task: "Write packages/trip_engine/test/rules/scoring_test.dart (§11)"
Task: "Write packages/trip_engine/test/rules/speech_test.dart (§12)"
Task: "Write packages/trip_engine/test/commands/hand_commands_test.dart"
Task: "Write packages/trip_engine/test/commands/tap_pay_test.dart"
Task: "Write packages/trip_engine/test/stories/us1_basic_trip_test.dart"

# Then the two independent modules together:
Task: "Implement lib/src/rules/speech.dart"
Task: "Implement lib/src/rules/fares.dart"
```

## Parallel Example: Foundational

```bash
# Three tracks at once:
Task: "T007–T014 content contract (schema field, capabilities packaging, V-T8–V-T11, sample, backend)"
Task: "T015–T016 app tunables (50 keys, TripHintsMode)"
Task: "T018 guards, T019 prng_test, T021 money_test, T025 capabilities_test (engine tests, no deps)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 (Setup), then Phase 2 (Foundational).
2. Phase 3 (US1): a basic trip plays end to end.
3. **Stop and validate**: run `us1_basic_trip_test.dart`. M02 could already drive a trip of regular
   passengers.

### Incremental Delivery

1. Add US2: exact replay plus the first fixtures, so B05 can begin mirroring.
2. Add US3 and US4: every MVP passenger type, so every sample trip's passengers work.
3. Add US5 and US6: the events, aids and endings, so every sample trip plays to 3 stars.
4. Add US7: resume.
5. Polish: coverage, fuzz, stress, docs, review. Then the one PR.

### Notes

- `[P]` tasks touch different files and have no unfinished dependencies.
- Never write a balancing number in `lib/`. A missing number is a missing `TripParams` field
  (constitution VIII).
- Never edit a generated file. Rerun `codegen` and `build_runner` instead.
- When a rule turns out ambiguous while coding, decide it in `packages/trip_engine/RULES.md` first,
  pin it with a fixture, then code it.
