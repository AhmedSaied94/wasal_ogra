# Publish content

Authors write content in **staging's** admin. Staging builds, validates and publishes packs, and
that is where they are tested. Production never builds: it **promotes** a pack staging published,
fetching the exact files and checking them again. Then the accepted content goes back into the
repository as `content/source`.

Contracts: `specs/003-b04-content-pipeline/contracts/` (`admin.md`, `pack-delivery.md`,
`content-source.md`, `api.md`). Background: research R5–R8 there.

| | Staging (`CONTENT_ROLE=source`) | Production (`CONTENT_ROLE=target`) |
| --- | --- | --- |
| Authoring, import, build | Yes, in its admin | Read-only |
| Publish | Yes | No |
| Promote | No | Yes, from a promotion code |
| Minimum app version | Yes | Yes |
| Pack files | `/var/lib/wassal/packs`, served at `https://staging-api.<host>/packs/` | `/var/lib/wassal/packs`, served at `https://api.<host>/packs/`, plus `core.floor.json` |

Everyone needs a staff account (staff-accounts.md) and the environment's private network
(private-network.md). Authors get the `content_author` group, publishers `content_publisher`:

```bash
ADMIN="sudo docker exec -it wassal-staging-admin-1 python manage.py"
$ADMIN create_staff <name> --group content_author
```

## 1. Author, build and publish on staging

1. **Write or import.** Edit content in the admin, or import a zip of a `content/source` layout
   (Content packs → "Import zip"). An import is all or nothing: one problem refuses the whole zip and
   lists every file, path and problem.
2. **Review the speech lines.** Speech pools → select the pools → "Mark reviewed". A build stays
   `draft` with `V-V1` for every unreviewed line. Reviews never travel in an export, so imported
   lines always need one.
3. **Build.** Content packs → "Build a new pack". The page refreshes until the build is
   `finished`. A green report makes the pack `validated`. Otherwise it stays `draft`, and the report
   lists each finding by stage, errors first, with a link to the object to fix.
4. **Publish.** Open the validated pack → "Publish" → confirm. Within a minute the pack is current
   and `GET /v1/content/manifest` offers it. Publishing needs the solver stage `passed`, which
   needs B05: until then staging refuses every publish (FR-022).
5. **Test** the pack on staging with a staging build of the app.

A published pack never changes. Its files are written once, and its record keeps only its minimum
app version mutable.

**After a schema change, build and publish a fresh pack.** A deploy that adds a required field (M09
added a line's `whats_new` and `display_fare_piasters`, and a vehicle's `short_name`) leaves the
published packs without it: apps from that release refuse them as unreadable and fall back to their
bundled pack, and production's promote refuses them against the new schema. Right after the deploy,
fill the new fields in the admin (rows from before the migration hold its defaults: a fare of 50 and
empty texts; a build refuses the empty texts, but 50 is a valid fare, so set each line's fare by
hand), then build and publish (steps 3–4).

The same schema change has four consequences around a release:

- **Deploy the release before promoting its first pack.** Production runs the schema stages again
  with its own copy of the schemas (`promote.py`), so a pack carrying the new fields is refused by a
  production that predates them. Tag and deploy production with M09 first, then promote.
- **Packs built before the migration can't be rolled back to.** A rollback rebuilds an earlier
  pack's parts and validates them against today's schema (`build.py`), so a pack built before
  `content.0010` fails its build. Roll back only to packs built after the deploy.
- **Don't publish a draft built before the deploy.** Publishing doesn't re-run the schema stage
  (`publish.py`), so such a pack goes out and every M09 app refuses it. Rebuild the draft after the
  deploy, then publish.
- **Older exports won't import.** `content_export` of a pre-M09 version lacks the required fields,
  and the import refuses it against today's schema. Export M09-era versions only.

### Authoring scenes

A scene's page, and the scenes on its chapter's page, have two fields that tell the app when to
play it by itself (M07, `specs/012-m07-onboarding/contracts/scenes.md`):

- **Plays kind** `opening`: at the first open, before the Name card. One scene in the pack, in the
  chapter of order 1, with **Plays trip** empty.
- **Plays kind** `after_trip`: after the first finish of the trip in **Plays trip**, which is then
  required. One scene per trip.
- **Plays kind** blank (the default): M10's rules play it.
- **Captions.** A panel's caption is a scene line whose speaker is `narrator`. Make it the panel's
  first line (the lowest order), and add at most one per panel. The app draws it in the caption
  chip, not a bubble.

Saving refuses a trip on a scene that isn't `after_trip`, and the reverse. An import and a build
report the other rules as `V-C3`–`V-C5`.

## 2. Promote to production

1. On staging's page of the tested pack, copy the **promotion code** (`core-<v>:<64 hex>`).
2. In production's admin: Content packs → "Promote from staging" → paste the code → "Promote".
3. Production fetches the release record and the pack from staging's public URL, checks the record
   against the code, the pack against the record, runs the schema, reference and content-rule
   stages again, stores both files and raises its floor file. Only then does the manifest switch.
   The result is on the pack's page, and in Content audit records.

A failed promotion changes nothing that apps see. Read its reason in the audit record:

| Reason | Meaning | Do |
| --- | --- | --- |
| `release_unreachable` | Staging's `core-<v>.release.json` didn't answer `200` after the retries | Check staging serves `/packs/`, then promote again |
| `release_mismatch` | The record isn't the one the code names: a mistyped code, or a different file | Copy the code again from the pack's page. If it still fails, staging's file differs from its record: run `content_files sync --verify` there |
| `release_not_passed` | A stage other than a `size` warning didn't pass, or the solver didn't run | Build and publish a pack that passed every stage |
| `pack_unreachable`, `pack_mismatch` | The pack file is missing, or isn't the one the record names | As for the record |
| `pack_invalid` | Production's own checks refused the pack. The findings are in the audit record. | Fix it on staging, publish a new version, promote that |
| `storage_error` | Production couldn't write or confirm its files, or the commit failed | Check `/var/lib/wassal/packs` (space, owner `10001`, mode `0755`), then promote again. A retry is safe. |

## 3. Bring the content back into the repository

The repository's `content/source/` holds only packs promoted to production.

1. In staging's admin, open the promoted pack → "Export content". It downloads the `content/source`
   layout of exactly that pack.
2. In a branch, replace `content/source/` with the zip's contents, check it, and open a PR:

```bash
cd tools/content_kit
uv run wassal-content validate-source ../../content/source
uv run wassal-content schema-diff --base origin/master
```

Once `content/source/pack.json` exists, a breaking schema change needs a major bump in
`content/schemas/schema-set.json`, and CI enforces it.

3. Bundle the pack into the staging and prod builds (M04,
   `specs/006-m04-content-loader/contracts/bundling.md`). Still in `tools/content_kit`:

```bash
uv run wassal-content bundle release \
  --packs-url https://api.193-122-74-125.sslip.io/packs/ \
  --out ../../apps/mobile/assets/content/release
```

It rebuilds the pack from `content/source/`, fetches production's release record
(`core-<v>.release.json`, over HTTPS, without following a redirect), and refuses unless the record
names the same pack, version, size and sha256, and every stage passed (`size` and `solver` may
warn). It then writes three files: `core-<v>.json.gz`, the record's copy `core-<v>.release.json`,
and `bundled.json`, and removes the README that stood in for them.

Commit the export and those three files in the same PR, and nothing else. Until they are committed,
`checkBundledPack` stops every staging and prod build with "No promoted pack is bundled".

CI then checks the whole chain, offline, from the committed record copy:

- the export validates and re-solves (B04, B05);
- `bundle release --check` rebuilds the pack and finds the same bytes as the bundled file, a record
  copy that agrees with it, and no other file;
- `test/repo/bundled_pack_test.dart` finds the release version equal to
  `content/source/pack.json`'s, sizes and sha256s that agree, and a `min_client_version` the pubspec
  version meets.

A pack promoted after the app's release only reaches players by download; bundle it in the next
app release.

## 4. Roll back

A rollback never re-serves an old version. It builds an earlier pack's content as a **new**
version, which you then publish and promote like any other.

1. On staging, open the published or retired pack to go back to → "Roll back to this" → confirm.
2. The build appears as a new draft with `rollback_of` set. Trips that differ from the current pack
   get a new `rev`.
3. Publish it, test it, then promote it to production (sections 1 and 2).

A pack built before a required-field schema change can't be rolled back to: the build reads the old
pack's parts and validates them against today's schema, so a pack from before `content.0010` fails
with the missing `whats_new`, `display_fare_piasters` or `short_name`. To undo an M09 pack, roll
back to one built after the M09 deploy, or edit and rebuild the older draft first.

## 5. The minimum app version (kill switch)

An app below a pack's minimum is offered the newest pack it can read instead, or none.

1. Open the pack on the environment to change → "Change minimum app version".
2. Enter `MAJOR.MINOR.PATCH`. Values below the floor of the pack's schema major are refused.
3. The manifest changes within a minute, and the change is in the audit log with its old and new
   values. Do it on production for players, on staging to test first.

## When something goes wrong

### A build fails with `version_floor_unavailable`

Staging numbers each build above production's floor file, which it reads from
`CONTENT_VERSION_FLOOR_URL`. It refuses to build when it can't, so it never reuses a number.

1. Check that production serves it: `curl -s https://api.<host>/packs/core.floor.json` gives
   `{"max_version":N,"pack_id":"core"}`.
2. If production answers `404`, the file is missing: on the prod VM run
   `sudo docker exec wassal-prod-worker-1 python manage.py content_files sync`. The worker also
   creates it when it starts.
3. If production is down, wait for it. Nothing is assigned until a build succeeds.

### A publish fails with `file_conflict`

A file with the pack's name already exists with different bytes. The publish wrote nothing, and
the existing file is untouched. This shouldn't happen: version numbers are never reused.

1. Don't delete the file. Note the version and look at it:
   `sudo ls -l /var/lib/wassal/packs/core-<v>.*`.
2. Run `sudo docker exec wassal-staging-worker-1 python manage.py content_files sync --verify`. It
   reports each file that doesn't match its record.
3. If a restored database is behind the files, build again: the new build gets a version above
   both.

### Files and records disagree

`content_files sync --verify` runs every night and reports to Sentry. To run it by hand, in the
worker, which is the only container that mounts the packs:

```bash
sudo docker exec wassal-<env>-worker-1 python manage.py content_files sync --verify
```

It writes missing files from the database and never overwrites one. On production it also raises
`core.floor.json` to the highest stored version.
