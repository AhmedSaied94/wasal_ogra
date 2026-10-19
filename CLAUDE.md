# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

**وصّل الأجرة** (code name `wassal`) is a casual puzzle game for mobile. You play a Cairo microbus driver who collects fares, hands back exact change before each stop, and saves up to furnish an apartment and get married. It launches on Android in Egypt first, then iOS and the Gulf.

The repo is on GitHub (`origin` → `AhmedSaied94/wasal_ogra`, default branch `master`). Right now it has:

- `apps/mobile/`: the Flutter app shell from **M03** (`specs/001-m03-app-shell/`): routing, theme tokens, RTL, digit styles, tunables and CI. Screens are still placeholders.
- `backend/`: the Django skeleton from **B01** (`specs/002-b01-backend-skeleton/`): settings that refuse bad configuration, health endpoints, the error envelope, throttling, the Celery heartbeat, Docker Compose for dev, staging and prod, and the staff-only admin.
- `docs/`: the source-of-truth design documents (see below).
- `.specify/`, `.claude/skills/` (plus older Codex and Copilot copies in `.agents/skills/` and `.github/skills/`): a [spec-kit](https://github.com/github/spec-kit) v1.2.1 scaffold for spec-driven development, with a ratified constitution.
- `tools/speckit-extensions/feature-branch/`: source of the project's own Spec Kit extension (see "Spec-kit workflow").
- `.github/workflows/mobile.yml`: mobile CI.

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
| Tests + coverage gate | `uv run pytest --cov --cov-fail-under=80` |
| Missing-migration check | `uv run manage.py makemigrations --check --dry-run` |
| Regenerate the API contract | `uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn` |
| Create a staff user / issue TOTP | `uv run manage.py create_staff <name>` / `uv run manage.py staff_totp <name>` |
| Deploy, roll back, restore | See `docs/runbooks/deploy-and-rollback.md` and `docs/runbooks/restore.md` |

- The API is on <http://localhost:8000> (the Android emulator reaches it as `10.0.2.2:8000`), the admin on <http://localhost:8001/admin/>.
- Tests need the stack's PostgreSQL and Valkey: they run against the real services, never mocks (constitution XIII). pytest reads only the `TEST_*` URLs from `backend/.env`.
- If port 5432 or 6379 is taken on your machine, export `WASSAL_DEV_PG_PORT` or `WASSAL_DEV_VALKEY_PORT` before `docker compose up`, and use the same port in the URLs in `backend/.env`.
- Every value comes from the environment (`specs/002-b01-backend-skeleton/contracts/environment.md`). Outside `dev` and `test`, a missing, empty or `change-me` secret stops the process at startup.

## Mobile commands

Flutter is pinned with FVM (`.fvmrc` at the repo root). Run everything through `fvm`, from `apps/mobile/`. CI (`.github/workflows/mobile.yml`) runs the same commands, in this order:

| Purpose | Command (in `apps/mobile`) |
| --- | --- |
| Install deps and generate l10n | `fvm flutter pub get` |
| Code generation (Riverpod) | `fvm dart run build_runner build -d` |
| Format check | `fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` |
| Analyze | `fvm flutter analyze --fatal-infos` |
| All tests and goldens | `fvm flutter test --coverage` |
| Coverage gate (≥ 80%) | `fvm dart run tool/check_coverage.dart --min 80` |
| Update goldens (Linux only) | `fvm flutter test --update-goldens test/goldens` |
| Run the dev variant | `fvm flutter run --flavor dev` |
| Build the dev APK | `fvm flutter build apk --flavor dev --debug` |
| Cold start on a device | `tool/perf/cold_start.sh <package> <runs>` (see `specs/001-m03-app-shell/quickstart.md`) |

- Every build needs `--flavor dev|staging|prod`; the app refuses to start without one.
- Generated files (`*.g.dart`, `lib/l10n/generated/`) are gitignored. Run `pub get` and `build_runner` after a fresh checkout.
- Goldens are generated on Linux. If CI disagrees with them, run the workflow by hand with `update_goldens: true` and commit the PNGs it uploads; CI is then the reference.
- `flutter test` also runs the repo guards: no Arabic outside comments in `lib/` (player text goes in `lib/l10n/app_ar.arb`), no `double`/`num` money, no raw colors or radii outside `lib/core/theme/tokens/`, the palette contrast checks and the tunables registry.

## Design documents (read before planning or coding)

| File | Language | Role |
| --- | --- | --- |
| `docs/product-spec.md` | Egyptian Arabic | Product and business: mechanics, economy, monetization, roadmap (the *what/why*) |
| `docs/ux-spec.md` | Egyptian Arabic | Every screen, the visual system, minimum sizes, navigation (the *what/why*) |
| `docs/architecture-backend.md` | English | Django backend (the *how*) |
| `docs/architecture-mobile.md` | English | Flutter client (the *how*) |

The two architecture docs are paired, so read both:

- **§3 "Shared Contract Glossary" is duplicated word for word in both.** It defines every identifier: currencies, denominations, `booster_id`, `ad_placement`, `product_id`, `line_id`/`trip_id`/`archetype`/`chapter_id`, and the API conventions. If you change it, change both copies.
- The Engineering Principles share the same numbering in both docs (backend §17, mobile §18), and the constitution's principles I–XIII use the same numbers. If you add, remove or rename a principle, update both docs and the constitution together.
- Open questions are tagged **NEEDS CLARIFICATION** and collected in backend §22 and mobile §24. Don't guess the answers. Resolve them in the feature's `research.md` or ask.

## Spec-kit workflow

- Spec-kit's integration is **Claude Code** (`.specify/integration.json`). Run each step as a slash command: `/speckit-constitution` → `/speckit-specify` → `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-analyze` → `/speckit-implement` (plus `/speckit-checklist`, `/speckit-converge` and `/speckit-taskstoissues`). The skill files live in `.claude/skills/speckit-<step>/SKILL.md`.
- The Specify CLI generates and hash-tracks these skill files, templates and scripts (`.specify/integrations/*.manifest.json`). Don't hand-edit them.
- **Feature branches are handled by hooks** (`.specify/extensions.yml`):
  - The core `git` extension creates the feature branch during `/speckit-specify`.
  - The project's `feature-branch` extension runs before every later step (clarify, plan, tasks, analyze, checklist, implement, converge, taskstoissues). It checks out the branch of the active feature in `.specify/feature.json`; if that branch only exists on the remote, it tracks it, and if it exists nowhere, it creates it.
  - If git refuses the switch (local changes in the way), the step stops. Don't stash, reset or discard anything to get past it; ask the user.
- To change the `feature-branch` extension, edit `tools/speckit-extensions/feature-branch/` and reinstall it with `specify extension add --dev tools/speckit-extensions/feature-branch --force`. Never edit the installed copy under `.specify/extensions/`.
- **The constitution** (`.specify/memory/constitution.md`, v1.0.0, ratified 2026-10-18) overrides conflicting guidance, including this file.
  - Every `plan.md` must pass its Constitution Check.
  - Principles I, II, III, IV and VI allow no exceptions: engine purity, integer money, parity, server authority, idempotency.
  - Any other deviation goes in the plan's Complexity Tracking and needs the owner's approval.
  - Change the constitution only through `/speckit-constitution`.
- **Tests are mandatory for every feature**, even though `tasks-template.md` says they are optional (constitution XIII).
  - Write tests first for engine rules, ledger/sync validators, entitlements, and purchase/webhook verification.
  - Coverage: ≥ 90% lines in `trip_engine`, ≥ 80% everywhere else.
- **Owner actions.** When `/speckit-implement` finishes a feature, add its section to `docs/owner-actions.md`. It lists everything only the owner can do (accounts, consoles, secrets, devices, live checks), split into before and after merge, each with its task ID and where its steps are. Keep the "Open now" table current, and tick items as the owner reports them done.
- Every feature ID becomes one `specs/NNN-<short-name>/` folder (sequential numbering). Backend features are `B01`–`B15` (backend §20) and mobile features are `M01`–`M20` (mobile §23). Plan each B/M pair together so they share `contracts/` content.
- MVP joint order (backend §21): M03 + B01 → M01 + B04 → B05 (parity) → M04 + M05 → M02 → B02 + B03 + M06 → M07–M10 → B10 + B07 + M11 → B06 + M12 → B08 + M13 → B09 + B11 + M14 → M15.
- `docs/delivery-plan.md` turns that order into spec numbers and branch names (`001-m03-app-shell` …). It also lists the open questions each feature must resolve and each step's "done when". Tick its Progress list when a feature merges.
- Helper scripts (run from the repo root):
  - `.specify/scripts/bash/create-new-feature.sh --json --short-name <name> [--number N] "<description>"` creates `specs/NNN-name/` and records it in `.specify/feature.json`. That file is machine-local and gitignored.
  - `.specify/scripts/bash/check-prerequisites.sh --json [--require-spec|--require-tasks|--paths-only]`
  - `.specify/scripts/bash/setup-plan.sh --json` and `setup-tasks.sh --json`

## Planned architecture (big picture)

A monorepo laid out as described in backend §5 and mobile §5:

```text
apps/mobile/            Flutter app: screens + Flame trip scene + Rive characters
packages/trip_engine/   Pure-Dart gameplay engine (no Flutter imports)
packages/content_models/ Dart models GENERATED from content/schemas
backend/                Django 5.2 + DRF; apps/<name>/{models,services/,api/,tasks,admin}
tools/solver/           Python `wassal_solver`: mirror of trip_engine + solver/generator
contracts/openapi.yaml  Generated by drf-spectacular, committed, consumed by mobile
content/schemas/        JSON Schema 2020-12 for packs (trip, line, item, catalog, …)
fixtures/parity/        {definition, seed, params, command_log, expected_result}
```

These invariants cut across both sides, and you need several docs to see them:

- **One rules engine, mirrored twice.** All trip rules live in `packages/trip_engine`, with a Python mirror in `tools/solver`. Neither the UI nor the server re-implements them. The engine is deterministic: a 33 ms fixed step, a `xorshift32` PRNG, and integer piasters. Replaying `(definition, seed, params, command_log)` reproduces the same `TripResult`. Any rule change must ship with updated `fixtures/parity/*.json` that pass in **both** Dart and pytest, or CI fails.
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
- **Deployment target:** one Oracle Cloud Always Free A1 VM (ARM64, 2 OCPU / 12 GB) in `me-jeddah-1`, running Docker Compose (staging and prod) behind a host-network Caddy. The admin is reachable only over WireGuard, and so is SSH. Backups go to Backblaze B2. Build images for `linux/arm64`. Operating it is in `docs/runbooks/`. iOS builds run on Codemagic, because the dev machine is Linux.

## UI rules (from `docs/ux-spec.md`)

- Arabic **RTL on every screen**. Arabic-Indic digits (١٢٣) by default, with a setting for Western digits. Goldens are tested in RTL with both digit settings.
- Reference frame is portrait 390×844 pt. Gameplay touch targets sit in the bottom third, for one-handed play.
- The minimum sizes are acceptance criteria, not suggestions:
  - touch targets ≥ 44×44 pt
  - any text ≥ 12 pt
  - bubble text ≥ 15 pt
  - back-row faces ≥ 50 pt
  - near-row faces ≥ 80 pt
  - money tokens ≥ 40×24 pt
- The visual style is called «ستيكر الميكروباص»: a taxi-yellow base (`#FFD23F`), thick ink borders (`#1D1A2B`) and hard shadows. The full palette is in the ux-spec «الألوان» section and should become theme tokens.
- Every station has both a color and a letter, so color-blind players can tell them apart. Text contrast meets WCAG 2.1 AA (constitution XI).
- Reduced-motion turns off the shake and the bubble pop.
- Content limits from the product spec: no real brands, government bodies or clubs; no smoking, harassment or violence; no loot boxes.
