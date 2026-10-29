# Quickstart: Validating M09 (Lines, Line Details, Vehicle Purchase)

How to prove the feature works. The contracts hold the details; this guide only says what to run
and what to expect.

## 1. Prerequisites

- A fresh checkout of `014-m09-lines-vehicles`.
- `content_models` and the app built as `CLAUDE.md` says (`build_runner` in
  `packages/content_models`, then `pub get` and `build_runner` in `apps/mobile`).
- Rive's Linux library: `fvm dart run rive_native:setup --verbose --clean --platform linux`.
- For §5, the dev stack is up (`docker compose … up -d --wait` in `backend`) and seeded.

## 2. Content fields ([contracts/content-fields.md](./contracts/content-fields.md))

| Run (where) | Expect |
| --- | --- |
| `uv run wassal-content codegen --check` (`tools/content_kit`) | no difference |
| `uv run wassal-content validate-source ../../content/examples/sample` | valid |
| `uv run pytest` (`tools/content_kit`) | the new invalid examples report exactly `$.display_fare_piasters`, `$.short_name` and V-X1 `$.whats_new.ar-EG` |
| `uv run wassal-content golden` · `bundle dev --check --out ../../apps/mobile/assets/content/dev` | match the committed files |
| `fvm dart test` (`packages/content_models`) | the round trip reads the three fields |
| `uv run manage.py makemigrations --check --dry-run` · `uv run pytest -n 4 --cov --cov-fail-under=80` (`backend`) | no missing migration; import/export is byte for byte with the fields; the admin forms save them |
| `uv run wassal-solver parity` · `uv run pytest -n 4` (`tools/solver`) | unchanged; the fingerprint is the same as on master |

## 3. Rules and screens (unit, widget, design, a11y)

In `apps/mobile`:

```bash
fvm flutter analyze --fatal-infos
fvm flutter test --coverage --exclude-tags backend
fvm dart run tool/check_coverage.dart --min 80
```

Look for, by file:

- **`test/core/progress/playable_test.dart`:**
  - the never-more-permissive sweep passes;
  - the US5 cases (`line_hay.20`, `line_gamaa.01`, `.18`) pass by name.
- **`test/features/home/domain/next_trip_test.dart`:** Home no longer offers `.18` before the shabka.
- **`test/features/lines/**`:** every state of the three contracts.
- **`test/core/routing/shell_test.dart`:** the lines tab opens at `/lines` after a trip started from
  a Lines card.
- **`test/goldens/design/{lines,line_details,buy_vehicle}_goldens_test.dart`** and the three layout
  tests pass, with the expected differences listed at the top of each (research R12). The owner's
  boards are checked once exported.
- **`test/a11y/{lines,line_details,buy_vehicle}_minimum_sizes_test.dart`:** at 360×640, 360×800 and
  390×844, scale 1.0 and 1.3.

Side by side with the design: `fvm flutter test --dart-define=DESIGN_COMPARE=true test/goldens/design`,
then open `build/design_compare/`.

## 4. The offline loop (integration, headless)

```bash
fvm flutter test integration_test/lines_loop_test.dart -d flutter-tester
```

The test runs offline, from a scripted chapter-2 player with enough coins:

1. «الخطوط»: the map shows Home's line, and the microbus tile shows its price.
2. The microbus tile, then «اشتريها»: the coins drop by the catalog price once; the sheet closes;
   the microbus is current; خط الجامعة is open (SC-002).
3. «كمّل» on خط الجامعة: the card for its first trip (the test sets the card setting to «always»).
   Close: the line's details. «العب المشوار ١»: the card again, then «اطلع».
4. The trip, then the result, then Home, then «الخطوط»: the map, not the card. The microbus is still
   current.

M07's and M08's integration tests (`first_session_test.dart`, `home_loop_test.dart`) still pass.

## 5. Against the dev stack (SC-003)

```bash
uv run manage.py shell < ../apps/mobile/test/backend/seed_backend.py   # in backend
WASSAL_E2E_API=http://localhost:8000 fvm flutter test --tags backend test/backend
```

Expect: the new case syncs a microbus purchase and the first trip start on خط الجامعة, both made
through Lines' path. Both are accepted, with no `not_unlocked`.

## 6. On a device (owner, after merge)

Build: `fvm flutter run --flavor dev`, with `adb reverse tcp:8000 tcp:8000` on the Redmi Note 7.

| # | Do | Expect |
| --- | --- | --- |
| 1 | Fresh install; play the tutorial; open «الخطوط» | `LinesFirst`'s state; no «new» dot during the first session |
| 2 | Earn until the microbus is affordable | the «new» dot on «الخطوط»; opening Lines clears it; a restart keeps it cleared |
| 3 | Airplane mode; buy the microbus | instant; خط الجامعة opens; it syncs when back online |
| 4 | «كمّل» on a line; close the card | back on the line's details |
| 5 | Empty tank; tap a cell | the fuel sheet |
| 6 | TalkBack on Lines and both sheets | the labels and order of research R13 |
| 7 | Time Lines, a line's details and the vehicle sheet from tap to content (SC-008) | under 0.5 s each |
| 8 | Reduced motion on | no slide beyond the design's; the focus card appears without a scroll animation |
