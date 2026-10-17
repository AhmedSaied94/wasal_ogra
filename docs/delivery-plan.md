# Delivery Plan: building the MVP with Spec Kit

| Field | Value |
| --- | --- |
| Scope | Phase 1, the MVP (Egypt, Android): 26 features in 12 steps |
| Order from | Joint MVP sequence in `docs/architecture-backend.md` §21; feature tables in backend §20 and mobile §23 |
| Rules | [`.specify/memory/constitution.md`](../.specify/memory/constitution.md) |
| Updated | 2026-10-18 |

This plan sets the order we build the game in and the Spec Kit routine every feature goes through.
Tick features off in [Progress](#progress) as they merge.

## Before the first feature

- [ ] Merge `chore/project-setup` into `master`. Every feature branch is cut from `master`.

## The routine for every feature

1. **Start from an up-to-date `master`** (`git switch master && git pull`). `/speckit-specify` cuts the
   new branch from wherever you are, so starting on another feature branch stacks the two features.
2. **`/speckit-specify`** with the feature ID, its short name, the scope, and the source sections listed
   under its step. The git extension creates the branch, Spec Kit writes `specs/<spec>/spec.md`, and
   that spec becomes the active feature. Example:

   ```text
   /speckit-specify M03 App shell (short name: m03-app-shell). Routing with the bottom-nav shell,
   theme tokens from the «ستيكر الميكروباص» palette, Arabic RTL on every screen, Arabic-Indic digits
   by default with a Western-digits setting. Sources: docs/ux-spec.md «النظام البصري» and
   «خريطة الشاشات والتنقل»; docs/architecture-mobile.md §5, §6, §9, §21.
   Out of scope: real screen content.
   ```

3. **`/speckit-clarify`**: answer up to 5 questions. The answers are written into the spec.
4. **`/speckit-plan`**: give it both architecture docs.
   - It writes `plan.md`, `research.md`, `data-model.md`, `contracts/` and `quickstart.md`, and runs
     the Constitution Check.
   - Every **NEEDS CLARIFICATION** item the feature touches must be resolved in `research.md`. Each
     step below lists them.
5. **`/speckit-checklist`** (optional): for example accessibility for screens, or security for auth
   and purchases.
6. **`/speckit-tasks`**: writes `tasks.md`. Test tasks are always included (constitution XIII).
7. **`/speckit-analyze`**: fix every CRITICAL finding before implementing. Constitution violations are
   always CRITICAL.
8. **`/speckit-implement`**: tests first. If it leaves gaps, run `/speckit-converge`.
9. **Review and merge.**
   - CI gates are green.
   - The code is reviewed, with a security review for changes to auth, purchases, the ledger, sync,
     webhooks or personal data.
   - The PR is merged into `master`. Then start the next feature.

From step 3 onward, the `feature-branch` extension checks out the active feature's branch before each
command, or creates it if it is missing. If your local changes block the switch, the command stops.
Commit or stash, then rerun it.

## Conventions

**Spec numbers and names.** Spec numbers are assigned in the order you run `/speckit-specify`.
The numbers below assume you follow this plan; if you don't, the numbers shift but the feature IDs
stay the same. Put the feature ID in the short name, so the folder, the branch and the ID line up:
`001-m03-app-shell`.

**One active feature at a time.** The active feature is the one `.specify/feature.json` points to,
which is the one you specified last. To return to another feature, ask Claude to make
`specs/<spec>` the active feature. The next command then checks out its branch.

**In a pair, the owner of the shared artifact goes first.** The consumer is specified after the
owner merges, so its branch already contains the artifact.

| Shared artifact | Owner (merges first) | Consumers |
| --- | --- | --- |
| `content/schemas/*.json` | B04 | M01, M04, B05 |
| `fixtures/parity/*.json` | M01 (writes the first fixtures) | B05 (must reproduce them exactly) |
| `contracts/openapi.yaml` | The backend feature of the pair | The mobile feature of the pair |

If a feature changes the Shared Contract Glossary (§3), it edits both architecture docs in the same PR.

## The MVP sequence

| Step | Specs | What you have after this step |
| --- | --- | --- |
| 1 | 001 M03 · 002 B01 | An empty app and an empty API, both running in CI |
| 2 | 003 B04 · 004 M01 | The trip engine and the schemas it reads |
| 3 | 005 B05 | The Python mirror; every trip proven 3-star solvable |
| 4 | 006 M04 · 007 M05 | The bundled pack loads; local wallet, ledger and fuel |
| 5 | 008 M02 | **The first playable trip, fully offline** |
| 6 | 009 B02 · 010 B03 · 011 M06 | Server-backed accounts and wallet |
| 7 | 012 M07 · 013 M08 · 014 M09 · 015 M10 | The full game loop |
| 8 | 016 B10 · 017 B07 · 018 M11 | Rewarded ads and interstitials |
| 9 | 019 B06 · 020 M12 | Real-money purchases |
| 10 | 021 B08 · 022 M13 | The daily return loop |
| 11 | 023 B09 · 024 B11 · 025 M14 | Store compliance |
| 12 | 026 M15 | Measuring the launch KPIs |

### Step 1: Foundations

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `001-m03-app-shell` | M03 | App shell: routing, theme tokens, l10n/RTL, digit setting | — | ux-spec «النظام البصري», «خريطة الشاشات والتنقل»; mobile §5, §6, §9, §21 |
| `002-b01-backend-skeleton` | B01 | Project skeleton: Django settings, Docker Compose, Caddy, CI/CD, Sentry, health checks | — | backend §2, §4, §5, §15 |

- **Resolve:** mobile §24.1 (Android `minSdk` and iOS minimum) in M03; backend §22.1 (OCI free-tier
  capacity, or the paid fallback) in B01.
- **Also in M03:**
  - Pin Flutter with FVM, and set up mobile CI on GitHub Actions.
  - Add a `ConfigSource` with bundled defaults, so tunables (constitution VIII) work before Firebase
    is wired up in M15.
- **Done when:**
  - The app launches in RTL with the theme tokens and both digit settings, and its goldens run in CI.
  - The API answers `/healthz` behind Caddy on the ARM64 Compose stack.
  - CI is green on both sides.
  - The real build, lint and test commands are added to `CLAUDE.md`.

### Step 2: The engine and its schemas

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `003-b04-content-pipeline` | B04 | Content pipeline: schemas, authoring admin, pack build and publish, manifest, model codegen | B01 | backend §9; mobile §14 |
| `004-m01-trip-engine` | M01 | `trip_engine`: rules, commands, events, determinism | B04 schemas | product-spec «ميكانيكيات المشوار», «أنواع الركاب», «الأحداث والمواقف»; ux-spec «شاشة المشوار»; mobile §7 |

- **Order inside B04:** make the schemas and model codegen B04's first user story. Merge that slice
  in its own PR as soon as it is green, so M01 can start while the admin and the pack build continue.
- **Resolve:**
  - backend §22.3 (a CDN in front of content packs) in B04;
  - mobile §24.4 (resume or restart when the app is killed mid-trip) in M01. This decides whether
    the engine needs snapshot and restore.
- **Done when:**
  - `trip.schema.json` and the generated models are on `master`.
  - Replaying `(definition, seed, params, command_log)` gives an identical `TripResult`.
  - The engine has ≥ 90% line coverage.
  - The first parity fixtures are in `fixtures/parity/`.

### Step 3: Parity

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `005-b05-solver-parity` | B05 | Solver and simulator, difficulty scoring, parity fixtures in CI | B04, M01 fixtures | backend §10; mobile §7.10 |

- **Resolve:** nothing open.
- **Done when:**
  - pytest reproduces every M01 fixture exactly, and CI fails on any mismatch.
  - Every authored trip is proven 3-star solvable before it is published.

### Step 4: Content and the local economy on the device

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `006-m04-content-loader` | M04 | Content pack loader, bundled pack, models from schemas | M03, B04 | mobile §14; backend §9 |
| `007-m05-local-economy` | M05 | Local persistence (drift), economy service, fuel | M03 | mobile §11, §13; product-spec «الاقتصاد» |

- **Resolve:** mobile §24.5 (does replaying a completed trip cost fuel?) in M05. B03 must agree with
  the answer.
- **Done when:**
  - The app loads the bundled pack and verifies its sha256.
  - The wallet, `ledger_ops` and fuel regeneration all work offline.
  - No float holds money anywhere.

### Step 5: The first playable trip

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `008-m02-trip-screen` | M02 | Trip screen: Flame scene, Rive characters, HUD, dashboard, overlays | M01, M04 | ux-spec «شاشة المشوار», «أثناء المشوار: الأحداث والنوافذ»; mobile §8 |

- **Resolve:**
  - mobile §24.2: choose the reference low-end device;
  - mobile §24.6: choose the Rive runtime and confirm its licensing;
  - mobile §24.4: design the UI side of the resume policy.
- **Done when:**
  - A trip from the bundled pack plays from start to finish with no network.
  - The minimum sizes pass in RTL goldens.
  - The scene holds ≥ 45 fps on the reference device.
- **Milestone:** the first internal test of "is the puzzle fun?".

### Step 6: Accounts and sync

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `009-b02-accounts-auth` | B02 | Accounts and auth: anonymous accounts, refresh rotation, Google/Apple linking and conflicts | B01 | backend §6, §13 |
| `010-b03-ledger-sync` | B03 | Economy ledger, bootstrap, state, sync engine, op validators, fuel reconciliation, flags | B02, B04 | backend §7, §12 |
| `011-m06-identity-sync` | M06 | Identity, bootstrap, sync queue | M05, B02, B03 | mobile §12, §16 |

- **Resolve:**
  - backend §22.6 (a re-install without a linked provider creates a new player) in B02 and M06;
  - backend §22.2 (the game-day timezone) in B03;
  - confirm that B03 matches the M05 answer to mobile §24.5.
- **Done when:**
  - The first online launch creates an anonymous account in the background.
  - Offline trips sync without duplicates.
  - `wallet == sum(ledger)` and idempotency are covered by property tests.
  - The stale-state path (`GET /v1/state`) works.

### Step 7: The full game loop

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `012-m07-onboarding` | M07 | Onboarding and tutorial overlays (5 tutorial trips) | M02 | ux-spec «البداية وأول جلسة»; product-spec «تجربة المستخدم» (أول جلسة) |
| `013-m08-home-result` | M08 | Home, pre-trip card, result screen | M02, M05 | ux-spec «الموقف», «كارت ما قبل المشوار», «شاشة النتيجة» |
| `014-m09-lines-vehicles` | M09 | Lines map, line detail, vehicle purchase | M05 | ux-spec «الخطوط والعربية والجراج»; product-spec «التقدم: الخطوط والعربيات» |
| `015-m10-apartment-story` | M10 | Apartment ch1–4, item sheet, family requests, chapters, story viewer | M05 | ux-spec «الشقة والقصة»; product-spec «القصة والميتا» |

- **Resolve:** nothing open in the architecture docs.
- **Done when:**
  - From first open, the first trip starts in under 20 s.
  - The five tutorial trips, home, results, line progress, vehicle purchase and apartment items all
    work offline.
  - The integration test from onboarding through the first 5 trips passes.
- **Option:** the closed test (50–100 players) could start here. Its KPI, 80% of new players
  finishing the first session, needs analytics, so pull M15 forward if you take this route.

### Step 8: Ads

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `016-b10-catalog-offers` | B10 | Live-ops catalog and offers: store product grants, offer eligibility, live settings | B03 | backend §8, §11 |
| `017-b07-ads-ssv` | B07 | Ads: AdMob SSV callback, reward polling, caps | B03 | backend §8 |
| `018-m11-ads` | M11 | Ads integration: rewarded, interstitial, consent | M05, B07 | mobile §15.1; product-spec «تحقيق الدخل» (أماكن الإعلانات) |

- **Resolve:**
  - backend §22.10 (BONAT pack amounts) in B10;
  - in M11: mobile §24.3 (which mediation networks) and backend §22.8 (the age rating, which sets the
    ad content rating).
- **Done when:**
  - Every placement in Glossary §3.4 works, with its caps enforced on the device and on the server.
  - No ad call is ever made while a trip is running.
  - `morning_piggy` is granted only through SSV.
  - UMP consent is collected before the first ad request.

### Step 9: Purchases

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `019-b06-purchases` | B06 | Purchases: verify, Google RTDN, voided purchases, entitlements | B03, B10 | backend §8 |
| `020-m12-shop-iap` | M12 | Shop, IAP, fuel sheet | M05, M06, B06 | mobile §15.2; ux-spec «المحل والبنزين والدفع» |

- **Resolve:** backend §22.5 (refunds of BONAT that was already spent) in B06. Backend §22.4 (the iOS
  purchase payload) waits for phase 3.
- **Done when:**
  - BONAT packs and `remove_ads` can be bought, verified and granted end to end.
  - The store transaction is acknowledged only after the server returns `acknowledge: true`.
  - Restore purchases works.
  - Recorded RTDN payloads, both valid and tampered, pass their tests.

### Step 10: The daily return loop

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `021-b08-daily-challenge` | B08 | Daily challenge: generation, delivery, replay verification, rewards | B03, B05 | backend §11 |
| `022-m13-daily-loop` | M13 | Daily reward, tasks, daily challenge | M06, B08 | ux-spec «الرجوع اليومي»; product-spec «الاحتفاظ والتفاعل» |

- **Resolve:** backend §22.11 (the retry cost after the free first attempt).
- **Done when:**
  - Every player gets the same challenge each game day.
  - The solver verifies results by replay.
  - The first attempt is free.
  - The streak rules match the product spec.

### Step 11: Store compliance

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `023-b09-privacy-deletion` | B09 | Privacy: account deletion API and web page, Apple token revocation, data inventory | B02 | backend §14 |
| `024-b11-push` | B11 | Push: tokens, categories, campaigns, caps, quiet hours | B02 | backend §11 |
| `025-m14-settings-account` | M14 | Settings, account linking, deletion, notifications | M06, B09, B11 | ux-spec «الإعدادات والحساب والتواصل»; mobile §16 |

- **Resolve:** in B09, backend §22.9 (legal review, and how long purchase records are kept) and §22.8
  (the age rating).
- **Done when:**
  - Account deletion works both in the app and on the web page.
  - A linking conflict lets the player choose which progress to keep; accounts are never merged.
  - Players get at most 2 pushes a day.
  - The store data-safety answers match backend §14.2.

### Step 12: Measurement

| Spec | ID | Feature | Depends on | Specify from |
| --- | --- | --- | --- | --- |
| `026-m15-analytics-config` | M15 | Analytics taxonomy, Crashlytics, Remote Config wiring | M03 | mobile §17, §14.3 |

- **Done when:**
  - Every event in mobile §17 fires with its parameters.
  - Remote Config overrides the bundled defaults.
  - Crashlytics receives symbols from release builds.
- **Then:** the closed test, followed by the Android beta in Egypt.

## After the MVP

Each phase starts when the gate before it is met, not on a date (product-spec «خارطة الطريق»).

| Phase | Gate to start it | Features |
| --- | --- | --- |
| 2: content and revenue, plus KSA and UAE | Egypt beta: D1 retention ≥ 35% and D7 ≥ 13% | M16 garage; B12 + M17 subscription and starter pack; content packs for `line_souq`, `micro_new` and ch5 (built through B04) |
| 3: public launch and iOS | Gulf purchases cover the cost of acquiring players | B13 + M18 leagues; B14 + M19 seasonal events and season pass; B15 + M20 referral and share clips; Apple purchases and Sign in with Apple (B06 extension, backend §22.4); device attestation (backend §22.7); `line_masyaf`, `line_safar`, ch6–7 |

## Progress

- [ ] Step 1: `001-m03-app-shell` · `002-b01-backend-skeleton`
- [ ] Step 2: `003-b04-content-pipeline` · `004-m01-trip-engine`
- [ ] Step 3: `005-b05-solver-parity`
- [ ] Step 4: `006-m04-content-loader` · `007-m05-local-economy`
- [ ] Step 5: `008-m02-trip-screen`
- [ ] Step 6: `009-b02-accounts-auth` · `010-b03-ledger-sync` · `011-m06-identity-sync`
- [ ] Step 7: `012-m07-onboarding` · `013-m08-home-result` · `014-m09-lines-vehicles` ·
  `015-m10-apartment-story`
- [ ] Step 8: `016-b10-catalog-offers` · `017-b07-ads-ssv` · `018-m11-ads`
- [ ] Step 9: `019-b06-purchases` · `020-m12-shop-iap`
- [ ] Step 10: `021-b08-daily-challenge` · `022-m13-daily-loop`
- [ ] Step 11: `023-b09-privacy-deletion` · `024-b11-push` · `025-m14-settings-account`
- [ ] Step 12: `026-m15-analytics-config`
