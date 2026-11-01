# Quickstart: Validating M10 (Apartment, Story Chapters, Scenes and Family Requests)

How to prove the feature works. The contracts hold the details; this guide only says what to run
and what to expect.

## 1. Prerequisites

- A fresh checkout of `015-m10-apartment-story`.
- `content_models` and the app built as `apps/mobile/CLAUDE.md` says (`build_runner` in
  `packages/content_models`, then `pub get` and `build_runner` in `apps/mobile`).
- Rive's Linux library: `fvm dart run rive_native:setup --verbose --clean --platform linux`.
- For §6, the dev stack is up (`docker compose … up -d --wait` in `backend`, image rebuilt after the
  schema change) and seeded.

## 2. Content fields ([contracts/content-fields.md](./contracts/content-fields.md))

| Run (where) | Expect |
| --- | --- |
| `uv run wassal-content codegen --check` (`tools/content_kit`) | no difference |
| `uv run wassal-content validate-source ../../content/examples/sample` | valid |
| `uv run pytest` (`tools/content_kit`) | each new invalid example reports exactly its rule (V-C6–V-C12, V-R3, V-R4) or its schema path (`$.scenes[0].title`, `$.slot`, `$.character`, `$.slot.w`) |
| `uv run wassal-content golden` · `bundle dev --check --out ../../apps/mobile/assets/content/dev` | match the committed files |
| `fvm dart test` (`packages/content_models`) | the round trip reads every new field |
| `uv run manage.py makemigrations --check --dry-run` · `uv run pytest -n 4 --cov --cov-fail-under=80` (`backend`) | no missing migration; import/export byte for byte with the fields and riders; the admin saves them; `test_story_fields.py` refuses each invalid example |
| `uv run wassal-solver parity` · `uv run pytest -n 4` (`tools/solver`) | unchanged; the fingerprint equals master's |
| `fvm dart test` (`packages/trip_engine`) | unchanged; `Xorshift32` is exported and nothing else moved |

## 3. Economy, sync and storage (tests first)

In `apps/mobile`:

```bash
fvm flutter test test/core/economy test/core/sync test/core/progress test/drift
```

Expect ([contracts/economy-ops.md](./contracts/economy-ops.md)):

- `story_progress` and `claim_request`: every refusal in order; a repeat stores no row; a claim never
  changes BONAT.
- Both payloads carry `content_version`.
- `stateFromSnapshot` fills `scenesSeen` and `requestsClaimed`; ids the pack lacks are kept.
- The v4 → v5 migration keeps `ledger_ops` rows.
- `pendingRewards` reports each source pending, then received once the base has it.

## 4. Rules and screens (unit, widget, design, a11y)

```bash
fvm flutter analyze --fatal-infos
fvm flutter test --coverage --exclude-tags backend
fvm dart run tool/check_coverage.dart --min 80
```

Look for, by file:

- **`test/core/progress/story_test.dart`:**
  - moments, waiting and story order;
  - `story_run_test.dart` scripts a player from the first open to chapter 4's end on the sample
    pack, and each scene becomes waiting at its moment exactly once (SC-005);
  - for the first-release pack, the same test with
    `--dart-define=STORY_RUN_PACK=<pack .json.gz>`, built from the release draft by
    `bundle dev --source … --out <scratch dir>` (tasks T135).
- **`test/features/story/application/story_due_watcher_test.dart`:** a vehicle bought here makes its
  goal scene due; a restored completion makes nothing due (SC-006).
- **`test/features/apartment/**`:**
  - every state in [contracts/apartment.md](./contracts/apartment.md);
  - double taps and retries spend once (SC-002);
  - `RoomDone` opens only from a purchase outcome.
- **`test/features/story/**`:** the viewer's taps, a sequence, skip and back recording, a replay with
  no op, share with the fake gateway, the timeline and the album
  ([contracts/scene-viewer.md](./contracts/scene-viewer.md)).
- **`test/features/trip/**`:** riders, the story title and strip, `fail_reason`, comments
  deterministic and silent on over-change ([contracts/story-trip.md](./contracts/story-trip.md)).
- **`test/features/onboarding/**`** and the router tests: the first-session scene location unchanged;
  after it, the viewer.
- **`test/goldens/design/*_goldens_test.dart`** for the nine artboards and their layout tests pass
  (SC-007), with the expected differences listed at the top of each (research R18). The owner's
  boards are checked once exported.
- **`test/a11y/*_minimum_sizes_test.dart`** for the apartment, the sheets, the dialog, the viewer,
  the timeline and the album, at 360×640, 360×800 and 390×844, scale 1.0 and 1.3 (SC-008).
- **`test/repo/**`:**
  - no Arabic literals;
  - no raw style values;
  - integer money;
  - the economy store is the only writer of `player_state`;
  - domain imports;
  - no ads in a trip.

Side by side with the design: `fvm flutter test --dart-define=DESIGN_COMPARE=true test/goldens/design`,
then open `build/design_compare/`.

## 5. The offline loop (integration, headless)

```bash
fvm flutter test integration_test/apartment_loop_test.dart -d flutter-tester
fvm flutter test integration_test/story_trip_test.dart -d flutter-tester
```

`apartment_loop_test` runs offline, from a scripted chapter-3 player with enough coins:

1. «الشقة»: the goal view, ready; «اشتري الشبكة» spends the catalog price once, and the story
   trip's card opens. Closing it lands on the apartment's rooms view (SC-001).
2. Buy the salon's pieces from their sheets, one with the requested style; the request's «خد» shows
   «+{n} بون في الطريق». The BONAT balance doesn't move (SC-003).
3. The last piece opens `RoomDone` with the reward «في الطريق»; «شوف المشهد» plays the goal scene,
   recorded once.
4. The timeline shows chapter 4 done; the album counts every scene of the sample pack, the goal
   scene unlocked.

`story_trip_test` plays `line_hay.03`:

- a scripted short change makes المعلم comment once;
- an over-change makes no comment;
- the `TripResult` equals the run without riders.

M07's, M08's and M09's integration tests (`first_session_test.dart`, `home_loop_test.dart`,
`lines_loop_test.dart`) still pass unchanged.

## 6. Against the dev stack (SC-003, SC-004, SC-006)

```bash
uv run manage.py shell < ../apps/mobile/test/backend/seed_backend.py   # in backend
WASSAL_E2E_API=http://localhost:8000 fvm flutter test --tags backend test/backend
```

Expect from `story_sync_test.dart`:

- a shabka purchase, a scene record, piece purchases and a claim, made through M10's paths, are all
  accepted, with no `not_unlocked`;
- the room's, chapter's and request's BONAT appear in the server's wallet exactly once, and the
  phone's balance only after the sync;
- a fresh install restoring the account shows the same apartment, timeline, album and claimed
  requests, and no scene plays by itself.

## 7. On a device (owner, after merge)

Build: `fvm flutter run --flavor dev`, with `adb reverse tcp:8000 tcp:8000` on the Redmi Note 7.

| # | Do | Expect |
| --- | --- | --- |
| 1 | Fresh install; play the tutorial; open «الشقة» | chapter 1's goal counted in trips; the teaser |
| 2 | Earn until the microbus is affordable; open «الشقة» | «جاهزة!»; the CTA opens the vehicle sheet; after buying, chapter 2's goal scene plays at the next Home arrival |
| 3 | Airplane mode; buy the shabka | instant; the story trip's card; after its first finish, its scene plays |
| 4 | Still offline: furnish the salon | the drop-in, سلمى's comment, `RoomDone` with «في الطريق»; BONAT unchanged |
| 5 | Back online | the pending chip goes; BONAT rises by the room's and chapter's rewards once |
| 6 | «الطلبات»: claim one; pick a style that misses another | the toast; the warning line before buying; the missed request leaves the list |
| 7 | Timeline and album; replay a scene; share its panel | replays from the first panel; the share sheet opens with the panel image |
| 8 | Reinstall and sign in with the linked account | the same apartment and album; no scene plays by itself |
| 9 | TalkBack on the tab, the sheet, the dialog, the viewer | the labels and announcements of the contracts |
| 10 | Time the tab, a piece sheet, the timeline and a scene's first panel (SC-009) | under 0.5 s, 0.5 s, 0.5 s and 1 s |
| 11 | Reduced motion on | fades only; still panels |
| 12 | Five new players open the tab once (SC-010) | four can say what they save for and how much is left |
