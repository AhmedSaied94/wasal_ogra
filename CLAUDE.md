# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

**وصّل الأجرة** (code name `wassal`) is a casual puzzle game for mobile. You play a Cairo microbus driver who collects fares, hands back exact change before each stop, and saves up to furnish an apartment and get married. It launches on Android in Egypt first, then iOS and the Gulf.

The repo is on GitHub (`origin` → `AhmedSaied94/wasal_ogra`, default branch `master`). Right now it has:

- `apps/mobile/`: the Flutter app shell from **M03** (`specs/001-m03-app-shell/`): routing, theme tokens, RTL, digit styles, tunables and CI. Screens are still placeholders. Since **M04** (`specs/006-m04-content-loader/`) it loads content packs: the one bundled in the build, newer ones it downloads in the background, and the switch to them at launch or on arrival at Home (since M07, also before a new player's first trip). Since **M05** (`specs/007-m05-local-economy/`) it keeps its economy offline in drift: the append-only operation log and its projection (wallet, fuel, inventory, ownership, progress), one service that validates and applies every change, fuel, trusted time, and what M06's sync will call. Since **M02** (`specs/008-m02-trip-screen/`) it plays trips: the trip screen (the Flame scene with Rive passengers, the Flutter overlays, HUD and dashboard), `TripController` stepping the engine and charging the economy, the trip's replay record in drift and the resume at launch, the failure card with the BONAT revive, بلية's hints, and the playtest tools on dev and staging. Since **M21** (`specs/008.5-m21-design-refresh/`) all of it is drawn in the «كرتون ناعم» design: the generated tokens and shared components, the bottom nav, sheets and dialogs, the `Loading` boot screen, the trip screen's zones, and every person, vehicle and UI animation from the owner's `wassal.riv`, with static art as the fallback. Since **M07** (`specs/012-m07-onboarding/`) it has the first session: the opening scene, the Name card, the five coached tutorial trips with بلية's coach, the سلمى scene, المعلم's fuel lesson, the name's re-ask on Home, the trip screen's compact profile for short screens, and the playtest «Onboarding» card.
- `backend/`: the Django skeleton from **B01** (`specs/002-b01-backend-skeleton/`): settings that refuse bad configuration, health endpoints, the error envelope, throttling, the Celery heartbeat, Docker Compose for dev, staging and prod, and the staff-only admin. Plus the content app from **B04** (`specs/003-b04-content-pipeline/`, `backend/apps/content/`): authoring in the admin, zip import and export, builds and validation, publishing on staging, promotion to production, the manifest endpoint and the pack files the edge serves. Plus the accounts from **B02** (`specs/009-b02-accounts-auth/`, `backend/apps/accounts/`): anonymous players by install id, sessions with rotating refresh tokens, Google linking and its conflicts, and the read-only player admin. Plus the economy from **B03** (`specs/010-b03-ledger-sync/`, `backend/apps/economy/` and `backend/apps/progress/`): the append-only ledger and its wallets, `GET /v1/bootstrap`, `GET /v1/state` and `POST /v1/sync` with its eleven operation types, fuel on the server's clock, the gifts and story rewards, display names and the name filter, flags of odd play, and the staff's balance adjustments.
- `content/`, `tools/content_kit/` and `packages/content_models/`: the content schemas from **B04** (`specs/003-b04-content-pipeline/`), with examples, a sample pack, and the server (Pydantic) and app (freezed) models generated from them.
- `packages/trip_engine/`: the pure-Dart rules engine from **M01** (`specs/004-m01-trip-engine/`): every trip rule, the 13 commands, replay and rebuild, and the fixture tool. Its living rules reference is `packages/trip_engine/RULES.md`.
- `tools/solver/`: the Python solver from **B05** (`specs/005-b05-solver-parity/`): a mirror of the trip rules, the solver (an idealized player that must earn 3 stars), the difficulty score, the balancing report and the bench. The backend runs it as the content pipeline's solver stage and the admin's trip preview.
- `fixtures/parity/`: the parity fixtures from **M01** and **B05**, `{definition, seed, params, command_log, expected_result}`, which both the Dart engine and the Python mirror replay in CI.
- `content/engine/capabilities.json`: what the engine supports (archetypes, events and their parameters, speech slots, change-request notes). The content kit validates trips against it.
- `docs/`: the source-of-truth design documents (see below).
- `docs/design/`: the visual design, Style C «كرتون ناعم» (adopted 2026-10-23): `HANDOFF.md`, `tokens.json`, the artboards as HTML, PNGs and measured boxes, icons, illustrations, and Lottie files as a motion reference. Feature **008.5** (M21) moved what was built to it; every feature after it builds its screens from it, with a sample, a golden and a layout test per artboard (`docs/design/README.md` "Checking a screen against the design").
- `.specify/`, `.claude/skills/` (plus older Codex and Copilot copies in `.agents/skills/` and `.github/skills/`): a [spec-kit](https://github.com/github/spec-kit) v1.2.1 scaffold for spec-driven development, with a ratified constitution.
- `tools/speckit-extensions/feature-branch/`: source of the project's own Spec Kit extension (see "Spec-kit workflow").
- `.github/workflows/mobile.yml`: mobile CI (it also builds and tests `packages/content_models` and `packages/trip_engine`).
- `codemagic.yaml`: the iOS build on Codemagic. Its one workflow, `ios-dev-unsigned`, builds the unsigned dev IPA (`docs/runbooks/ios-test-build.md`).

## Backend commands

Python is pinned by `backend/.python-version` and managed with uv (never pip). Run everything from `backend/`. CI (`.github/workflows/backend.yml`) runs the same commands. `docker compose …` below is short for `docker compose -f docker/compose.yml -f docker/compose.dev.yml`.

| Purpose | Command (in `backend`) |
| --- | --- |
| First setup | `cp .env.example .env && uv sync` |
| Start the local stack (migrates first) | `docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait` |
| Stop it (keep data) / wipe it | `docker compose … down` / `docker compose … down -v` |
| Migrate | `uv run manage.py migrate` |
| Lint and format check | `uv run ruff check . && uv run ruff format --check .` |
| Type check | `uv run mypy .` |
| Tests + coverage gate (on 4 workers, as CI; at most 7) | `uv run pytest -n 4 --cov --cov-fail-under=80` |
| Missing-migration check | `uv run manage.py makemigrations --check --dry-run` |
| Regenerate the API contract | `uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn` |
| Create a staff user / issue TOTP | `uv run manage.py create_staff <name> [--group content_author\|player_support]` / `uv run manage.py staff_totp <name>` |
| Print a new token signing key entry (`kid:key`) | `uv run manage.py auth_signing_key` (rotation: `docs/runbooks/auth-keys.md`) |
| The auth property test at 10,000 examples (once per feature that touches auth) | `HYPOTHESIS_PROFILE=thorough uv run pytest apps/accounts/tests/test_properties.py` |
| The economy property test at 10,000 examples (once per feature that touches the economy) | `HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py` |
| Write the missing rules index rows of published packs (a deploy step after B03; worker container on a host) | `uv run manage.py content_index --rebuild` |
| Check every wallet against its ledger (exit 1 on a mismatch) | `uv run manage.py economy_check` (a mismatch: `docs/runbooks/economy.md`) |
| Import / export content (a `content/source` layout or zip) | `uv run manage.py content_import <dir-or-zip> --actor <staff>` / `uv run manage.py content_export <dir> [--version N] --actor <staff>` |
| Build a pack, or only print its checksums | `uv run manage.py content_build --actor <staff>` / `uv run manage.py content_build --actor <staff> --dry-run [--version N]` |
| Rewrite missing pack files, hash the present ones | `uv run manage.py content_files sync --verify` |
| Deploy, roll back, restore | See `docs/runbooks/deploy-and-rollback.md` and `docs/runbooks/restore.md` |

- The API is on <http://localhost:8000> (the Android emulator reaches it as `10.0.2.2:8000`), the admin on <http://localhost:8001/admin/>.
- Tests need the stack's PostgreSQL and Valkey: they run against the real services, never mocks (constitution XIII). pytest reads only the `TEST_*` URLs from `backend/.env`.
- If port 5432 or 6379 is taken on your machine, export `WASSAL_DEV_PG_PORT` or `WASSAL_DEV_VALKEY_PORT` before `docker compose up`, and use the same port in the URLs in `backend/.env`.
- Every value comes from the environment (`specs/002-b01-backend-skeleton/contracts/environment.md`). Outside `dev` and `test`, a missing, empty or `change-me` secret stops the process at startup.
- B04 adds the `CONTENT_*` variables (`specs/003-b04-content-pipeline/contracts/environment.md`): `CONTENT_ROLE` (`source` on dev and staging, `target` on prod), `CONTENT_PACKS_DIR`, `CONTENT_PACKS_PUBLIC_URL`, `CONTENT_VERSION_FLOOR_URL` (staging: production's packs URL), `CONTENT_PROMOTION_SOURCE_URL` (prod: staging's packs URL), `CONTENT_SOLVER_STAGE` (`solver`, the real stage, by default on staging and prod; `stand_in` in dev and test only), `CONTENT_MANIFEST_CACHE_SECONDS` and `CONTENT_HTTP_TIMEOUT_SECONDS`. The settings check refuses a role or URL in the wrong environment.
- B02 adds the `AUTH_*`, `GOOGLE_*` and four `THROTTLE_*` variables (`specs/009-b02-accounts-auth/contracts/environment.md`). `AUTH_SIGNING_KEYS` is required everywhere, and `GOOGLE_OAUTH_CLIENT_IDS` outside dev and test.
- B03 adds the `ECONOMY_*` and `SYNC_*` variables, `CONTENT_INDEX_KEEP` and `THROTTLE_SYNC_RATE` (`specs/010-b03-ledger-sync/contracts/environment.md`). All have defaults; the four fuel numbers must equal `apps/mobile/assets/config/tunables.json` (a test checks), and the server-only ones have no Remote Config key until B10.
- **Every balance change goes through `apps.economy.services.ledger`** (`apply_entry`, `flush_entries`, `apply_now`), which writes the `LedgerEntry` and the `Wallet` together. Nothing else assigns `jenehat` or `bonat` (an AST scan test fails on it), and nothing edits or deletes a ledger row. Sync operations are handlers in `apps/economy/services/ops/`, registered with `sync.register`; they read and change the batch's in-memory state, never the ORM (a test checks).
- **Every new `/v1` endpoint needs a player token and the two headers (`X-Client-Version`, `X-Platform`), and is limited per player**, unless its view opts out explicitly (B02 FR-032–FR-035). Those are the REST framework defaults (`PlayerAuthentication`, `IsAuthenticated` + `ClientHeaders`, the player throttle). The public ones today are `/healthz`, `/readyz`, the manifest and `POST /v1/auth/anonymous` and `/refresh`. A failed auth check raises `apps.common.errors.ApiError`, never DRF's `AuthenticationFailed`.
- The content commands that act for a person need `--actor <staff>` and make the admin's permission checks. Only the worker mounts the packs directory, so on a host run `content_files` in the worker container. Publishing and promoting: `docs/runbooks/content-publishing.md`.

## Mobile commands

Flutter is pinned with FVM (`.fvmrc` at the repo root). Run everything through `fvm`, from `apps/mobile/`. CI (`.github/workflows/mobile.yml`) runs the same commands, in this order:

| Purpose | Command (in `apps/mobile`) |
| --- | --- |
| Install deps and generate l10n | `fvm flutter pub get` |
| Code generation (Riverpod, drift) | `fvm dart run build_runner build -d` |
| Format check | `fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` |
| Analyze | `fvm flutter analyze --fatal-infos` |
| All tests and goldens (the `backend`-tagged ones need the dev stack) | `fvm flutter test --coverage --exclude-tags backend` |
| Coverage gate (≥ 80%) | `fvm dart run tool/check_coverage.dart --min 80` |
| The sync against the dev stack (`sync-e2e`: stack up, seeded once, then the `backend`-tagged tests) | `uv run manage.py shell < ../apps/mobile/test/backend/seed_backend.py` (in `backend`), then `WASSAL_E2E_API=http://localhost:8000 fvm flutter test --tags backend test/backend` |
| The first session end to end (headless; there is no Linux runner) | `fvm flutter test integration_test/first_session_test.dart -d flutter-tester` |
| Update goldens (Linux only) | `fvm flutter test --update-goldens test/goldens` |
| Run the dev variant | `fvm flutter run --flavor dev` |
| Build the dev APK | `fvm flutter build apk --flavor dev --debug` |
| Cold start on a device | `tool/perf/cold_start.sh <package> <runs>` (see `specs/001-m03-app-shell/quickstart.md`) |
| After a table change: bump `schemaVersion`, export the schema, generate its step and tests | `fvm dart run drift_dev make-migrations` |
| Schema tests only | `fvm flutter test test/drift` |
| Rive's Linux library, before `flutter test` (`--clean` is required with a restored pub cache) | `fvm dart run rive_native:setup --verbose --clean --platform linux` |
| Rive's Android library, before the first Android build | `fvm dart run rive_native:setup --platform android` |
| Rewrite the trip's stand-in sounds (CI checks the committed files match) | `python3 tool/sfx/generate.py` |
| A trip's frame rate, response and memory on a device | `tool/perf/trip_fps.sh <package> <trip_id>` (see `specs/008-m02-trip-screen/quickstart.md`) |
| Regenerate the design tokens from `docs/design/tokens.json` | `fvm dart run tool/design/gen_tokens.dart` |
| Copy the design's icons and illustrations into `assets/` | `fvm dart run tool/design/sync_assets.dart` |
| The Rive tests only (after `rive_native:setup`) | `fvm flutter test --tags rive` |
| Rewrite the Rive goldens after a new export | `fvm flutter test --update-goldens test/features/trip/rive_art_goldens_test.dart` |

- Every build needs `--flavor dev|staging|prod`; the app refuses to start without one.
- iOS builds run only on Codemagic (`codemagic.yaml` at the repo root), because the dev machine is Linux.
  - The flavors are the Xcode schemes `dev`, `staging` and `prod`, with `Debug-`, `Release-` and `Profile-<flavor>` configurations. Each scheme sets its bundle ID and `APP_DISPLAY_NAME`.
  - Every iOS plugin is a Swift Package, so there is no Podfile. Don't add one: it makes `flutter build ios` run `pod install`, and the build fails.
  - Until there is a paid Apple Developer account, the only workflow is the unsigned dev IPA, sideloaded with a free Apple ID: `docs/runbooks/ios-test-build.md`.
- Generated files (`*.g.dart`, `lib/l10n/generated/`) are gitignored. Run `pub get` and `build_runner` after a fresh checkout.
- The app depends on `packages/content_models`, whose generated parts are gitignored too. After a fresh checkout, build it first (see "Content commands").
- A dev build calls the local stack over plain HTTP, which only the dev flavor allows (constitution 1.2.0). On a phone or an emulator, run `adb reverse tcp:8000 tcp:8000` and the default `http://localhost:8000` works. `--dart-define=WASSAL_DEV_API_BASE=<url>` points a dev build elsewhere.
- Staging and prod builds bundle the pack production promoted last, so they fail at `checkBundledPack` until `apps/mobile/assets/content/release/` holds one. Committing it is a step of `docs/runbooks/content-publishing.md` §3.
- The app database is `<app support>/db/wassal.sqlite`, opened during startup. Device backup and phone-to-phone transfer leave it out (`res/xml/data_extraction_rules.xml`, `backup_rules.xml`). Only `lib/core/economy/drift_economy_store.dart` writes the economy's tables, and only through `EconomyService`. Only `lib/features/trip/data/drift_trip_records.dart` writes the trip's (`trip_record`, `trip_record_command`, `trip_intent`: the replay record of the trip in progress and its outbox of economy calls). Only `lib/core/account/drift_account_store.dart` writes `account` and `server_info` (M06: the player, and the last bootstrap's cached blocks). The economy store also writes `player_state` (M07: the driver's name and the tutorial grant, part of the projection), and only `lib/features/onboarding/data/drift_first_session_store.dart` writes `first_session` (M07: the opening, the scenes seen, the fuel lesson, the step reached).
- A table change needs a new `schemaVersion` and its step in `AppDatabase.upgradeSteps`, and `make-migrations` adds its schema to `drift_schemas/app/` and its tests to `test/drift/`. Commit both. `test/drift/app/schema_test.dart` checks that a new file has the current version's exported schema, and `make-migrations`' `test/drift/app/migration_test.dart` checks every step between versions (v2, M02, added the trip's three tables).
- Every person, vehicle and UI animation comes from one Rive file, `assets/rive/wassal.riv`, made to `specs/008.5-m21-design-refresh/contracts/rive-characters.md` (artboards, state machines, view models; `Person` draws all 24 people by its `look` number). Its editable source is in the owner's Rive account. Boot decodes it in the step `art` and checks it against the contract; an artboard that fails falls back to the design's static SVGs alone, and the debug panel lists the problems. After exporting a new version, run the Rive golden command above, review the sheets and commit them with it. The tests tagged `rive` need the file and Rive's Linux library.
- SQLite comes from the `sqlite3` package's build hook, which downloads a prebuilt library on the first build (network needed once). Don't add `sqlite3_flutter_libs`.
- Goldens are generated on Linux. If CI disagrees with them, run the workflow by hand with `update_goldens: true` and commit the PNGs it uploads; CI is then the reference.
- M07's tests play the release draft's five tutorial trips from `apps/mobile/test/fixtures/tutorial/`, copied by hand from `content/drafts/core-r1/pack/` in the `content-core-r1` worktree and layered over the sample by `test/helpers/tutorial_content.dart` (its README says what and when). The sample's own trips and parity fixtures don't change. When the draft's `line_hay`, trips 01–05 or the sleeper's pools change, copy them again and rerun those tests.
- `flutter test` also runs the repo guards: no Arabic outside comments in `lib/` (player text goes in `lib/l10n/app_ar.arb`), no `double`/`num` money, no raw colors, radii, font sizes, shadows, animation durations or curves outside `lib/core/theme/tokens/` (`trip_motion.dart`'s named constants aside), nothing of the retired «ستيكر الميكروباص» design, no Material ink or stock buttons, the design tokens generated from `docs/design/tokens.json`, the design's assets copied as `tool/design/sync_assets.dart` writes them, the palette contrast checks, the tunables registry, no Flutter or plugin import in a `domain/` folder (each folder lists what it may import: in `lib/core/economy/domain/`, only `content_models`, `trip_engine` and the content and economy domains), plain HTTP only in the dev source set, bundled packs that agree with their records, no REAL column, the economy's tables written only by its store with `ledger_ops` rows changing only in their sync columns (and the trip's only by theirs), no `sqlite3_flutter_libs`, the backup exclusion (the database and the secure storage files, with no `<include>`), the economy's sync calls (`EconomySync`) only from `lib/core/sync/`, `lib/core/account/` and `lib/core/economy/`, no token, session or install id in logs or the preference store, no text drawn in the trip's Flame canvas, no ad SDK under `lib/features/trip/`, and a rider's money (`PassengerState.balance`, `.paidIn`) read only by the trip's projection and the tutorial coach.

### Trip engine commands

Run these in `packages/trip_engine`, after `packages/content_models` has been built (see "Content commands"). CI runs them in the mobile `packages` job.

| Purpose | Command (in `packages/trip_engine`) |
| --- | --- |
| Install deps | `fvm dart pub get` |
| Format check | `fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` |
| Analyze | `fvm dart analyze --fatal-infos` |
| Tests (rules, fixtures, replay, fuzz, perf budget) | `fvm dart test --coverage=coverage` |
| Coverage gate (≥ 90%) | `fvm dart run coverage:format_coverage --lcov --report-on=lib --in=coverage --out=coverage/lcov.info && fvm dart run ../../apps/mobile/tool/check_coverage.dart --min 90 --lcov coverage/lcov.info` |
| Replay every fixture, exit 1 on a difference | `fvm dart run tool/fixtures.dart check` |
| Recompute a fixture's `expected_result` (then review the diff) | `fvm dart run tool/fixtures.dart update <file>...` |
| Print a fixture's event sequence | `fvm dart run tool/fixtures.dart show <file>` |
| Regenerate the longest-trip stress fixture | `fvm dart run tool/stress_fixture.dart` |

- A rule change edits `packages/trip_engine/RULES.md`, both engines (this package and `tools/solver/src/wassal_solver/engine/`) and the affected fixtures in the same PR (constitution III). `update` rewrites only `expected_result`; review every changed fixture before committing.
- Every fixture needs an entry in `test/fixtures/expectations/`, which pins what the fixture is about. The fixtures test fails on a fixture without one.
- The engine takes every balancing number as `TripParams`, built from `apps/mobile/assets/config/tunables.json` with `TripParams.fromTunables`. It has no defaults of its own.

## Content commands

The schemas in `content/schemas/` are the only definition of content. `tools/content_kit` (the uv project `wassal-content`, Python pinned by its `.python-version`) generates both model sets from them and validates content. CI runs the same commands in the backend workflow's `content-kit` job and in the mobile `packages` job.

| Purpose | Command |
| --- | --- |
| First setup (in `tools/content_kit`) | `uv sync` |
| Regenerate after a schema change | `uv run wassal-content codegen` |
| Generated files match the schemas (CI) | `uv run wassal-content codegen --check` |
| Validate one document | `uv run wassal-content validate <file> [--part trip]` |
| Validate a content layout | `uv run wassal-content validate-source ../../content/examples/sample` |
| Breaking schema changes | `uv run wassal-content schema-diff --base origin/master` |
| Sample pack checksums | `uv run wassal-content golden` (check) / `golden --update` (rewrite, then review) |
| Bundle the sample into dev builds / check it (CI) | `uv run wassal-content bundle dev --out ../../apps/mobile/assets/content/dev` / `bundle dev --check --out …` |
| Bundle production's promoted pack into staging and prod / check it offline (CI) | `uv run wassal-content bundle release --packs-url https://api.193-122-74-125.sslip.io/packs/ --out ../../apps/mobile/assets/content/release` / `bundle release --check --out …` |
| Lint, types, tests | `uv run ruff check . && uv run ruff format --check . && uv run mypy . && uv run pytest --cov --cov-fail-under=80` |
| App models: build (in `packages/content_models`) | `fvm dart pub get && fvm dart run build_runner build -d` |
| App models: analyze and test | `fvm dart analyze --fatal-infos && fvm dart test --coverage=coverage` |
| App models: coverage gate | `fvm dart run coverage:format_coverage --lcov --report-on=lib --in=coverage --out=coverage/lcov.info && fvm dart run ../../apps/mobile/tool/check_coverage.dart --min 80 --lcov coverage/lcov.info` |

- After editing a schema: run `codegen`, then `build_runner` in `packages/content_models`, and commit the schema with `_generated.py`, `src/wassal_content/schemas/*.json` and `lib/src/generated/*.dart`. The `*.freezed.dart` and `*.g.dart` parts are gitignored.
- Never edit a generated file by hand: `codegen --check` fails on any difference.
- The schemas follow a restricted profile (research R3 of B04): closed objects, integers only, no `null`, no `default`, no combinators, and every object and enum named in `$defs`. `codegen` refuses anything else.
- `content/source/` holds only exports of packs promoted to production. Until its `pack.json` exists, schemas may change freely; after that, a breaking change needs a major bump in `content/schemas/schema-set.json`.

## Solver commands

`tools/solver` is the uv project `wassal-solver` (Python pinned by its `.python-version`). Run everything from `tools/solver`. CI runs the same commands in the backend workflow's `solver` job.

| Purpose | Command (in `tools/solver`) |
| --- | --- |
| First setup | `uv sync` |
| Lint, format check, types | `uv run ruff check . && uv run ruff format --check . && uv run mypy .` |
| Tests + both coverage gates (80%, and 90% for the mirror) | `uv run pytest -n 4 --cov --cov-fail-under=80 && uv run coverage report --include='*/wassal_solver/engine/*' --fail-under=90` |
| Time and memory budgets (skipped under coverage) | `uv run pytest tests/perf -q` |
| Copy the app's tunables / check the copy | `uv run wassal-solver sync` / `uv run wassal-solver sync --check` |
| Replay every parity fixture through the mirror | `uv run wassal-solver parity` |
| Write a solver fixture from a trip's 3-star run | `uv run wassal-solver fixture <trip.json>... [--out DIR]` |
| Solve a trip or a layout | `uv run wassal-solver solve <trip.json \| layout> [--trip ID] [--json] [--reaction-ms N]` |
| Re-solve every trip of a layout | `uv run wassal-solver check-source <layout> [--bands error\|warning]` |
| Balancing report | `uv run wassal-solver report <layout \| pack.json.gz> [--csv FILE]` |
| Bench corpus and its digest | `uv run wassal-solver bench --digest` |

- The solver's settings (reaction and tap times, the effort budget, the safety cap, the score's table) are in `src/wassal_solver/data/settings.json`. Changing them changes `settings_version`.
- Any change to the package's code or data changes `solver_fingerprint`, so the backend solves every trip again instead of reusing a stale result.
- `fixture` never overwrites a file, and Python never rewrites an `expected_result`: only Dart's `tool/fixtures.dart update` does.
- After a `tools/solver` change, run `uv sync --reinstall-package wassal-solver` in `backend/` (and rebuild the dev image) so the backend uses it.

## Design documents (read before planning or coding)

| File | Language | Role |
| --- | --- | --- |
| `docs/product-spec.md` | Egyptian Arabic | Product and business: mechanics, economy, monetization, roadmap (the *what/why*) |
| `docs/ux-spec.md` | Egyptian Arabic | Every screen, the visual system, minimum sizes, navigation (the *what/why*) |
| `docs/architecture-backend.md` | English | Django backend (the *how*) |
| `docs/architecture-mobile.md` | English | Flutter client (the *how*) |
| `docs/design/HANDOFF.md` | English | The visual design: tokens, components, the trip screen's geometry, characters, motion, navigation, and every screen (§11). Read `docs/design/README.md` first. |

The two architecture docs are paired, so read both:

- **§3 "Shared Contract Glossary" is duplicated word for word in both.** It defines every identifier: currencies, denominations, `booster_id`, `ad_placement`, `product_id`, `line_id`/`trip_id`/`archetype`/`chapter_id`, and the API conventions. If you change it, change both copies.
- The Engineering Principles share the same numbering in both docs (backend §17, mobile §18), and the constitution's principles I–XIII use the same numbers. If you add, remove or rename a principle, update both docs and the constitution together.
- Open questions are tagged **NEEDS CLARIFICATION** and collected in backend §22 and mobile §24. Don't guess the answers. Resolve them in the feature's `research.md` or ask.

The design (`docs/design/`) decides how screens look:

- **Its README's project overrides win over HANDOFF.md.** Animation stays on Rive (the constitution locks it), so `docs/design/lottie/` is a motion reference only. Identifiers come from the glossary, not the art names (`microbus_old` is `micro_old`; HANDOFF §5.3's passenger ids are skins, not archetypes).
- **Precedence.** For visual values: the artboard HTML, then HANDOFF.md, then the ux-spec. For behaviour: the constitution, then merged features' decisions, then HANDOFF.md, then the ux-spec. HANDOFF was written against the docs as they were before M01.
- **Which feature builds which artboard,** and which of HANDOFF §9.3's open questions it settles, is in `docs/delivery-plan.md` "Design sources". Each artboard gets a golden beside `docs/design/png/<Artboard>.png` and a layout test against `docs/design/boxes/<Artboard>.json` (HANDOFF §10).

## Spec-kit workflow

- Spec-kit's integration is **Claude Code** (`.specify/integration.json`). Run each step as a slash command: `/speckit-constitution` → `/speckit-specify` → `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-analyze` → `/speckit-implement` (plus `/speckit-checklist`, `/speckit-converge` and `/speckit-taskstoissues`). The skill files live in `.claude/skills/speckit-<step>/SKILL.md`.
- The Specify CLI generates and hash-tracks these skill files, templates and scripts (`.specify/integrations/*.manifest.json`). Don't hand-edit them.
- **Feature branches are handled by hooks** (`.specify/extensions.yml`):
  - The core `git` extension creates the feature branch during `/speckit-specify`.
  - The project's `feature-branch` extension runs before every later step (clarify, plan, tasks, analyze, checklist, implement, converge, taskstoissues). It checks out the branch of the active feature in `.specify/feature.json`; if that branch only exists on the remote, it tracks it, and if it exists nowhere, it creates it.
  - If git refuses the switch (local changes in the way), the step stops. Don't stash, reset or discard anything to get past it; ask the user.
- To change the `feature-branch` extension, edit `tools/speckit-extensions/feature-branch/` and reinstall it with `specify extension add --dev tools/speckit-extensions/feature-branch --force`. Never edit the installed copy under `.specify/extensions/`.
- **The constitution** (`.specify/memory/constitution.md`, v1.6.0, ratified 2026-10-18, amended 2026-10-27) overrides conflicting guidance, including this file.
  - Every `plan.md` must pass its Constitution Check.
  - Principles I, II, III, IV and VI allow no exceptions: engine purity, integer money, parity, server authority, idempotency.
  - Any other deviation goes in the plan's Complexity Tracking and needs the owner's approval.
  - Change the constitution only through `/speckit-constitution`.
- **Tests are mandatory for every feature**, even though `tasks-template.md` says they are optional (constitution XIII).
  - Write tests first for engine rules, ledger/sync validators, entitlements, and purchase/webhook verification.
  - Coverage: ≥ 90% lines in `trip_engine`, ≥ 80% everywhere else.
- **Owner actions.** When `/speckit-implement` finishes a feature, add its section to `docs/owner-actions.md`. It lists everything only the owner can do (accounts, consoles, secrets, devices, live checks), split into before and after merge, each with its task ID and where its steps are. Keep the "Open now" table current, and tick items as the owner reports them done.
- Every feature ID becomes one `specs/NNN-<short-name>/` folder (sequential numbering). Backend features are `B01`–`B15` (backend §20) and mobile features are `M01`–`M22` (mobile §23). The exceptions are `specs/008.5-m21-design-refresh/` (M21), inserted between 008 and 009, and `specs/012.5-m22-animated-scenes/` (M22), inserted between 012 and 013; `/speckit-specify` needs their names given explicitly (`docs/delivery-plan.md`, "Conventions"). Plan each B/M pair together so they share `contracts/` content.
- MVP joint order (backend §21): M03 + B01 → M01 + B04 → B05 (parity) → M04 + M05 → M02 → M21 (spec 008.5, the new design) → B02 + B03 + M06 → M07 → M22 (spec 012.5, the animated scenes) → M08–M10 → B10 + B07 + M11 → B06 + M12 → B08 + M13 → B09 + B11 + M14 → M15.
- `docs/delivery-plan.md` turns that order into spec numbers and branch names (`001-m03-app-shell` …). It also lists the open questions each feature must resolve and each step's "done when". Tick its Progress list when a feature merges.
- Helper scripts (run from the repo root):
  - `.specify/scripts/bash/create-new-feature.sh --json --short-name <name> [--number N] "<description>"` creates `specs/NNN-name/` and records it in `.specify/feature.json`. That file is machine-local and gitignored.
  - `.specify/scripts/bash/check-prerequisites.sh --json [--require-spec|--require-tasks|--paths-only]`
  - `.specify/scripts/bash/setup-plan.sh --json` and `setup-tasks.sh --json`

## Architecture (big picture)

A monorepo laid out as described in backend §5 and mobile §5:

```text
apps/mobile/            Flutter app: screens + Flame trip scene + Rive characters
packages/trip_engine/   Pure-Dart gameplay engine (no Flutter imports)
packages/content_models/ Dart models GENERATED from content/schemas
tools/content_kit/      Python `wassal-content`: codegen, validation, canonical pack files
backend/                Django 5.2 + DRF; apps/<name>/{models,services/,api/,tasks,admin}
tools/solver/           Python `wassal_solver`: mirror of trip_engine + solver, score, report
contracts/openapi.yaml  Generated by drf-spectacular, committed, consumed by mobile
content/schemas/        JSON Schema 2020-12 for packs (trip, line, item, catalog, …)
content/examples/       valid/invalid documents, the sample pack and its golden checksums
fixtures/parity/        {definition, seed, params, command_log, expected_result}
docs/design/            The visual design: HANDOFF.md, tokens.json, artboards, PNGs, boxes, icons, art
```

These invariants cut across both sides, and you need several docs to see them:

- **One rules engine, mirrored twice.** All trip rules live in `packages/trip_engine` (exact rules in its `RULES.md`), with a Python mirror in `tools/solver`. Neither the UI nor the server re-implements them. The engine is deterministic: a 33 ms fixed step, a `xorshift32` PRNG, and integer piasters. Replaying `(definition, seed, params, command_log)` reproduces the same `TripResult`. Any rule change must ship with updated `fixtures/parity/*.json` that pass in **both** Dart and pytest, or CI fails.
- **Integer money only.** Trip cash is in piasters (1 EGP = 100, smallest coin 50). `JENEHAT`, `BONAT` and `FUEL` are integers. Floats are forbidden for money. **BONAT can never be converted into JENEHAT.**
- **Server authority for value.** BONAT, purchases, entitlements and subscriptions are decided by the backend. The client is optimistic only for JENEHAT and progress, and the server checks both against bounds such as `max_earnings_jenehat` and catalog prices for the declared `content_version`.
- **Offline-first sync** (backend §7, mobile §12). The client records ops (`trip_start`, `trip_result`, `spend_bonat`, …), each with a UUIDv7 `client_txn_id`, and sends them through `POST /v1/sync`. The server runs one transaction per batch with `SELECT … FOR UPDATE` on `Wallet`, makes ops idempotent through `ProcessedOp`, and returns a per-op accepted/rejected result. Soft anomalies are **accepted and recorded as `PlayerFlag`**, not rejected, so honest offline play is never punished.
- **Ledger.** Every currency change is an append-only `LedgerEntry`, and `Wallet` is the materialized balance. Every mutation goes through `economy.services.apply_entry()`. Writing to `Wallet` directly is forbidden, and a test scans for it. A property test checks that `wallet == sum(ledger)`.
- **Content is data in immutable versioned packs.** Packs are authored in Django admin, validated against the schema, then solver-validated (every trip must be 3-star solvable), then built as gzipped JSON plus a sha256 and published under a new version. A `trip_id` is permanent; rule changes bump `rev`. Pydantic and Dart models are generated from `content/schemas`, and hand-edited models are not allowed.
- **No Arabic text in code.** The engine emits `speech_key`s, and the Arabic lines live in speech pools in content packs. Server-side player text (push templates, offers) is stored as data. There is no runtime LLM.
- **Tunables.** Every balancing number has a Firebase Remote Config key with a bundled default (mobile §14.3). The server keeps its copies in `liveops.LiveSetting`.
- **No ads during a running trip.** No ad SDK call may run while `TripState.status == running`. The two in-trip rewarded placements (`traffic_jam`, `trip_revive`) either pause the engine first or come after the trip fails. Interstitials appear only between trips.
- **Purchases are acknowledged on the store only after the server confirms.** The client acknowledges a store transaction only once `/v1/purchases/verify` returns `acknowledge: true`.

### Backend conventions (backend §5, §17.1)

- Business logic goes in `apps/<app>/services/`. Views and serializers stay thin.
- Use the error envelope `{"error": {"code", "message", "details"}}` with the code table in §6.2.
- UUIDv7 primary keys. Migrations are expand/contract, so the previous release keeps working during a deploy.
- External calls (stores, FCM) run in Celery with timeouts and retries. The exception is purchase verification, which is synchronous with a 10 s timeout and recovers through RTDN.
- The committed `contracts/openapi.yaml` must match the code. CI diffs it.

### Mobile conventions (mobile §6, §10, §11)

- Layers: Presentation → Application (Riverpod) → Domain (`trip_engine`, economy rules) ← Infrastructure.
- The domain layer never imports Flutter, Flame, Firebase or any plugin.
- Every plugin sits behind an interface (`AdsGateway`, `PurchaseGateway`, `ApiClient`, `ConfigSource`, `AnalyticsSink`).
- `TripController` owns the `TripEngine`. Widgets send commands and never mutate state directly.
- Bubbles and the HUD are Flutter widgets drawn over the Flame scene, not text drawn in the canvas.

## Project choices that override generic defaults

- **Mobile:** use Riverpod with `riverpod_generator`, not BLoC. Use **drift (SQLite)** for structured local data; Hive and Isar were explicitly rejected (mobile §25). Use `flutter_secure_storage` for tokens. Use `freezed` + `json_serializable`, `dio`, `go_router`. Pin Flutter with FVM (`.fvmrc`). The flavors are `dev`, `staging` and `prod`.
- **Backend:** Python 3.13 managed with **`uv`** (not pip). Plain Django + DRF, with Django admin as the content-authoring and live-ops tool (no Wagtail, no React). PostgreSQL 17, Redis/Valkey, Celery with `django-celery-beat`, `simplejwt`, `drf-spectacular`. CI runs `ruff`, `mypy` (django-stubs), `pytest` with real Postgres/Redis, `hypothesis`, `schemathesis` and the parity tests.
- **Deployment target:** two Oracle Cloud Always Free A1 VMs (ARM64) in `me-jeddah-1`, one per environment: production and staging, each 1 OCPU / 6 GB with its own reserved IP, running Docker Compose behind its own host-network Caddy. `provision.sh --env` fixes each VM's environment. Each VM has its own WireGuard network (`10.66.0.1` prod, `10.67.0.1` staging); its admin is reachable only over it, and so is SSH. Backups run on production, and on staging for its authored content (B04), each into its own Backblaze B2 buckets; the monthly restore drill runs on staging. Build images for `linux/arm64`. Operating it is in `docs/runbooks/`. iOS builds run on Codemagic, because the dev machine is Linux.

## UI rules (from `docs/ux-spec.md` and `docs/design/`)

- Arabic **RTL on every screen**. Arabic-Indic digits (١٢٣) by default, with a setting for Western digits. Goldens are tested in RTL with both digit settings.
- Reference frame is portrait 390×844 pt. Gameplay touch targets sit in the bottom third, for one-handed play. The exceptions are the scene's own items (passengers, dropped money, a passenger's answer buttons), the pause button in the top bar and, on internal builds, the debug icon beside it (constitution XI).
- The minimum sizes are acceptance criteria, not suggestions:
  - touch targets ≥ 44×44 pt
  - any text ≥ 12 pt
  - bubble text ≥ 15 pt
  - back-row faces ≥ 50 pt
  - near-row faces ≥ 80 pt
  - money tokens ≥ 40×24 pt
- The visual style is Style C, «كرتون ناعم» (`docs/design/`, adopted 2026-10-23). It has a pale sky ground (`#E8F4FB`), white cards with no outlines, and depth from solid "lip" shadows that a press pushes down. The fonts are Marhey and Readex Pro. It replaced «ستيكر الميكروباص» (yellow ground, thick ink borders, Lalezar and Baloo Bhaijaan 2), which the app kept until 008.5. Every value comes from `docs/design/tokens.json` through the theme tokens; screens use the shared components of HANDOFF §3, never restyled raw widgets.
- Every station has both a color and a letter, so color-blind players can tell them apart. Text contrast meets WCAG 2.1 AA (constitution XI).
- Reduced-motion turns off the shake and the bubble pop.
- Content limits from the product spec: no real brands, government bodies or clubs; no smoking, harassment or violence; no loot boxes.
