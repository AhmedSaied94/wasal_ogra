# Quickstart: Content Pack Loader (M04)

How to run and check this feature. The contracts hold the details. This guide only lists the steps
and what you should see.

## Prerequisites

- FVM and the pinned Flutter (`.fvmrc`), uv, Docker. An Android emulator or a phone with USB
  debugging.
- The backend's local stack for scenario 3 (`backend/`, CLAUDE.md "Backend commands").

## Setup

```bash
# The content models' generated parts, which the app now imports
cd packages/content_models && fvm dart pub get && fvm dart run build_runner build -d
# The app
cd ../../apps/mobile && fvm flutter pub get && fvm dart run build_runner build -d
```

## 1. Automated checks

```bash
# In apps/mobile: format, analyze, every test including the loader, the guards and the CI perf budget
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm flutter analyze --fatal-infos
fvm flutter test --coverage && fvm dart run tool/check_coverage.dart --min 80

# In packages/content_models: the strict decoder
fvm dart test

# In tools/content_kit: the bundle command and the bundled files
uv run pytest tests/test_bundle.py
uv run wassal-content bundle dev --check --out ../../apps/mobile/assets/content/dev
uv run wassal-content bundle release --check --out ../../apps/mobile/assets/content/release
```

**Expected**: everything passes. `--check release` passes with only `README.md` in the release
directory until production's first promotion.

## 2. First launch with no network (US1)

```bash
# In apps/mobile
fvm flutter run --flavor dev
```

Turn on airplane mode, clear the app's storage, then open it again.

**Expected:**

- The boot screen hands over to الموقف.
- `flutter logs` shows `content: active v1 (bundled) in <ms> ms`.
- No request is attempted while offline. When the connection comes back, the updater checks once.

## 3. A new pack arrives from the local stack (US2)

1. Start the stack and forward its port to the device:

   ```bash
   cd backend && docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait
   adb reverse tcp:8000 tcp:8000
   ```

2. Import the sample, then review its speech lines and publish in the dev admin at
   `http://localhost:8001/admin/`:

   ```bash
   uv run manage.py content_import ../content/examples/sample --actor <staff>
   ```

   On a fresh stack this publishes version 1, the same bytes as the bundled pack. Then change one
   speech line, review it, build and publish again: version 2 (`docs/runbooks/content-publishing.md`
   §1).
3. Clear the app's storage, open it, and go from الموقف to الخطوط and back.

**Expected:**

- `curl -s localhost:8000/v1/content/manifest` shows version 2.
- After the round trip, `flutter logs` shows `content: active v2 (stored)`.
- Reopening the app within 15 minutes makes no request. After the app is killed and reopened, v2
  is still active and is checked again before it is read.

## 4. A bad download never becomes active (US3)

The cases (tampered, truncated, oversized, a redirect, unreadable, a wrong version, every kill
point) run against a local HTTP server and real temp directories in
`test/core/content/` and `test/core/network/`:

```bash
fvm flutter test test/core/content test/core/network
```

**Expected**: every case passes. `kill_points_test.dart` reports one verified active pack after
each kill point.

## 5. A staging or prod build without a promoted pack fails (US4)

```bash
fvm flutter build apk --flavor staging --debug
```

**Expected**, while `content/source/` is empty: the build stops at `checkBundledPack` with "No
promoted pack is bundled…". After production's first promotion, the publisher runs `bundle release`
(contracts/bundling.md) and the same build succeeds.

## 6. Reference-device timing (SC-002, SC-003, owner)

On the Galaxy A06, in profile mode:

```bash
fvm flutter drive --profile --flavor dev \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/content_load_perf_test.dart
```

**Expected:**

- The MVP-size synthetic pack decodes in ≤ 500 ms.
- The 2 MiB pack decodes in ≤ 1.5 s.
- The cold start to الموقف (M03's `tool/perf/cold_start.sh`) stays at a median ≤ 3,000 ms. With a
  real MVP pack, that is measured again on the first prod build after production's first promotion.

## Done when

- [ ] Scenarios 1 to 5 pass. Scenario 6 is recorded in `docs/owner-actions.md`.
- [ ] CI is green: mobile (app, packages, build-android) and backend (`content-kit`, with the
  bundle checks).
- [ ] The app loads the bundled pack and verifies its sha256 (delivery plan, step 4).
