# Contract: Checking for and Downloading New Packs (FR-015 to FR-027)

The client side of B04's `GET /v1/content/manifest` (B04 contracts/api.md) and pack files (B04
contracts/pack-delivery.md). Decisions: research R7, R9 to R12 and R14.

## `ContentRemote` (`lib/core/content/content_remote.dart`)

```dart
abstract interface class ContentRemote {
  /// GET <api base>/v1/content/manifest.
  Future<ManifestResult> fetchManifest({required CancelToken cancel});

  /// Streams entry.url into [target]. Hashes while writing.
  /// Stops past entry.size.
  Future<DownloadResult> download(ManifestPack entry, File target,
      {required CancelToken cancel});
}

sealed class ManifestResult {}   // ManifestOk(Manifest) | ManifestFailed(detail)
sealed class DownloadResult {}   // Downloaded(size, sha256) | DownloadFailed(reason, detail)
                                 // | DownloadCancelled()
```

`DioContentRemote` is the only production implementation, built by `createHttpClient(flavor,
appInfo)` in `lib/core/network/http_client.dart`.

## Requests

| | Manifest | Pack |
| --- | --- | --- |
| Method, URL | `GET <base>/v1/content/manifest`, `<base>` from `apiBaseUrl(flavor)` | `GET <entry.url>`, exactly as given (FR-019) |
| Headers | `Accept: application/json`, `X-Client-Version: <version>+<build>`, `X-Platform: android` (or `ios`) | `X-Client-Version`, `X-Platform` |
| Auth | None (B04 FR-033) | None |
| Timeouts | connect 10 s, receive 10 s | connect 10 s, 30 s between chunks, 120 s total (`timeout`) |
| Redirects | `followRedirects: false`. Any `3xx` → `manifest_failed/redirect`. | Same → `download_failed/redirect` |
| Success | `200` only. Anything else → `manifest_failed/status` (a `429` included) | `200` only → else `download_failed/status` |
| Body cap | 65,536 bytes, counted while streaming → `manifest_failed/too_large` | `entry.size` bytes. One byte more → `too_large`, and the part file is deleted. |
| Parsing | UTF-8, `decodeContentJson`, `Manifest.fromJson`. Any failure → `manifest_failed/unreadable` | None here: `decodePackFile` checks it (contracts/loading.md) |

**URL rules (FR-018, FR-036, research R12).**

- **Staging and prod:** the base URL and every pack URL must be `https`.
- **Dev:** `http` is also allowed for `localhost`, `127.0.0.1` and `10.0.2.2`.

The check runs before any request. Android's network config enforces the same rule underneath
(research R12).

## When a check runs

`ContentUpdater.check({bool force = false})` runs on each of these triggers:

- startup completing (from `ContentController`);
- `AppLifecycleListener.onResume`;
- `ConnectivitySource.changes`, going from `none` to any connection;
- `force: true`, reserved for M06 when bootstrap reports a newer `content.version`. It skips the
  throttle and nothing else.

A check returns at once without doing anything if:

- the last check was less than 15 minutes ago (`now - state.last_check_at < 15 min`, and a
  `last_check_at` in the future counts as elapsed);
- another check or download is running;
- the app isn't in the foreground.

## One check

1. Keep the current `last_check_at` as `previous`, then call `store.markChecked(now)`.
2. `fetchManifest`. On `ManifestFailed`, record `manifest_failed` with its detail and stop.
3. Take the `core` entry (data-model.md "Manifest entry"). If there is none, or nothing is new,
   stop silently. If the entry is ignored, record `entry_ignored` with its detail and stop.
4. `store.beginDownload(v)`, then `download(entry, part)`.
   - `DownloadCancelled`: delete the part file, call `store.restoreChecked(previous)`, and stop,
     with no record. A cancelled check doesn't count toward the 15 minutes (FR-015), so the next
     resume checks again at once.
   - `DownloadFailed`: delete the part file, record the reason and stop.
5. Run `decodePackFile(bytes, expected from entry)` in an isolate.
   - `size_mismatch` or `sha256_mismatch`: `recordFailure` (attempts; the 3rd is
     `checksum_failed`), delete the part file, stop.
   - Any other refusal: `recordFailure` (unusable), delete the part file, stop.
6. `store.commitDownload(v, expected)`. The decoded pack becomes the in-memory ready pack, and any
   older ready pack is dropped.

A `storage_error` at any step deletes the part file, is recorded, and stops. Steps 4 to 6 hold a
`CancelToken` that `AppLifecycleState.paused`, `hidden` and `detached` cancel.

## The switch at Home (FR-024 to FR-027)

`HomeArrival` (`lib/core/content/home_arrival.dart`) listens to `router.routerDelegate`. When the
current path changes from anything else to exactly `/home` (the Home destination's path in
`routes.dart`), it calls `ContentController.switchIfReady()`. That method does all of this
synchronously, in one state change:

1. If there is no ready pack, it returns.
2. It sets `state = AsyncData(ActiveContent(ready))`.
3. It calls `store.activate(ready.version)`. The file deletion is awaited off the frame, and a
   storage error there is recorded and cleaned at the next launch.

At launch, `ContentController.build` has already made a ready pack active before the boot screen
hands over (contracts/loading.md "Launch").

**It never switches** on `/home/pre-trip/:tripId`, `/trip/:tripId`, `/trip/:tripId/result`, a sheet,
or any other screen. It also never switches while Home is already showing: only an arrival counts.

## What the player sees

Nothing. There is no banner, toast or «محتاج نت» mark for content updates (spec Assumptions). A
failure is only an event in `state.json`.
