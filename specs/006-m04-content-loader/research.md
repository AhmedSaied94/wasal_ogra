# Research: Content Pack Loader (M04)

Phase 0 decisions for [plan.md](./plan.md). The spec's Clarifications already fixed three points:
the app becomes `1.0.0`, downloads are in M04, and staging and production builds bundle only
`content/source/`. One more was settled during planning: plain HTTP in dev builds only, which
constitution 1.2.0 now allows (R12). Nothing in the architecture docs is left open for this
feature.

Versions were resolved against pub.dev on 2026-10-21 with `fvm flutter pub add --dry-run`.

## R1. Dependencies

**Decision.**

| Package | Version | Why | Behind |
| --- | --- | --- | --- |
| `content_models` | path `../../packages/content_models` | The generated models (constitution VII) | — |
| `dio` | `^5.11.1` | The locked HTTP client. Streams the manifest and the pack with byte counters, cancel tokens and timeouts. | `ContentRemote` |
| `crypto` | `^3.0.7` | Chunked SHA-256, as in `trip_engine` (M01 plan) | — |
| `path_provider` | `^2.1.6` | The app's private support directory | `PackStore` (takes a directory) |
| `connectivity_plus` | `^7.3.2` | "When a connection comes back" (FR-015). M06 and the offline banner need it too. | `ConnectivitySource` |
| `package_info_plus` | `^10.2.2` | The app's version and build for `X-Client-Version` | `AppInfo` |

Every plugin sits behind an interface the app defines, so tests use fakes (constitution, Architecture
boundaries). The app still doesn't depend on `trip_engine`: M02 adds that dependency.

**Alternatives rejected.**

- `package:http`: dio is the locked client.
- Polling for connectivity: it's slower to notice a connection coming back, and it does background
  work while the app is idle.

## R2. The app's version is 1.0.0

**Decision.** `apps/mobile/pubspec.yaml` goes from `0.1.0+1` to `1.0.0+2` (spec Clarifications).
`X-Client-Version` is `<version>+<build>` from `package_info_plus`, for example `1.0.0+2`. The
server ignores `+BUILD`. A guard test (R13) checks three things:

- the version is at least `min_client_version_by_major["1"]` in `content/schemas/schema-set.json`;
- it is at least the bundled pack's `min_client_version`;
- it parses as `MAJOR.MINOR.PATCH+BUILD`.

**Why.** No pack may declare a minimum below the floor (B04 FR-032), and the manifest offers nothing
to an app below every pack's minimum. The build number goes up so that Play accepts the next upload.

## R3. Strict decoding

**Decision.** A hand-written `decodeContentJson(String text)` in `packages/content_models`, next to
`canonicalJson`:

- It runs `jsonDecode`, then walks the result.
- It refuses `null`, any `double`, integers outside ±(2^53 - 1), lone surrogates, non-string keys,
  nesting deeper than 32 levels, and a root that isn't an object.
- Each refusal throws a `ContentJsonError` with the JSON path.

The loader then calls `Pack.fromJson` (or `Manifest.fromJson`). Fields the models don't know are
ignored, which is B04's FR-008. An unknown enum value throws in the generated code (`$enumDecode`),
and a missing required field throws a `TypeError`. The decode function maps every exception and
error from untrusted bytes to the reason `unreadable`, inside one boundary function (R4).

**Why.**

- The generated code reads every integer as `(json['x'] as num).toInt()`, which turns `1.5` into
  `1` without complaint. The Python loader refuses any decimal point or exponent (B04 R2), and both
  sides must accept the same documents.
- `jsonDecode` returns a `double` for `1.0`, `1e3` and for integers past 64 bits, so refusing doubles
  in the walk catches every non-integer number token.
- It sits in `content_models` because what counts as valid content is a property of the models, as
  `canonicalJson` is. M02's trip records and B08-side tools can reuse it.

**Duplicate keys** aren't visible after `jsonDecode`. That's acceptable here: every byte the app
reads is pinned by a sha256 to a canonical file, which has none. The server built a downloaded file,
and the content kit built the bundled one.

**Alternatives rejected.**

- A hand-written JSON tokenizer: more code and slower, for the duplicate-key case only, which can't
  occur.
- JSON Schema validation on the device: no validator in the locked stack, and the pipeline is the
  authority (spec Assumptions).

## R4. The verification pipeline and its caps

**Decision.** One pure function, `decodePackFile(Uint8List bytes, ExpectedPack expected)`, returns
`PackDecoded(pack)` or `PackRefused(reason)`. It runs these steps in order and stops at the first
failure:

| # | Step | Refusal |
| --- | --- | --- |
| 1 | `bytes.length == expected.size` | `size_mismatch` |
| 2 | SHA-256 of the bytes `== expected.sha256` | `sha256_mismatch` |
| 3 | gzip-decode as a stream, counting output, stopping past 32 MiB | `decompress_too_large`, or `unreadable` for a corrupt stream |
| 4 | Strict UTF-8 decode | `unreadable` |
| 5 | `decodeContentJson`, then `Pack.fromJson` | `unreadable` |
| 6 | `pack_id == "core"` and `version == expected.version` | `wrong_identity` |
| 7 | The `schema_version` major is in the app's supported set, `{1}` | `schema_unsupported` |

- **Isolates.** The loader calls it through `Isolate.run`, so decompressing and parsing never run
  on the UI isolate. `Isolate.exit` hands the parsed `Pack` back without copying. Tests call it
  directly.
- **Caps.** They are production's own promotion caps (B04 contracts/pack-delivery.md): a 16 MiB
  download, which the updater enforces before step 1 (R10), and a 32 MiB decompressed size. The
  manifest body is capped at 64 KiB, as the release record is.
- **Supported majors.** The set is a constant in the loader, `{1}`. A test checks it against the
  majors in `content/schemas/schema-set.json`'s `min_client_version_by_major`, so a schema major
  bump fails the app's tests until the app is taught to read it.

**Alternatives rejected.**

- Hashing after decompressing: that decompresses untrusted bytes, which B04's hand-over forbids.
- Parsing on the UI isolate: a 2 MiB pack would freeze the boot screen and later the trip scene.

## R5. Where packs and their records live

**Decision.**

- **Directory.** `<getApplicationSupportDirectory()>/content/`. It is private to the app, and the
  OS never evicts it.
- **Files.**
  - `core-<v>.json.gz`: a stored pack.
  - `tmp/core-<v>.part`: a download in progress.
  - `state.json`: the record (data-model.md "Content state").
- **Every write is atomic.** Write a temporary file, flush it to disk (`flush: true`), then
  `rename` it over the target. A download is renamed to its final name only after its size and
  sha256 match. `state.json` is written after the files it lists exist, and files it no longer lists
  are deleted after it is written.
- **At launch**, the loader removes `tmp/` and every pack file `state.json` doesn't list. It drops
  `state.json` entries whose file is missing. So a kill at any moment leaves either the old state or
  the new one, with at worst a stray file to delete (FR-028, SC-005).
- **A damaged or unknown `state.json`** counts as empty. Every stored file is deleted, the bundled
  pack is used, and the next check downloads again.

**Why the app support directory.** The OS may clear the cache directory under storage pressure. That
would silently drop the player back to the older bundled content until the next download. External
storage is readable by other apps (FR-032).

**Alternatives rejected.**

- drift now: M05 creates the app database, and mobile §11's `content_cache` can take over this
  record then (hand-over). A database dependency for one record would arrive before its owner
  feature.
- `shared_preferences` for the record: it can't be written atomically together with the files it
  describes.

**Android Auto Backup** includes this directory by default. A restore onto a new phone is safe:
every stored file is checked again at launch, and an app version change clears the unusable list
(R14).

## R6. Choosing the active pack at launch

**Decision.** Startup (`appStartup`) waits for `activeContentProvider`, which works through these
steps (FR-002):

1. Reconcile the directory (R5).
2. Clear `unusable` and `attempts` if `state.app_version` differs from the running app's version and
   build (R14).
3. Collect the candidates: the stored `ready` and `active` entries whose `min_client_version` is at
   most the app's version, and the bundled pack. Sort them by version, highest first.
4. Decode each candidate with its expected values until one passes:
   - a stored entry is checked against its own record;
   - the bundled pack is checked against `bundled.json`.
5. The winner becomes active. The other stored entries are deleted. If the bundled pack wins, all
   stored entries are deleted. Record each stored candidate that failed as `stored_check_failed`.
6. If nothing passes, which needs a damaged install, startup fails, and M03's boot screen shows its
   error and retry (FR-008).

At most 3 candidates exist (an active entry, a ready one and the bundled pack), so the worst case is
3 decodes. The usual case is 1.

## R7. Switching at Home

**Decision.**

- **The ready pack stays in memory.** When a download is verified, the decoded `Pack` stays in
  memory as the ready pack, so the switch is instant. Memory peaks at twice one pack: about 10 MB for
  a 2 MiB pack, well inside the 300 MB budget.
- **What triggers the switch.** A listener on the router's delegate watches the current location.
  When the location becomes the Home destination's path (`/home`, from `routes.dart`) and a ready
  pack exists, the switch runs in one synchronous state change:
  - `ActiveContent` is replaced;
  - `state.json` is written with the ready entry as `active`;
  - the old stored file is deleted.
- **At launch,** R6 makes a ready pack active before Home appears, because startup completes before
  the boot screen hands over.
- **Nowhere else.** The trip, pre-trip and result screens, sheets on top of Home, and every other
  screen have a different location, so a switch can't happen there (FR-024).

**Why.**

- Mobile §14.1 names the Home visit as the swap point.
- Watching the location doesn't depend on how M08 builds Home, or on trip state, which M02 hasn't
  built yet.
- A switch only needs to avoid a trip that is running. A trip resumed after a kill keeps its own
  definition from its replay record (M01 R10).

**Alternatives rejected.**

- Decoding at the moment of arrival: the swap would finish asynchronously and could land after the
  player has left Home for a trip.
- Switching "whenever no trip is running": that needs trip state from M02, and a swap under an open
  apartment or shop screen would change the prices on screen.

## R8. The content source

**Decision.**

- **The interface.** `ContentSource` is an abstract interface in
  `lib/core/content/domain/content_source.dart`, which imports only `content_models`. Its methods
  are in [contracts/content-source.md](./contracts/content-source.md). A guard test forbids
  Flutter, plugin and `dart:io` imports in `lib/core/content/domain/` (constitution I, FR-012).
- **The implementation.** `PackContentSource` builds its lookup maps and ordered lists once per
  pack, and is immutable.
- **Riverpod.**
  - `activeContentProvider` is a keep-alive `AsyncNotifier` (`ContentController`). Its state is
    `ActiveContent {version, origin, source}`.
  - `contentSourceProvider` reads it synchronously after startup (`requireValue`), as M03's
    `configSourceProvider` does.
  - Readers `ref.watch` it, so a switch rebuilds them with the whole new pack at once (FR-011,
    FR-025).

**Why.** One immutable object per pack makes "all or nothing" true by construction: nobody can see
half a switch.

## R9. When the app checks for updates

**Decision.** `ContentUpdater` runs a check:

- once startup has completed;
- on `AppLifecycleListener.onResume`;
- when `ConnectivitySource` goes from no connection to any connection.

Each check is subject to these rules:

- **Throttle.** It runs only if 15 minutes have passed since `state.last_check_at`. The time is
  wall-clock, and a clock earlier than the stored time counts as elapsed, so a wrong clock can delay
  a check by at most one interval. Failed checks count too, which bounds retries. A check
  cancelled because the app left the foreground doesn't count: its previous time is put back, so
  a quick switch to another app doesn't delay the update by 15 minutes.
- **One at a time.** A check or download already running makes a new trigger a no-op.
- **Foreground only.** On `AppLifecycleState.paused`, `hidden` or `detached`, the updater cancels
  its request through dio's `CancelToken` and deletes the partial file. Nothing runs in the
  background (constitution budgets).
- **No player-visible state.** Content updates have no screen (spec Assumptions).

**Alternatives rejected.**

- A periodic timer: it does more work for no fresher content. Packs change at most a few times a
  week.

## R10. The HTTP side

**Decision.** `DioContentRemote implements ContentRemote` is built by a shared factory in
`lib/core/network/http_client.dart`, which M06 extends with the auth interceptor.

| Setting | Manifest | Pack download |
| --- | --- | --- |
| URL | `<api base>/v1/content/manifest` | The entry's `url`, used as given |
| Headers | `Accept: application/json`, `X-Client-Version`, `X-Platform` (`android` or `ios`) | The same two version headers, no `Accept` |
| Connect timeout | 10 s | 10 s |
| Receive timeout | 10 s | 30 s between chunks, and 120 s for the whole file |
| Redirects | Not followed: a `3xx` is a failure | Not followed |
| Body | Streamed and stopped past 64 KiB | Streamed to `tmp/`, hashed chunk by chunk, stopped past the entry's `size` |
| Accepted status | `200` only | `200` only |

- **No redirects.** B04's edge serves both directly, so a redirect is either a fault or a
  downgrade attempt. Refusing it also keeps the HTTPS check (R12) on the URL actually fetched.
- **No certificate pinning.** The hosts use Let's Encrypt, whose certificates rotate, and packs may
  move to a CDN as a server setting (B04 R5). The sha256 chain needs only an authentic manifest,
  which TLS gives.
- **No token.** The manifest is public until B02 (B04 FR-033).

## R11. API addresses per flavor

**Decision.** `lib/core/network/api_environment.dart` maps each `Flavor` to its base URL:

| Flavor | Base URL | Source |
| --- | --- | --- |
| `dev` | `http://localhost:8000`, or the `--dart-define=WASSAL_DEV_API_BASE=…` value | B01 dev stack, reached through `adb reverse tcp:8000 tcp:8000` |
| `staging` | `https://staging-api.141-147-129-92.sslip.io` | `docs/runbooks/provision-host.md` |
| `prod` | `https://api.193-122-74-125.sslip.io` | `docs/runbooks/provision-host.md` |

- **`localhost` with `adb reverse`, not `10.0.2.2`.** The dev stack's manifest hands out
  `CONTENT_PACKS_PUBLIC_URL=http://localhost:8000/packs/`. With `adb reverse`, the same name reaches
  the host from an emulator and from a phone, so manifest and pack URLs both work unchanged.
- **The domain switch.** The delivery plan's domain-switch item gains one line: also edit this file.
  An app release is needed anyway to change a shipped build's API host.

**Alternatives rejected.**

- A JSON asset per flavor: it means an async read at startup, and a release is still needed to
  change it.
- `--dart-define` for every flavor: every build command would need flags, and CLAUDE.md's
  `fvm flutter run --flavor dev` would stop working as written.

## R12. Plain HTTP in dev only (constitution 1.2.0, 2026-10-21)

**Decision.**

- **The dev flavor's exception.** `android/app/src/dev/res/xml/network_security_config.xml`
  permits cleartext for `localhost`, `127.0.0.1` and `10.0.2.2` only.
  `android/app/src/dev/AndroidManifest.xml` points `android:networkSecurityConfig` at it.
- **Staging and prod** keep Android's default for target SDK 36, which refuses cleartext. The app
  also refuses any URL that isn't `https` (FR-018, FR-036): the manifest base and every pack URL.
  Dev accepts `http` only for those three hosts.
- **The INTERNET permission.** `android/app/src/main/AndroidManifest.xml` gains it. Until now only
  the debug and profile manifests had it.
- **A guard test** checks that the main, staging and prod source sets have no network security
  config, and that the dev config permits cleartext for those three hosts and nothing else.
- **iOS** (phase 3) keeps App Transport Security's default.

Constitution 1.2.0 (Security & privacy, amended 2026-10-21) allows exactly this. It allows plain
HTTP from the dev flavor to the developer's own machine, and requires staging and prod to refuse it
in the app and in the platform config, with a test (T034). Planning first recorded it as a
Complexity Tracking exception. `/speckit-analyze` finding C1 showed that an exception with no end
doesn't meet Governance "Exceptions", so the owner made it a rule.

**Alternative rejected.** Local HTTPS for dev (Caddy with an internal CA): it changes B01's dev
stack and needs a CA installed on every emulator and phone. It would still be a dev-only trust
exception.

## R13. Bundling a pack into the app

**Decision.**

- **The command.** `tools/content_kit` gains `wassal-content bundle`:
  - **`bundle dev --out <dir>`** builds `content/examples/sample/` as version 1. It writes
    `core-1.json.gz` and `bundled.json`, whose `min_client_version` is the schema set's floor. The
    file must equal `sample.golden.json`'s sha256.
  - **`bundle release --packs-url <production packs URL> --out <dir>`** reads `content/source/`. It
    builds the pack at its `pack.json` version and fetches `core-<v>.release.json` over HTTPS (at
    most 64 KiB, 10 s timeout). It checks that the record's `sha256` and `size` equal the rebuilt
    file's, and that every stage passed. It then writes `core-<v>.json.gz`, the record copy, and
    `bundled.json` with the record's `min_client_version` and the record's own sha256 (the
    promotion code's hash).
  - **`bundle --check <mode> --out <dir>`** works offline and runs in CI. It rebuilds the pack and
    compares the bytes, checks that `bundled.json` agrees with the file (and with the record copy,
    for release), and runs `validate-source`, which includes M01's speech-slot rule V-T10.
- **The assets.**
  - `apps/mobile/assets/content/dev/` is bundled in the dev flavor.
  - `apps/mobile/assets/content/release/` is bundled in staging and prod. It holds only a
    `README.md` until production's first promotion.
  - Both are flavor-scoped asset directories in `pubspec.yaml`, as M03's `tunables.dev.json` is.
- **The build fails** without a promoted pack (FR-034). A Gradle check on the staging and prod
  variants fails `preBuild` when `assets/content/release/bundled.json` is missing.
- **A guard test in `flutter test`**, which works offline, checks four things:
  - each `bundled.json` agrees with its file's size and sha256;
  - the dev file's sha256 equals `sample.golden.json`;
  - the release version equals `content/source/pack.json`'s, or both are absent;
  - the app version rule (R2).
- **The publisher's step.** The runbook's §3 ("Bring the content back into the repository") gains
  it: after committing the export, run `bundle release`, and commit the three files in the same
  pull request.

**Why.**

- The content kit already holds the only canonical builder and the golden test. Dart's zlib could
  compress the same JSON to different bytes, so the sha256 would never match production's.
- Committed files keep `flutter build` self-contained: no Python on Codemagic or in the Gradle
  build.
- The release record is fetched once, by a person, over HTTPS. CI then checks the copy offline.

**Alternatives rejected.**

- Generating the files during the Flutter build: Python would be needed in every mobile build.
- Fetching from production at build time: the build would need the network and wouldn't be
  reproducible.
- Committing only the export and gzipping it in Dart: the bytes could differ from production's.

## R14. Unusable versions, attempts and reason codes

**Decision.**

- **Attempts.** A size or sha256 mismatch increments `attempts[v]`. The third one marks the
  version unusable with the reason `checksum_failed`. Any failure at steps 3 to 7 (R4) marks it
  unusable at once.
- **Clearing.** `unusable` and `attempts` are cleared when the app version and build differ from
  `state.app_version` (FR-023).
- **Reason codes.** These are recorded in `state.events`, the last 20, each `{at, version?,
  reason}`:
  - `manifest_failed`, with a `detail` of `unreachable`, `status`, `too_large`, `unreadable` or
    `redirect`;
  - `entry_ignored`, with a `detail` of `insecure_url`, `min_client_version` or `unusable`;
  - `too_large`, `download_failed`, `size_mismatch`, `sha256_mismatch`, `decompress_too_large`,
    `unreadable`, `wrong_identity`, `schema_unsupported`;
  - `storage_error`, `stored_check_failed`, `bundled_check_failed`.

  They also go to `dart:developer` `log`. No URL, header or pack content is recorded. M15 reports
  them.

## R15. Performance and how it is measured

**Decision.**

- **CI budget.** A test helper builds two synthetic packs in a temp directory: one of MVP size (50
  trips cloned from the sample, chapters 1 to 4, every pool), and one at 2 MiB compressed, made with
  pseudo-random speech text. A perf test decodes both with `decodePackFile`. Its budgets on the CI
  runner are 300 ms and 1 s, a regression guard; the runner is faster than the A06.
- **On the device.** `integration_test/content_load_perf_test.dart` builds the same two synthetic
  packs on the phone and times `decodePackFile` through `Isolate.run`. The owner runs it on the
  Galaxy A06 with `flutter drive --profile`, alongside M03's `tool/perf/cold_start.sh` (median ≤
  3,000 ms). Targets: SC-002 (≤ 500 ms for the MVP pack), SC-003 (≤ 1.5 s for 2 MiB). This is an
  owner action, as M03's T092 was. The cold start with a real MVP pack is measured again on the
  first prod build after production's first promotion.
- **The load line.** Debug and profile builds print `content: active v<N> (<origin>) in <ms> ms`
  with `debugPrint`.
- **New dev dependency.** `integration_test` (Flutter SDK), with `test_driver/integration_test.dart`.

## R16. Tests

**Decision.**

| Level | What |
| --- | --- |
| `content_models` | `decodeContentJson`: every refusal and its JSON path; vectors shared with `canonicalJson` |
| Decoder | One case per reason code in R4, with the sample pack as the passing case |
| Store and launch | Reconcile, selection order, fallbacks, app-update cases and unusable-list clearing, on real temp directories |
| Kill points | `PackStore` takes a test hook that throws at each numbered step (contracts/loading.md "Kill points"). After each one, launch runs again on the same directory, and the test asserts exactly one verified active pack and no stray files. |
| Updater | Triggers, throttle (fake clock), entry acceptance, attempts, cancel on background, one-at-a-time, with a fake `ContentRemote` |
| HTTP | `DioContentRemote` against a real local `HttpServer` (`dart:io`): manifest size cap, redirect refused, non-200, slow chunks, a body over the declared size, cancel |
| Switching | Widget tests with the real router: a download finishing on the trip and pre-trip placeholders and on a sheet doesn't switch; arriving at `/home` does |
| Guards | Domain imports, the cleartext config, the bundled pack and the app version (R2, R12, R13) |
| Perf | R15 |
| content_kit | pytest for `bundle` in all three modes. The release record comes from an injected fetcher, and the HTTPS check is tested on its own. |

Coverage: ≥ 80% for the app, `content_models` and `content_kit` (constitution XIII). No goldens
change (FR-040).

## R17. Documents

- **`docs/architecture-mobile.md`.**
  - §14.1: the app checks the manifest itself until M06; the bundled-pack source per flavor; the
    switch points; the caps.
  - §11: `content_cache` is the `state.json` record until M05.
  - §5: the `core/content` and `core/network` files.
- **`CLAUDE.md`.** The `bundle` commands, and building `packages/content_models` before the app.
  Also `adb reverse` for dev.
- **`docs/runbooks/content-publishing.md` §3.** The bundling step (R13).
- **`docs/delivery-plan.md`.**
  - Progress: B05 merged in #6, and this feature's line.
  - The domain-switch item: also edit `api_environment.dart`.
- **`docs/owner-actions.md`.** The M04 section, at `/speckit-implement`: the A06 measurements (R15),
  a live update check against staging after its next publish (SC-006), and the first `bundle
  release` after production's first promotion.

## Handed to later features

- **M02:**
  - Read trips and speech pools through `contentSourceProvider`.
  - Record the active content version when a trip starts, in the trip's own record, so its result
    declares the version it was played with, even when a later launch has switched packs.
- **M05:**
  - Read catalog prices through the content source, and declare the active version in ledger
    operations.
  - `state.json` may move into the `content_cache` table.
  - Progress may name a trip the active pack doesn't have, after a fallback to the bundled pack
    (R6). Readers must skip it rather than fail.
- **M06:**
  - Trigger `ContentUpdater.check(force: true)` when bootstrap reports a newer `content.version`.
  - Add the player token through the shared HTTP factory once B02 makes the manifest require it.
    The first online launch then creates the account before its first manifest check.
- **M15:** Report `state.events`.
- **B10:** The force update takes over when the manifest offers nothing (spec Edge Cases).
- **The domain switch** (delivery plan, step 1): also edit `lib/core/network/api_environment.dart`.
