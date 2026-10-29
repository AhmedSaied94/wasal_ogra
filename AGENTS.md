# AGENTS.md

`wassal` (وصّل الأجرة) is a Flutter mobile game with a Django backend, a pure-Dart rules engine,
a Python mirror/solver, and content packs. Work is spec-driven.

Read first:
- `CLAUDE.md` — detailed feature map and full command tables (the best orientation).
- `.specify/memory/constitution.md` — overrides all other guidance.
- `.specify/feature.json` — the active Spec Kit feature; its folder is under `specs/NNN-*`.
- `README.md`'s "Status: design and planning" line is stale; the app and backend exist.

## Layout and ownership

- `apps/mobile/` — Flutter app: UI, Flame trip scene, Rive art, drift storage.
- `packages/trip_engine/` — pure Dart trip rules. No Flutter imports. `RULES.md` is the reference.
- `packages/content_models/` — generated Dart models. Never hand-edit.
- `backend/` — Django 5.2 + DRF. Business logic in `apps/<name>/services/`, thin views.
- `tools/content_kit/` — schemas, validation, codegen, pack bundling (`wassal-content`).
- `tools/solver/` — Python mirror of the engine plus solver (`wassal-solver`).
- `content/schemas/` — the only content definition. `fixtures/parity/` — Dart/Python parity fixtures.
- `docs/` — product/UX/architecture docs; `docs/design/` is the visual source of truth.
- `.github/workflows/` — executable source of truth for CI commands and path filters.

## Setup order that matters

- Flutter is pinned with FVM (`.fvmrc`, 3.47.7). Always use `fvm`, never bare `flutter`/`dart`.
- Build `packages/content_models` first; the app and `trip_engine` import its gitignored parts.
- Backend Python is pinned (`backend/.python-version`) and managed with `uv`, never pip.
- Backend tests need real PostgreSQL and Valkey: start the dev stack first.
- Rive's Linux library is needed before `flutter test`; Android's before the first Android build.
- Do not add a Podfile for iOS; every plugin is a Swift Package on purpose.
- Staging/prod builds fail until `apps/mobile/assets/content/release/` holds a promoted pack.

## Core commands

Backend (from `backend/`):

```bash
cp .env.example .env && uv sync
docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait
uv run ruff check . && uv run ruff format --check . && uv run mypy .
uv run pytest -n 4 --cov --cov-fail-under=80
uv run manage.py makemigrations --check --dry-run
uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn
```

Mobile (from `apps/mobile/`):

```bash
cd ../../packages/content_models && fvm dart pub get && fvm dart run build_runner build -d
cd ../../apps/mobile
fvm flutter pub get
fvm dart run build_runner build -d
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm flutter analyze --fatal-infos
fvm dart run rive_native:setup --verbose --clean --platform linux
fvm flutter test --coverage --exclude-tags backend
fvm dart run tool/check_coverage.dart --min 80
```

- Focused test: `fvm flutter test test/path/to_test.dart` or `uv run pytest path::test_name`.
- Backend-tagged app tests need the dev stack plus `WASSAL_E2E_API=http://localhost:8000`.
- Goldens are Linux-generated. If CI disagrees, run the mobile workflow with
  `update_goldens: true` and commit its PNGs; CI is the reference.
- Design tokens: `fvm dart run tool/design/gen_tokens.dart`; design assets:
  `fvm dart run tool/design/sync_assets.dart`.
- Drift table changes: bump `schemaVersion`, then `fvm dart run drift_dev make-migrations`; commit
  the schema and generated migration tests.
- Builds need a flavor: `fvm flutter build apk --flavor dev --debug`.

Engine (from `packages/trip_engine/`, after content models are built):

```bash
fvm dart pub get
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm dart analyze --fatal-infos
fvm dart test --coverage=coverage
fvm dart run coverage:format_coverage --lcov --report-on=lib --in=coverage --out=coverage/lcov.info
fvm dart run ../../apps/mobile/tool/check_coverage.dart --min 90 --lcov coverage/lcov.info
fvm dart run tool/fixtures.dart check
```

The engine coverage gate is 90% (80% everywhere else). After an intentional rule change, update
affected fixtures with `fvm dart run tool/fixtures.dart update <file>` and review the result.

Content/solver (from their own directories):

```bash
# tools/content_kit
uv sync && uv run wassal-content codegen --check
uv run wassal-content validate-source ../../content/examples/sample
uv run wassal-content bundle dev --check --out ../../apps/mobile/assets/content/dev

# tools/solver
uv sync && uv run wassal-solver parity ../../fixtures/parity
```

After changing `tools/content_kit` or `tools/solver`, run
`uv sync --reinstall-package wassal-content --reinstall-package wassal-solver` in `backend/`.

## Generated code and contracts

- `content/schemas/` is authoritative. Schema edits require `wassal-content codegen`, then
  `build_runner` in `packages/content_models`. Codegen output is committed; `*.freezed.dart` and
  `*.g.dart` are gitignored. Never edit generated files by hand.
- `contracts/openapi.yaml` is committed and must match the code; regenerate it with `spectacular`.
- `apps/mobile/lib/l10n/generated/` and `*.g.dart` are gitignored; run `pub get` + `build_runner`
  after a fresh checkout.
- Content changes that alter a published schema need a major bump and `schema-diff`; see
  `CLAUDE.md` "Content commands".

## Invariants that fail tests or break the game

- Money is integer piasters. No `double`/`num` money and no REAL columns; use `JENEHAT`, `BONAT`,
  `FUEL` integers. BONAT never converts to JENEHAT.
- One rules engine, mirrored twice. A rule change updates `packages/trip_engine/RULES.md`, both
  engines, and `fixtures/parity/` in the same change.
- Player-visible Arabic lives in `lib/l10n/app_ar.arb`, not in `lib/`. Comments may be Arabic.
- Style values come from `docs/design/tokens.json` via theme tokens. No raw colors, radii, font
  sizes, shadows, durations, or curves outside `lib/core/theme/tokens/` (named motion constants in
  `trip_motion.dart` are the only exception).
- Rive is the locked motion stack (`wassal.riv`, `wassal_scenes.riv`); do not add Lottie. Static
  SVGs are the fallback.
- No ads and no text drawn in the Flame canvas during a running trip.
- Only the owning drift store writes its tables; economy changes go through `EconomyService`.
- Backend balance changes go only through `apps.economy.services.ledger` (`apply_entry`,
  `flush_entries`, `apply_now`). Never assign `jenehat`/`bonat` directly.
- New `/v1` endpoints need player auth, `X-Client-Version`/`X-Platform`, and per-player throttling
  unless explicitly public. Errors use the `{"error": {"code", "message", "details"}}` envelope.
- Server decides value (BONAT, purchases, entitlements). The client is optimistic only for
  JENEHAT/progress.
- Migrations are expand/contract; UUIDv7 primary keys.
- Never commit secrets or generated credentials.

## Workflow

- Spec Kit steps are OpenCode commands in `.opencode/commands/speckit.*` (for example
  `/speckit.specify`; `.claude/skills/speckit-*` is the Claude mirror). The feature-branch hook
  checks out the active feature branch before every step. If git refuses the switch, stop and ask;
  do not stash, reset, or discard changes.
- Each feature gets `specs/NNN-<name>/` and a matching branch. Backend features are `B01`–`B15`,
  mobile features `M01`–`M22`; the delivery order is in `docs/delivery-plan.md`.
- Tests are mandatory even though the Spec Kit template calls them optional. Coverage gates:
  90% lines in `trip_engine`, 80% everywhere else.
- Once per auth/economy feature, run its property test at 10,000 examples:
  `HYPOTHESIS_PROFILE=thorough uv run pytest apps/{accounts,economy}/tests/test_properties.py`.
- When `/speckit-implement` finishes, add the feature's section to `docs/owner-actions.md`.
