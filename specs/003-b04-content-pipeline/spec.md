# Feature Specification: Content Pipeline (B04)

**Feature Branch**: `003-b04-content-pipeline`

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "feature 003". Feature 003 in `docs/delivery-plan.md` is B04, step 2:
"Content pipeline: schemas, authoring admin, pack build and publish, manifest, model codegen".
Depends on B01. Sources: docs/architecture-backend.md §9 (with §6.3–§6.4 for the manifest, §12
"content" for the authoring data and §15 for pack storage); docs/architecture-mobile.md §14.
Resolve backend §22.3 (a CDN in front of content packs). Handed over from B01: keep content packs
and their CDN separate from the Backblaze B2 backup buckets, and never reuse the backup keys. Order
inside B04: the schemas and model codegen are the first user story, merged in their own PR as soon
as they are green, so M01 can start. Done when (B04's part of step 2): `trip.schema.json` and the
generated models are on `master`.

## Clarifications

### Session 2026-10-19

- Q: Where do content authors write content, and how does a pack reach production players? → A:
  Authors write on staging, and the tested pack is promoted to production.
  - Authors write, import, build and publish on staging's admin. Testers play staging's published
    pack in staging builds.
  - A publisher on production then promotes that exact file: same version, same checksum. Players
    get byte for byte what testers played. This mirrors how code ships (staging on merge,
    production on tag, B01).
  - Production's admin doesn't author, import or build. It promotes and shows history (FR-039,
    FR-039a).
  - Following from the answer:
    - Rollbacks are also built on staging and promoted (FR-028). A rollback built on production
      would give production version numbers that staging doesn't know.
    - Version numbers come only from staging, which never reuses one that production has used,
      even after staging is rebuilt (FR-039b).
    - B01 doesn't back up staging, and authoring work now lives there, so it needs its own recovery
      path (FR-039c).
    - Promotion must not give either host access to the other's admin, private network or storage
      keys (B01 isolation).
  - The content of every promoted pack still goes into `content/source` (FR-040).
- Q: Until B05 adds the solver check, may staging publish packs without it? → A: No. Nothing is
  published in staging or production until the solver check exists.
  - That leaves no exception to constitution VII.
  - B04 is proven in tests and on the local stack. The first live publish on staging, and the
    success criteria that need it (SC-007, SC-008, SC-012), are checked with B05 (FR-022).
- Q: When does a content identifier become permanent, so it can no longer be renamed or deleted?
  → A: Once it is in a pack published on staging.
  - Staging knows this locally, and every production pack was published on staging first.
  - Identifiers in drafts and in validated but unpublished packs can still be renamed (FR-016).
- Q: May a publisher change a published pack's minimum app version afterwards? → A: Yes, raise or
  lower it.
  - It is the only part of a published pack that can change. The file and its checksum never do.
  - Each environment keeps its own value, and every change is audited.
  - Raising it is the fast kill switch for app versions that a pack breaks: within 1 minute those
    apps are offered the newest older pack they can read (FR-030, FR-031).
  - Lowering it fixes a value set too high, but never below what the pack's schema version needs
    (FR-010, FR-032).

## User Scenarios & Testing *(mandatory)*

This feature has four kinds of users, none of them players:

- **Developers** who build on the schemas and the generated models: the engine (M01), the solver
  (B05), the app's content loader (M04), the ledger and sync validators (B03) and the daily
  challenge (B08).
- **Content authors**: staff who write lines, trips, the story and the dialogue in the admin.
- **The publisher**: a staff member allowed to put a pack in front of players.
- **The mobile app**, which asks the manifest for the current pack and downloads it.

Today the project owner is the developer, the author and the publisher. Players see this feature
only through the content the app shows them.

Two terms used throughout:

- **App models** are the typed content models the mobile app and the engine use
  (`packages/content_models`).
- **Server models** are the typed content models the backend and the solver use.

Both are generated from the schemas (constitution VII).

### User Story 1 - One set of content schemas, with models generated from it for app and server (Priority: P1)

Developers get the content schemas in `content/schemas/`. They cover every part of a pack listed in
backend §9.2: the pack itself, trips, lines, vehicles with their seat layouts, chapters, rooms,
items, speech pools, the catalog, daily rewards, tasks, and the manifest. The app models and the
server models are generated from these schemas and are never written by hand. A shared set of
example files, both valid and deliberately invalid, shows exactly what the schemas accept.

**Why this priority**: M01 builds the engine on the trip schema, and B05, M04, B03 and B08 all read
content through these models. The delivery plan asks for this slice to merge first, in its own PR,
so M01 can start while the rest of B04 continues.

**Independent Test**: Take the backend §9.3 example trip, made self-contained (FR-004). It passes
the trip schema, and the app models and the server models both read it and write it back as the
same canonical JSON. Change a fare to 475 piasters or remove `trip_id`, and the schema rejects it,
naming the field. Edit a generated model by hand, and CI fails.

**Acceptance Scenarios**:

1. **Given** the shared example set, **When** CI runs, **Then** every valid example passes its
   schema, and every invalid example fails it with the path of the offending field.
2. **Given** a valid example, **When** it is read and written back by the app models and by the
   server models, **Then** both outputs are identical to the example's canonical form.
3. **Given** a schema changes and the generated models were not regenerated, or a generated model
   was edited by hand, **When** CI runs, **Then** it fails.
4. **Given** a trip with an archetype that isn't in the glossary, a payment in a denomination
   outside glossary §3.2, a fare that isn't a multiple of 50 piasters, or any fractional number,
   **When** it is validated, **Then** it is rejected.
5. **Given** a newer pack that only adds optional fields, **When** an app built with the older
   models reads it, **Then** it reads the pack and ignores the fields it doesn't know.
6. **Given** a single trip definition taken out of its pack, **When** it is validated against the
   trip schema on its own, **Then** it passes: it carries its stations and fares, its vehicle's
   seat layout, its passengers, events, tray, rules and seed, so a daily challenge or a parity
   fixture can carry it alone.

---

### User Story 2 - Authors write content in the admin (Priority: P2)

A content author signs in to staging's admin, or the local stack's (B01: staff account, second
factor, private network; Clarifications). They
create and edit lines and their stations, vehicles and seat layouts, trips with their passengers
and events, chapters, rooms, apartment items with their style variants, the bride's family's
requests, speech pools and their lines, catalog prices, the daily reward streak, and task
templates. Arabic text shows and edits right to left. Mistakes a single form can catch are shown
on save, next to the field. Authors can also import content from JSON files and export it, so it
can be reviewed and kept in the repository (`content/source`).

**Why this priority**: There is no pack without content. Authoring needs the schemas from US1
first.

**Independent Test**: Enter the §9.3 trip by hand in the admin and export it. The export matches
the example file. Import the whole sample set into an empty environment and export it again. The
files are identical.

**Acceptance Scenarios**:

1. **Given** an author entering a trip, **When** they save it with a fare that isn't a multiple of
   50 piasters, a passenger whose destination isn't one of the trip's stations, or a seat that isn't
   in the vehicle's layout, **Then** each problem is shown on its field and nothing is saved.
2. **Given** any Arabic text field, **When** an author types in it, **Then** the text runs right to
   left and is stored exactly as typed.
3. **Given** a set of `content/source` files, **When** an author imports them, **Then** valid files
   create or update content. **Given** one invalid file in the set, **Then** the whole import is
   refused, the report names each file and field, and nothing is applied.
4. **Given** authored content, **When** it is exported, imported into an empty environment and
   exported again, **Then** the two exports are identical.
5. **Given** an identifier (a trip, line, station, vehicle, item, room or chapter) that is in a pack
   published on staging, **When** an author tries to rename or delete it, **Then** the change is
   refused with the reason. **Given** an identifier that so far appears only in drafts, **When** an
   author renames it, **Then** the rename is allowed.
6. **Given** a staff member without the author role, **When** they open the content pages, **Then**
   they can read but can't change anything.
7. **Given** a reviewed speech line, **When** its text is edited, **Then** its review is cleared,
   and the next build reports the line as unreviewed.
8. **Given** any change to authored content, **When** it is saved, **Then** the change history
   records who changed what, and when.

---

### User Story 3 - The system builds and validates a pack (Priority: P3)

An author asks for a draft pack built from the current content. The system takes a snapshot of the
content, gives it the next version number, and checks it: against the schemas, for references that
don't resolve, for the content rules, and with the solver (from B05). It then builds the pack file
with its checksum. The author gets one validation report that lists every problem and where to fix
it. The build runs in the background, so the author can keep working.

**Why this priority**: Nothing can be published without a validated pack. The checks are what keep
broken or unfair content away from players.

**Independent Test**: Build from the sample content. The report is green and the file's checksum
matches the recorded one. Building the same content with the same version again gives a
byte-identical file. Break a reference, rebuild, and the report names it. That pack can't be
published.

**Acceptance Scenarios**:

1. **Given** content that passes every check, **When** a pack is built, **Then** the report is green
   and the pack has a version, a size and a checksum.
2. **Given** the same content and the same version number, **When** the pack is built twice, on any
   machine, **Then** the two files are byte-identical.
3. **Given** content with a reference that doesn't resolve (a missing station, a speech key with no
   pool, an item in a room that doesn't exist, a catalog price for a product that doesn't exist, a
   purchasable product with no price), **When** a pack is built, **Then** the report lists each
   problem with its entity, identifier and field, and the pack stays a draft.
4. **Given** a speech line that hasn't been reviewed, contains a digit, or uses a placeholder other
   than `{amount}` and `{station}`, **When** a pack is built, **Then** the report lists it as an
   error.
5. **Given** a price in the wrong currency for its kind (an apartment item priced in BONAT, a
   booster priced in JENEHAT), **When** a pack is built, **Then** the report lists it as an error.
6. **Given** a trip whose definition changed since the current published pack, **When** a pack is
   built, **Then** that trip's `rev` is one higher than in the published pack, and unchanged trips
   keep theirs.
7. **Given** an author edits content while a build is running, **When** the build finishes,
   **Then** the pack contains the content as it was when the build started.
8. **Given** the solver check isn't available yet (before B05), **When** a pack is built on
   staging, **Then** the report marks the solver stage "not available", and the pack can't be
   published or promoted.

---

### User Story 4 - A publisher publishes a pack, and the app learns about it (Priority: P4)

A publisher reads a green report and publishes the pack. The exact file that was validated goes to
public storage under a name that is never reused. Its checksum is confirmed from storage, and only
then does the manifest start offering it. Apps check the manifest when they start, then download,
verify and swap the pack (M04, mobile §14.1). Every publish is in the audit log. A rollback
publishes an earlier pack's content again, under a new version.

**Why this priority**: Publishing is what gets new trips and balance fixes to players without an
app release (constitution VII). It depends on everything before it.

**Independent Test**: Publish the sample pack. The manifest lists it with its URL, checksum, size
and minimum app version. Downloading the URL from outside gives a file with that checksum. Publish
a changed pack, and the manifest moves to it while the earlier file stays downloadable. Roll back,
and a new version with the earlier content appears.

**Acceptance Scenarios**:

1. **Given** a validated pack and a publisher, **When** they publish it, **Then** the file is stored,
   its checksum is confirmed from storage, and only then does the manifest offer it.
2. **Given** storage is unreachable or the upload fails during a publish, **When** the publish ends,
   **Then** the manifest still offers the previous pack, the publish is marked failed with its
   reason, and retrying it is safe.
3. **Given** a published pack, **When** anyone tries to change its file, its checksum or anything in
   its record other than the minimum app version, **Then** the change is refused. Its file stays
   downloadable, with the same checksum.
4. **Given** a validated pack whose version isn't higher than the current published version (for
   example because another pack was published meanwhile), **When** someone publishes it, **Then** it
   is refused and must be rebuilt.
5. **Given** a publisher picks an earlier published pack to roll back to, **When** they confirm,
   **Then** that content is validated and published as a new version, and the manifest offers it.
6. **Given** an app whose version is below the current pack's minimum app version, **When** it asks
   the manifest, **Then** it is offered the newest published pack it can read.
7. **Given** an environment where no pack has been published yet, **When** an app asks the
   manifest, **Then** the answer lists no packs, and the app keeps the pack it ships with.
8. **Given** a publish, a failed publish, a rollback or a change of minimum app version, **When** it
   happens, **Then** the audit log records who, when, which version, its checksum and its validation
   report, and no staff member can edit that record.
9. **Given** an author without the publisher role, **When** they try to publish or roll back,
   **Then** they are refused.
10. **Given** the pack storage, **When** anyone tries to list its contents, or to read a draft,
    **Then** they are refused. Only published files can be read, and only by their exact name.
11. **Given** the current pack breaks app version 1.2, **When** a publisher raises its minimum app
    version to 1.3, **Then** within 1 minute the manifest offers 1.2 apps the newest older pack they
    can read, and the change is in the audit log. **When** the publisher tries to lower the minimum
    below what the pack's schema version needs, **Then** they are refused.

---

### User Story 5 - A pack tested on staging is promoted to production (Priority: P5)

Authors write and publish on staging, and testers play that pack in staging builds. When it is
good, a publisher on production promotes it. Production gets the exact file the testers played,
with the same version and the same checksum. Production's admin doesn't write or build content.
Rollbacks are built on staging and promoted the same way (Clarifications).

**Why this priority**: This is how content reaches players. It builds on publishing (US4), and it
means no pack reaches players before testers have played it.

**Independent Test**: Publish a pack on staging, then promote it on production. Production's
manifest offers the same version and checksum as staging's, and the file in production's storage
is byte-identical to staging's. Try to edit content in production's admin, and nothing can be
changed.

**Acceptance Scenarios**:

1. **Given** a pack published on staging, **When** a production publisher promotes it, **Then**
   production's manifest offers the same version with the same checksum, and production's stored
   file is byte-identical to staging's.
2. **Given** a file whose checksum doesn't match staging's record, for example because it was
   corrupted or tampered with on the way, **When** it is promoted, **Then** the promotion is refused
   and production's current pack doesn't change.
3. **Given** a staging pack whose version isn't higher than production's current version, **When**
   it is promoted, **Then** the promotion is refused.
4. **Given** a staging pack whose solver stage didn't pass, **When** it is promoted, **Then** the
   promotion is refused.
5. **Given** production's admin, **When** anyone tries to author, import or build content there,
   **Then** they can't. Production's content pages are read-only.
6. **Given** staging was rebuilt from scratch, **When** its next pack is built, **Then** that pack's
   version is higher than any version production has used.
7. **Given** a promotion, **When** it completes or fails, **Then** production's audit log records
   who, when, the version, the checksum and staging's validation report.
8. **Given** staging is unreachable, **When** a publisher tries to promote, **Then** the promotion
   fails cleanly, production keeps its current pack, and a later retry works.

---

### Edge Cases

- **Two publishes at once**: they run one after the other. Versions only go up. A pack that is no
  longer newer than the current one is refused and must be rebuilt (US4-4).
- **A storage name already taken**: if the stored bytes are the same, it counts as a retry that
  already succeeded. If they differ, the existing file is never overwritten, the publish or
  promotion is refused, and the operator is alerted.
- **Production restored from an earlier backup**: promotions made after that backup are missing
  from production's records, but their files are still in storage. Promoting them again is safe,
  since the stored bytes match (the case above).
- **Staging rebuilt or lost**: its version numbering resumes above every version production has used
  (FR-039b). Authored content comes back with at most 24 hours lost (FR-039c). Content in
  `content/source` can also be imported again.
- **Staging down when production needs a rollback**: the rollback waits until staging is back,
  within B01's 4-hour recovery target. Meanwhile production keeps offering its current pack, and an
  app that can't read a pack keeps the one it has (M04).
- **Promoting out of order** (version 14 before version 13): allowed. Version 13 can no longer be
  promoted afterwards, because it isn't higher than production's current version.
- **Content edited during a build**: the pack is the snapshot taken when the build started
  (US3-7). The report says when that snapshot was taken.
- **A station, seat or item used elsewhere is deleted**: the form refuses it when the reference is
  in the same record. Otherwise the build reports the broken reference.
- **A published trip is changed**: its `trip_id` stays, its `rev` goes up at the next build, and
  players keep their stars, which are stored by `trip_id` (backend §9.1).
- **A published identifier is renamed or deleted**: refused (FR-016). Taking a published trip,
  line, vehicle, item or chapter out of later packs is out of scope for the MVP.
- **An old app and a newer pack**: if the app can't read the newest pack, the manifest offers the
  newest one it can (FR-030). If no published pack fits, the app keeps its bundled pack, and the
  force-update path (B10) brings it up to date.
- **An old app on a pack older than the last 5 versions**: the server no longer looks up that
  version (FR-035). How its sync ops are judged belongs to B03.
- **A pack over the size budget**: the report warns above 2 MB compressed (mobile §19), but the pack
  can still be published.
- **Text with stray braces or an unknown placeholder** (`{amout}`, `{amount`): an error in the
  report.
- **Numbers in text**: any player-visible text with a digit, Arabic-Indic or Western, is an error.
  Numbers go through a placeholder (`{amount}` in dialogue, `{target}` in task text) so the
  player's digit setting applies (constitution X). Other counts are written in words. The plan
  widened this from speech lines to all text (research R14).
- **The solver check times out on one trip** (from B05): that trip fails the solver stage, and the
  pack can't be published. The time budget is B05's.
- **Validation of a big pack takes minutes**: it runs in the background. If the worker restarts
  mid-build, the build is marked failed and can be started again. It never leaves a half-built pack
  that looks valid.
- **Storage or CDN down after a publish**: apps keep the pack they have and retry later (M04).
  Offline play is unaffected (constitution V).
- **A staff member loses the publisher role** while a publish is running: the publish that already
  started finishes. Later ones are refused.
- **The manifest is hammered**: it is rate-limited like every other endpoint (B01) and stays cheap,
  since it reads only the current pack's record.

## Requirements *(mandatory)*

### Functional Requirements

#### Schemas and generated models

- **FR-001**: `content/schemas/` MUST hold one schema per pack part in backend §9.2: `pack`, `trip`,
  `line`, `vehicle` (with its seat layout), `chapter`, `room`, `item`, `speech_pool`, `catalog`
  and `manifest`, plus daily rewards and tasks. The plan decides whether those two get their own
  files or live in `pack`. The schemas are written in JSON Schema 2020-12 (constitution VII) and are
  the only definition of content shared by the app, the backend and the solver.
- **FR-002**: Every identifier MUST follow the formats in Shared Contract Glossary §3.6. Kinds the
  glossary lists as a closed set accept only its values: `archetype`, in-trip `event_id`,
  `booster_id`, `denomination`, `line_id`, `vehicle_id`, `chapter_id`, `room_id`, seat rows and
  columns, and currencies. Adding a value is a glossary change: both architecture docs and the
  schema change in the same PR. Open kinds (`station_id`, `skin`, item slugs, `speech_key`) follow
  the glossary's format.
- **FR-003**: Every amount MUST be an integer: piasters inside trips, `JENEHAT` and `BONAT` in the
  catalog and in rewards. Fares, payments, the initial tray and bag fares MUST be multiples of 50
  piasters, and payments and the tray MUST use only the §3.2 denominations. No fractional number may
  appear anywhere in a pack, including times and percentages (constitution II). This also keeps
  the app and the server reading every value the same way.
- **FR-004**: A trip definition MUST be self-contained. It carries:
  - `trip_id`, `rev`, `line_id` and `vehicle_id`;
  - its vehicle's seat layout (mobile §7.2 `Seat`);
  - 1 to 4 drop-off stations in order, each with its arrival time and fare (ux-spec «الألوان»: a
    trip has at most 4 drop-off stations);
  - the initial tray, the rules, the passengers and the events;
  - the star rules and `max_earnings_jenehat`;
  - the seed it is played with (mobile §7.10).

  It MUST pass the trip schema on its own, so a daily challenge (B08) or a parity fixture (M01, B05)
  can carry one trip without the rest of its pack.
- **FR-005**: Packs MUST hold content, not tunables. Numbers that have a Remote Config key (mobile
  §14.3), such as hop and bubble timings, reputation changes, fuel and ad caps, MUST NOT appear in a
  pack (constitution VIII). Catalog prices are content (constitution VII).
- **FR-006**: Every player-visible text in a pack (line and station names, item names, chapter
  titles, story dialogue, task and request text, speech lines) MUST be stored per locale, with an
  `ar-EG` text required and an `ar` text optional. That way a variant for Gulf players can be added
  later without breaking older apps (constitution VII).
- **FR-007**: The app models and the server models MUST be generated from the schemas and only
  from them. CI MUST fail if the models in use differ from what the schemas generate. Hand-edited
  models are forbidden (constitution VII).
- **FR-008**: The generated models MUST ignore fields they don't know, so an older app can read a
  newer pack that only adds optional fields.
- **FR-009**: A shared example set MUST live next to the schemas: valid and invalid examples for
  every schema. It includes the §9.3 trip made self-contained (FR-004), and a small sample pack
  that uses every part of every schema. CI MUST check that:
  - every valid example passes and every invalid example fails, with the path of the field at fault;
  - the app models and the server models both read every valid example and write it back in
    exactly its canonical form.
- **FR-010**: Once a pack has been published in production, a breaking schema change MUST raise that
  schema's major version, and CI MUST fail a breaking change made without that bump. Breaking means
  removing or renaming a field, changing its type, narrowing its allowed values, or adding a
  required field. A pack built with a new major version MUST require an app version that can read
  it (FR-032). Until the first production publish, the schemas may change freely, because no
  player's app has read a pack yet.
- **FR-011**: The canonical form of a pack (key order, text encoding, whitespace and compression
  settings) MUST be defined once. The same content with the same version MUST always produce the
  same bytes, in any build and on any machine.

#### Authoring

- **FR-012**: Authors MUST be able to create, edit and read in the admin every pack part from FR-001
  except the manifest. This includes items' style variants (up to 3 per item, at the same price:
  product-spec «الشقة») and the bride's family's requests (optional side tasks with BONAT rewards).
- **FR-013**: On save, a form MUST check whatever a single record can show (field types, glossary
  values, multiples of 50, references inside the record) and report each problem next to its field.
  Nothing invalid is saved. Checks that span records run at build time (FR-021).
- **FR-014**: Arabic text fields MUST show and edit right to left, and store text exactly as typed.
- **FR-015**: Authors MUST be able to import content from JSON files in the `content/source` format,
  and export it to that format.
  - An import validates everything first and is all or nothing. Its report names each file and
    field at fault.
  - Authors can export the current content, or the content of any published pack as it was built.
  - Export, import into an empty environment and export again MUST give identical files.
  - Exported files are ordered and formatted consistently, so a diff shows only what changed.
- **FR-016**: An identifier MUST become permanent once it is in a pack published on staging
  (Clarifications). Every production pack was published on staging first, so this covers every
  identifier players have seen. A permanent identifier can't be renamed or deleted, because
  players' and testers' progress and ownership refer to it (backend §9.1, §12). The content behind
  it can still change. Identifiers that appear only in drafts or in validated but unpublished packs
  stay free to rename. The record of which identifiers are permanent MUST survive a staging rebuild
  (FR-039c).
- **FR-017**: Every speech line MUST carry a review state: who reviewed it against the content
  limits, and when (constitution XII). Editing a reviewed line clears its review.
- **FR-018**: Every change to authored content MUST be recorded with who made it, what changed, and
  when.
- **FR-019**: There MUST be two content roles, which the operator gives to staff accounts (B01
  creates staff accounts):
  - **author**: edits, imports, exports, builds and validates;
  - **publisher**: publishes and rolls back on staging, promotes on production, and sets a pack's
    minimum app version (the `content.publish` permission of backend §9.1).

  Staff without a role can read content but can't change it, and no other path (an import, a
  command, a background job started by someone else) gets around a missing role.

#### Building and validating

- **FR-020**: A build MUST snapshot the authored content, give the pack the next version number, run
  the validation, and produce the pack file (canonical JSON, gzip-compressed) with its sha256 and
  size (backend §9.1). Builds run on staging and on the local stack, never on production (FR-039).
  They run in the background. The admin shows each build's status and, when it ends, its report.
- **FR-021**: Validation MUST run these stages and put every finding in one report:
  1. **Schema**: every part against its schema.
  2. **References**: every reference resolves. Trips point at their line, vehicle, stations and
     seats. Each passenger's boarding and destination stations are stations of the trip, in order.
     Group members and group sizes agree. Speech keys have pools. Items belong to existing rooms.
     Chapter goals point at existing items, lines or vehicles. Catalog prices and purchasable
     products match one to one.
  3. **Content rules**:
     - each product kind is priced in its currency: JENEHAT for apartment items, vehicles and
       upgrades; BONAT for boosters, fuel, revive, unlimited fuel and cosmetics (backend §7.4);
     - no real-money price appears in a pack;
     - nothing in a pack converts BONAT into JENEHAT (constitution IV);
     - every speech line is reviewed (FR-017) and uses only the placeholders `{amount}` and
       `{station}`, correctly formed. Task text may use only `{target}`, and other text no
       placeholders at all;
     - no player-visible text contains a digit (Edge Cases);
     - every speech pool has at least one line;
     - every text has its `ar-EG` value.
  4. **Solver**: every trip is solvable with 3 stars and sits in its line's difficulty band
     (backend §10.1). B05 supplies this stage.
  5. **Size**: a warning above 2 MB compressed (mobile §19).

  Each finding names the entity, its identifier, the field, the problem, and whether it is an error
  or a warning.
- **FR-022**: A pack MUST become validated only when every stage passed. Warnings don't block it.
  Until B05 supplies the solver stage, the report marks that stage "not available". Staging refuses
  to publish, and production to promote, any pack whose solver stage didn't pass, with no exception
  (Clarifications). Tests and the local stack use a stand-in solver stage, so the rest of the flow
  can be built and tested now. The first live publish on staging comes with B05, and so do the live
  checks of SC-007, SC-008 and SC-012.
- **FR-023**: At build time, a trip whose definition differs from the one in the current published
  pack MUST get that trip's `rev` plus 1. Unchanged trips keep their `rev`, and new trips start at
  1 (backend §9.1).
- **FR-024**: Publishing MUST use the exact file that was built and validated, never a rebuild.

#### Publishing, the manifest and delivery

- **FR-025**: Publishing MUST require the publisher role and a validated pack whose version is
  higher than the current published version (backend §9.1).
- **FR-026**: A publish MUST store the file in public storage under a name made of the pack id and
  its version that is never reused (`core-<version>.json.gz`, backend §9.1). It then confirms the
  stored file's checksum, and only after that makes the pack current. If any step fails, the
  previous pack stays current, the publish is marked failed with its reason, and retrying is safe.
  A name already taken by different bytes is never overwritten: the publish is refused and the
  operator is alerted.
- **FR-027**: Published packs MUST be immutable. The one exception is the minimum app version in a
  pack's record (FR-032). The file and its checksum never change. Pack files are served over HTTPS
  and can be read
  only by their exact name. Listing the storage is not public, and drafts and validated but
  unpublished packs never go to public storage. Since a file never changes, it is served with
  long-lived caching.
- **FR-028**: To roll back, a publisher on staging MUST be able to pick an earlier published pack.
  Its content is built as a new version, validated, and published like any other pack (backend
  §9.1). The rollback reaches production by promotion (FR-039a).
- **FR-029**: `GET /v1/content/manifest` (backend §6.3, §6.4) MUST answer with the current content
  version and, for each pack, its id, version, URL, sha256, size and minimum app version. The
  response MUST match the manifest schema, and the endpoint MUST be in `contracts/openapi.yaml`.
- **FR-030**: When a request states an app version below the current pack's minimum app version,
  the manifest MUST offer the newest published pack that app can read. A request that doesn't state
  its version is offered the current pack. With nothing published, the manifest lists no packs.
- **FR-031**: The manifest MUST reflect a new publish, a promotion or a change of minimum app
  version within 1 minute.
- **FR-032**: Every pack MUST declare the minimum app version that can read it. It is kept in the
  pack's record and offered in the manifest, not inside the pack file.
  - The publisher sets it at publish time. It defaults to the previous published pack's value.
  - A publisher MAY raise or lower it later, on that environment only. A promotion carries staging's
    value, and production can then change its own (Clarifications).
  - It can never go below the first app version that reads the pack's schema major version
    (FR-010). The plan decides where that mapping is recorded.
  - Every change is audited (FR-038).
- **FR-033**: Until B02 adds player sign-in, the manifest MUST be readable without a player token.
  B02 then puts it behind the access token like the rest of `/v1` (backend §6.3). It is
  rate-limited like every other endpoint (B01).
- **FR-034**: In the MVP there is one pack, `core`, and the content version is the `core` pack's
  version. The manifest format MUST still allow more packs later.
- **FR-035**: For each of the last 5 published versions, the backend MUST be able to look up that
  version's catalog prices and trip definitions (backend §9.1), so B03 can check spend ops and trip
  results against the version a client declares. Older versions drop out of these lookups, and
  their files stay downloadable.
- **FR-036**: Any published pack MUST be retrievable by version, as its file and checksum, so the
  mobile build can bundle it (M04, mobile §14.1).
- **FR-037**: The plan's research MUST resolve backend §22.3 and record the decision in backend §15
  and §22.3. Pack storage and any CDN in front of it MUST:
  - cost USD 0 (the B01 budget);
  - serve over HTTPS;
  - carry the expected load within their free limits (10k DAU for the MVP, the 100k DAU design
    point in backend §2);
  - stay separate from the Backblaze B2 backup buckets, with their own keys, never the backup keys
    (B01 handover);
  - be separate for staging and production, so neither host holds a key to the other's storage.

  The key that can write packs MUST be held only where publishing runs, never by the API service.
  The research also records how pack URLs move to the real domain later, as a configuration change
  only (B01 FR-042a).
- **FR-038**: The audit log MUST record every publish, promotion, rollback and change of minimum app
  version, and every failed one, with who did it, when, the version, the checksum and the
  validation report
  (constitution: content publishes are audit-logged). Records can't be edited or deleted from the
  admin.

#### Environments and the repository

- **FR-039**: Content MUST reach players along one path (Clarifications):
  - Authors write, import, build and publish on staging, and developers do the same on the local
    stack. Testers play staging's published packs in staging builds.
  - Production's admin MUST NOT offer authoring, import or builds, and its content pages are
    read-only. Production gets packs only by promotion (FR-039a).
  - Rollbacks are built on staging (FR-028) and promoted like any other pack.
- **FR-039a**: A publisher on production MUST be able to promote a pack published on staging.
  - Production receives the identical file and confirms that its checksum matches staging's record.
    It checks the file against the schemas, stores it under the same name, confirms the stored
    checksum, and only then makes it current.
  - The pack keeps staging's version number, which must be higher than production's current
    version.
  - Staging's validation report and minimum app version travel with it. The report must show every
    stage passed, the solver stage included. A production publisher may change the minimum app
    version later (FR-032, FR-038).
  - Promotion MUST NOT need either host to reach the other's admin or private network, or to hold
    the other's storage keys (B01 isolation). The plan picks the transfer path.
  - If any step fails, production keeps its current pack and the promotion can be retried, as for a
    publish (FR-026).
- **FR-039b**: Version numbers MUST come only from staging, and staging MUST never assign a version
  at or below one production has used, even after staging is rebuilt from scratch.
- **FR-039c**: B01 doesn't back up staging, but authors now work there, so the content authored on
  staging MUST be recoverable with at most 24 hours of work lost if the staging host is lost. So
  MUST staging's record of its published packs, which sets the version numbering (FR-039b) and the
  permanent identifiers (FR-016). That 24-hour limit is production's recovery point (backend §15). The plan picks how, for example by backing up
  staging's content data or by regular exports to `content/source`.
- **FR-040**: The content of every pack promoted to production MUST also be in `content/source` in
  the repository, as the publisher's export of that pack (FR-015) committed through a pull request.
  CI validates every file there against the schemas, and from B05 re-solves every trip
  (constitution CI gates, backend §16).

#### Quality and documentation

- **FR-041**: The feature ships with its tests (constitution XIII): the schema examples, the
  round trip through the app and server models, every validation rule with a deliberately broken
  case, the import and export round trip, roles, and the publish failure paths. Backend tests run
  against the real database and cache. Line coverage stays at least 80% for the backend and for
  every package this feature adds.
- **FR-042**: `CLAUDE.md` MUST list the new commands: generate the models, validate
  `content/source`, build a pack locally, and import and export content. Backend §9, §15 and §22.3,
  and mobile §14, MUST be updated wherever this feature settles something they leave open.

### Key Entities *(include if feature involves data)*

- **Content schema**: the definition of one pack part, with a version whose major number changes on
  a breaking change (FR-010).
- **Authored content** (backend §12 "content"), edited in the admin and exported to
  `content/source`:
  - **Line**: stations in order, difficulty band and unlock rule.
  - **Station**: an identifier unique within its line, and a name.
  - **Vehicle**: seat layout, capacity, and its price, which lives in the catalog.
  - **Trip**: line, vehicle, stations with times and fares, tray, rules, passengers, events, star
    rules, earnings cap, seed and `rev`.
  - **Passenger spec**: archetype, look (`skin`), seat, boarding and destination stations, payment,
    group and speech keys.
  - **Trip event**: an `event_id` and its timing and parameters.
  - **Chapter**: savings goal, scenes and unlock rule.
  - **Room**, and **Item** with up to 3 style variants.
  - **Family request**: an optional side task with a BONAT reward.
  - **Speech pool**: a `speech_key` and its lines.
  - **Speech line**: text per locale, and its review state.
  - **Catalog price**: a product kind, a product id, a currency and an amount.
  - **Daily reward day** and **Task template**.
- **Content pack**: pack id, version, status (`draft`, `validated`, `published`, `retired`),
  sha256, size, URL, minimum app version, validation report, snapshot time, and who published it
  and when. On production, it also records who promoted it and when. `retired` means it is no
  longer one of the last 5 versions the server looks up (FR-035).
- **Promotion**: a staging pack (version and checksum) made current on production, with who, when
  and the outcome.
- **Validation report**: a result per stage (passed, failed or not available) and the findings,
  each with its entity, identifier, field, problem and severity.
- **Manifest**: the current content version and the packs an app should have.
- **Audit record**: who, when, what (a publish, promotion, rollback or minimum app version change,
  and whether it failed), version, checksum and report.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The app models and the server models write back every valid example, and every pack
  built in tests, in exactly its canonical form: 100%. The schema rejects every invalid example and
  names the field at fault: 100%.
- **SC-002**: A deliberately stale or hand-edited generated model, an invalid `content/source` file,
  and (after the first production publish) a breaking schema change without a major-version bump
  each block the merge every time.
- **SC-003**: An author new to the admin enters the §9.3 example trip by hand in under 15 minutes,
  and its export matches the example file.
- **SC-004**: Building the same content with the same version gives byte-identical files every
  time, in CI and on both hosts.
- **SC-005**: A set of deliberately broken packs, with at least one per rule in FR-021, has every
  fault reported with its entity and field, and none of those packs can be published.
- **SC-006**: Not counting the solver stage, whose time budget is B05's, building and validating a
  pack with the MVP's content volume takes under 1 minute. That volume is 2 lines, 50 trips,
  chapters 1–4 with their rooms and items, and their speech pools. The resulting pack is under 2 MB
  compressed.
- **SC-007**: Within 1 minute of a publish on staging or a promotion on production, that
  environment's manifest offers the new pack, and its file downloads from an outside network with
  the recorded checksum. A promoted file is byte-identical to staging's every time.
- **SC-008**: A rollback is offered by production's manifest within 15 minutes of the publisher
  starting it on staging, promotion included.
- **SC-009**: A check that downloads every published pack again finds no file whose checksum
  differs from its record.
- **SC-010**: With storage made to fail during a publish, the previous pack is still the one
  offered in every run, and a retry once storage is back succeeds.
- **SC-011**: The manifest answers 95% of requests within 150 ms at the design rate of 100 requests
  per second.
- **SC-012**: Storing and serving packs costs USD 0 per month, for both environments together, at
  the expected MVP load: 10k daily players and a new pack every week.
- **SC-013**: After the staging host is lost and rebuilt, the authored content is back with at most
  24 hours of work missing, and the next staging pack's version is above production's current one.

## Assumptions

- **Tools**: the constitution fixes JSON Schema 2020-12, the admin as the authoring tool, background
  jobs on B01's `content` queue, and S3-compatible object storage, which backend §15 names as OCI
  Object Storage for packs. The plan picks the model generators, the schema-diff check and any CDN
  (FR-037).
- **The solver stage comes from B05.** Until then, staging can't publish and production can't
  promote (FR-022). No consumer needs a published pack before B05: M01 needs only the schemas and
  models, and M04 (step 4) comes after B05 (step 3). Setting up the live pack storage can therefore
  wait until B05 is merged, though it may be done earlier.
- **The engine's speech keys**: M01 defines which `speech_key`s the engine emits. Once that list
  exists, validation also checks that each of those keys has a pool.
- **The trip schema will grow with M01.** Changes follow FR-010. They are free until the first
  production publish.
- **Art ships in the app.** Packs are JSON only and refer to art by slug (passenger `skin`, item
  variants, comic panels). Downloading art is out of scope.
- **Content to author**: this feature ships only the sample content (FR-009). The MVP content set
  (20 trips on `line_hay`, 30 on `line_gamaa`, chapters 1–4 with their rooms, items and dialogue)
  is written by authors through this pipeline. It isn't part of this feature.
- **Phase 2 parts** (vehicle upgrades, cosmetics and the garage; `line_souq`, `micro_new` and ch5)
  are out of scope. The schemas leave room to add them as optional parts (FR-008, FR-010).
- **Real-money products** and their store prices belong to live ops (B10), not to packs.
- **Daily challenge templates** (B08) are server-side and are not in packs.
- **Bundling (M04)**: an app build bundles only a pack published in the environment its flavor
  talks to, so that environment's server knows the bundled version (FR-035, FR-036).
- **Client version**: requests are required to carry `X-Client-Version` from B02 and B10 on.
  FR-030 uses it whenever it is present.
- **Owner actions**: the owner creates the pack storage and its keys for staging and for
  production, gives the author role on staging and the publisher role on both, and adds authors'
  devices to staging's private network (B01). These go
  in `docs/owner-actions.md` when `/speckit-implement` finishes.
- **Dependencies**: B01 is merged. This feature feeds M01 (trip schema and app models), B05 (server
  models and the solver stage), M04 (manifest, pack files, bundling), B03 (lookups by version, FR-035)
  and B08 (trip schema).
- **Out of scope**:
  - the solver, difficulty scoring and the admin preview (B05);
  - the app's pack loader, bundled pack and swap (M04);
  - catalog price checks on spend ops (B03);
  - taking published identifiers out of later packs;
  - test-only packs for tester accounts before a publish;
  - phase 2 and phase 3 content.
