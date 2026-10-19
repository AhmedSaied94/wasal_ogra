# Quickstart: Content Pipeline (B04)

How to set up, run and validate B04 end to end.

- **Where to run commands**: from the repository root unless noted.
- **CI's checks** are in [contracts/ci-checks.md](./contracts/ci-checks.md).
- **What you'll see**: shapes in [contracts/content-schemas.md](./contracts/content-schemas.md),
  admin pages in [contracts/admin.md](./contracts/admin.md).
- **Live checks come later.** Nothing is published on staging or production until B05 (spec
  Clarifications). The live checks are in [After B05](#after-b05-live-checks-on-the-hosts).

## Prerequisites

The B01 setup (`backend/.env`, the dev stack and a staff account with TOTP), plus:

| Tool | Version | Notes |
| --- | --- | --- |
| uv | 0.13.1 | For `tools/content_kit` and the backend |
| FVM and Flutter | `.fvmrc` (3.47.7) | For `packages/content_models` |

Add the new variables to `backend/.env` from `backend/.env.example` (contracts/environment.md):
`CONTENT_ROLE=source`, `CONTENT_PACKS_DIR`, `CONTENT_PACKS_PUBLIC_URL` and
`CONTENT_SOLVER_STAGE=stand_in`.

## 1. Schemas and models (US1, the first PR)

```bash
cd tools/content_kit
uv sync
uv run wassal-content codegen --check         # no drift: models and the schema copy match
uv run pytest --cov --cov-fail-under=80       # profile, examples, round trip, golden, rules, diff
uv run wassal-content validate-source ../../content/examples/sample
cd ../../packages/content_models
fvm dart pub get && fvm dart run build_runner build -d
fvm dart analyze --fatal-infos && fvm dart test
```

Expected:

- Every command exits 0.
- **The schema rejects broken trips.** Change `fare_piasters` to `475` in a copy of
  `content/examples/valid/trip/line_gamaa.12.json`, then run
  `uv run wassal-content validate <file> --part trip` (the part is inferred only inside a `trip/`
  or `trips/` folder). The finding names `$.stations[0].fare_piasters` and exits 1 (US1-1,
  US1-4).
- **Hand edits are caught.** Edit any line in `lib/src/generated/trip.dart`, and
  `codegen --check` fails (US1-3).
- **Old apps ignore new fields.** The suite's unknown-field case adds `"future_field": 1` to a
  valid trip. The Dart and Pydantic models still read it, while the schema check refuses it
  (US1-5).

## 2. Authoring in the admin (US2)

```bash
cd backend
uv sync && docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait --build
uv run manage.py create_staff author1 --group content_author && uv run manage.py staff_totp author1
uv run manage.py content_import ../content/examples/sample --actor author1
```

On <http://localhost:8001/admin/content/>:

1. **Enter a trip by hand.** Delete `line_gamaa.02`, the sample's copy of the §9.3 trip. Enter it
   again from the §9.3 example (contracts/content-schemas.md), keeping the `trip_id`
   `line_gamaa.02`. Time it: under 15 minutes is the target (SC-003). Save it with a fare of 475 →
   the error is shown on the field and nothing is saved (US2-1).
2. **Arabic is right to left.** Type in a station name → the text runs right to left (US2-2).
3. **Round trip.** "Export current content" gives a zip. Unzip it and `diff -r` it against
   `content/examples/sample`. Only `pack.json`'s version differs: `0` against the sample's (US2-4).
4. **Imports are all or nothing.** Import a zip with one invalid file → the whole import is
   refused, and the report names the file and field (US2-3).
5. **Read-only without the role.** Sign in as a staff member without `content_author` → pages are
   read-only (US2-6).
6. **Reviews clear on edit.** Mark the lines of one pool reviewed, then edit one line's text. Its
   review is gone (US2-7).

## 3. Build and validate (US3)

1. **Review the speech lines first.** Reviews are never exported, so imported lines arrive
   unreviewed (contracts/content-source.md). As `author1`, run "Mark reviewed" on every speech
   line. Until then, every build stays `draft` with `V-V1` for each unreviewed line.
2. "Build a new pack" → the status goes from `queued` to `running` to `validated` within a minute
   (SC-006). The report shows every stage green, and solver `passed`, because the local stack uses
   the stand-in.
3. **Builds are reproducible.** On a fresh import of the sample, before any edits (re-entering a
   trip by hand gives it a new seed), run
   `uv run manage.py content_build --actor author1 --dry-run --version 1` twice. Both print the same
   `sha256`, which equals `content/examples/sample.golden.json` (SC-004). A dry run prints the
   checksums even with findings, so unreviewed lines don't matter here.
4. **Broken references are reported.** Point a passenger at a station outside the trip, then
   build → `V-T4` names the trip, field and path, and the pack stays `draft` (US3-3).
5. **Unreviewed lines block.** Leave one speech line unreviewed → `V-V1` (US3-4). Put a digit in a
   task text → `V-X1` (R14).
6. **`rev` follows changes.** Change one trip, then build and publish (next section). Only that
   trip's `rev` went up (US3-6).

## 4. Publish, the manifest and rollback, on the local stack (US4)

```bash
uv run manage.py create_staff pub1 --group content_publisher && uv run manage.py staff_totp pub1
curl -s localhost:8000/v1/content/manifest            # {"version":0,"packs":[]} before any publish
```

1. **Publish a validated pack** as `pub1`. Within a minute, `curl -s localhost:8000/v1/content/manifest`
   shows it, with URL, `sha256`, size and `min_client_version` (US4-1, SC-007). Then
   `curl -s <url> | sha256sum` equals the `sha256`.
2. **Published packs are frozen.** Try to change the published pack's report or file in the admin
   → refused (US4-3).
3. **Old apps get older packs.** Raise its minimum app version to `9.0.0`. With `-H
   'X-Client-Version: 1.0.0'`, the manifest now offers the previous pack, or nothing if there is no
   older one. The audit log has the change (US4-11). Set it back.
4. **Rollback.** On an earlier pack, "Roll back to this" → a new version with the earlier content
   builds. Publish it, and the manifest offers it (US4-5, SC-008).
5. **Storage failures change nothing.** Make the packs directory read-only (`chmod a-w
   backend/var/packs`) and publish → the publish fails, the manifest still offers the previous
   pack, and a failed audit record exists. Restore the permission and retry → it succeeds
   (US4-2, SC-010).

## 5. Promotion (US5)

There is only one local environment, so promotion is proven by the automated suite. It starts a
local HTTP server as "staging" and runs a `target`-role settings override against it:

```bash
cd backend && uv run pytest apps/content/tests/test_promotion.py -v
```

Expected: these cases pass:

- the happy path, with a byte-identical file;
- a wrong code (`release_mismatch`);
- a tampered pack (`pack_mismatch`);
- a lower version;
- the solver stage `not_available`;
- staging unreachable, then a retry that succeeds;
- production's admin being read-only;
- the version floor after a simulated staging rebuild, with a gap in production's numbers (US5-1 to
  US5-8).

## After B05: live checks on the hosts

These checks become owner actions when B04's implementation finishes (`docs/owner-actions.md`).
They run once B05 is merged and staging can publish:

1. **Setup on both hosts.** `/var/lib/wassal/packs/` exists, the edge carries the `/packs/` route,
   and `CONTENT_*` is set in `/etc/wassal/<env>.env` (contracts/environment.md).
2. **Staging backups.** The buckets, the write-only key and the Healthchecks.io check exist, and
   `wassal-backup@staging.timer` is enabled. One night later, the backup is in
   `wassal-staging-backup-daily` (FR-039c).
3. **Publish on staging.** From an outside network, `curl -sI
   https://<staging-api>/packs/core-<v>.json.gz` shows the immutable cache header, and the body's
   sha256 matches (SC-007).
4. **Promote.** Copy the promotion code from staging's pack page into production's "Promote from
   staging" form. Within a minute, production's manifest offers the same version and `sha256`
   (SC-007, US5-1).
5. **Export to the repository.** Export the promoted pack from either admin, unzip it into
   `content/source/`, and open a PR. CI validates it, and from then on runs the schema-diff check
   (FR-040, research R3).
6. **Staging recovery (SC-013, once).** On a scratch staging rebuild, restore the latest staging
   backup, then build. The authored content is back, and the new version is above production's.
7. **Cost (SC-012).** After a month, the OCI and B2 consoles show USD 0, and the edge access logs
   show the `/packs/` downloads.
