# Research: Content Pipeline (B04)

Phase 0 of [plan.md](./plan.md). Each section gives the decision, why, and what was rejected. The
open item this feature had to settle, backend §22.3 (a CDN for packs), is R5. Facts that came from a
lookup are dated 2026-10-19.

## R1. Generating the app models and the server models

**Decision.** One in-house generator, `wassal-content codegen`, in the shared Python package
`tools/content_kit` (R13). It reads `content/schemas/` in the restricted profile of R3, builds one
intermediate description of every type, and writes from it:

- the server models: Pydantic v2 classes in
  `tools/content_kit/src/wassal_content/models/_generated.py`;
- the app models: freezed + json_serializable sources in
  `packages/content_models/lib/src/generated/<part>.dart`. `build_runner` then produces their
  `.freezed.dart` and `.g.dart` parts, which stay gitignored as everywhere else in the repo.

Both outputs are committed and start with a "generated, do not edit" header. CI regenerates them and
fails on any difference (FR-007). The Dart files carry `// dart format off`, and ruff excludes the
Python file, so formatters never rewrite generated code and the diff stays exact. Mapping rules,
the same for both languages:

| Schema | Python (Pydantic v2) | Dart (freezed) |
| --- | --- | --- |
| object with `properties` | `BaseModel`, `extra="ignore"`, `frozen=True` | `@freezed` class, `fromJson`/`toJson` |
| required property | required field | `required` named parameter |
| optional property | `T \| None = None`, omitted on output | `T?`, `includeIfNull: false` |
| `integer` | `int` (strict) | `int` |
| `string` (with `enum`) | `StrEnum` | `enum` with `@JsonValue` |
| `integer` `enum` (denominations) | `IntEnum` | `enum` with `@JsonValue` |
| `array` | `tuple[T, ...]` | `List<T>` |
| map (`additionalProperties` + `propertyNames`) | `dict[K, V]` | `Map<String, V>` |
| `$ref` | the referenced class | the referenced class |
| property name not a valid identifier (`ar-EG`) | `Field(alias="ar-EG")`, `by_alias` | `@JsonKey(name: 'ar-EG')` |

Unknown fields are ignored on both sides (FR-008). Class names come from each `$defs` key or root
`title`, so the two languages always use the same names.

Every Dart class is `@Freezed(copyWith: false, toStringOverride: false, map:
FreezedMapOptions.none, when: FreezedWhenOptions.none)`. Content definitions are read, never
changed or matched on, so a copy method and the pattern helpers are dead code. freezed's parts
contain members no test can reach (the mixin's `==` and `hashCode`, which the concrete class
overrides), so M03's coverage gate excludes `*.freezed.dart` the way it already excludes `*.g.dart`.
The round-trip test compares `fromJson(toJson(x)) == x` too, which exercises the concrete `==` and
`hashCode`.

Versions:

- Python: `pydantic==2.13.5` (2026-08-28; 2.14.x is under two weeks old).
- Dart: `freezed ^4.0.2` (2026-09-18) with `freezed_annotation ^3.1.0`, `json_serializable ^6.14.1`
  with `json_annotation ^4.12.0`, `build_runner ^2.16.2`, and `test` and `lints` at their current
  versions.
- The package targets the app's SDK floor (`^3.13.0`), so it works with the FVM-pinned Flutter
  3.47.7.

**Why.**

- The engine, the app, the solver and the backend must read every field the same way. One
  generator with one type map guarantees that. The round-trip test (FR-009) then proves it.
- The Dart options are weak:
  - `json_schema_to_freezed` 1.0.1 has 5 likes, an unverified uploader and its last release 17
    months ago. Its examples are draft-07, and it doesn't document `$defs` or cross-file `$ref`.
  - `schema2dart` 1.0.4 has 4 likes and an unverified uploader, and generates neither freezed nor
    json_serializable code.
  - quicktype emits draft-06 and works best from sample JSON.
- Our profile is small (R3), so the generator stays small: about 500 lines plus tests.

**Alternatives rejected.**

- `datamodel-code-generator` 0.86.0 for Python only. It's mature, but its naming and optionality
  rules differ from any Dart tool. Matching two generators' quirks costs more than the shared
  generator.
- Hand-written models: forbidden (constitution VII).
- Plain Dart classes instead of freezed: possible, but the locked stack names freezed +
  json_serializable for mobile models.
- Generating at build time only, without committing: the mobile build would then need Python, and
  reviewers couldn't see the models in a PR.

## R2. Validating against the schemas

**Decision.**

- **Validator.** `jsonschema==4.26.0` with `referencing==0.37.0`, using `Draft202012Validator`. A
  `referencing.Registry` holds every schema file under its `$id`, so cross-file `$ref`s resolve with
  no network access.
- **Parsing.** Every pack and every `content/source` file is parsed with `json.loads(...,
  parse_float=reject, parse_constant=reject)`. A decimal point or an exponent anywhere, even in
  `1.0`, is refused before validation. JSON Schema's `integer` accepts `1.0`, and FR-003 doesn't.
- **Untrusted input.** Imports come from outside, so the loader also refuses, each with its line
  and column:
  - duplicate keys, invalid UTF-8 and a byte-order mark;
  - integers outside I-JSON's range, ±(2^53 - 1) (RFC 7493), which Dart and Python read alike;
  - strings or keys holding a lone surrogate, which have no UTF-8 encoding;
  - nesting deeper than 32 levels (content nests about 8), so no recursive reader downstream can
    run out of stack.

  Everything it refuses raises its own error type, never a parser or interpreter error.
- **Errors.** Each one reports `error.json_path`, which becomes the field in the report (FR-021).

**Why.**

- jsonschema is the reference Python implementation of 2020-12, and backend §2 already lists it.
- `referencing` is its supported way to resolve refs offline.

**Alternatives rejected.**

- `fastjsonschema`: its 2020-12 support is incomplete, and its error paths are poorer.
- Validating through the Pydantic models only: they can't express patterns, `multipleOf`, or the
  cross-record rules.

## R3. The schema profile, the schema version and breaking changes

**Decision.**

- **The profile.** The schemas use only these keywords:
  - `$schema`, `$id`, `$defs`, `$ref`, `title`, `description`, `$comment`;
  - `type`, but only `object`, `array`, `string`, `integer` and `boolean`;
  - `properties`, `required`, and `additionalProperties`, either `false` or a schema together with
    `propertyNames` for maps;
  - `enum` and `const`;
  - `minimum`, `maximum` and `multipleOf`;
  - `minLength`, `maxLength` and `pattern`;
  - `items`, `minItems`, `maxItems` and `uniqueItems`.

  `null`, `number`, `default`, `oneOf`, `anyOf`, `allOf`, `if`, `then`, `else` and `not` are not
  allowed. Bounds are integers within ±(2^53 - 1) (`multipleOf` at least 1, lengths and counts at
  least 0), and `uniqueItems` is a boolean. A `pattern` starts with `^`, compiles, and spells out
  its classes: `\d`, `\w`, `\s` and `\b` match different characters in ECMA-262 and Python. A
  final unescaped `$` is matched as ECMA-262's end anchor (`\Z` in Python). A profile check runs
  in CI, and the generator refuses anything outside the profile.
- **Strictness.** Every object is `additionalProperties: false`, so a typo in authored content is an
  error. Old apps still read newer packs, because the models ignore unknown fields (FR-008); only
  the server and CI validate.
- **Optional fields** are left out of a document instead of being set to `null`. The canonical form
  therefore has no `null`, and Python and Dart write the same bytes.
- **One version for the whole set.** `content/schemas/schema-set.json` holds
  `{"version": "1.0", "min_client_version_by_major": {"1": "1.0.0"}}`. Every pack carries
  `schema_version`. Raising the set's major version satisfies FR-010's "raise that schema's major
  version" for whichever schema broke.
- **The breaking-change check.** `wassal-content schema-diff --base origin/master` compares the two
  schema sets within the profile. It reports:
  - a property removed or renamed, or its type changed;
  - an enum value removed, or `minimum`/`maximum`/`pattern`/`maxLength` tightened;
  - a property newly required;
  - `additionalProperties` changed from a schema to `false`.

  CI fails when the change breaks but the set's major version didn't go up. The check is active only
  once `content/source/pack.json` exists, which happens with the first export of a pack promoted to
  production (FR-040). That is exactly FR-010's "once a pack has been published in production",
  without a manual switch.
- **The app-version floor** for FR-032 is `min_client_version_by_major[major]`. A PR that raises the
  major version must add its floor.

**Why.**

- The profile keeps the generator small and the two languages identical (R1).
- No `null` and no `default` means "absent" has exactly one representation.
- A single set version is one thing to bump and one value in the pack.
- Deriving "stable" from `content/source` removes a step the owner could forget.

**Alternatives rejected.**

- A version per schema file: it multiplies bookkeeping, and a pack would need several versions.
- `json-schema-diff` (npm): it adds a Node toolchain to backend CI and doesn't know our profile.
- A manual `stable: true` flag: it's easy to forget.

## R4. The canonical form and the checksum

**Decision.**

- **Canonical JSON.** The RFC 8785 (JCS) rules restricted to our data: UTF-8, keys sorted by UTF-16
  code units (our keys are ASCII, so code-point order is identical), no whitespace, minimal string
  escaping as `JSON.stringify` does it, and integers only (R2). Python gets it with
  `json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)` on data that has no
  floats. Dart gets it with `jsonEncode` over a recursively key-sorted map, in a small hand-written
  helper next to the generated models. Both refuse what the loader refuses (R2): `null`, floats,
  integers outside ±(2^53 - 1) and lone surrogates.
- **The pack file** is `gzip.compress(canonical, compresslevel=9, mtime=0)`, with no file name in
  the header.
- **The `sha256`** in the manifest, the pack record and the release record is the SHA-256 of the
  **gzip file as served**. The app checks it before it decompresses or parses anything (M04).
- **Determinism, checked 2026-10-19.** A 2.6 MB Arabic-heavy JSON compressed at level 9 with
  `mtime=0` gave byte-identical output under the local uv Python (python-build-standalone, zlib
  1.3.2) and under `python:3.13.16-slim-trixie` (Debian zlib 1.3.1), which is the backend image's
  runtime.
- **The golden test.** CI keeps a committed golden checksum for the sample pack, for both the
  canonical JSON and the gzip file. A future change of compressor, such as zlib-ng, shows up as a
  red test, not a silent difference (FR-011, SC-004).
- **Size** in the manifest is the gzip file's byte length.

**Why.**

- Checking the file as downloaded means nothing untrusted is decompressed before it is verified.
- Sorted keys and integer-only data make the bytes independent of how a dict or map was built.

**Alternatives rejected.**

- A checksum over the uncompressed JSON: it would survive a compressor change, but the app would
  have to decompress unverified bytes first. The measurement above shows the compressor is stable.
  The golden test guards the rest.
- Serving with `Content-Encoding: gzip`: HTTP clients decompress transparently, and the app could
  no longer check the file it got.

## R5. Where packs are served, and a CDN (resolves backend §22.3)

**Decision.**

- **Each host's edge serves its own packs**, from a local directory, under `/packs/` on that
  environment's API hostname. There is no object storage and no CDN for the MVP.
- **Writing.** The worker writes each published file to `/var/lib/wassal/packs/` with create-only
  semantics (`O_CREAT|O_EXCL`) and confirms its checksum by reading it back.
- **Serving.** The edge's Caddy mounts the directory read-only and serves it with
  `Cache-Control: public, max-age=31536000, immutable`, `Content-Type: application/gzip`, and no
  directory listing. The API container doesn't mount it.
- **The database is the source of truth.** Each pack record also stores the gzip bytes (at most a
  few MB per pack), so production's nightly backup covers every promoted pack. A `content_files
  sync` job rewrites a missing file from the database and never overwrites a different one: it
  alerts instead.
- **Pack URLs** are `CONTENT_PACKS_PUBLIC_URL` + file name, built when the manifest is served, never
  stored. Moving to `cdn.<domain>` is therefore one setting (B01 FR-042a).
- **Backend §22.3 is resolved as "no CDN in the MVP".** Put Cloudflare's free plan in front of a
  `cdn.<domain>` hostname, whose origin is the production edge, only once the real domain exists and
  load calls for it. Pack files are immutable and `.gz` is in Cloudflare's default cache list, so
  that is a DNS change plus the base URL.

**Why.** The numbers are for the MVP, with about 30k monthly players and a new pack each week:

- **Origin requests.** Each player downloads each new pack once, which is about 4 × 30k = 120k
  downloads a month. OCI Object Storage's Always Free tier allows 50,000 API requests a month across
  all operations, according to Oracle's terms as mirrored by third parties. That would fail SC-012
  at MVP load. The edge has no request cap.
- **Bandwidth.** 120k × about 0.5 MB is about 60 GB a month, well inside the 10 TB of outbound
  traffic Always Free includes. At the 100k DAU design point it is about 200 GB.
- **Cost and keys.** USD 0, no third-party account, and no storage key to leak. The "write key" of
  FR-037 is the directory's write permission, which only the worker container has. The API never
  holds it.
- **Separation.** It is separate from Backblaze B2 by construction (B01 handover). Each host serves
  only its own directory, so there is one set of packs per environment.
- **Immutability.** The worker creates files and never rewrites them. The edge mounts the directory
  read-only. Losing the directory loses nothing, because the database holds every file.
- **Statelessness.** The constitution asks code to stay stateless. The directory is a cache of
  database rows, so the scale path in backend §15 stays open. When there are several API hosts, the
  base URL moves to object storage behind the CDN.

**Alternatives rejected.**

- **OCI Object Storage, public bucket.** It works technically:
  - "read without list" visibility;
  - a create-only IAM policy without `OBJECT_OVERWRITE`;
  - one bucket and one customer secret key per environment.

  But 50k requests a month is below MVP demand, and Cloudflare in front of it needs the domain plus
  a Host-header override. It stays the scale-path option.
- **Cloudflare R2.** Production use needs a custom domain on Cloudflare, since `r2.dev` URLs are
  rate-limited. Enabling it asks for a payment method.
- **A packs bucket in Backblaze B2.** Free egress is only 3× the stored data unless it is fronted by
  Cloudflare. It would also mix packs into the backup account, which the B01 handover warns
  against.
- **Django streaming packs from the database.** It ties up gunicorn workers on 0.5 MB responses at
  peaks. Caddy's `sendfile` is free.

## R6. Promotion from staging to production (FR-039a)

**Decision.** Production pulls from staging over staging's public API hostname. A code the
publisher carries from one admin to the other anchors the transfer.

1. **Staging publishes two files.** When a pack is published on staging, the worker writes
   `core-<v>.json.gz` and `core-<v>.release.json`. The release record is canonical JSON holding:
   - `pack_id`, `version`, `schema_version`, `sha256`, `size` and `min_client_version`;
   - `built_at` and `published_at`;
   - each validation stage's result (`passed`, `warning` or `not_available`) and the warning
     findings.

   It holds no staff names and no personal data, because it is public.
2. **The promotion code.** Staging's admin shows `core-<v>:<sha256 of the release record>`.
3. **The publisher pastes it into production's admin**, on the "Promote" form. The publisher's
   device is on both private networks (B01).
4. **Production's worker fetches and checks the release record** from `CONTENT_PROMOTION_SOURCE_URL`
   (staging's `/packs/` URL), with a 10 s timeout and retries. Its hash must equal the code. Every
   stage must be `passed` or a warning, and `solver` must be `passed` (FR-022).
5. **It fetches and checks the pack:** its size and sha256 must match the record. It decompresses
   with a 16 MiB cap, parses it with the strict loader (R2), and re-runs the stages that work on the
   pack alone: schema, references and content rules (R9). It checks that the version is higher
   than production's current one.
6. **It stores and switches.** It writes both files create-only (R5), stores the record with the
   gzip bytes, fills the version lookups (R12), makes the pack current, and records the promotion in
   the audit log. Any failure leaves the current pack in place, and a retry is safe: the same bytes
   at an existing name count as already stored.

**Why.**

- No credential crosses hosts. Production reaches only a public URL and doesn't need staging's
  admin or private network (B01 isolation).
- A pasted SHA-256 can't be forged by anyone who controls the network path, and HTTPS adds
  transport integrity. If staging itself were compromised, so would its authoring be, and
  production still re-validates the file.

**Alternatives rejected.**

- **Signing release records with a staging key.** It adds key management and rotation, and buys
  nothing the pasted hash doesn't already give, as long as a human starts every promotion.
- **Uploading the pack file through production's admin.** It works, but the publisher handles
  files by hand, and the report wouldn't travel with them.
- **Production calling staging's admin API.** That needs cross-host credentials and reachability
  that B01 forbids.

## R7. Version numbers come only from staging (FR-039b)

**Decision.** At each build on staging, the next version is `max(A, B, C) + 1`:

- **A**: the highest version in staging's own records;
- **B**: the version in `content/source/pack.json` from the last import, if any;
- **C**: the highest version production has ever stored, read from production's public **floor
  file**, `<CONTENT_VERSION_FLOOR_URL>core.floor.json`.

The floor file is canonical JSON, `{"max_version":14,"pack_id":"core"}`. Production's worker
maintains it (contracts/pack-delivery.md "The floor file"):

- **It only goes up.** Each write is `max(value in the file, new value)`, as an atomic replace.
- **It never lags.** A promotion raises it after the pack's files are confirmed and before the
  commit that makes the pack current. If that commit then fails, the floor is one higher than
  needed, which only skips a number.
- **It is always there.** The worker creates it at startup when it is missing, from the highest
  version in production's records, or 0.

Staging reads the file before taking the row lock, so a slow production never holds the lock. Any
answer other than a valid file, a `404` included, refuses the build with `version_floor_unavailable`
and assigns nothing. A set-up production host always has the file, so a `404` means something is
wrong. On dev and test, no floor URL is set and only A and B apply.

The number comes from a row lock on the `ContentChannel` row, so concurrent builds never share one.
Production never assigns a number. It keeps staging's (FR-039a).

**Why.** Production's own record of what it stored is the ground truth, and the floor file
publishes exactly that:

- **No credentials.** Reading it needs none, and it doesn't depend on whether B02 puts the manifest
  behind a token.
- **Nothing to leak.** It shows only the highest version number, which the manifest already shows.
- **It survives a database restore.** It sits on production's disk next to the pack files, and
  restoring production's database never lowers it.

A, B and C together cover:

- a staging restore from a backup up to 24 hours old (R8);
- a staging rebuilt from `content/source` only;
- a staging rebuilt from nothing, where C alone is enough;
- production rebuilt from an older backup, where the recreated floor file may be lower than before
  but staging's A is still above every number production used.

**Alternatives rejected.**

- **Probing production's pack files upwards until the first missing one.** Production's numbers
  have gaps by design: a draft that fails validation still takes a number, and so does a pack
  published on staging but never promoted. Say production holds 12 and 14 and staging is restored
  from a backup that knows only 12. The probe stops at 13, which is below production's newest
  version, so it breaks FR-039b.
- Reading production's manifest: B02 may put it behind a player token (FR-033).
- A floor the operator sets by hand after a rebuild: it's easy to forget, and it fails silently.
- Letting production refuse duplicates as the only guard: it's safe, but staging and production
  would hold different packs under the same number, which breaks bundling (FR-036).

## R8. Recovering staging's authoring work (FR-039c)

**Decision.**

- **Run B01's nightly backup job on the staging host too.** The `backup_db` command and the
  `wassal-backup@.timer` template are already environment-agnostic. Its target is staging's own
  Backblaze B2 buckets, `wassal-staging-backup-daily` (14 days) and
  `wassal-staging-backup-weekly` (56 days), with:
  - a **write-only staging key** that is not production's;
  - its own Healthchecks.io check;
  - the same Object Lock and USD 0 caps.

  Production's backups and the drill key are untouched.
- **Recovery.** Restoring staging is the restore runbook with staging's buckets. If no backup is
  usable, import `content/source` (last promoted state), then rebuild version numbering from R7.
- **Speech-line reviews.** They are authoring metadata and are not in `content/source`. After a
  fallback import, lines need reviewing again; the bulk "mark reviewed" action makes that quick.

**Why.**

- It reuses a tested job, its alerts and its runbook, and adds only configuration and owner setup.
- 24 hours matches production's recovery point (backend §15).
- The dump also brings back staging's pack records, audit log and permanent identifiers (FR-016).

**Alternatives rejected.**

- **A content-only export to B2.** It's new code and a new format, and loses the admin change
  history.
- **Nightly pull requests from staging into `content/source`.** That needs a GitHub token on the
  host, and turns every draft into a commit.
- **Keeping B01's "staging is not backed up" assumption.** It contradicts FR-039c now that authors
  work on staging.

## R9. Authoring data, the admin and roles

**Decision.**

- **App.** A new Django app, `apps/content`, with relational authoring models: UUIDv7 primary keys,
  and each glossary identifier as a unique field (data-model.md). Admin inlines edit the nested
  parts:
  - trip stations, passengers and events on the trip page;
  - seats on the vehicle page;
  - item variants on the item page;
  - scene lines on the scene page;
  - speech lines on the pool page.

  Foreign keys stop a station, seat or item being deleted while something refers to it (FR-013).
- **Arabic text.** Every Arabic field has two columns, `<name>_ar_eg` (required) and `<name>_ar`
  (optional). Their widgets carry `dir="rtl"` and `lang="ar"` (FR-014). No inline JavaScript is
  added, so B01's admin CSP is unchanged.
- **Roles.** Two groups, created by a data migration, with custom permissions:
  - `content_author`: change on the authoring models, plus `content.build_pack`,
    `content.import_content`, `content.export_content` and `content.review_speech`;
  - `content_publisher`: `content.publish_pack`, `content.rollback_pack`, `content.promote_pack`
    and `content.change_min_client_version`.

  Every service function checks the permission itself, so a job or command started without the
  permission is refused too (FR-019). Commands that act for a person take a required `--actor`
  (contracts/admin.md "Management commands").
- **Environment role.** `CONTENT_ROLE` is `source` on dev, test and staging, and `target` on
  production. With `target`, the authoring admin is read-only (`has_add`, `has_change` and
  `has_delete` return `False`), and import, build, publish and rollback are not offered. Promotion
  is offered only with `target`. The settings check refuses `source` in production and `target`
  outside it (FR-039).
- **Validation in two layers.**
  - Schema, references and content rules run on the built pack JSON, in `wassal_content.validate`.
    That way CI can run them on `content/source` and production can run them on a promoted file.
  - The review stage (it needs authoring data) and the solver stage live in `apps/content`.
- **The solver stage** is a plug-in point set by `CONTENT_SOLVER_STAGE`. The default reports
  `not_available`. A pass-all stand-in exists for tests and dev, and the settings check refuses it
  in staging and production. B05 supplies the real stage.
- **Import and export** (contracts/content-source.md):
  - Format: a zip in the `content/source` layout.
  - Import limits: at most 4 MiB uploaded, 8 MiB uncompressed and 2,000 entries. That is about 4×
    the MVP content, and keeps JSON parsing inside the staging admin container's 256 MB. Only
    `.json` entries under the known folders are accepted; absolute paths, `..` and symlinks are
    refused.
  - The import is all or nothing, in one transaction (FR-015).
  - The admin hostname gets an explicit `request_body max_size 8MiB` in the edge. It has none today.

**Why.**

- Relational models give inline editing that meets SC-003, plus database-level integrity.
- One validator over the pack means staging, production and CI apply the same rules.

**Alternatives rejected.**

- **One JSON document per entity, edited as raw JSON.** Authors would edit passengers as text, so
  SC-003 fails.
- **A separate authoring front end:** the constitution makes the admin the authoring tool.
- **A `CONTENT_AUTHORING_ENABLED` boolean:** two roles, each checked in settings, can't be
  half-configured.

## R10. Background jobs

**Decision.**

- **Queue.** Builds, publishes, promotions and file syncs run on B01's `content` queue as Celery
  tasks with `bind=True`.
- **Retries.** Network steps (promotion fetches, reading the floor file) retry three times with backoff for
  connection errors and `5xx`. Validation failures are results, not errors, and are never retried.
- **Delivery.** Tasks use `acks_late=True` and `reject_on_worker_lost=True`, so a task lost to a
  restart runs again. Every task is idempotent:
  - a build re-run produces the same bytes;
  - a publish or promotion re-run finds its files already stored.
- **Stuck builds.** A beat job marks builds still `running` after 30 minutes as `failed`, so none
  looks done when it isn't.
- **File checks.** A daily beat job runs `content_files sync --verify`. It re-hashes every published
  file and recreates missing ones from the database. A mismatch is an error event in Sentry, which
  emails the operator (B01). The same check is a restore-drill invariant,
  `content.published_packs_intact` (B01 registry), which confirms the stored bytes against each
  pack's `sha256`.

**Why.** Builds can take minutes once B05's solver runs. A worker restart must never leave a
half-built pack looking valid (spec Edge Cases).

**Alternatives rejected.**

- **Synchronous builds in the admin request.** Gunicorn's timeout and admin worker memory make
  that fragile.
- **A separate queue:** `content` already exists for this.

## R11. The manifest endpoint

**Decision.**

- **Endpoint.** `GET /v1/content/manifest` on the API role (contracts/api.md), with no
  authentication until B02 (FR-033). It uses B01's address throttle and error envelope.
- **Caching.** The response for a given (offered version) is cached in Valkey for 30 s. Publish,
  promotion and minimum-version changes delete the cache key in the same transaction's
  `on_commit`, so FR-031's 1 minute holds with margin.
- **Response headers.** `Cache-Control: no-store`, as B01 already sets on the API.
- **`X-Client-Version`** is parsed as `MAJOR.MINOR.PATCH[+BUILD]`. If it is present and valid, the
  manifest offers the newest published pack whose `min_client_version` is at most that version. If
  it is missing or invalid, it offers the current pack. B02 and B10 make the header mandatory
  later.
- **Contract checks.** The response must validate against `manifest.schema.json`, checked by a
  test. The endpoint is in `contracts/openapi.yaml`, through a drf-spectacular serializer.

**Why.**

- One indexed query plus a cache hit stays well inside SC-011's 150 ms p95 at 100 rps.
- Serving old apps the newest pack they can read is what makes the minimum-version kill switch work
  (FR-030, FR-032).

**Alternatives rejected.**

- Edge-level caching of the manifest: B01's edge has no cache module.
- Answering an old app with `426`: that is B10's force-update path, not the manifest's.

## R12. Version lookups for B03 (FR-035)

**Decision.**

- **Index tables.** Two, filled at publish or promotion:
  - `PackTripIndex(version, trip_id, rev, definition, max_earnings_jenehat, last_station_at_s)`;
  - `PackPriceIndex(version, sku_kind, sku_id, currency, amount)`.
- **Retiring.** The 6th newest published pack and anything older become `retired`, and their index
  rows are deleted. Their files and records stay.
- **API.** `apps.content.services.lookups` exposes `catalog_price(version, sku_kind, sku_id)` and
  `trip_definition(version, trip_id)`, which B03 calls inside sync.

**Why.** Sync validates up to 100 ops per batch inside one transaction (backend §7.3). Indexed rows
beat decompressing and parsing a pack on every batch.

**Alternative rejected.** An in-process cache of parsed packs per worker: it costs memory in every
gunicorn worker, and stays cold after each deploy.

## R13. The shared Python package, and the image's build context

**Decision.**

- **The package.** `tools/content_kit` is its own uv project, distribution `wassal-content`,
  import `wassal_content`, typed with `py.typed`. It holds:
  - the generator (R1) and the generated Pydantic models;
  - the canonical form and pack file helpers (R4);
  - the loader and validator (R2, R9);
  - the schema-diff (R3);
  - the `content/source` reader and writer;
  - a copy of `content/schemas` as package data, written by codegen and drift-checked like the
    models.

  It has no Django dependency.
- **Dependents.** The backend depends on it as a path dependency (`wassal-content = { path =
  "../tools/content_kit" }`). B05's solver will do the same.
- **Build context.** The backend image's build context moves from `backend/` to the repository
  root, because a path dependency outside the context can't be copied. A root `.dockerignore`
  admits only `backend/`, `tools/content_kit/` and `content/schemas/`. The changes:
  - `docker build -f backend/docker/Dockerfile .` in CI;
  - `context: ../..` in `compose.dev.yml`;
  - the Dockerfile's `COPY` lines.
- **CI.**
  - **backend.yml:** add `content/`, `tools/content_kit/` and `packages/content_models/` to the
    path rule. Add steps for the package's lint, types and tests (≥ 80% coverage), the codegen drift
    check, the profile check, the examples check, `content/source` validation and the schema-diff.
  - **mobile.yml:** the path rule already covers `packages/`; add `content/`. Add a
    `content_models` job: `pub get`, `build_runner`, analyze, tests (≥ 80%).

  Both workflows stay the existing required checks, so the owner changes no branch protection.

**Why.**

- One copy of the canonical form, the validator and the models for the backend, the solver and CI.
- The root build context is needed by B05 anyway.

**Alternatives rejected.**

- **The shared code inside `backend/`.** The solver at `tools/solver` couldn't depend on it without
  the same context problem, and CI could only validate `content/source` by booting Django.
- **A new required `content.yml` workflow.** It needs a branch-protection change by the owner, and
  a skipped required check stays pending (B01's lesson in `backend.yml`).

## R14. Rules for player-visible text

**Decision.**

- **No digits.** No player-visible text in a pack contains a digit: any Unicode `Nd`, which includes
  ASCII 0–9, Arabic-Indic ٠–٩ and Extended Arabic-Indic ۰–۹. Numbers go through placeholders so the
  player's digit setting applies (constitution X).
- **Placeholders by kind of text:**

  | Text | Placeholders |
  | --- | --- |
  | Speech lines | `{amount}`, `{station}` |
  | Task text | `{target}` |
  | Everything else | none |

  Braces must be balanced and their names valid.
- **Required text.** Every text has a non-empty `ar-EG`. `ar` is optional. Neither may have leading
  or trailing whitespace.
- **Spec change.** This extends FR-021's digit rule from speech lines to every text, and the spec is
  updated to match. A task like «رجّع ٢٠ باقي صح» has the same digit-setting problem as dialogue.

**Why.** Constitution X requires the Western-digits setting to work everywhere. A digit baked into
content text would ignore it.

**Alternative rejected.** Digits allowed outside speech lines: it breaks the setting on task cards.

## R15. Savings goals that aren't a room or a vehicle

**Decision.**

- **The gap.** Chapter goals have four kinds: `complete_line` (ch1), `own_vehicle` (ch2), `purchase`
  (ch3's «الشبكة», ch7's wedding costs) and `complete_room` (ch4 onward). A `purchase` goal is
  bought with JENEHAT through a catalog price of a new kind, `chapter`, whose `sku_id` is the
  `chapter_id`.
- **Doc changes in this PR.** Backend §7.4's `spend_jenehat` `sku_kind` list gains `chapter`, and
  §9.2's catalog row is updated to match. B03 implements the op, and M10 the screen.
- **Not a glossary change.** It adds no new identifier kind: the `sku_id` is a glossary `chapter_id`.

**Why.** Chapter 3 is MVP content. The glossary's `item_id` is `<room_id>.<slug>`, and the shabka
belongs to no room. Without this kind, the MVP chapters can't be authored.

**Alternative rejected.** A pseudo-room for story purchases: `room_id` is a closed glossary set
(`salon`, `kitchen`, `bedroom`), and the apartment screen would have to hide it.

## R16. Testing (constitution XIII)

**Decision.**

- **`tools/content_kit` (pytest, no database).**
  - Unit tests for every validation rule, each with a broken case (SC-005).
  - Tests for the generator itself: a schema fixture compiled to known outputs.
  - The round trip of every valid example through the Pydantic models (FR-009).
  - The golden checksums (R4).
  - The schema-diff over fixture pairs.
  - The zip-safety rules.
  - A `hypothesis` property: any value the models accept writes out in canonical form, and reads
    back equal.
- **`packages/content_models` (dart test).** The round trip of every valid example in canonical
  form, against the same files.
- **`backend/apps/content` (pytest-django, real PostgreSQL and Valkey).**
  - Admin forms and permissions per role and per `CONTENT_ROLE`.
  - Identifier permanence.
  - The import and export round trip (US2-4).
  - Builds: snapshot, `rev` bumps, version assignment under concurrency, and the floor file read
    from a local HTTP server, with gaps in production's numbers.
  - Publish and promotion, including every failure path: storage, a wrong checksum, a lower
    version, a missing solver stage. Files go to a temporary directory and promotion uses a local
    HTTP server.
  - Manifest selection and caching, and its schema match.
  - The audit log is append-only.
  - Lookups and retiring.
  - The restore-drill invariant.
- **Contract.** B01's `schemathesis` run picks up the manifest endpoint from `contracts/openapi.yaml`.
- **Coverage.** At least 80% each for `tools/content_kit`, `packages/content_models` and the backend
  (FR-041). Tests come first for the validation rules and the publish and promotion guards.

**Why.** These are the paths where a mistake reaches every player. The constitution requires real
services and tests first.

## Handed to later features

- **M01:**
  - The trip schema here is the first cut. M01 refines event parameters and passenger timing, and
    whatever else the engine needs, freely until the first production promotion (FR-010).
  - M01 lists the `speech_key`s the engine emits, so validation can check that each has a pool.
  - The engine reads `TripDefinition` from `package:content_models`.
- **B05:**
  - Supply the solver stage through `CONTENT_SOLVER_STAGE`, and re-solve `content/source` in CI.
    The root build context (R13) is ready for `tools/solver`.
  - Run the first live publish on staging, and the live checks SC-007, SC-008 and SC-012.
- **M04:**
  - Verify the gzip file's `sha256` before decompressing, with a decompression cap.
  - Bundle a pack that production has promoted.
  - Read pack URLs only from the manifest.
- **B02:** the manifest is public until then (FR-033). R7's floor file doesn't depend on that
  choice.
- **B03:**
  - Use `apps.content.services.lookups` (R12).
  - Accept `spend_jenehat` with `sku_kind: chapter` (R15).
- **M10:** chapter goal kinds (R15) and the family requests' variant conditions.
- **Scale path:** once there is more than one API host, or before a big launch, put Cloudflare on
  `cdn.<domain>`, and move packs to object storage if the edge stops being the only origin (R5).
