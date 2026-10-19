# Implementation Plan: Content Pipeline (B04)

**Branch**: `003-b04-content-pipeline` | **Date**: 2026-10-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/003-b04-content-pipeline/spec.md`

## Summary

B04 makes content into data, and gets that data from an author's edit to players' phones without
an app release (constitution VII). It ships in two pull requests:

- **PR 1, US1: schemas and models.** The delivery plan asks for this slice first, so M01 can start.
  - `content/schemas/`: fourteen JSON Schema 2020-12 files in a small profile, plus
    `schema-set.json`, with valid and invalid examples and a sample pack.
  - `tools/content_kit` (`wassal_content`), a Django-free Python package holding:
    - one code generator that writes both the Pydantic server models and the freezed app models
      (`packages/content_models`), both committed and drift-checked;
    - the canonical form and pack-file helpers;
    - the validator, with stable rule codes;
    - the `content/source` reader and writer;
    - a breaking-change check that switches on with the first production export.
- **PR 2, US2–US5: the pipeline.**
  - `backend/apps/content`, with relational authoring models and admin inlines (Arabic fields right
    to left), and two roles.
  - Zip import and export in the `content/source` layout.
  - Background builds on the `content` queue that snapshot, number, validate and gzip a pack. The
    solver stage is a plug-in point that B05 fills. Until then, staging and production can't
    publish.
  - Publishing on staging to the host's own `/packs/` directory, which the edge serves as
    immutable files.
  - Promotion on production: it pulls the identical file from staging's public URL, anchored by a
    code the publisher pastes.
  - `GET /v1/content/manifest`, with lookups by version for B03, an append-only audit log, and
    nightly backups on staging for the authoring work.

Backend §22.3 is resolved as **no CDN in the MVP**. Each host's edge serves its packs. Cloudflare
on `cdn.<domain>` is a configuration step later (research R5).

Technical approach and versions: [research.md](./research.md).

## Technical Context

**Language/Version**:

- Python 3.13.16 with uv 0.13.1, for the backend and `tools/content_kit` (two uv projects; the
  backend depends on the kit by path).
- Dart ≥ 3.13 with Flutter 3.47.7 via FVM, for `packages/content_models`.

**Primary Dependencies**:

- New on the Python side: `jsonschema==4.26.0` and `referencing==0.37.0` for 2020-12 validation;
  `pydantic==2.13.5` for the server models.
- New on the Dart side: `freezed ^4.0.2`, `freezed_annotation ^3.1.0`, `json_serializable ^6.14.1`,
  `json_annotation ^4.12.0`, `build_runner ^2.16.2`, `test`, `coverage` and `lints`.
- Everything else is B01's stack: Django 5.2.18, DRF, drf-spectacular, Celery 5.6 and beat, and
  `requests` for reading the floor file and for promotion fetches (R1, R2, R6, R7).

**Storage**:

- PostgreSQL 17 holds authored content, pack records with their gzip bytes, the index tables and
  the audit log (data-model.md).
- Valkey holds the manifest cache (30 s).
- The host filesystem's `/var/lib/wassal/packs/` holds the published files, written create-only by
  the worker and served read-only by the edge (R5).
- Backblaze B2 holds staging's own nightly backups (R8).

**Testing**:

- **`tools/content_kit`**: pytest, with a `hypothesis` round trip. It needs no database.
- **`backend/apps/content`**: pytest-django on real PostgreSQL and Valkey, with a local HTTP server
  standing in for staging and production pack URLs.
- **`packages/content_models`**: `dart test`, a round trip over the same examples.
- **Coverage**: at least 80% in each of the three (R16).

**Target Platform**: Linux containers on the two ARM64 Always Free VMs (B01). The edge's Caddy
serves `/packs/`. The Dart package runs anywhere the app or engine runs.

**Project Type**: monorepo additions: a shared Python library and CLI, a backend Django app with
admin and REST endpoint, a pure-Dart package, and CI and edge configuration.

**Performance Goals**:

- A build and validation of MVP-size content in under 1 minute, not counting the solver (SC-006).
- The manifest at p95 < 150 ms and 100 rps (SC-011).
- A publish or promotion visible within 1 minute (SC-007), and a rollback within 15 minutes
  (SC-008).

**Constraints**:

- USD 0 (SC-012).
- Integers only in packs (FR-003).
- Byte-identical builds (FR-011), proven by a golden checksum (R4).
- A published file is never overwritten (FR-026, FR-027).
- No credentials cross hosts (FR-039a).
- Imports are capped at 4 MiB zipped and 8 MiB unzipped (content-source.md).
- The staging admin has 256 MB and the worker 384 MB (B01 sizing).

**Scale/Scope**:

- MVP content: 2 lines, about 50 trips, chapters 1–4 with their rooms and items, a few hundred
  speech lines. A pack is about 0.5 MB compressed.
- About 30k monthly players at 10k DAU, and about 120k pack downloads a month. The design point is
  100k DAU (R5).
- One pack id (`core`) and two environments.

## Constitution Check

*GATE: passed before Phase 0, and re-checked after Phase 1 below.*

| # | Principle | Applies | How B04 satisfies it |
| --- | --- | --- | --- |
| I | Engine purity | Yes | No trip rule is implemented. Validation checks references and shapes. Whether a trip is solvable or scored is left to B05's solver stage. The Dart models are pure Dart, with no Flutter import, so the engine can depend on them. |
| II | Integer money | Yes | `integer` only in the schema profile. Loaders refuse any float token. Fares, payments and the tray are multiples of 50 in §3.2 denominations. The Dart `int` and Python `int` models generate from that. No money conversion happens here. |
| III | Parity | Indirectly | No engine change and no fixtures yet. The single generator and the round trip give the engine (Dart) and the solver (Python) identical `TripDefinition` models, which parity depends on. |
| IV | Server authority | Yes | Catalog prices live in versioned packs. The FR-035 lookups let B03 check spend ops against the declared version. No SKU kind can grant JENEHAT or carry a real-money price (`V-M1`, closed `sku_kind`). Promotion and publishing are staff actions on the server only. |
| V | Offline-first | Yes | Packs are files the app downloads and verifies, and it keeps its bundled pack when the manifest has nothing for it (api.md). A storage, edge or promotion failure leaves the current pack in place. |
| VI | Idempotency | Yes | There are no player state-changing endpoints. Publish, promotion, the file sync and build re-runs are idempotent: the same bytes at the same name count as success (pack-delivery.md). The manifest is a pure read. |
| VII | Content, not code | Yes, core | This feature *is* the principle: immutable versioned packs that validate against `content/schemas`, built canonically with sha256, published under new versions, rolled back by re-publishing. `trip_id` is permanent and `rev` bumps on change. The models are generated, never hand-edited, and drift-checked. Player text lives only in packs, with `ar-EG` required and `ar` optional. Prices come from the catalog. The pipeline is authored in the admin, then schema-validated, solver-validated (B05), built, published, and promoted unchanged. |
| VIII | Tunable numbers | Yes | Packs hold no tunables (FR-005). Pipeline thresholds such as cache seconds and timeouts are environment settings, not game tunables. |
| IX | No ads in a trip | No | — |
| X | RTL and Arabic first | Yes | Arabic admin fields are `dir="rtl"`. No digit appears in any pack text, so the Western-digit setting works everywhere (R14). No player screens are added. |
| XI | Accessible minimums | No | No player screens. The ≤ 4 drop-off stations rule supports the color-and-letter station scheme. |
| XII | No runtime LLM | Yes | Every speech line carries a human review, and an unreviewed line blocks the build (`V-V1`). Nothing is generated at runtime. |
| XIII | Small, testable features | Yes | Tests come first for the validator rules, the publish and promotion guards, identifier permanence and the audit log. Backend tests run on real PostgreSQL and Valkey. `schemathesis` covers the manifest. Each of the three code units is gated at ≥ 80%. One feature, one folder, two PRs in the delivery plan's order. |

**Locked stack.** B04 uses it as is:

- Django admin as the authoring tool, with no Wagtail and no React.
- Celery and beat, PostgreSQL 17 and Valkey, drf-spectacular.
- freezed + json_serializable for the Dart models, and uv for Python.

Additions that the stack doesn't list: `jsonschema` (already in backend §2), `referencing` (its
companion), and `pydantic` (named in backend §9.2).

**Architecture boundaries.**

- Business logic lives in `apps/content/services/`, and in `wassal_content` for everything that
  doesn't need Django. Views, serializers and admin actions stay thin and call services.
- Errors use B01's envelope, and no new codes are needed (api.md).
- Every new table has a UUIDv7 key.
- Migrations only add tables and seed data, so they are expand-only.
- **Statelessness**: the packs directory is a cache of database rows. `content_files sync`
  rebuilds it, so state stays in the database (R5). The one exception is production's floor
  file, which only ever goes up and which sync raises from the database (R7).
- Outbound calls (reading the floor file, promotion fetches) run in Celery with timeouts and
  retries.

**Security & privacy.**

- **Permissions** are checked in services, not just in the admin (FR-019). Production's authoring
  is read-only by configuration, and settings checks refuse a mismatched `CONTENT_ROLE` or the
  stand-in solver outside dev and test.
- **The audit log** is append-only. Content publishes are audit-logged, as the constitution's
  security section requires.
- **Public pack files** carry no personal data or staff names. The bucket-style listing is off, and
  drafts are never public.
- **Imports** guard against zip-slip and zip bombs. Promotion fetches have hard size caps, and
  their integrity is anchored by the pasted SHA-256.
- No new secrets, except staging's own write-only backup key. No key crosses hosts.
- A security review is due before merge. The PR touches admin permissions, file writes and outbound
  HTTP, though not auth, purchases, the ledger or sync.

**Post-design re-check (after Phase 1).** It still passes. The design adds three things the
pre-check didn't foresee, and none needs a Complexity Tracking entry:

- **Packs are self-hosted on each edge** instead of OCI Object Storage. Backend §15 had named OCI;
  the constitution names no pack store. The change is recorded in backend §4, §15 and §22.3 in the
  same PR (FR-037).
- **Staging is now backed up** (R8). That reverses B01's assumption, not a principle.
- **A new catalog `sku_kind`, `chapter`** (R15). It is not a glossary change, because its ids are
  glossary `chapter_id`s, but backend §7.4 and §9.2 are updated with it.

## Project Structure

### Documentation (this feature)

```text
specs/003-b04-content-pipeline/
├── plan.md              # This file
├── research.md          # R1–R16 and the handover list
├── data-model.md        # apps/content tables, files and invariants
├── quickstart.md        # Local validation now, live checks after B05
├── contracts/
│   ├── content-schemas.md   # the schema set 1.0, rule codes, canonical form
│   ├── content-source.md    # the layout, import and export
│   ├── pack-delivery.md     # files, release record, publish, promotion, version floor
│   ├── api.md               # GET /v1/content/manifest
│   ├── admin.md             # roles, pages, actions, validation report
│   ├── environment.md       # new settings, mounts, staging backup
│   └── ci-checks.md         # backend.yml and mobile.yml additions
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
.dockerignore                           # new: the root build context admits backend/, tools/content_kit/, content/schemas/
content/
├── schemas/                            # PR 1: *.schema.json (14) + schema-set.json
├── examples/
│   ├── valid/<part>/*.json             # PR 1
│   ├── invalid/<part>/*.json + expected.json
│   ├── sample/                         # PR 1: content/source layout, every part used
│   └── sample.golden.json              # PR 1: golden checksums
└── source/README.md                    # PR 2: promoted packs land here (FR-040)

tools/content_kit/                      # PR 1: uv project "wassal-content"
├── pyproject.toml  uv.lock
├── src/wassal_content/
│   ├── cli.py                          # wassal-content codegen | validate | validate-source | schema-diff
│   ├── profile.py                      # the schema-profile check (R3)
│   ├── codegen/{ir.py,python.py,dart.py}
│   ├── models/_generated.py            # generated server models
│   ├── schemas/                        # generated copy of content/schemas
│   ├── canonical.py  packfile.py       # R4
│   ├── loader.py  validate.py  rules/  # R2 and the V-* rules
│   ├── source.py                       # the content/source reader and writer
│   └── schema_diff.py
└── tests/

packages/content_models/                # PR 1: pure Dart package
├── pubspec.yaml  analysis_options.yaml  build.yaml
├── lib/content_models.dart             # exports
├── lib/src/canonical_json.dart         # hand-written helper (R4)
├── lib/src/generated/*.dart            # generated (committed); *.freezed.dart, *.g.dart gitignored
└── test/round_trip_test.dart

backend/
├── pyproject.toml                      # PR 2: + wassal-content path dependency
├── apps/content/                       # PR 2
│   ├── models/{lines,trips,story,speech_economy,packs}.py   # authoring, packs, index, audit
│   ├── admin.py  apps.py  checks.py  signals.py  # checks: packs dir at worker start; signals: permanence
│   ├── forms.py  widgets.py            # RTL widgets, per-kind validation
│   ├── services/
│   │   ├── snapshot.py  build.py  versioning.py  # snapshot → Pack JSON, rev, floor (R7)
│   │   ├── stages.py                   # review stage, solver plug-in point
│   │   ├── publish.py  promote.py  rollback.py  files.py
│   │   ├── importer.py  exporter.py    # zip in content/source layout
│   │   ├── permanence.py  lookups.py  audit.py  manifest.py
│   ├── api/{serializers.py,views.py}   # GET /v1/content/manifest
│   ├── tasks.py                        # build, publish, promote, sweep, sync files
│   ├── invariants.py                   # content.published_packs_intact
│   ├── management/commands/            # content_import, content_export, content_build, content_files
│   ├── migrations/                     # tables + groups + beat rows
│   └── tests/
├── config/settings/base.py             # + apps.content, CONTENT_* settings
├── config/urls.py                      # + /v1/content/manifest; dev-only /packs/
├── docker/Dockerfile                   # root build context
├── docker/compose.yml, compose.dev.yml # worker packs mount; dev context ../..
├── docker/edge/{Caddyfile,Caddyfile.dev,compose.yml}   # /packs/ route; admin body limit; ro mount
├── docker/host/provision.sh            # /var/lib/wassal/packs; staging backup timer
└── .env.example, docker/env/*.env      # CONTENT_* values
apps/mobile/                            # untouched in B04 (M04 adds the dependency)
.github/workflows/{backend.yml,mobile.yml}   # contracts/ci-checks.md
contracts/openapi.yaml                  # + /v1/content/manifest
docs/                                   # backend §4, §7.4, §9, §12, §15, §22.3; mobile §5, §14.1; runbooks; CLAUDE.md commands
```

**Structure decision.** Code that doesn't need Django lives in `tools/content_kit`, so the backend,
B05's solver and CI share one copy (R13). Django-specific authoring, publishing and delivery live
in `backend/apps/content`, following backend §5's app layout. The app models are the
`packages/content_models` package that mobile §5 already plans.

## Delivery slices

| PR | Stories | Merges when | Unblocks |
| --- | --- | --- | --- |
| 1 | US1 (+ the CI job `content-kit`, the `content_models` steps in mobile `check`, and the schema docs in backend §9.2 and mobile §14.1) | `trip.schema.json` and the generated models are green in CI | M01 can be specified (delivery plan step 2) |
| 2 | US2–US5 (+ the root build context, the edge, provisioning, staging backups, the manifest in OpenAPI, the doc updates, CLAUDE.md commands and owner actions) | Every check green. Owner "before merge" items done (the staging backup setup can follow, before authors start). Security review done. | M04 (after B05), B03 lookups, B05's solver stage |

## Documentation updated in this feature (FR-042)

- **Backend doc:**
  - §4: the diagram and the object-storage row become "packs served by each edge".
  - §7.4: the `spend_jenehat` `sku_kind` list gains `chapter`.
  - §9.1: the flow gains "publish on staging, promote to production".
  - §9.2: the schema list and the catalog row.
  - §12 "content": the model list.
  - §15: the object-storage, CDN and backup rows.
  - §22.3: resolved.
- **Mobile doc:** §5 (`packages/content_models`), and §14.1 (the gzip sha256 and how packs are
  delivered).
- **Repository:**
  - `CLAUDE.md`: the content commands, and an overview line for `tools/content_kit` and
    `packages/content_models`;
  - `docs/delivery-plan.md`: the step 2 note that PR 1 is merged, and the B04 progress line;
  - `docs/owner-actions.md`: the B04 section;
  - `docs/runbooks/`: deploy (edge update), restore (staging), and a new `content-publishing.md`.

## Complexity Tracking

No constitution violations. Nothing to justify.
