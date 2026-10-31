# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**وصّل الأجرة** (code name `wassal`) is a casual puzzle game for mobile. You play a Cairo microbus driver who collects fares, hands back exact change before each stop, and saves up to furnish an apartment and get married. It launches on Android in Egypt first, then iOS and the Gulf. The repo is on GitHub (`origin` → `AhmedSaied94/wasal_ogra`, default branch `master`).

## Areas and their guides

Each area keeps what it has built, its commands, its notes and its guards in its own `CLAUDE.md`. Claude Code loads one when you open a file in its folder. **Before you run a command or change a file in an area, read its guide if it isn't loaded yet**: when you reach the area only through a shell or an MCP tool, and always as a subagent.

| Path | What it is | Guide |
| --- | --- | --- |
| `apps/mobile/` | The Flutter app: screens, the Flame trip scene, Rive art, drift storage; iOS builds on Codemagic (`codemagic.yaml`) | `apps/mobile/CLAUDE.md` |
| `backend/` | Django 5.2 + DRF: accounts, the ledger and sync, the content pipeline, the admin; Docker Compose; `contracts/openapi.yaml` | `backend/CLAUDE.md` |
| `packages/trip_engine/`, `fixtures/parity/` | The pure-Dart rules engine (rules reference: `RULES.md`); the parity fixtures both engines replay | `packages/trip_engine/CLAUDE.md` |
| `content/`, `tools/content_kit/`, `packages/content_models/` | The content schemas (the only definition of content), examples, sample pack and `content/engine/capabilities.json`; the `wassal-content` kit; the generated Dart models | `tools/content_kit/CLAUDE.md` |
| `tools/solver/` | The Python mirror of the engine, the solver, the difficulty score, the balancing report and the bench | `tools/solver/CLAUDE.md` |
| `tools/speckit-extensions/` | The source of the project's Spec Kit extensions, `feature-branch` and `review` | `tools/speckit-extensions/CLAUDE.md` |
| `docs/` | The design documents (below); `docs/runbooks/` for operating the servers | |
| `.github/workflows/` | CI (`backend.yml`; `mobile.yml`, which also builds and tests `content_models` and `trip_engine`), the executable source of truth for commands and path filters | |

`AGENTS.md` is a shorter guide for other agents. Features so far, by spec folder: 001 M03 app shell · 002 B01 backend skeleton · 003 B04 content pipeline · 004 M01 trip engine · 005 B05 solver and parity · 006 M04 content loader · 007 M05 local economy · 008 M02 trip screen · 008.5 M21 design refresh · 009 B02 accounts · 010 B03 ledger and sync · 011 M06 identity and sync · 012 M07 onboarding · 012.5 M22 animated scenes · 013 M08 Home and result · 014 M09 lines and vehicles · 015 M10 apartment and story. Each area's guide says what each built there.

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

The design (`docs/design/`, Style C «كرتون ناعم», adopted 2026-10-23) decides how screens look:

- **Its README's project overrides win over HANDOFF.md.** Animation stays on Rive (the constitution locks it), so `docs/design/lottie/` is a motion reference only. Identifiers come from the glossary, not the art names (`microbus_old` is `micro_old`; HANDOFF §5.3's passenger ids are skins, not archetypes).
- **Precedence.** For visual values: the artboard HTML, then HANDOFF.md, then the ux-spec. For behaviour: the constitution, then merged features' decisions, then HANDOFF.md, then the ux-spec. HANDOFF was written against the docs as they were before M01.
- **Which feature builds which artboard,** and which of HANDOFF §9.3's open questions it settles, is in `docs/delivery-plan.md` "Design sources". Each artboard gets a sample, a golden beside `docs/design/png/<Artboard>.png` and a layout test against `docs/design/boxes/<Artboard>.json` (HANDOFF §10, `docs/design/README.md` "Checking a screen against the design").

## Spec-kit workflow

- Spec-kit's default integration is **Claude Code** (`.specify/integration.json`). Run each step as a slash command: `/speckit-constitution` → `/speckit-specify` → `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-analyze` → `/speckit-implement` → `/speckit-review-implementation` (plus `/speckit-checklist`, `/speckit-converge` and `/speckit-taskstoissues`). The skill files live in `.claude/skills/speckit-<step>/SKILL.md` (older Codex and Copilot copies in `.agents/skills/` and `.github/skills/`).
- **opencode is installed too** (`.opencode/commands/speckit.<step>.md`), so `/speckit.implement` can run on another model there. Then run `/speckit-review-implementation` in Claude Code: it reviews the change set against the merge base layer by layer, runs the CI checks the change triggers, writes `specs/<feature>/reviews/round-<K>.md`, and appends a `Review fixes (round K)` phase to `tasks.md` for the next `/speckit.implement`. Its arguments: `base=<ref>`, `layers=<…>`, `no-run`, `fix`.
- The Specify CLI generates and hash-tracks the skill files, templates and scripts (`.specify/integrations/*.manifest.json`). Don't hand-edit them. To change the project's own extensions, see `tools/speckit-extensions/CLAUDE.md`.
- **Feature branches are handled by hooks** (`.specify/extensions.yml`):
  - The core `git` extension creates the feature branch during `/speckit-specify`.
  - The project's `feature-branch` extension runs before every later step. It checks out the branch of the active feature in `.specify/feature.json`; if that branch only exists on the remote, it tracks it, and if it exists nowhere, it creates it.
  - If git refuses the switch (local changes in the way), the step stops. Don't stash, reset or discard anything to get past it; ask the user.
- **The constitution** (`.specify/memory/constitution.md`, v1.6.0, ratified 2026-10-18, amended 2026-10-27) overrides conflicting guidance, including this file.
  - Every `plan.md` must pass its Constitution Check.
  - Principles I, II, III, IV and VI allow no exceptions: engine purity, integer money, parity, server authority, idempotency.
  - Any other deviation goes in the plan's Complexity Tracking and needs the owner's approval.
  - Change the constitution only through `/speckit-constitution`.
- **Tests are mandatory for every feature**, even though `tasks-template.md` says they are optional (constitution XIII).
  - Write tests first for engine rules, ledger/sync validators, entitlements, and purchase/webhook verification.
  - Coverage: ≥ 90% lines in `trip_engine`, ≥ 80% everywhere else.
- **Owner actions.** When `/speckit-implement` finishes a feature, add its section to `docs/owner-actions.md`. It lists everything only the owner can do (accounts, consoles, secrets, devices, live checks), split into before and after merge, each with its task ID and where its steps are. Keep the "Open now" table current, and tick items as the owner reports them done.
- **Area guides.** When a feature adds a command, file, guard or rule, put it in its area's `CLAUDE.md`, and only what crosses areas here.
- Every feature ID becomes one `specs/NNN-<short-name>/` folder (sequential numbering). Backend features are `B01`–`B15` (backend §20) and mobile features are `M01`–`M22` (mobile §23). The exceptions are `specs/008.5-m21-design-refresh/` (M21), inserted between 008 and 009, and `specs/012.5-m22-animated-scenes/` (M22), inserted between 012 and 013; `/speckit-specify` needs their names given explicitly (`docs/delivery-plan.md`, "Conventions"). Plan each B/M pair together so they share `contracts/` content.
- MVP joint order (backend §21): M03 + B01 → M01 + B04 → B05 (parity) → M04 + M05 → M02 → M21 (spec 008.5, the new design) → B02 + B03 + M06 → M07 → M22 (spec 012.5, the animated scenes) → M08–M10 → B10 + B07 + M11 → B06 + M12 → B08 + M13 → B09 + B11 + M14 → M15.
- `docs/delivery-plan.md` turns that order into spec numbers and branch names (`001-m03-app-shell` …). It also lists the open questions each feature must resolve and each step's "done when". Tick its Progress list when a feature merges.
- Helper scripts (run from the repo root): `.specify/scripts/bash/create-new-feature.sh --json --short-name <name> [--number N] "<description>"` (creates `specs/NNN-name/` and records it in the machine-local, gitignored `.specify/feature.json`), `check-prerequisites.sh --json [--require-spec|--require-tasks|--paths-only]`, `setup-plan.sh --json` and `setup-tasks.sh --json`.

## Invariants across the repo

These cut across both sides, and you need several docs to see them:

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
- **Content limits** from the product spec: no real brands, government bodies or clubs; no smoking, harassment or violence; no loot boxes.

## Project choices that override generic defaults

- **Mobile:** use Riverpod with `riverpod_generator`, not BLoC. Use **drift (SQLite)** for structured local data; Hive and Isar were explicitly rejected (mobile §25). Use `flutter_secure_storage` for tokens. Use `freezed` + `json_serializable`, `dio`, `go_router`. Pin Flutter with FVM (`.fvmrc`). The flavors are `dev`, `staging` and `prod`.
- **Backend:** Python 3.13 managed with **`uv`** (not pip). Plain Django + DRF, with Django admin as the content-authoring and live-ops tool (no Wagtail, no React). PostgreSQL 17, Redis/Valkey, Celery with `django-celery-beat`, `simplejwt`, `drf-spectacular`. CI runs `ruff`, `mypy` (django-stubs), `pytest` with real Postgres/Redis, `hypothesis`, `schemathesis` and the parity tests.
- **Deployment:** two Oracle Cloud Always Free A1 VMs (ARM64), production and staging, each running Docker Compose behind its own Caddy (details in `backend/CLAUDE.md`, operations in `docs/runbooks/`). Build images for `linux/arm64`. iOS builds run on Codemagic, because the dev machine is Linux.
