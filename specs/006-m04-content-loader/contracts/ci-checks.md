# Contract: CI Changes and Test Inventory (FR-014, FR-039, constitution XIII)

## `.github/workflows/mobile.yml`

- **`app`, `build-android` and `update-goldens`**: before `flutter pub get`, build the content
  models, whose `.freezed.dart` and `.g.dart` parts are gitignored:

  ```yaml
  - name: content_models build
    working-directory: packages/content_models
    run: |
      dart pub get
      dart run build_runner build -d
  ```

- **`app`**: no other change. `flutter test --coverage` now includes the content loader's tests and
  the new repo guards. The 80% gate stays as it is, and generated parts are already excluded.
- **`packages`**: `content_models` gains `decodeContentJson` and its tests, under its existing 80%
  gate.
- **`build-android`**: still builds `--flavor dev --debug`. A staging or prod build is not added
  until a promoted pack exists. The Gradle check would refuse it before then, by design.
- **Change filter**: unchanged. `apps/mobile/`, `packages/` and `content/` already trigger it.

## `.github/workflows/backend.yml`

- **`content-kit` job**, after `validate-source`:

  ```yaml
  - name: Bundled packs match their sources
    run: |
      uv run wassal-content bundle dev --check --out ../../apps/mobile/assets/content/dev
      uv run wassal-content bundle release --check --out ../../apps/mobile/assets/content/release
  ```

- **Change filter**: add `apps/mobile/assets/content/`, so a change to the bundled files runs the
  job.

## Tests added

| Where | File | Covers |
| --- | --- | --- |
| `packages/content_models/test/` | `strict_json_test.dart` | every refusal of `decodeContentJson`, its JSON path, the depth limit, and the shared canonical vectors |
| `apps/mobile/test/core/content/` | `decode_pack_file_test.dart` | each decoder step and reason code, with the sample pack as the passing case |
| | `pack_content_source_test.dart` | every lookup, ordering and unknown-id case, on the sample pack |
| | `pack_store_test.dart` | reconcile, atomic writes, attempts, unusable, app-version clearing, events cap |
| | `launch_selection_test.dart` | data-model.md "Choosing the active pack at launch", every row |
| | `kill_points_test.dart` | every `KillPoint` (contracts/loading.md), then launch, then the invariants |
| | `content_updater_test.dart` | triggers, throttle, entry rules, the check steps, cancel on background, one at a time |
| | `home_arrival_test.dart` | the switch only on arrival at `/home`, with the real router |
| | `startup_test.dart` | startup waits for content; a damaged bundled pack shows the boot retry |
| | `perf/load_budget_test.dart` | the MVP-size and 2 MiB synthetic packs within their CI budgets (research R15) |
| `apps/mobile/test/core/network/` | `dio_content_remote_test.dart` | against a local `HttpServer`: headers, caps, redirects, status, timeouts, cancel, URL rules, and an MVP-size download at 1 Mbit/s within 30 s (SC-006) |
| | `api_environment_test.dart` | the base URL per flavor and the dev override |
| `apps/mobile/test/repo/` | `bundled_pack_test.dart` | contracts/bundling.md "What refuses a wrong build" |
| | `domain_imports_test.dart` | no Flutter, plugin or `dart:io` import in `lib/core/content/domain/` |
| | `cleartext_config_test.dart` | only the dev source set has a network config, and it permits cleartext for its three hosts only |
| `apps/mobile/test/helpers/` | `content.dart` | the sample `ActiveContent`, a fake `ContentRemote`, temp stores, synthetic packs |
| `apps/mobile/integration_test/` | `content_load_perf_test.dart` | the on-device timing of research R15. Run by the owner on the A06 (quickstart scenario 6), not in CI. |
| `tools/content_kit/tests/` | `test_bundle.py` | the three modes, every failure in contracts/bundling.md, with an injected record fetcher |

The existing repo guards (no Arabic literals, integer money, no raw style values) cover the new
`lib/` files without change.
