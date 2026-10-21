# Contract: Loading and Verifying a Pack (FR-001 to FR-008, FR-028 to FR-032)

How the app turns pack bytes into active content, and how it keeps the files on the device
consistent. Decisions: research R3 to R6 and R14.

## `decodePackFile`

```dart
/// Pure Dart (dart:io's gzip, package:crypto, package:content_models).
/// Called through Isolate.run.
PackDecodeResult decodePackFile(Uint8List bytes, ExpectedPack expected);

sealed class PackDecodeResult {}
final class PackDecoded extends PackDecodeResult {
  final PackContentSource source;   // indexed in this isolate
  final int canonicalBytes;         // decompressed length, for the perf log
}
final class PackRefused extends PackDecodeResult {
  final RefusalReason reason;
}
```

**Steps, in order.** Nothing is decompressed before steps 1 and 2 pass.

| # | Check | Refusal |
| --- | --- | --- |
| 1 | `bytes.length == expected.size` | `size_mismatch` |
| 2 | `sha256(bytes) == expected.sha256` | `sha256_mismatch` |
| 3 | gzip decodes, at most 33,554,432 bytes (32 MiB) out | `decompress_too_large`, or `unreadable` |
| 4 | Strict UTF-8 (`utf8.decode`, `allowMalformed: false`) | `unreadable` |
| 5 | `decodeContentJson` (content_models), then `Pack.fromJson` | `unreadable` |
| 6 | `pack.packId == 'core'` and `pack.version == expected.version` | `wrong_identity` |
| 7 | The major of `pack.schemaVersion` is in `supportedSchemaMajors` (`{1}`) | `schema_unsupported` |

- Every exception or error thrown while running steps 3 to 5 on these bytes becomes `unreadable`.
  This is the one place untrusted bytes meet generated code, so it is the one boundary that catches
  broadly.
- The function has no I/O and no clock, so the same bytes always give the same result.

## `decodeContentJson` (`packages/content_models`, hand-written)

```dart
/// jsonDecode, then a walk that refuses what B04's Python loader refuses.
/// Throws ContentJsonError(path, message).
Map<String, Object> decodeContentJson(String text);
```

It refuses `null`, any `double`, integers outside ±9,007,199,254,740,991, lone surrogates in strings
or keys, nesting deeper than 32, and a root that isn't an object. The manifest is read the same way
(contracts/updates.md).

## `PackStore`

It owns `<dir>/` (production: `<app support>/content/`; tests: a temp directory) and is the only
writer of `state.json` and the pack files.

| Operation | Effect |
| --- | --- |
| `reconcile()` | Deletes `tmp/`, every `core-*.json.gz` that `state.json` doesn't list, and every entry whose file is missing. A `state.json` with an unknown `format`, or one that doesn't parse, counts as empty. |
| `beginDownload(v)` | Opens `tmp/core-<v>.part` for writing |
| `commitDownload(v, expected)` | Flushes the part file, renames it to `core-<v>.json.gz`, writes `state.json` with the entry as `ready`, then deletes the older `ready` entry's file, if any |
| `activate(v)` | Writes `state.json` with `v` as `active` and without the old `active` entry, then deletes that entry's file |
| `dropStored()` | Writes `state.json` with no stored entries, then deletes their files (the bundled pack won) |
| `recordFailure(v, reason, detail)` | Updates `attempts` or `unusable` (research R14) and appends an event |
| `setAppVersion(av)` | If `av` differs, clears `unusable` and `attempts`, and records `av` |
| `markChecked(at)` | Sets `last_check_at` |
| `restoreChecked(previous)` | Puts `last_check_at` back to `previous`, or removes it when `previous` is null. Used only when a check is cancelled (contracts/updates.md "One check"). |

**Atomic writes.** Each write of `state.json` goes to `state.json.tmp`, flushed, then renamed over
`state.json`. A pack file is renamed into place only after it is complete. Files are deleted only
after the `state.json` that drops them is written.

**Kill points.** `PackStore` takes an optional `void Function(KillPoint)` hook that tests use to
throw at each of these points, then rerun the launch on the same directory:

| `KillPoint` | Between |
| --- | --- |
| `partWritten` | the last chunk and the flush |
| `partFlushed` | the flush and the rename |
| `renamed` | the rename and the `state.json` write |
| `stateWritten` | the `state.json` write and deleting the superseded file |
| `activateStateWritten` | `activate`'s `state.json` write and deleting the old active file |

After every kill point, the next launch ends with exactly one verified active pack, data-model.md's
invariants hold, and no stray file is left (SC-005).

## Launch (`ContentController.build`)

1. `store.reconcile()`, then `store.setAppVersion(appInfo.versionWithBuild)`.
2. Candidates: the stored entries whose `min_client_version` ≤ the app's version, plus the bundled
   pack (`bundled.json` and its file, read from the asset bundle). Sort by version, descending.
3. For each candidate, read its bytes and run `decodePackFile` in an isolate. The first
   `PackDecoded` wins.
   - A refused stored candidate: an event `stored_check_failed`, and its entry and file are removed.
     No attempt is counted and the version isn't marked unusable, so the next check downloads it
     again (spec US3-7).
   - A refused bundled pack: event `bundled_check_failed`.
4. If a stored entry won and is `ready`, call `store.activate(v)`. If the bundled pack won, call
   `store.dropStored()`.
5. If no candidate passed, throw `ContentUnavailable`. `appStartup` fails, and the boot screen shows
   its retry.
6. In profile and debug builds, print `content: active v<N> (<origin>) in <ms> ms` with
   `debugPrint`, so it shows in `flutter logs` (research R15). Release builds print nothing.

## Reason codes (`RefusalReason`, `state.events[].reason`)

| Reason | `detail` values | Raised by |
| --- | --- | --- |
| `manifest_failed` | `unreachable`, `status`, `too_large`, `unreadable`, `redirect` | updater |
| `entry_ignored` | `insecure_url`, `min_client_version`, `unusable` | updater |
| `too_large` | — | updater: the entry's `size` exceeds 16 MiB, or the body exceeds the entry's `size` |
| `download_failed` | `unreachable`, `status`, `redirect`, `timeout` | updater |
| `size_mismatch`, `sha256_mismatch` | — | decoder steps 1 and 2 (attempts) |
| `checksum_failed` | — | the 3rd size or sha256 failure of one version (moves it to `unusable`) |
| `decompress_too_large`, `unreadable`, `wrong_identity`, `schema_unsupported` | — | decoder steps 3 to 7 (`unusable` at once) |
| `storage_error` | — | a failed write, rename or delete. The download is discarded and retried later. |
| `stored_check_failed` | the decoder reason | launch |
| `bundled_check_failed` | the decoder reason | launch |

A cancelled download isn't recorded: it isn't a failure.
