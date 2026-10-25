# Wassal El-Ogra (وصّل الأجرة) Constitution

Non-negotiable engineering rules for the `wassal` monorepo: the Flutter client, the Django backend,
the shared trip engine and its Python mirror, and the content pipeline. Principles I–XIII carry the
same numbers as the Engineering Principles in `docs/architecture-backend.md` §17 and
`docs/architecture-mobile.md` §18.

## Core Principles

### I. Engine Purity (NON-NEGOTIABLE)

- Every rule that decides a trip's outcome (fares, tray, hand, passing chain, passenger archetypes,
  stations, events, reputation, stars, earnings) MUST live only in `packages/trip_engine` and its
  Python mirror in `tools/solver` (`wassal_solver`).
- The UI MUST NOT re-implement or patch trip rules. Widgets send commands to `TripController`, which
  owns the `TripEngine`; they render state and events and never mutate state directly.
- The server MUST NOT re-implement trip rules. It validates bounds (Principle IV) or replays a run
  through the solver.
- The domain layer (`trip_engine`, economy rules, progression rules) MUST NOT import Flutter, Flame,
  Firebase or any plugin. It depends only on interfaces it defines (`Clock`, `Random`,
  `ContentSource`).
- The engine MUST be deterministic: a 33 ms fixed logic step, a seeded `xorshift32` PRNG, integer
  arithmetic, and no wall clock, platform RNG or I/O. Replaying
  `(definition, seed, params, command_log)` MUST produce the same `TripResult`.

**Rationale:** One deterministic rules engine is what makes replay, solver validation,
daily-challenge verification and share clips possible. A second copy of the rules would drift.

### II. Integer Money (NON-NEGOTIABLE)

- Trip cash (fares, change, tray, tips) MUST be integer piasters (1 EGP = 100; smallest coin 50).
  The only valid denominations are those in Shared Contract Glossary §3.2.
- `JENEHAT`, `BONAT` and `FUEL` MUST be integers.
- Only integer types may hold a money or currency value, in every layer: Dart, Python, JSON
  payloads, database columns, analytics parameters and test fixtures. Floating-point money is
  forbidden.
- The piaster → `JENEHAT` conversion (whole pounds, rounded down, capped by
  `max_earnings_jenehat`) MUST happen in the engine only. Formatting for display (pounds,
  half-pounds, digit style) happens only at the presentation edge.

**Rationale:** Half-pound coins make float rounding errors visible to players and break parity
between Dart and Python.

### III. Parity or It Didn't Happen (NON-NEGOTIABLE)

- Any change to engine rules, scoring, default parameters or PRNG use MUST ship in the same change
  with updated `fixtures/parity/*.json` files of the form
  `{definition, seed, params, command_log, expected_result}`.
- Every parity fixture MUST pass in both the Dart suite (`packages/trip_engine`) and pytest
  (`tools/solver`). CI MUST fail on any mismatch, and a change with failing parity MUST NOT merge.
  - Fixtures may exist before `tools/solver` does, since the delivery plan has M01 write the first
    ones and B05 build the mirror. Until the feature that creates `tools/solver` merges, every
    fixture MUST pass the Dart suite, and its `definition` MUST pass the content-kit checks (the
    trip schema and the engine's content rules). CI MUST fail on any Dart mismatch.
  - The feature that creates `tools/solver` MUST reproduce every existing fixture before it merges.
    From then on, both suites are required.
- A change that is not meant to affect outcomes MUST still pass the existing fixtures unchanged.

**Rationale:** The solver validates content and verifies competitive results. If it disagrees with
the client, players get trips that cannot be solved or results that get rejected.

### IV. Server Authority for Value (NON-NEGOTIABLE)

- The backend decides BONAT balances, real-money purchases, entitlements and subscriptions. The
  client treats them as a read-only cache. It may spend BONAT optimistically up to the last known
  balance and MUST roll back when the server rejects the op.
- The client may be optimistic only for JENEHAT and progress. The server MUST validate those against
  the trip's `max_earnings_jenehat`, the catalog prices for the declared `content_version`, and
  unlock order.
- Store transactions MUST be acknowledged or completed only after `POST /v1/purchases/verify`
  returns `acknowledge: true`. Subscription status MUST come from server entitlements, never from
  local state alone.
- Ad rewards that grant BONAT (`morning_piggy`) MUST be verified on the server through AdMob SSV.
- BONAT MUST NEVER be converted into JENEHAT, and JENEHAT MUST NEVER be sold for real money. No
  code path may do either.
- Every currency change MUST be an append-only `LedgerEntry` written through
  `economy.services.apply_entry()`, with `Wallet` updated as the materialized balance in the same
  transaction. Direct `Wallet` writes are forbidden, and a test MUST scan for them. A property test
  MUST prove `wallet == sum(ledger)` for each currency. On the client, writes go through
  `EconomyService.apply(op)` in one DB transaction over append-only `ledger_ops`.

**Rationale:** Premium currency and purchases carry real money. Server authority blocks fake
purchases and edited balances. Keeping the two currencies apart means the apartment is earned by
playing, so it keeps its value.

### V. Offline-First Play

- Every regular trip MUST be playable with no network, from the bundled or cached content pack.
  Apartment purchases with JENEHAT and already-downloaded story scenes MUST also work offline and
  sync later.
- First launch MUST NOT require registration, settings, network or ads. The first trip MUST be
  playable within 20 s of first open. The anonymous account is created in the background on the
  first online launch.
- Features that need the network (real-money purchases, daily challenge, leagues, rewarded ads,
  content updates) MUST show the «محتاج نت» state and MUST NOT block flows that work offline.
- A backend outage or maintenance mode MUST degrade features, never stop play.
- Offline progress reaches the server only as sync ops. Soft anomalies (fuel overdraft within
  tolerance, unusually fast runs) MUST be accepted and recorded as `PlayerFlag`. Only hard
  violations are rejected, so honest offline play is never punished.

**Rationale:** People play in transit, often with poor coverage. The product depends on short
sessions that work anywhere.

### VI. Idempotent Everything (NON-NEGOTIABLE)

- Every state-changing request MUST carry a client-generated UUIDv7 `client_txn_id`. The server
  MUST store each result in `ProcessedOp` and return the stored result on replay.
  - Credential exchanges are idempotent on their own credential instead: account creation, token
    renewal and provider linking (`POST /v1/auth/anonymous`, `/v1/auth/refresh`, `/v1/auth/link`).
    The install id, the refresh token's session and `jti`, and the provider account make a
    repeated request give the same outcome. Their results hold tokens, so they MUST NOT be stored
    in `ProcessedOp`.
  - Every other state-changing request keeps `client_txn_id` and `ProcessedOp`.
- `POST /v1/sync` MUST process ops in array order inside one transaction per batch, serialized per
  player with `SELECT … FOR UPDATE` on `Wallet`, and return an accepted or rejected result for each
  op. A rejected op MUST NOT abort the batch.
- Store and ad webhooks (RTDN, Apple server notifications, AdMob SSV) MUST be idempotent on their
  notification id.
- Server time is authoritative for fuel, rewards and daily resets.
  - The client MUST derive time from an anchor advanced by the device's monotonic uptime. The
    anchor is the last server time (`server_time_offset` from `/v1/bootstrap`), or the device
    clock until a server time exists.
  - The client MAY read the device clock only to take a new anchor: on first open, or after a
    device restart while offline. A new anchor MUST NOT move trusted time backward.
  - Changing the device clock while the device stays on MUST have no effect.
  - The server MUST NOT accept device time as authority. It recomputes fuel, rewards and daily
    resets from its own clock, and its state replaces the client's on sync.
- A property test MUST prove that applying the same batch twice yields the same state.

**Rationale:** Mobile networks retry and offline queues replay. Without idempotency, every retry
risks a double grant or a double spend. A credential exchange already carries a unique credential,
and storing its result would keep bearer tokens at rest. Offline play (Principle V) needs a clock
before any server contact and after a restart. Counting uptime from an anchor means a clock change
gains nothing while the phone stays on, and the server's recomputation keeps any device-side gain
provisional.

### VII. Content, Not Code

- Trips, lines, vehicles, apartment items, chapters, catalog prices and speech pools MUST be data
  in immutable, versioned content packs that validate against `content/schemas` (JSON Schema
  2020-12).
- Every pack MUST go through the pipeline: authored in Django admin, schema-validated,
  solver-validated (every trip 3-star solvable), built as gzipped JSON with a sha256, then
  published under a new version. A published pack MUST NOT be changed.
- A `trip_id` is permanent. A rule change to a published trip bumps its `rev`.
- Pydantic and Dart content models MUST be generated from `content/schemas`. Hand-edited models are
  forbidden.
- Player-visible text MUST NOT appear in Dart or Python source. UI strings live in ARB files.
  Dialogue lives in speech pools, and the engine emits only `speech_key`s. Server-side copy, such as
  push templates and offers, is stored as data with an `ar-EG` default and an `ar` fallback.
- Prices MUST be read from the catalog, never from constants.

**Rationale:** New lines and balance fixes ship without an app release, every pack can be validated
and rolled back, and copy is reviewed as content rather than code.

### VIII. Tunable Numbers

- Every balancing number (hop and bubble timings, reputation deltas, fuel max and regeneration, ad
  caps, the undo window and similar) MUST have a Firebase Remote Config key with a bundled default.
  The server MUST keep a matching copy in `liveops.LiveSetting`.
- The engine MUST receive tunables as explicit `params`, which are part of the replay tuple. It
  MUST NOT read Remote Config directly.
- Magic balancing constants in code are forbidden. A new tunable MUST be added to the key table in
  mobile §14.3 and to the backend settings in the same change.

**Rationale:** Difficulty and economy will be retuned after every playtest. Retuning must not need a
release, and every replay must record the values it ran with.

### IX. No Ads in a Trip

- No ad SDK call may be made while `TripState.status == running`.
- Player-initiated rewarded placements inside a trip (`traffic_jam`, `trip_revive`) MUST pause the
  engine first or happen in the `failed` state.
- Interstitials MUST appear only between trips and MUST follow Glossary §3.4 exactly: every 3
  trips, never in the first 10 trips, never right after a rewarded ad, and never for `remove_ads`
  owners or subscribers. There are no banners in v1.
- A rewarded ad is an offer, never a gate. Where the Glossary also sells the same reward for BONAT,
  the BONAT option MUST appear next to the ad. Ad caps MUST be enforced both on the device and on
  the server.
- Consent MUST be collected through Google UMP before the first ad request. On iOS, the ATT prompt
  MUST come before any personalized ads.

**Rationale:** A trip is a 60–90 second puzzle under time pressure. An interruption breaks the game
and feels like a punishment («الإعلان اختيار، مش عقاب»).

### X. RTL and Arabic First

- Every screen MUST be designed, built and tested in Arabic RTL.
- Digits MUST default to Arabic-Indic (١٢٣), with a setting for Western digits (123).
- Golden tests MUST cover every screen in RTL with both digit settings.
- Player-visible copy MUST be colloquial Egyptian Arabic in the characters' voice, kept
  understandable to players from other Arab countries.
- The reference frame is portrait 390×844 pt. Layouts MUST NOT assume LTR for flow, alignment,
  directional icons or swipe direction.

**Rationale:** The game launches in Egypt and then the Gulf. RTL added late shows up as broken
layouts and costs player trust.

### XI. Accessible Minimums

The minimum sizes in ux-spec «الأحجام الدنيا» are acceptance criteria. A screen that misses any of
them is not done.

- Touch targets MUST be ≥ 44×44 pt, all text ≥ 12 pt, and bubble text ≥ 15 pt after scaling. Faces
  MUST be ≥ 50 pt wide in the back row and ≥ 80 pt in the near row. Money tokens MUST be ≥ 40×24 pt
  with a 15 pt amount.
- During a trip, every control the player plays with MUST sit in the bottom third of the screen,
  for one-handed play. Two kinds of touch are exempt:
  - what the scene itself shows: the passengers, money dropped on the floor, and the answers to a
    passenger's question, placed next to that passenger;
  - controls that stop play rather than play it: the pause button in the top bar (ux-spec
    «الشريط العلوي»), which the phone's back button doubles, and the debug panel of internal builds.
- Every station MUST be marked by both a color and a letter. Colors that must be told apart MUST
  differ in lightness, not only in hue. Text contrast MUST meet WCAG 2.1 AA.
- Reduced motion MUST disable the scene shake and the bubble pop. Haptics MUST have an off setting.
- No more than two speech bubbles may be visible at once. Each stays up for at least the line's
  `trip_bubble_min_ms` and stays inside the scene bounds.
- Key events (payment, short change, an approaching station) MUST reach the player through more
  than one channel: sound, visual and text. Change beyond what was owed is not a key event: it stays
  silent during the trip, as the product spec says («المستغل يسكت»), and the result lists it.

**Rationale:** In the prototype playtest, small faces and fast text were the main cause of
confusion. These numbers are the fix. The pause button is used rarely and on purpose, so keeping it
away from the thumb prevents accidental pauses, and the back button reaches it one-handed. Silent
over-change is a game rule: the player learns it from the result, not from a cue.

### XII. No Runtime LLM

- Neither the client nor the server may call an LLM or any other generative model at runtime.
- All dialogue, push templates and offer copy MUST be written, and reviewed against the content
  limits, before shipping.
- Speech lines MUST be picked deterministically from the trip seed.

**Rationale:** This keeps costs down, works offline, keeps content safe, and meets the stores'
obligations for AI-generated content.

### XIII. Small, Testable Features

- Each feature ID (`B01`–`B15`, `M01`–`M20`) MUST become exactly one `specs/NNN-<short-name>/`
  folder. Each feature MUST be independently testable and ship with its own tests.
- Tests are mandatory for every feature. The "Tests are OPTIONAL" default in the spec-kit tasks
  template does not apply to this project.
- Tests come first: red, then green, then refactor. This is mandatory for engine rules, ledger and
  sync validators, entitlement resolution, and purchase and webhook verification.
- Coverage: `packages/trip_engine` MUST reach ≥ 90% line coverage, and every other package and app
  ≥ 80%.
- Required test levels:
  - engine unit tests for every rule, archetype and event;
  - `hypothesis` property tests for the ledger invariant and idempotency;
  - `schemathesis` contract tests against `contracts/openapi.yaml`;
  - RTL golden tests;
  - `integration_test` flows for onboarding through the first 5 trips, empty fuel through an ad or
    BONAT, and purchase through verification;
  - recorded webhook payloads, both valid and tampered.
- Backend integration tests MUST run against real PostgreSQL and Redis, not mocks.

**Rationale:** A small part-time team can only move quickly if each slice can be verified without
hand-testing the whole game.

## Platform, Security & Content Constraints

**Locked stack.** Changing any item here requires a MINOR amendment.

- Mobile:
  - Flutter stable, pinned with FVM (`.fvmrc`). Flame for the trip scene, Rive for characters.
  - Riverpod with `riverpod_generator` (not BLoC), `go_router`, `freezed` + `json_serializable`,
    and `dio`.
  - `drift` (SQLite) for structured local data; Hive and Isar were rejected.
  - `flutter_secure_storage` for tokens.
  - Flavors: `dev`, `staging` and `prod`.
- Backend:
  - Python 3.13, managed with `uv`.
  - Django 5.2 LTS + DRF. Django admin is the content-authoring and live-ops tool (no Wagtail, no
    React).
  - PostgreSQL 17, Redis 7 or Valkey, Celery 5 + `django-celery-beat`, `simplejwt` and
    `drf-spectacular`.
- Deployment: two ARM64 Oracle Cloud Always Free VMs, one per environment (production and
  staging), each 1 OCPU / 6 GB and each running Docker Compose behind its own Caddy, with images
  built for `linux/arm64`. Staging and production never share a VM. iOS builds run on Codemagic.

**Architecture boundaries.**

- Mobile layers run Presentation → Application (Riverpod) → Domain ← Infrastructure. Every plugin
  MUST sit behind an interface (`AdsGateway`, `PurchaseGateway`, `ApiClient`, `ConfigSource`,
  `AnalyticsSink`) so features can be tested with fakes.
- Speech bubbles and the HUD are Flutter widgets layered over the Flame scene. Text is never drawn
  in the canvas.
- Backend business logic lives in `apps/<app>/services/`. Views and serializers stay thin.
- Errors use the envelope `{"error": {"code", "message", "details"}}` with the codes in backend
  §6.2. Error messages MUST NOT leak internals or personal data.
- Primary keys are UUIDv7. Migrations follow expand/contract, so the previous release keeps working
  during a deploy. Backend code stays stateless so the scale path in backend §15 stays open.
- Calls to the stores and FCM run in Celery, with timeouts and retries. The one exception is
  purchase verification, which runs synchronously with a 10 s timeout and recovers through RTDN.

**Security & privacy.**

- HTTPS only, with TLS and HSTS. The client MUST NOT call plain HTTP endpoints, with one exception:
  the `dev` flavor MAY call the developer's own machine (`localhost`, `127.0.0.1` and the Android
  emulator's `10.0.2.2`) over plain HTTP, to reach the local development stack. Staging and
  production builds MUST refuse plain HTTP, both in the app's own URL check and in the platform's
  network configuration, and a test MUST keep it that way. Dev builds are never distributed.
- Secrets MUST NOT appear in source code, in committed config, or in committed `.env` files. They
  come from host-mounted env files or a secret manager.
- Tokens are stored only in `flutter_secure_storage`, never in SharedPreferences.
- Access JWTs last 15 min. Refresh tokens last 30 days and are rotated and blacklisted on use.
  - A renewal repeated with the same refresh token within a short retry window (seconds, a server
    setting) MUST return the same successor, not a new one. That way a lost answer or two racing
    renewals don't fork the session.
  - Any other use of a spent refresh token MUST be refused, and MUST end every token renewed from
    the same sign-in.
- The server MUST verify Google and Apple ID tokens, and every webhook signature (Pub/Sub OIDC,
  Apple JWS, AdMob ECDSA).
- Input is validated with strict serializers and size limits, and every endpoint is rate-limited.
  Raw SQL, where unavoidable, MUST be parameterized.
- Django admin runs on a separate hostname, is staff-only and requires 2FA. Content publishes and
  wallet adjustments are audit-logged.
- Personal data is kept to a minimum: no email, phone number or real name.
- Account deletion MUST be available both in the app and on a public web page, as the stores
  require.

**Product & content limits** (from product-spec «حدود المحتوى»).

- No real brands, government bodies or sports clubs.
- No smoking, harassment or violence.
- The comedy targets situations, never religion, region, skin color, class or disability.
- Salma and every female character have their own opinions and make their own decisions.
- No loot boxes: every paid product shows its exact contents before purchase.
- Paying can speed up progress but never replace it. Real money never buys apartment items
  directly.
- Content MUST stay within all-ages limits until the store age rating is decided (backend §22.8).

**Performance budgets.** These are acceptance criteria, measured on the reference devices.

- The trip scene targets 60 fps and MUST NOT drop below 45 fps on the reference low-end Android
  device.
- Cold start to Home: < 3 s.
- Android download size: < 80 MB.
- Memory during a trip: < 300 MB.
- No background work except FCM and scheduled local notifications.
- Crash-free sessions: ≥ 99.5%.
- Backend p95 latency:
  - `GET /v1/bootstrap` < 150 ms;
  - `POST /v1/sync` (100 ops) < 250 ms;
  - `POST /v1/purchases/verify` < 2.5 s.
- Backend availability: 99.5% monthly.

## Development Workflow & Quality Gates

- **Sources of truth.** `docs/product-spec.md` and `docs/ux-spec.md` define the *what* and *why*.
  `docs/architecture-backend.md` and `docs/architecture-mobile.md` define the *how* and are always
  read together when planning. This constitution sets the rules that none of them may break.
- **Spec-kit flow.** constitution → specify → clarify → plan → tasks → analyze → implement.
  - Each B/M pair is planned together, so both share the same `contracts/` content.
  - Features follow the MVP joint order in backend §21.
  - Only the current roadmap phase is built. A phase starts when the product-spec gate before it
    is met, not on a date.
- **Shared Contract Glossary.** Backend §3 and mobile §3 MUST stay word-for-word identical, so a
  change edits both copies at once. Glossary identifiers are the only valid names in code, content,
  analytics and API payloads.
- **No guessing.** Every **NEEDS CLARIFICATION** item a feature touches MUST be resolved before
  `/speckit-tasks`, either in that feature's `research.md` or by asking the project owner.
- **Constitution Check.** Every `plan.md` MUST list the principles the feature touches and how it
  satisfies each one. The check runs before Phase 0 research and again after Phase 1 design. A
  deviation MUST be recorded in Complexity Tracking, with its justification and the simpler
  alternative that was rejected.
- **API contract.** `contracts/openapi.yaml` is generated by `drf-spectacular` and committed. CI
  MUST diff it against the code, and mobile DTOs are checked against the same file.
- **CI gates.** All of these MUST pass before a merge:
  - backend: `ruff`, `mypy` (django-stubs), and `pytest` with real Postgres and Redis, including the
    `hypothesis` and `schemathesis` suites;
  - mobile: `dart analyze`, and the unit, widget and golden tests;
  - parity fixtures, in both Dart and pytest;
  - content: schema validation of `content/source`, and a fresh solve of every published trip;
  - the OpenAPI diff;
  - the scan for direct `Wallet` writes.
  Checks for floats in money code and for Arabic literals in source SHOULD be automated as soon as
  that code exists.
- **Review.**
  - Every change is reviewed against this constitution.
  - Changes to auth, purchases, the ledger, sync, webhooks or personal data also get a security
    review.
  - Commits follow Conventional Commits.
- **Release.**
  - Android goes from Play internal testing to closed testing (Egypt), then to production.
  - iOS ships through TestFlight.
  - Release builds are obfuscated, with symbols uploaded to Crashlytics.

## Governance

- **Supremacy.** This constitution overrides conflicting guidance in the architecture docs,
  `CLAUDE.md`, the spec-kit templates and any agent defaults. When a conflict turns up, fix the
  lower-ranked document or amend this one; never diverge silently. Product and UX decisions still
  belong to the product and UX specs. This document only codifies the parts that are
  non-negotiable for engineering.
- **Amendments.**
  - Every amendment is made through `/speckit-constitution`. It records a Sync Impact Report, a
    version bump and its rationale, plus any migration needed for existing specs and plans.
  - Principles I–XIII mirror backend §17 and mobile §18. Adding, removing, renumbering or renaming
    a principle MUST update both docs in the same change, so the numbering stays identical.
  - The project owner approves every amendment.
- **Versioning.** This document follows semantic versioning:
  - MAJOR: a principle is removed or redefined in a backward-incompatible way.
  - MINOR: a principle or section is added, guidance is materially expanded, or the locked stack
    changes.
  - PATCH: clarifications and wording only.
- **Compliance.**
  - `/speckit-plan` enforces the Constitution Check gate.
  - `/speckit-analyze` reports any violation as CRITICAL.
  - Code review verifies the principles a change touches.
  - CI enforces the rules that can be automated.
  - Overall compliance is reviewed at each roadmap phase gate.
- **Exceptions.**
  - Principles I, II, III, IV and VI admit no exceptions. Changing them requires an amendment.
  - An exception to any other principle MUST be time-boxed and recorded in the feature's Complexity
    Tracking with the owner's approval. It MUST come with a follow-up task that removes it.
- **Runtime guidance.** `CLAUDE.md` at the repository root carries day-to-day agent guidance and
  MUST stay consistent with this constitution.

**Version**: 1.5.0 | **Ratified**: 2026-10-18 | **Last Amended**: 2026-10-24
