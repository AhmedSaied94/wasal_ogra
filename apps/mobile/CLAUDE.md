# apps/mobile/CLAUDE.md

The Flutter app: what it has, its commands, its guards, its conventions and the UI rules. The project-wide rules are in the root `CLAUDE.md`.

## What the app has

- **M03** (`specs/001-m03-app-shell/`): the app shell: routing, theme tokens, RTL, digit styles, tunables and CI.
- **M04** (`specs/006-m04-content-loader/`): content packs: the one bundled in the build, newer ones it downloads in the background, and the switch to them at launch or on arrival at Home (since M07, also before a new player's first trip).
- **M05** (`specs/007-m05-local-economy/`): the economy offline in drift: the append-only operation log and its projection (wallet, fuel, inventory, ownership, progress), one service that validates and applies every change, fuel, trusted time, and what M06's sync calls.
- **M02** (`specs/008-m02-trip-screen/`): trips: the trip screen (the Flame scene with Rive passengers, the Flutter overlays, HUD and dashboard), `TripController` stepping the engine and charging the economy, the trip's replay record in drift and the resume at launch, the failure card with the BONAT revive, بلية's hints, and the playtest tools on dev and staging.
- **M21** (`specs/008.5-m21-design-refresh/`): all of it drawn in the «كرتون ناعم» design: the generated tokens and shared components, the bottom nav, sheets and dialogs, the `Loading` boot screen, the trip screen's zones, and every person, vehicle and UI animation from the owner's `wassal.riv`, with static art as the fallback.
- **M06** (`specs/011-m06-identity-sync/`): the player's account and the economy's sync with the server (`lib/core/account/`, `lib/core/sync/`).
- **M07** (`specs/012-m07-onboarding/`): the first session: the opening scene, the Name card, the five coached tutorial trips with بلية's coach, the سلمى scene, المعلم's fuel lesson, the name's re-ask on Home, the trip screen's compact profile for short screens, and the playtest «Onboarding» card.
- **M22** (`specs/012.5-m22-animated-scenes/`): the comic panels animate from a second Rive file, `wassal_scenes.riv`, and their lines play in turn: each bubble appears while its speaker talks, with the drawings as the fallback.
- **M08** (`specs/013-m08-home-result/`): the loop runs from الموقف: Home with the next trip, the line card, the savings goal and one arrival item at a time; the pre-trip card with its stops, star goals, «جديد» card and boosters; the result with its breakdown, mistakes, pay, quote and a shareable picture; and the phone's port of the server's unlock rules (`lib/core/progress/domain/`).
- **M09** (`specs/014-m09-lines-vehicles/`): الخطوط: the vehicle strip and the line map, a line's details with its trip grid, starting any open trip from Lines (its card opens at `/lines/:lineId/pre-trip/:tripId`, under the details), buying the next vehicle offline through M05's `buy`, the lines tab's «new» dot, and the phone-only rules beside the port (`playable.dart`: a story trip waits for its chapter's goal, vehicles sell in pack order).
- **M10** (`specs/015-m10-apartment-story/`): الشقة and the story: the tab's goal view (the chapter's goal, bought once through `GoalPurchase`) and rooms view (a room's scene of pieces, each bought through `PiecePurchase` in a style, `RoomDone` with its reward «في الطريق»), the chapters timeline and the album, the scene viewer (`/story/scene/:sceneId`, `/story/:chapterId`, `/story/album`; each scene's panels play once and are recorded through `StoryService`), the family requests sheet (`/apartment/requests`; «خد» records `claim_request` and the server pays the BONAT, so the phone shows it pending), the apartment's pre-trip card (`/apartment/pre-trip/:tripId`), and a chapter's story trip with its riders. Two new operations (`story_progress`, `claim_request`) and drift schema 5. The rules are the phone's port in `lib/core/progress/domain/` (`story.dart`, `requests.dart`, `rewards.dart`).
  - **Riders** (`features/trip/`): a chapter's `story_trip_info` gives the trip its title, the strip's condition, the failure line and the riders. `TripFacts.storyInfo` carries it; `TripView.storyStrip` and `riderBubble` project it; `RiderComponent` draws each rider in its seat through the scene's art factory (`Look.asset` is the character's own drawing). A rider's comment is the pure `riderComment` over a fresh `Xorshift32`, never the engine's generator, so the engine, its result and the parity fixtures are untouched.
  - **Art** the app ships, not packs: `ApartmentArt` and `PanelArt` map a slug to a synced drawing, and a slug with none draws its token fallback. The salon's room and its pieces have no drawing yet (only the modern أنتريه, the shabka goal, the teaser room and the requests' tea tray), so the rooms view, the piece sheet, `RoomDone` and Home's story-end tile draw tokens.
  - **The boards of 2026-10-31** (ten, `specs/015-m10-apartment-story/contracts/design-briefs.md` "As drawn"): the rooms header holds the pending chip (`PendingChip`, hidden when nothing is pending) beside the coins pill; after a purchase `boughtPieceProvider` makes the room drop the piece in and show سلمى's bubble until the next tap or scroll; a finished room's «شوف المشهد» is a button of its own inside `ChapterBar` (`trailingIsControl`); `PieceSheet` hangs the request mark off its style tile and prices its CTA on a `PriceChip`; `RoomDoneDialog` announces itself once; a done chapter's «شوف المشهد» is read with its scene's title; Home's card at the end of the story is «شقة العُمر» with the finished room's tile.

## Commands

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
| The loop from Home: card, trip, result and back, with SC-002's timings (headless) | `fvm flutter test integration_test/home_loop_test.dart -d flutter-tester` |
| The loop from Lines: buy the microbus, «كمّل», the details, the trip and back, with SC-008's timings (headless) | `fvm flutter test integration_test/lines_loop_test.dart -d flutter-tester` |
| A story trip's rider: one short change gives one comment, an over-change none, and the result is the one without the rider (headless) | `fvm flutter test integration_test/story_trip_test.dart -d flutter-tester` |
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
| The scenes' frame rate and memory on a device (a fresh install's opening and سلمى scene) | `tool/perf/scene_fps.sh <package>` (see `specs/012.5-m22-animated-scenes/quickstart.md`) |
| Regenerate the design tokens from `docs/design/tokens.json` | `fvm dart run tool/design/gen_tokens.dart` |
| Copy the design's icons and illustrations into `assets/` | `fvm dart run tool/design/sync_assets.dart` |
| The Rive tests only (after `rive_native:setup`) | `fvm flutter test --tags rive` |
| Rewrite the Rive goldens after a new export | `fvm flutter test --update-goldens test/features/trip/rive_art_goldens_test.dart` |
| Rewrite the scenes' Rive goldens after a new export of `wassal_scenes.riv` | `fvm flutter test --update-goldens test/features/onboarding/rive_scene_goldens_test.dart` |

## Builds

- Every build needs `--flavor dev|staging|prod`; the app refuses to start without one.
- Generated files (`*.g.dart`, `lib/l10n/generated/`) are gitignored. Run `pub get` and `build_runner` after a fresh checkout.
- The app depends on `packages/content_models`, whose generated parts are gitignored too. After a fresh checkout, build it first (`tools/content_kit/CLAUDE.md`).
- A dev build calls the local stack over plain HTTP, which only the dev flavor allows (constitution 1.2.0). On a phone or an emulator, run `adb reverse tcp:8000 tcp:8000` and the default `http://localhost:8000` works. `--dart-define=WASSAL_DEV_API_BASE=<url>` points a dev build elsewhere.
- Staging and prod builds bundle the pack production promoted last, so they fail at `checkBundledPack` until `apps/mobile/assets/content/release/` holds one. Committing it is a step of `docs/runbooks/content-publishing.md` §3.
- SQLite comes from the `sqlite3` package's build hook, which downloads a prebuilt library on the first build (network needed once). Don't add `sqlite3_flutter_libs`.
- iOS builds run only on Codemagic (`codemagic.yaml` at the repo root; its one workflow, `ios-dev-unsigned`, builds the unsigned dev IPA), because the dev machine is Linux.
  - The flavors are the Xcode schemes `dev`, `staging` and `prod`, with `Debug-`, `Release-` and `Profile-<flavor>` configurations. Each scheme sets its bundle ID and `APP_DISPLAY_NAME`.
  - Every iOS plugin is a Swift Package, so there is no Podfile. Don't add one: it makes `flutter build ios` run `pod install`, and the build fails.
  - Until there is a paid Apple Developer account, the only workflow is the unsigned dev IPA, sideloaded with a free Apple ID: `docs/runbooks/ios-test-build.md`.

## Storage

- The app database is `<app support>/db/wassal.sqlite`, opened during startup. Device backup and phone-to-phone transfer leave it out (`res/xml/data_extraction_rules.xml`, `backup_rules.xml`).
- Each table has one writer:
  - Only `lib/core/economy/drift_economy_store.dart` writes the economy's tables, and only through `EconomyService`. The economy store also writes `player_state` (M07: the driver's name and the tutorial grant, part of the projection).
  - Only `lib/features/trip/data/drift_trip_records.dart` writes the trip's (`trip_record`, `trip_record_command`, `trip_intent`: the replay record of the trip in progress and its outbox of economy calls).
  - Only `lib/core/account/drift_account_store.dart` writes `account` and `server_info` (M06: the player, and the last bootstrap's cached blocks).
  - Only `lib/features/onboarding/data/drift_first_session_store.dart` writes `first_session` (M07: the opening, the scenes seen, the fuel lesson, the step reached).
- A table change needs a new `schemaVersion` and its step in `AppDatabase.upgradeSteps`, and `make-migrations` adds its schema to `drift_schemas/app/` and its tests to `test/drift/`. Commit both. `test/drift/app/schema_test.dart` checks that a new file has the current version's exported schema, and `make-migrations`' `test/drift/app/migration_test.dart` checks every step between versions (v2, M02, added the trip's three tables).
- M10's schema 5 added the ops `story_progress` and `claim_request` and two `player_state` columns, `scenes_seen` (scene ids by chapter) and `requests_claimed` (request ids), written only by the economy store like the rest of the projection. `StoryService.recordSeen` records a scene and also writes M07's scenes-seen flag; `backfill` records the scenes a player had already seen without writing that flag.
- The pre-trip card's setting is the device preference `pref.pre_trip_card`, which falls back to the `pre_trip_card_mode` tunable. Lines keeps the news it has shown in `pref.lines_seen` (M09), a read marker for the tab's «new» dot, not game state.

## Art, goldens and test content

- The Rive art comes from two files, each with its contract (`RiveContract`).
  - `assets/rive/wassal.riv` holds every person, vehicle and UI animation, made to `specs/008.5-m21-design-refresh/contracts/rive-characters.md` (artboards, state machines, view models; `Person` draws all 24 people by its `look` number).
  - `assets/rive/wassal_scenes.riv` (M22) holds the scenes' comic panels, made to `specs/012.5-m22-animated-scenes/contracts/rive-scenes.md`: one 358×540 artboard per panel slug, its `Panel` state machine, and four Booleans that make a character talk.
  - Their editable sources are in the owner's Rive account. Boot decodes both in the step `art` and checks each against its contract; an artboard that fails falls back to the design's static SVGs alone, and the debug panel lists both files' problems, each starting with its file's path.
  - After exporting a new version, run that file's Rive golden command above, review the sheets and commit them with it. The tests tagged `rive` need the files and Rive's Linux library.
- `assets/illustrations/vehicles/` holds all four vehicles' drawings (M09 synced `microbus_new.svg` and `microbus_travel.svg`), each the static fallback of its `VehicleSprite`.
- Goldens are generated on Linux. If CI disagrees with them, run the workflow by hand with `update_goldens: true` and commit the PNGs it uploads; CI is then the reference.
- The result's share goes through `ShareGateway` (`lib/core/platform/share_gateway.dart`, `share_plus`), so tests use `test/helpers/fake_share_gateway.dart`; iOS gets it as a Swift Package (no Podfile).
- M07's tests play the release draft's five tutorial trips from `apps/mobile/test/fixtures/tutorial/`, copied by hand from `content/drafts/core-r1/pack/` in the `content-core-r1` worktree and layered over the sample by `test/helpers/tutorial_content.dart` (its README says what and when). The sample's own trips and parity fixtures don't change. When the draft's `line_hay`, trips 01–05 or the sleeper's pools change, copy them again and rerun those tests.
- M10's board samples (`test/design/samples/apt_states.dart`, `story_states.dart`) play `releaseDraftPack()` (`test/helpers/synthetic_packs.dart`): the draft's catalog, salon, items, requests and chapters 1 to 4, copied by hand into `apps/mobile/test/fixtures/release_draft/` (its README says when to copy again). **The draft wins on every text it owns** (owner decision 2026-10-31), so a board's chapter line, tagline, comment or scene title differs from the board; each difference is in the board's "As drawn" note and the layout test's header. The check harness (`test/design/design_check.dart`) takes the unmatched node near a box when two share a label.

## Repo guards

`flutter test` also runs the repo guards:

- no Arabic outside comments in `lib/` (player text goes in `lib/l10n/app_ar.arb`)
- no `double`/`num` money
- no raw colors, radii, font sizes, shadows, animation durations or curves outside `lib/core/theme/tokens/` (`trip_motion.dart`'s named constants aside)
- nothing of the retired «ستيكر الميكروباص» design, no Material ink or stock buttons
- the design tokens generated from `docs/design/tokens.json`, the design's assets copied as `tool/design/sync_assets.dart` writes them, and the palette contrast checks
- the tunables registry
- no Flutter or plugin import in a `domain/` folder, and each folder lists what it may import:
  - `lib/core/economy/domain/`: only `content_models`, `trip_engine` and the content and economy domains
  - `lib/core/progress/domain/`: only the models, the content source and the SKU ids' wire names
  - M08's `features/{home,pre_trip,result}/domain/`: also the engine, the progress domain, the trip domain's looks and each other
  - M09's `features/lines/domain/`: the models, the content source, the SKU ids' wire names, the progress domain, Home's `savings_target.dart` and `next_trip.dart`, and itself
  - M10's `features/apartment/domain/` and `features/story/domain/`: the models, the content source and its domain, the SKU ids' wire names, the progress domain, Home's `savings_target.dart`, and each its own folder (the trip's `rider_comments.dart` stays under the trip's list)
- plain HTTP only in the dev source set
- bundled packs that agree with their records
- no REAL column
- the ARB's keys unique (a JSON object keeps the last of two equal keys, and `gen_l10n` doesn't say)
- the economy's tables written only by its store, with `ledger_ops` rows changing only in their sync columns (and the trip's only by theirs)
- no `sqlite3_flutter_libs`
- the backup exclusion (the database and the secure storage files, with no `<include>`)
- the economy's sync calls (`EconomySync`) only from `lib/core/sync/`, `lib/core/account/` and `lib/core/economy/`
- no token, session or install id in logs or the preference store
- no text drawn in the trip's Flame canvas
- no ad SDK under `lib/features/trip/`
- a rider's money (`PassengerState.balance`, `.paidIn`) read only by the trip's projection and the tutorial coach

## Conventions (mobile §6, §10, §11)

- Layers: Presentation → Application (Riverpod) → Domain (`trip_engine`, economy rules) ← Infrastructure.
- The domain layer never imports Flutter, Flame, Firebase or any plugin.
- Every plugin sits behind an interface (`AdsGateway`, `PurchaseGateway`, `ApiClient`, `ConfigSource`, `AnalyticsSink`).
- `TripController` owns the `TripEngine`. Widgets send commands and never mutate state directly.
- Bubbles and the HUD are Flutter widgets drawn over the Flame scene, not text drawn in the canvas.

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
