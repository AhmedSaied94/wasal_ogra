# Contract: Pack Files, Release Records, Promotion and Version Numbers

This covers how published packs are stored and served (research R5), how production promotes them
(R6), and how staging assigns version numbers (R7), using production's floor file.

## Public files on each host

The host's edge serves these files under `CONTENT_PACKS_PUBLIC_URL`, which is
`https://<api-host>/packs/` today.

| File | Content | Headers |
| --- | --- | --- |
| `core-<v>.json.gz` | The pack file (contracts/content-schemas.md "Canonical form") | `Content-Type: application/gzip`, `Cache-Control: public, max-age=31536000, immutable`, `X-Content-Type-Options: nosniff`, no `Content-Encoding` |
| `core-<v>.release.json` | Its release record (below) | `Content-Type: application/json`, same caching |
| `core.floor.json` | Production only: the highest version production has ever stored ("The floor file", below) | `Content-Type: application/json`, `Cache-Control: no-store`, `X-Content-Type-Options: nosniff` |

- **Anything else** under `/packs/` is a `404`: other names, directories, a listing, hidden files.
  Caddy's `file_server` has browsing off, and path matchers admit only
  `^/packs/core-[0-9]+\.(json\.gz|release\.json)$` and `^/packs/core\.floor\.json$`. On staging,
  `core.floor.json` doesn't exist and answers `404`.
- **Request limits**: `/packs/` gets no request body, and B01's limits stay in force.
- **Rate limits**: Django's throttles don't apply. The edge's connection limits do (backend §13).

## Release record (`core-<v>.release.json`)

Written once, in canonical JSON, when a pack is published on staging.

```json
{"built_at":"2026-11-02T10:00:00Z","min_client_version":"1.0.0","pack_id":"core",
 "published_at":"2026-11-02T10:05:00Z","schema_version":"1.0","sha256":"<64 hex>","size":412233,
 "stages":{"content_rules":"passed","references":"passed","review":"passed","schema":"passed",
           "size":"passed","solver":"passed"},
 "version":12,"warnings":[]}
```

- A stage value is `passed`, `warning` (only for `size`), or `not_available` (only for `solver`,
  and such a pack is never published).
- `warnings` lists the warning findings (`{code, entity, id, path, message}`).
- The record holds no staff names. The **promotion code** is `core-<v>:<sha256 of the record's
  bytes>`, and staging's admin shows it on the pack's page.

## Publish on staging (`CONTENT_ROLE=source`)

1. **Check.** The publisher has `content.publish_pack`. The pack is `validated`, its solver stage
   `passed`, and its version is above the current pack's.
2. **Write both files create-only** (`O_CREAT|O_EXCL`, then `fsync` the file and the directory).
   - If a name already exists with the same bytes, it counts as already stored.
   - If it exists with different bytes, the publish is refused and logged at error level, so it
     reaches Sentry, which emails the operator. The file is not overwritten.
3. **Confirm.** Read both files back and compare their sha256 with the record.
4. **Commit, in one transaction:** `status=published`, `ContentChannel.current`, the
   `PublishedIdentifier` rows, the index rows (R12), retiring the 6th newest, and the audit record.
   `on_commit` deletes the manifest cache.
5. **If anything fails**, the pack stays `validated`, a failed audit record is written, and a
   retry is safe.

## Promotion on production (`CONTENT_ROLE=target`)

**The publisher's input.** The promotion code, pasted from staging's admin, and the version, which
is part of the code. Production's worker then:

| Step | Check | On failure |
| --- | --- | --- |
| 1 | The actor has `content.promote_pack`. The version is above production's current version. The code matches `^core-[0-9]+:[0-9a-f]{64}$`. | Refused, nothing fetched |
| 2 | `GET <CONTENT_PROMOTION_SOURCE_URL>core-<v>.release.json` (10 s timeout, 3 retries on connection errors or `5xx`, at most 64 KiB). Its sha256 equals the code. | Failed: `release_unreachable` or `release_mismatch` |
| 3 | Every stage is `passed` (or a `size` warning), and `solver` is `passed` | Failed: `release_not_passed` |
| 4 | `GET …core-<v>.json.gz` (at most 16 MiB). Its size and sha256 equal the record. | Failed: `pack_unreachable` or `pack_mismatch` |
| 5 | Decompress (at most 32 MiB), parse strictly, and run stages 1–3 against production's schema set. `pack_id`, `version` and `schema_version` equal the record. `min_client_version` is at least the floor for its major. | Failed: `pack_invalid` (findings in the audit record) |
| 6 | Write both files create-only and read them back. Raise the floor file to this version (below). Then commit: `origin=promoted`, `status=published`, `current`, index rows, retiring, audit. `on_commit` deletes the manifest cache. | Failed: `storage_error`. A retry is safe. |

- **Atomic switch.** The current pack changes only at step 6's commit (FR-039a).
- **The floor goes up first.** It is raised before the commit, so it never lags production's
  files. If the commit then fails, the floor is higher than needed, which only skips a number.
- **Failure reasons** are short codes without URLs or secrets. They go in `failure_reason` and the
  audit record.

## The floor file (`core.floor.json`, production only)

The highest version production has ever stored, so staging never reuses a number (FR-039b,
research R7):

```json
{"max_version":14,"pack_id":"core"}
```

- **Format.** Canonical JSON. `max_version` is an integer ≥ 0, and `pack_id` is `"core"`.
- **It only goes up.** Every write is `max(value in the file, new value)`. A restore of
  production's database never lowers it.
- **Atomic.** Write a temporary file in the same directory, `fsync` it, `rename` it over
  `core.floor.json`, then `fsync` the directory. Mode `0644`.
- **Who writes it.** Only production's worker (`CONTENT_ROLE=target`):
  - promotion step 6, after the pack's files are confirmed and before the commit;
  - `content_files sync`, from the highest version among production's stored packs;
  - worker startup, when the file is missing, from the highest version in production's records,
    or 0. So a set-up production host always has it.
- **What it reveals.** Only the highest version number, which production's manifest already shows.
- **If production's whole host is lost,** the file is recreated from production's restored records,
  which may be older. That is still safe: staging assigned every newer number itself, so its own
  records are already above them.

## Version numbers (`CONTENT_ROLE=source`, research R7)

At each build:

1. **Read the floor (staging only).** If `CONTENT_VERSION_FLOOR_URL` is set, the build reads
   `GET <floor-url>core.floor.json` **before** taking any lock:
   - 10 s timeout, 3 retries on connection errors or `5xx`, at most 1 KiB, parsed strictly;
   - `floor = max_version` from the file;
   - any other answer refuses the build with `version_floor_unavailable`, and nothing is assigned.
     That includes a `404`, another status, a timeout, a body over 1 KiB, a body that doesn't parse,
     a wrong `pack_id`, or a `max_version` that isn't an integer ≥ 0.
2. **Assign, under `SELECT … FOR UPDATE` on `ContentChannel`:**
   `n = max(last_assigned_version, imported content/source version, floor) + 1`. Without a floor
   URL (dev, test), `floor` is 0.
3. `last_assigned_version = n`. The draft gets version `n`.

Gaps in production's numbers don't matter. Production may hold 12 and 14, because 13 was a draft
that failed or a staging pack that was never promoted. Its floor file still says 14, so staging's
next build is 15 even after a restore that only knew 12.

Production (`target`) never assigns versions, and its builds don't exist (FR-039).

## Keeping files and records together

`manage.py content_files sync [--verify]` runs daily from beat with `--verify`, and on demand in
the rebuild runbook. For each `published` or `retired` pack:

- if the file or release record is missing, write it from the database (create-only);
- if it is present, with `--verify`, hash it. A mismatch is an error event, and the file is not
  touched.

On production it also raises `core.floor.json` to the highest stored version, never lowering it.
It never deletes, and apart from that floor file it never overwrites. The restore drill's
`content.published_packs_intact` invariant checks the same thing on the database side (data-model
"Invariants").

## Moving to a CDN later (research R5)

Set `CONTENT_PACKS_PUBLIC_URL=https://cdn.<domain>/packs/`, and point `cdn.<domain>` (Cloudflare,
proxied, free plan) at the production edge. Add the host to the edge's site list, which is
configuration. Nothing else changes: URLs are built per response, and files are immutable.
