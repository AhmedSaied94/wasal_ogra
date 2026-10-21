# Feature Specification: Content Pack Loader (M04)

**Feature Branch**: `006-m04-content-loader`

**Created**: 2026-10-21

**Status**: Draft

**Input**: User description: "feature 0006 (next feature in docs/delivery-plan.md)". Feature 006 in
`docs/delivery-plan.md` is M04, step 4: "Content pack loader, bundled pack, models from schemas". It
depends on M03 (merged in #1) and B04 (merged in #3 and #4). B05 (merged in #6) gave B04 its solver
stage, so staging can now publish packs. Sources: docs/architecture-mobile.md §14 (with §5, §6, §11
and §19); docs/architecture-backend.md §9 (with §6.4 and §13); B04's `contracts/api.md`,
`contracts/pack-delivery.md` and `contracts/content-schemas.md`; docs/ux-spec.md «شاشة التحميل».
Resolve: nothing open in the architecture docs. Handed over from B04 (research, "Handed to later
features"): verify the gzip file's sha256 before decompressing, with a decompression cap; bundle a
pack that production has promoted; read pack URLs only from the manifest. Handed over from M01
(research): the bundled pack must carry a speech pool for every engine slot. From B04's CI contract:
the app starts depending on `content_models` here. Done when: the app loads the bundled pack and
verifies its sha256.

## Clarifications

### Session 2026-10-21

- Q: The app is `0.1.0`, but no pack may declare a minimum app version below the schema set's floor
  for major version 1, which is `1.0.0`, so the manifest would offer this app nothing. Which side
  changes? → A: The app becomes `1.0.0` in M04. That is what B04 means by the floor: the first app
  version that reads schema major 1, which M04 is. `schema-set.json` stays as it is, and later
  internal builds raise the build number (FR-035).
- Q: Should M04 also download new packs from the manifest, or ship only the bundled pack and leave
  downloading to M06? → A: Downloads are in M04 (user stories 2 and 3). Until bootstrap exists, the
  app checks the manifest itself (FR-015), and M06 adds bootstrap's content version as one more
  reason to check.
- Q: Where should a staging build get its bundled pack: from a pack staging has published, or only
  from the newest pack production has promoted (`content/source/`)? → A: Only from `content/source/`,
  for staging and production builds alike. Staging serves that pack too, because production
  promoted it from staging with the same bytes, and CI already validates and re-solves
  `content/source/`. Staging-only packs reach staging builds through the manifest download. Until
  production's first promotion, only dev builds can be made (FR-033, FR-034, US4).

## User Scenarios & Testing *(mandatory)*

The people involved:

- **The player**, who must always have a game to play, online or not.
- **The owner**, who makes the dev, staging and production builds and publishes packs.
- **The features that read content**: the trip screen (M02), the economy and its prices (M05), and
  Home, lines and the apartment (M08–M10). They all read the one active pack this feature provides.

### User Story 1 - The game always has content, even offline on first launch (Priority: P1)

A player installs the game and opens it with no connection. The boot screen appears. The app checks
the pack that came with it, reads it, and the player reaches Home with every line, trip, price and
line of dialogue available. Nothing asks for the network.

**Why this priority**: Constitution V requires every regular trip to be playable with no network,
and the first trip within 20 s of first open. Every later feature reads its content from here. Until
this works, nothing in the game can be played.

**Independent Test**: Install a dev build on a device in airplane mode and open it. It reaches Home,
and the active content reports the bundled pack's version and serves its trips and catalog prices.
In CI, an app test with no network does the same.

**Acceptance Scenarios**:

1. **Given** a fresh install and no network, **When** the app opens, **Then** it reaches Home with
   the bundled pack active, and the active version is the bundled pack's version.
2. **Given** the bundled pack file, **When** the app loads it, **Then** it first checks the file's
   size and sha256 against the values recorded in the build, and only then decompresses and reads
   it.
3. **Given** a bundled file that fails that check (a damaged install), **When** the app opens,
   **Then** it doesn't read the file, and the boot screen shows its failure state with a retry
   (M03) instead of reaching Home with broken content.
4. **Given** the active pack, **When** a feature asks for a trip by id, a line's trips in order, the
   lines in order, a vehicle, a catalog price by SKU, a speech pool by key, a chapter, room, item or
   family request, the daily rewards or the tasks, **Then** it gets them from the active pack, as the
   models generated from the schemas.
5. **Given** the reference device (Galaxy A06) and a pack of the MVP's size, **When** the app cold
   starts, **Then** the pack is decompressed and parsed off the UI thread, so the boot screen keeps
   responding while it loads, and Home appears within the 3 s cold-start budget.

---

### User Story 2 - New content arrives without an app update (Priority: P2)

Authors publish a new pack on staging, and production promotes it. The next time a player opens the
game with a connection, the app learns of it from the manifest and downloads it while the player
plays. It checks the file and starts using it the next time the player arrives at Home, never in
the middle of a trip.

**Why this priority**: Constitution VII. New lines, story chapters and balance fixes must ship
without an app release, and the content pipeline (B04, B05) was built for exactly this. It comes
after US1 because a player with only the bundled pack can still play.

**Independent Test**: On the local stack, publish version 2 built from the sample content. Open a
dev build that holds version 1, play a trip, and return to Home: version 2 is now active. In CI, the
same flow runs against a fake server.

**Acceptance Scenarios**:

1. **Given** the app holds version N and the manifest offers N + k to this app version, **When**
   the app checks the manifest, **Then** it downloads the file from the URL in that manifest entry,
   and from nowhere else.
2. **Given** a finished download, **When** its size and sha256 both match the manifest entry,
   **Then** the app decompresses it within the cap, reads it through the generated models, and
   checks its pack id, version and schema version. Only then does it keep the file as the next pack.
3. **Given** a verified next pack and a trip running or paused, or the pre-trip card or result
   screen showing, **When** the download finishes, **Then** nothing changes until the player
   arrives at Home. There the next pack becomes the active pack in one step.
4. **Given** a verified next pack on the device, **When** the app launches, **Then** the next pack
   becomes active before Home appears.
5. **Given** the manifest offers version 0 with no packs, or a version no higher than the one the
   app holds, **When** the app checks it, **Then** the app keeps its pack and downloads nothing.
6. **Given** the manifest request fails (no connection, a timeout, a server error, a rate limit or
   a body that doesn't read), **When** the app checks, **Then** it keeps its pack, shows the player
   nothing, and tries again at the next check.
7. **Given** any manifest request, **When** the app sends it, **Then** it states the app's version
   and platform, so the server offers the pack this version can read.
8. **Given** a version the app has already verified, **When** the manifest offers it again,
   **Then** the app does not download it again.

---

### User Story 3 - A bad file or an interrupted update never breaks the game (Priority: P2)

A downloaded file is untrusted bytes until it is checked. Mobile connections drop mid-download,
phones kill apps and run out of space, and stored files get damaged. None of this may leave a player
without a working pack, or with a pack that was never verified.

**Why this priority**: A broken pack would stop every trip on every device that took it. This story
makes US2 safe to ship, so the two ship together, but it can be tested on its own.

**Independent Test**: A fake server serves tampered, truncated, oversized, mislabeled and unreadable
files, and the app is killed at each step of download, verification and activation. In every case,
the previous pack stays active, or the new one becomes active complete.

**Acceptance Scenarios**:

1. **Given** a download whose size or sha256 differs from the manifest entry, **When** it finishes,
   **Then** the app discards it without decompressing it, keeps its current pack, and may download
   it again at a later check.
2. **Given** a manifest entry that declares more than the download cap, or a download that grows
   past its declared size, **When** the app sees it, **Then** it stops, and reads nothing.
3. **Given** a verified file that decompresses past the cap, **When** the app reads it, **Then** it
   stops and discards the file.
4. **Given** verified bytes that don't read as a pack this app understands (a value the models
   don't know, a missing field, a non-integer number, an unsupported schema major version, or a pack
   id or version that differs from the manifest entry), **When** the app reads them, **Then** it
   discards the file and records that version as unusable, so this app version never downloads it
   again. A later, higher version is tried normally, and an app update clears the record.
5. **Given** the app is killed at any moment of a download, its verification or the switch,
   **When** it launches again, **Then** exactly one complete, verified pack is active (the old one
   or the new one), and no partial file is ever read.
6. **Given** the device runs out of storage during a download, **When** the write fails, **Then**
   the app discards the partial file, keeps its pack, and tries again at a later check.
7. **Given** a stored downloaded pack, **When** the app launches, **Then** it checks the file
   against its recorded size and sha256 again before reading it. If the check fails, it deletes the
   file, uses the bundled pack, and downloads again at the next check.
8. **Given** an app update whose bundled pack is newer than the stored download, **When** the app
   launches, **Then** the bundled pack becomes active and the older download is deleted. **Given**
   an update whose bundled pack is older, **Then** the app keeps the newer download, as long as this
   app version can read it.

---

### User Story 4 - Every build ships a pack its server knows (Priority: P3)

The owner makes dev, staging and production builds. Each build bundles a pack that the environment
it talks to serves byte for byte, so the app and the server always mean the same content by the same
version number.

**Why this priority**: If a build bundled a pack under a version its server never published, or
published with different bytes, the app would believe it has version N, never download the real N,
and later declare N in sync operations that the server checks against different prices (backend
§7.4). Mobile §14.1 forbids a staging-only pack in a production build for this reason. Staging and
production builds both bundle the newest pack production has promoted: staging knows it too,
because production promoted it from staging with the same bytes (Clarifications). It is P3 because,
until production's first promotion, only dev builds are made, and US1 covers those.

**Independent Test**: The build check is given a correct pack and then each wrong case. It accepts
the first and refuses each of the others with its reason.

**Acceptance Scenarios**:

1. **Given** a dev build, **When** it is made, **Then** it bundles the sample content
   (`content/examples/sample/`) built as version 1, which matches the sample's committed golden
   checksums and is what a fresh local stack publishes from the same sample.
2. **Given** a staging or production build, **When** it is made, **Then** it bundles the newest
   pack production has promoted, whose export is in `content/source/`, byte-identical to
   production's file. Packs that only staging has published reach staging builds through the
   manifest download (US2).
3. **Given** `content/source/` holds no promoted pack yet, **When** a staging or production build
   is made, **Then** the build fails and says so.
4. **Given** a pack that production doesn't serve with the same sha256, whose minimum app
   version is above the app's version, or that fails the content kit's checks (schema, references,
   content rules, and a speech pool for every engine slot), **When** a build is made with it,
   **Then** the build fails with the reason.
5. **Given** any change, **When** CI runs, **Then** it checks that the bundled pack reads through
   the app's models and matches the checksum recorded for it.

---

### Edge Cases

- **Several manifest entries.** The manifest may list up to 5 entries. The app uses only the `core`
  pack and ignores any other.
- **A misconfigured entry.** An entry whose minimum app version is above this app's version, or (in
  staging and production builds) whose URL isn't HTTPS, is ignored as if it weren't there.
- **The server raises the minimum app version** of the pack the player holds. The manifest then
  offers an older pack or none. The app keeps the pack it has, because it never moves to a lower
  version and the pack still works offline. B10's force update handles outdated apps.
- **Long offline periods.** The app plays from its bundled or stored pack indefinitely.
- **A wrong device clock** changes nothing: no decision here depends on the time of day.
- **A trip resumed after the app was killed** (M01 research R10) uses the definition saved in its
  own replay record, so a switch at launch doesn't change that trip.
- **Many launches in a short time.** The app checks the manifest at most once every 15 minutes.
- **Two checks at once.** Only one download runs at a time.
- **The app goes to the background mid-download.** No work continues in the background (constitution
  budgets). The download is abandoned. The cancelled check doesn't count toward the 15 minutes, so
  returning to the app starts it again from the beginning.
- **A pack that drops a trip the player has stars on** can't happen: published identifiers are
  permanent (B04). The loader never touches progress.
- **A pack that names art the app doesn't have** is the trip screen's and apartment's concern
  (M02, M10), not the loader's.
- **A server that keeps serving bytes that don't match** its own manifest. The app stops trying that
  version after 3 failed checks, so a broken server can't drain a player's data.

## Requirements *(mandatory)*

### Functional Requirements

#### The bundled pack and startup

- **FR-001**: Every build MUST contain exactly one pack file for the `core` pack, together with its
  version, size and sha256, recorded by the build from that same file.
- **FR-002**: At launch, the app MUST make active the highest-version pack it can use: a verified
  next pack, a stored active pack, or the bundled pack. The bundled pack is the fallback whenever
  nothing else passes its checks.
- **FR-003**: The app MUST check every pack file it reads (bundled, stored or downloaded) against
  its expected size and sha256 before it decompresses or parses anything. The sha256 is over the
  gzip file as served (B04 research R4).
- **FR-004**: Decompression MUST stop at 32 MiB, production's own promotion cap, and the file is then
  refused.
- **FR-005**: The app MUST read a pack only through the generated content models. A pack is
  readable when every value has the type its schema gives (integers only, every required field
  present, every enum value known); fields the models don't know are ignored (B04 FR-008).
- **FR-006**: After reading a pack, the app MUST check that its pack id is `core`, that its version
  equals the expected version, and that its schema major version is one this app reads.
- **FR-007**: The app MUST decompress and parse every pack off the UI thread, so the boot screen,
  and later the trip scene, keep drawing frames while a pack loads. With a pack of the MVP's size,
  the app MUST still reach Home within the 3 s cold-start budget on the reference device.
- **FR-008**: If no pack passes its checks, which can only happen with a damaged install, the boot
  screen MUST show its failure state with a retry (M03) and MUST NOT show Home.

#### Reading content

- **FR-009**: The rest of the app MUST read content only through one read-only content source that
  serves the active pack. It answers at least: lines in order; a line's trips in order; a trip by
  id; vehicles; a catalog price by SKU kind and SKU id; a speech pool by key; chapters, rooms,
  items and family requests; daily rewards; and tasks.
- **FR-010**: The content source MUST expose the active pack's version, so the economy and sync
  can declare it (M05, M06).
- **FR-011**: The content source MUST tell its readers when the active pack changes, which happens
  only at the points in FR-024.
- **FR-012**: The part of the content source that the engine and the economy rules use MUST be an
  interface free of Flutter and plugin imports (constitution I, mobile §6 `ContentSource`).
- **FR-013**: The app MUST use the content models generated from `content/schemas` and MUST NOT
  define content types of its own. Prices come only from the catalog (constitution VII).
- **FR-014**: The content models' build, analysis and tests MUST run on the app's CI path, and the
  existing codegen check keeps those models equal to the schemas.

#### Checking the manifest

- **FR-015**: The app MUST check the manifest at launch, when it returns to the foreground, and
  when a connection comes back, at most once every 15 minutes, and only while the app is open. A
  check cancelled because the app left the foreground doesn't count toward the 15 minutes.
- **FR-016**: Each flavor MUST know its environment's API address from its build configuration.
  The manifest request goes to that address, states the app's version and its platform, and gives
  up after 10 s.
- **FR-017**: The app MUST read the manifest through the generated manifest model. A body over
  64 KiB, a body that isn't JSON, or one that doesn't read counts as a failed check.
- **FR-018**: The app MUST act only on the `core` entry, and only when the entry's version is above
  the active pack's and any next pack's, its minimum app version is at most the app's version, its
  version isn't recorded as unusable, and (in staging and production builds) its URL is HTTPS.
- **FR-019**: Pack URLs MUST come only from the manifest. The app MUST NOT build a pack URL itself
  or keep a list of pack hosts, so moving packs to a CDN stays a server setting (B04 research R5).

#### Downloading

- **FR-020**: The app MUST run at most one download at a time. It MUST refuse an entry that declares
  more than 16 MiB, production's promotion cap, and MUST stop a download that grows past the size
  its entry declares.
- **FR-021**: Downloads MAY use any connection: packs are small, and the pipeline warns about any
  pack over 2 MiB compressed (B04 `V-S1`).
- **FR-022**: A partial download MUST never be read. An interrupted download starts again from the
  beginning at a later check.
- **FR-023**: A version that fails its size or sha256 check 3 times MUST be recorded as unusable. A
  version that passes those checks but doesn't read (FR-005, FR-006) MUST be recorded as unusable at
  once. The app never downloads an unusable version again, until the app's version changes: an
  update clears the record, because a newer app may read that pack.

#### Switching packs

- **FR-024**: A verified next pack MUST become active only at launch, before Home appears, or when
  the player arrives at Home. It MUST NOT become active while a trip is running or paused, or while
  any other screen shows.
- **FR-025**: The switch MUST be all or nothing. A reader sees either the whole old pack or the
  whole new one.
- **FR-026**: The app MUST NOT switch to a version lower than the active one.
- **FR-027**: A switch MUST NOT change a trip resumed from its replay record, which keeps the
  definition it started with.

#### Storage and recovery

- **FR-028**: A downloaded pack and what the app records about it (version, size, sha256, state)
  MUST survive restarts and app updates. Every write MUST be made so that a kill at any moment
  leaves the previous state intact.
- **FR-029**: The device MUST hold at most the stored active pack and one next pack, besides the
  bundled pack inside the app. Superseded, refused and partial files MUST be deleted.
- **FR-030**: A stored pack that fails its launch check (FR-003) MUST be deleted, and the bundled
  pack used until a download replaces it.
- **FR-031**: After an app update, the higher of the new bundled pack and the stored pack MUST be
  active, as long as this app can read it. The other one, if it is a download, is deleted.
- **FR-032**: Pack files MUST be kept in the app's private storage, which other apps can't read or
  write.

#### Builds

- **FR-033**: A dev build MUST bundle the sample content built as version 1, which matches
  `content/examples/sample.golden.json`. Staging and production builds MUST bundle the newest pack
  production has promoted (its export in `content/source/`), byte-identical to production's file.
  Staging also serves that file, because production promoted it from staging (Clarifications).
- **FR-034**: A build MUST fail when `content/source/` holds no promoted pack (staging and
  production builds), when its pack's sha256 differs from production's release record, when the
  pack's minimum app version is above the app's version, or when the pack fails the content kit's
  checks, including a speech pool for every engine slot (M01).
- **FR-035**: The app's version MUST be at least the schema set's floor for major version 1
  (`min_client_version_by_major["1"]`, `1.0.0`), because no pack may declare a lower minimum (B04
  FR-032), and the manifest offers nothing to an app below every pack's minimum. M04 raises the app
  from `0.1.0` to `1.0.0`, since it is the first app version that reads schema major 1. The floor
  stays as it is, and later internal builds raise the build number (Clarifications).

#### Security and privacy

- **FR-036**: Staging and production builds MUST reach the manifest and pack files only over HTTPS
  (constitution, Security & privacy).
- **FR-037**: The manifest request MUST carry no token, identifier or personal data beyond the app's
  version and platform. The manifest is public until B02 (B04 FR-033).
- **FR-038**: Every refused file and failed check MUST be recorded on the device with a short reason
  code (for example `size_mismatch`, `sha256_mismatch`, `too_large`, `unreadable`, `wrong_identity`,
  `schema_unsupported`, `manifest_failed`), for M15 to report. Records MUST NOT contain pack content.
  The player sees nothing.

#### Testing

- **FR-039**: Tests MUST cover every refusal reason, every point where a switch may and may not
  happen, a kill at each step of download, verification and switch, the app-update cases, the
  build check's accept and refuse cases, and reading the sample pack through the app's models.
  New code MUST reach at least 80% line coverage (constitution XIII).
- **FR-040**: This feature adds no screen. The boot screen and its failure state are M03's, and
  their goldens stay as they are.

### Key Entities

- **Content pack**: one immutable, versioned bundle of all game content (lines, vehicles, trips,
  chapters, rooms, items, family requests, speech pools, the catalog, daily rewards, tasks). It has a
  pack id (`core`), a version, and a schema version. Its shape is set by `content/schemas`.
- **Pack file**: the gzip of the pack's canonical JSON, as the server serves it, with a byte size
  and a sha256 over those bytes. Each version has exactly one pack file.
- **Bundled pack**: the pack file inside the app, with the version, size and sha256 the build
  recorded. It is always present and is the fallback.
- **Manifest entry**: what the server offers this app version: pack id, version, URL, sha256, size
  and minimum app version. It is the only source of pack URLs.
- **Stored pack**: a downloaded pack file on the device, with its recorded version, size, sha256
  and state: downloading, verified next pack, or active. A refused or superseded file is deleted.
- **Active content**: the one pack the app reads from at any moment, with its version. It changes
  only at launch or on arrival at Home.
- **Unusable version**: a version this app version will not download again, with its reason code.
  The record is cleared when the app's version changes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a fresh install with no network, 100% of launches reach Home with a usable pack,
  in CI and on the reference device.
- **SC-002**: With a pack of the MVP's size (50 trips, chapters 1 to 4 and their dialogue), the
  median cold start to Home on the Galaxy A06 stays at or under 3 s, and loading the pack takes at
  most 500 ms of it.
- **SC-003**: A pack at the pipeline's size warning (2 MiB compressed) loads in at most 1.5 s on the
  reference device.
- **SC-004**: 100% of the tampered, truncated, oversized, mislabeled and unreadable files in the
  test set are refused before they can become active, and in every case the previous pack stays
  active.
- **SC-005**: Killing the app at each step of a download, its verification and the switch leaves
  exactly one complete, verified pack active on the next launch, in 100% of runs.
- **SC-006**: A device that opens the app with a working connection at least 1 minute after a
  promotion (B04 FR-031) has the new pack active at its first arrival at Home after the download.
  On a 1 Mbit/s connection, an MVP-size pack downloads and is verified within 30 s.
- **SC-007**: No switch ever happens during a trip: zero switches in tests that finish a download
  at every point of a trip.
- **SC-008**: Each pack version is downloaded at most once per device after it verifies, and at most
  3 times if it keeps failing its checks.
- **SC-009**: No build can ship a pack its environment doesn't serve byte for byte: the build check
  refuses every mismatch case in its tests.

## Assumptions

- **Dependencies.** M03 and B04 are merged, and B05 is merged, so staging can publish. B02 is not:
  the manifest needs no player token until then (B04 FR-033). When B02 lands, M06 adds the token to
  the request.
- **No bootstrap yet.** `GET /v1/bootstrap` arrives with B03 and M06. Downloading is still M04's
  (Clarifications), so until then the app checks the manifest itself (FR-015). M06 then adds
  bootstrap's `content.version` as one more reason to check. The manifest stays the only source of
  pack URLs.
- **The pipeline is the authority on content rules.** The app doesn't re-run the server's reference
  and content rules on a download. Its checks are the chain from the HTTPS manifest to the checksum
  to the file, plus reading through the models and checking the pack's identity. The bundled pack
  gets the full content-kit checks at build time (FR-034).
- **One pack.** Only the `core` pack exists. Regional line packs (product-spec phase 4) are future
  work.
- **Art ships in the app.** Packs are JSON only and refer to art by slug (B04).
- **No player-facing update UI.** Updates are silent. Constitution V counts content updates among
  the features that need the network, but they have no screen or button of their own, so there is
  nothing to mark «محتاج نت», and they never block play. The offline banner belongs to the features
  that need the network, and the force-update card to B10. The boot screen, including its
  pass-through when loading takes under 2 s (ux-spec «شاشة التحميل»), is M03's.
- **No analytics yet.** Reason codes are recorded on the device (FR-038). M15 sends them.
- **Local storage.** M05 adds the app database, which mobile §11 gives a `content_cache` table. M04
  comes first in the same step, so the plan decides where M04 records its stored pack, keeping it
  small enough to move into M05's database later.
- **The dev stack.** The flavor's API address is build configuration, not a secret. The local stack
  serves plain HTTP on the developer's machine. Constitution 1.2.0 lets the dev flavor reach it that
  way, and only the dev flavor; staging and production builds never call plain HTTP (plan research
  R12).
- **Before the first promotion.** Staging and production builds need a pack production has
  promoted, so until production's first promotion only dev builds can be made. That is harmless:
  production has no players before the closed test (delivery plan step 7 or 12), and promoting a
  pack to it early only makes those builds possible.
- **Operational numbers.** The 15-minute check interval, the 3-attempt limit and the caps (64 KiB
  manifest, 16 MiB download, 32 MiB decompressed, the last two equal to production's promotion caps)
  are protocol limits, not balancing numbers, so constitution VIII's Remote Config rule doesn't
  apply to them. The plan may still make them tunable.
- **Hand-overs.**
  - M02 reads trips and speech pools from the content source.
  - M05 reads catalog prices and declares the active version in its ledger operations.
  - M06 adds the bootstrap trigger and the player token.
  - M15 reports the reason codes.
  - M02 measures the trip scene's frame rate with a download running.
- **Out of scope**: the trip screen and every other screen that shows content (M02, M08–M10);
  choosing speech lines and filling their placeholders (M02); prices in the economy (M05);
  bootstrap and sync (M06); the force update (B10); analytics (M15); downloading art; packs other
  than `core`.
