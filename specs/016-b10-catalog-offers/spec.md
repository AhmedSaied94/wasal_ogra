# Feature Specification: Live-ops Settings, Store Catalog and Offers (B10)

**Feature Branch**: `016-b10-catalog-offers`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "feature 016 (next in docs/delivery-plan.md)". In `docs/delivery-plan.md`
step 8, spec 016 is B10: "Live-ops catalog and offers: store product grants, offer eligibility, live
settings", which depends on B03. Sources: `docs/architecture-backend.md` §8.1 (the store product
catalog), §11.2 (`expire_offers`), §11.4 (offers), §12 (`StoreProduct`, `Offer`, `LiveSetting`),
§6.2 (`426`, `503 maintenance`), §6.5 (versioning and force update) and §15 (maintenance mode); the
phone side in `docs/architecture-mobile.md` §14.3 and §15.2; the shop's data in
`docs/design/HANDOFF.md` (`Shop`, "Dynamic data"). To resolve (delivery plan, step 8): backend
§22.10 (the BONAT pack amounts) and HANDOFF §9.3 #8 (a maintenance end time in the 503 answer).
Handed over from M01 (research R19): create the server's live settings with every key in
`apps/mobile/assets/config/tunables.json`, ending M01's exception to constitution VIII. Handed over
from B03 (research R14 and "Handed to later features"): move B03's server-only numbers, and the rest
of its economy settings, from env settings into live settings, ending B03's exception to
constitution VIII; answer `426 client_outdated`; make bootstrap's `client` block live. Handed over
from M06 (research R18, R19): the `426` and the maintenance answer with its end time, whose field
name M06 proposed as `details.until`. Handed over from B02 (research R10): refuse old app versions
from the same parsed `X-Client-Version`. Done when (step 8, together with B07 and M11): every ad
placement's caps are enforced on the device and on the server, reading their numbers from one
place.

## Clarifications

### Session 2026-11-01

- Q: How are the phone-facing live settings kept equal to Firebase Remote Config? → A: Remote
  Config stays the place phone values are edited (its conditions and experiments live there). A
  daily server job reads Remote Config's default values with a read-only credential and flags every
  phone-facing setting whose server copy differs (FR-009).
- Q: What BONAT amount and bonus does each pack get at launch (backend §22.10)? → A: The core-r1
  draft sets none, so the smaller packs: `bonat_pack_s` 60, `bonat_pack_m` 300 + 30 bonus,
  `bonat_pack_l` 800 + 120 bonus, with `bonat_pack_l` as best value. They are catalog data, retuned
  after the closed test without a release (FR-020).
- Q: Does `result_double` get a daily cap on top of one per trip? → A: No, not now. It stays one per
  trip until closed-test data shows a cap is needed; adding one later is a new tunable on both sides
  (FR-029).
- Q: Before raising the minimum app version, should the admin show how many active players are on
  each app version? → A: Yes. The server records each player's last app version and platform, and
  the version settings show active players (last 7 days) per version and the share a new minimum
  would block, before the save (FR-031, FR-032).
- Q: While maintenance is on, do the scheduled jobs that write data pause? → A: Yes. Each job that
  writes skips its run, logs the skip, and runs on its next schedule; monitoring jobs, which write
  only their own check rows, keep running (FR-034).
- Q: Does a drift between a server live setting and Remote Config also alert the operator? → A:
  Yes, for the settings both sides apply (today `fuel_max`, `fuel_max_subscriber`,
  `fuel_regen_minutes`, `ads_fuel_refill_daily_cap`): the check reports them to Sentry, which emails
  the operator. Drift on a setting only the phone applies gets the admin mark only (FR-009).
- Q: Can maintenance be switched from the command line, and does the deploy turn it on? → A: Both
  the admin and a management command switch it, each recorded in the history. The deploy doesn't
  switch it by itself; the deploy runbook says when to run the command by hand (FR-033).

## User Scenarios & Testing *(mandatory)*

Players see this feature only through what it makes possible: a shop whose packs show the right
amounts, an update screen when their app is too old to play safely, and a calm "we'll be back at
17:30" card instead of errors while the servers are being worked on. Its direct users are:

- **The live-ops operator** (the owner, for now), who retunes the economy after every playtest,
  turns maintenance on and off, raises the minimum app version, and edits store products and
  offers, all in the admin, without a release or a restart.
- **The app**, which reads the client block in bootstrap, the products and offers list, and the
  `426` and `503 maintenance` answers.
- **The later backend features**: B06 grants what a store product says it grants, B07 caps ad
  rewards with live numbers, B08 and B11 read their own live numbers, B12 and B14 add offers.

### User Story 1 - The operator retunes a number without a release (Priority: P1)

After a playtest the owner decides that two overdrafts a day is too generous and that comeback
gifts should come after 5 days away instead of 7. They open the admin's live settings, change both
numbers, and within a minute every server process applies the new values. The change is recorded
with who made it, when, and the old and new values. A value outside its allowed range, or one that
breaks a rule between two settings (a subscriber's tank smaller than the normal tank), is refused
with a message that names the setting.

**Why this priority**: Constitution VIII requires one server copy of every balancing number, and two
earlier features (M01, B03) shipped with time-boxed exceptions that end only when this exists. Every
other story in this feature, and B07's ad caps, read their numbers from here.

**Independent Test**: Change `ECONOMY_FUEL_OVERDRAFT_PER_DAY`'s live value from 2 to 1 in the admin,
then send a sync batch with two empty-tank starts on one game day: the second is refused with
`cap_reached` without a restart. Try to save 0 for the tank and see the refusal.

**Acceptance Scenarios**:

1. **Given** the server is running with the defaults, **When** the operator saves a new valid value
   for a server-only number, **Then** every server process applies it to requests that start at
   most 60 seconds later, with no restart and no deploy.
2. **Given** a live setting, **When** the operator saves a value of the wrong type, outside its
   range, or one that breaks a cross-setting rule, **Then** the save is refused, the old value stays
   in force, and the message names the setting and the rule.
3. **Given** any saved change, **When** the operator opens the setting, **Then** they see its
   history: who changed it, when, the old and the new value, and an optional note.
4. **Given** a setting changed away from its default, **When** the operator resets it, **Then** the
   default applies again and the reset is recorded like any change.
5. **Given** a fresh database, **When** the server starts, **Then** every setting exists with its
   default, every phone-facing setting's default equals the app's bundled default in
   `tunables.json`, and CI fails if the two ever differ.
6. **Given** a staff member without the live-ops permission, **When** they open the admin, **Then**
   they can't see or change live settings, products or offers.

---

### User Story 2 - An app too old to play safely is asked to update (Priority: P1)

A rule change shipped in app 1.3.0, and older apps would send results the server can no longer
judge. The operator raises the minimum Android version to 1.3.0. A player on 1.2.4 opens the game:
bootstrap still answers, says the update is forced, and the app shows its blocking update card. Any
other player call from that app is answered `426 client_outdated`, so nothing it sends is applied.
Players on 1.3.0 or later notice nothing. When the operator also raises the latest version, newer
apps that are below it are offered an optional update.

**Why this priority**: Without it, the only way to stop an unsafe old app is to change the server
in a way that breaks it. M06 already handles both answers on the phone and waits for this to make
them real.

**Independent Test**: Set the Android minimum to 1.3.0, then call bootstrap and sync with
`X-Client-Version: 1.2.4`: bootstrap answers 200 with `force_update: true`, sync answers `426`. The
same calls from 1.3.0 and from `X-Platform: ios` are unaffected.

**Acceptance Scenarios**:

1. **Given** a minimum version for a platform, **When** an app of that platform below it calls
   bootstrap, **Then** the answer is 200 with `client.min_version`, `client.latest_version` and
   `force_update: true`.
2. **Given** the same app, **When** it calls any other player endpoint, **Then** the answer is
   `426 client_outdated` with the minimum version in `details`, and nothing is applied.
3. **Given** the same app, **When** it signs in (`auth/anonymous`, `auth/refresh`) or reads the
   content manifest, **Then** those calls still work, so it can reach bootstrap and learn it must
   update.
4. **Given** an app at or above the minimum, **When** it calls anything, **Then** no version answer
   is given; `force_update` is false and `latest_version` is the platform's latest.
5. **Given** the operator tries to save a minimum above the latest for a platform, **When** they
   save, **Then** it is refused.
6. **Given** players active in the last 7 days on several app versions, **When** the operator enters
   a new minimum for a platform, **Then** before saving they see the count of active players per
   version and how many, and what share, the new minimum would block.

---

### User Story 3 - The shop shows what each store product gives (Priority: P2)

The shop lists three BONAT packs and «شيل الإعلانات». The amounts, the free bonus on the larger
packs, and which pack carries the «أوفر كيس» ribbon come from the server's store catalog, not from
the app: the app asks the store only for the localized price. The same catalog tells B06 what to
grant when a purchase of each product is verified. The operator can change a pack's amount, its
bonus, its ribbon, or hide a product, and the next shop open reflects it.

**Why this priority**: M12's shop and B06's purchase grants both need it, and both come in step 9,
right after this feature. It resolves backend §22.10.

**Independent Test**: Call the offers endpoint as an Android player: it lists `bonat_pack_s`,
`bonat_pack_m`, `bonat_pack_l` and `remove_ads` with their grants and display data. Deactivate
`bonat_pack_s` in the admin and call again: it is gone.

**Acceptance Scenarios**:

1. **Given** the seeded catalog, **When** a player's app asks for products and offers, **Then** the
   answer lists every active product for the app's platform with its kind, what it grants (BONAT
   amount and bonus, or the entitlement), and its display hints (the best-value ribbon, the display
   order), and never a real-money price.
2. **Given** a product deactivated or not offered on the app's platform, **When** the app asks,
   **Then** that product is not in the answer.
3. **Given** a product's grants, **When** B06 verifies a purchase of it, **Then** it grants exactly
   what the catalog says at that moment, through the ledger, and records what it granted on the
   purchase (B06 builds this; B10 provides the catalog and one way to read it).
4. **Given** the operator edits a product's grants, **When** they save, **Then** the change is
   recorded with who and when, a BONAT amount must be a positive integer, and a product id must be
   one of glossary §3.5.

---

### User Story 4 - Maintenance pauses the server's writes, not the game (Priority: P2)

The owner needs twenty minutes to migrate the database. They turn maintenance on in the admin with
an end time of 17:30 Cairo. Players keep playing trips offline; their app's sync answers `503
maintenance` with the end time, holds its queue, and Home shows the maintenance card with «17:30»
in the player's digits. Reads such as bootstrap keep working. When the owner turns maintenance off,
the next sync goes through and nothing was lost.

**Why this priority**: Without it, the only way to pause writes is to take the API down, which
turns into error states on every phone. It settles HANDOFF §9.3 #8's end time, which M06's card
already reads.

**Independent Test**: Turn maintenance on with an end time; `POST /v1/sync` answers `503` with code
`maintenance` and the end time in `details.until`; `GET /v1/bootstrap` answers 200. Turn it off;
the same sync is applied.

**Acceptance Scenarios**:

1. **Given** maintenance is on, **When** a player app calls a state-changing endpoint, **Then** the
   answer is `503` with code `maintenance` and nothing is applied.
2. **Given** maintenance is on with an end time, **When** the answer is sent, **Then**
   `details.until` holds the end time in ISO-8601 UTC; without an end time, `details.until` is
   absent.
3. **Given** maintenance is on, **When** the app calls a read (bootstrap, state, offers, the
   manifest) or signs in, **Then** it is answered normally.
4. **Given** maintenance is on, **When** a store or ad network calls one of its server callbacks
   (B06, B07), **Then** the callback is still received and recorded, so nothing they send is lost.
5. **Given** the end time has passed and maintenance is still on, **When** the app calls, **Then**
   maintenance stays on (only the operator ends it) and `details.until` is omitted rather than shown
   in the past.

---

### User Story 5 - Offers appear only to the players they are meant for (Priority: P3)

Later features add offers: the starter pack after chapter 1 until day 7 (phase 2), a seasonal sale,
a season pass (phase 3). The operator creates an offer that points at a store product, gives it a
time window, a priority and eligibility rules (country, days since install, whether the player has
ever paid, products owned, chapter reached), and the server decides for each player whether it
shows. Expired offers stop showing on their own. No offer ships at launch; the rules engine is
built and tested now so later features add data, not code.

**Why this priority**: The MVP has no offer to show, but B12 and B14 depend on the mechanism, and the
offers endpoint the shop calls is the same one.

**Independent Test**: Create an offer for `remove_ads` limited to `country = EG` and players
installed less than 7 days ago; call the endpoint as an Egyptian player on day 2 (listed), on day 8
(not listed) and as a Saudi player (not listed). Set its end in the past: the hourly job marks it
expired and it no longer lists.

**Acceptance Scenarios**:

1. **Given** an active offer within its window whose every rule the player meets, **When** the app
   asks, **Then** the offer is listed with its product, its end time and its priority order.
2. **Given** the player fails any rule, or owns the non-consumable product it sells, **When** the
   app asks, **Then** the offer is not listed.
3. **Given** an offer whose end has passed, **When** the hourly job runs, **Then** it is marked
   expired, and it is never listed after its end even before the job runs.
4. **Given** a rule the server doesn't know, **When** the operator saves the offer, **Then** the
   save is refused with the rule's name.

---

### Edge Cases

- **A server process can't read the live settings** (a database error during its periodic
  re-read). It keeps using the last values it read and logs a warning; it never falls back silently
  to code defaults while a different value is saved. A process that has never read them fails like
  any request during a database outage.
- **Two operators save the same setting at once.** The last save wins, both are in the history, and
  every process converges on the saved value within the propagation window.
- **A setting changed in the middle of a sync batch.** The batch uses one snapshot of the settings
  from its start to its end (as B03's per-batch settings do today).
- **A deploy whose code adds a setting.** The new setting is created with its default on migrate; a
  setting the code no longer knows is kept, marked unused, and ignored.
- **An env value set on a host before this feature** (B03 allowed a host's env file to override a
  default). On the first migrate, a value that differs from the default becomes the live value, so
  the deploy changes nothing a player sees; afterwards the env variable is ignored and the deploy
  check warns that it should be removed.
- **`X-Client-Version` missing or malformed.** The existing header check (B02) refuses it before any
  version comparison; a build suffix (`+BUILD`) is ignored as the manifest already does.
- **A scheduled job already running when maintenance is turned on.** It finishes its current run
  (each run is chunked and short, as B03's prune is); the switch applies from its next run.
- **Maintenance during an in-flight batch.** A batch that started before maintenance was turned on
  finishes normally; the switch applies to requests that start after it.
- **A product the store doesn't return** (not yet set up in Play Console). The server still lists it;
  the app hides what the store doesn't return (HANDOFF `Shop`, "States").
- **An offer pointing at a deactivated product.** It is not listed.
- **A pack's amount changed while a purchase is pending.** The purchase is granted what the catalog
  says when it is verified, and the purchase row records the amount it got.

## Requirements *(mandatory)*

### Functional Requirements

#### Live settings

- **FR-001**: The server MUST hold one live setting for every key in
  `apps/mobile/assets/config/tunables.json`, with the same default, and one for each of B03's
  economy and sync balancing numbers (`ECONOMY_FUEL_*`, `ECONOMY_TRAFFIC_JAM_ADS_PER_TRIP`,
  `ECONOMY_NAME_MIN_LENGTH`/`MAX_LENGTH`, `SYNC_MIN_DURATION_PERCENT`, `SYNC_FAST_RUN_PERCENT`,
  `SYNC_TRIPS_PER_DAY_FLAG`, `SYNC_CLOCK_CLAMP_FLAG_MINUTES`, `SYNC_SESSION_GAP_MINUTES`,
  `SYNC_COMEBACK_AWAY_DAYS`, `SYNC_COMEBACK_COOLDOWN_DAYS`, `SYNC_CONTENT_MAX_AGE_DAYS`), the
  per-platform minimum and latest app versions, and the maintenance switch and end time.
- **FR-002**: Every server code path that today reads one of those numbers from an env setting MUST
  read it from the live settings instead, and the env variables MUST be retired from
  `config/env.py` and `.env.example` (ending M01's and B03's exceptions to constitution VIII).
- **FR-003**: Deployment settings that are not balancing numbers MUST stay env settings:
  `SYNC_GAME_TIMEZONE`, `SYNC_OP_RETENTION_DAYS`, `THROTTLE_*` rates, `CONTENT_INDEX_KEEP` and every
  secret or URL.
- **FR-004**: Each setting MUST declare its type (integer, string from a closed list, version), its
  allowed range or values, its default, who applies it (the phone only, the server only, or both),
  and a one-line meaning.
  Cross-setting rules MUST be checked on save: subscriber tank ≥ tank; fast-run percent ≥ minimum
  duration percent; name maximum ≥ name minimum; minimum version ≤ latest version per platform;
  and mobile §14.3's caps (`booster_traffic_jam_ms` ≤ 60000, `booster_traffic_jam_max_per_trip` ≤ 5).
- **FR-005**: A saved change MUST apply on every server process to requests that start at most 60
  seconds later, without a restart.
- **FR-006**: Every change and reset MUST be recorded: setting, old value, new value, staff member,
  time and an optional note. Records are never edited or deleted.
- **FR-007**: A sync batch MUST read one snapshot of the settings for its whole run.
- **FR-008**: CI MUST fail when a phone-facing setting's default differs from `tunables.json`, or
  when `tunables.json` has a key the server lacks (replacing B03's four-key parity test).
- **FR-009**: Firebase Remote Config MUST stay the place where phone-facing values are edited. A
  daily scheduled job MUST read Remote Config's default values with a read-only credential and, for
  each phone-facing setting whose server value differs, mark the setting as drifted in the admin
  with both values and log a warning. When the drifted setting is one both the phone and the server
  apply (FR-004's flag; today `fuel_max`, `fuel_max_subscriber`, `fuel_regen_minutes` and
  `ads_fuel_refill_daily_cap`, and B07's caps when it adds them), the job MUST also report it to
  Sentry, one event per run naming every such setting and both values. It MUST never write to Remote Config or change a live value
  by itself. When Remote Config can't be reached, the job retries with backoff, records that the
  check didn't run, and leaves earlier drift marks as they were. Conditional values (per country,
  experiments) aren't compared; only defaults are.
- **FR-010**: Only staff in a new `live_ops` permission group (and superusers) MUST be able to view
  or change live settings, store products and offers, with B01's TOTP admin login.
- **FR-011**: On the first migrate on a host, a B03 env value that differs from its default MUST
  become that setting's live value, recorded in its history as an import, so the deploy changes no
  behaviour.

#### Client version policy

- **FR-012**: Bootstrap's `client` block MUST come from the live per-platform minimum and latest
  versions (for the request's `X-Platform`), with `force_update` true when `X-Client-Version` is
  below the minimum. Bootstrap MUST still answer 200 then.
- **FR-013**: Every other player endpoint MUST answer `426 client_outdated` to an app below its
  platform's minimum, with `details.min_version`, before applying anything. `POST /v1/auth/anonymous`,
  `POST /v1/auth/refresh`, the content manifest and the health endpoints MUST be exempt.
- **FR-014**: Versions MUST be compared as `MAJOR.MINOR.PATCH` integers with any `+BUILD` ignored,
  using the version parsing B02 already does for `X-Client-Version`.
- **FR-031**: Every bootstrap MUST record the player's app version and platform, overwriting the
  previous one (B02's columns, also set on sign-in and renewal; the build suffix is ignored when
  versions are counted), and the player's activity time comes from their last bootstrap, state or
  sync. It is deleted
  with the player (B09) and never sent to analytics from the server.
- **FR-032**: The admin's version settings MUST show, per platform, the players seen in the last 7
  days per app version, and, for a minimum being entered, how many of them and what share it would
  block, before the operator confirms the save. Players never seen with a version (before this
  feature) are shown as "unknown" and not counted as blocked.

#### Maintenance

- **FR-015**: While maintenance is on, every state-changing player endpoint (`POST /v1/sync`,
  `POST /v1/auth/link`, `DELETE /v1/account`, and later `POST /v1/purchases/verify` and
  `POST /v1/daily-challenge/result`) MUST answer `503` with code `maintenance` and apply nothing.
- **FR-016**: The answer MUST carry `details.until` (ISO-8601 UTC) when the operator set an end time
  that is still in the future, and omit it otherwise. The field name is recorded in backend §6.2.
- **FR-017**: Reads, sign-in and refresh, the admin, and machine callbacks from stores and ad
  networks MUST keep working during maintenance.
- **FR-018**: Turning maintenance on or off MUST be recorded like any setting change and apply
  within the window of FR-005.
- **FR-033**: Maintenance MUST also be switchable with a management command (`on` with an optional
  end time, `off`, and a status read) that takes `--actor <staff>`, checks that staff member's
  `live_ops` permission as the admin does, and records the change in the same history. The deploy
  workflow MUST NOT switch it by itself; `docs/runbooks/deploy-and-rollback.md` MUST say when to run
  it by hand (a migration that rewrites or locks a large table) and how to run it in a host's
  container.
- **FR-034**: While maintenance is on, every scheduled job that writes data (today
  `economy.tasks.prune` and `expire_offers`; later features' jobs too) MUST skip its run and log the
  skip, then run on its next schedule. Monitoring jobs, which write nothing but their own check
  rows (the Remote Config drift check, the Celery heartbeat), MUST keep running. A job whose skipped run would lose something for a player (a daily
  grant, a push due that day) MUST catch up on its next run; this is a rule for the later features
  that add such jobs.

#### Store product catalog

- **FR-019**: The server MUST keep a catalog entry for each glossary §3.5 product the MVP sells:
  `bonat_pack_s`, `bonat_pack_m`, `bonat_pack_l` (consumable; a BONAT amount and a bonus, both
  integers ≥ 0, amount > 0) and `remove_ads` (non-consumable; grants the `remove_ads` entitlement,
  from which the `no_interstitials` flag is derived). Each entry has its platforms, an active flag,
  a display order and a best-value flag (at most one active pack carries it). Phase 2 and 3 products
  are added later as data.
- **FR-020**: The seeded packs MUST be `bonat_pack_s` 60 BONAT, `bonat_pack_m` 300 + 30 bonus and
  `bonat_pack_l` 800 + 120 bonus, with `bonat_pack_l` as best value (resolves backend §22.10). The
  `Shop` board's sample (120 / 500 + 50 / 1,200 + 200) is only a drawing: these seeded values win.
- **FR-021**: The catalog MUST never hold a real-money price; prices are store price tiers only.
- **FR-022**: The server MUST offer one way for other features to read a product's grants at a
  moment, and B06 MUST use it to grant (the grant itself, through the ledger, is B06's).
- **FR-023**: Catalog changes MUST be recorded with who, when and the old and new grants.

#### Offers and the products endpoint

- **FR-024**: `GET /v1/offers` MUST answer, for the calling player and their platform, the active
  catalog products (FR-019, without prices) and the offers the player is eligible for, each with its
  product, end time and priority, ordered by priority. It follows the `/v1` defaults (player token,
  headers, per-player throttle).
- **FR-025**: An offer MUST have an id, a kind, a product, a start, an optional end, a priority and
  a set of rules; it is listed only between its start and its end, only when its product is active
  on the player's platform, and only when the player meets every rule.
- **FR-026**: The rules MUST support: country in a list; days since install within a range; payer
  status (has or hasn't made a granted purchase, neutral until B06 records purchases); owns or
  doesn't own a product; reached a chapter. An offer selling a non-consumable is never listed to a
  player who owns it. An unknown rule MUST be refused when the offer is saved.
- **FR-027**: An hourly scheduled job MUST mark offers past their end as expired; listing MUST not
  depend on the job having run.
- **FR-028**: No offer is seeded for launch.

#### Ad caps

- **FR-029**: The server's ad caps (`ads_fuel_refill_daily_cap`, the traffic-jam ads per trip, and
  the caps B07 adds) MUST be live settings that B07 and B03's validators read, so the device and the
  server enforce the same numbers. `result_double` MUST stay one per trip with no daily cap; this
  feature adds no new ad tunable.

#### Contracts and docs

- **FR-030**: `contracts/openapi.yaml`, backend §6.2 (the 426 and the maintenance `details`), §6.4
  (bootstrap's `client` block), §12 and mobile §14.3 (the server-only numbers are live settings, no
  longer env) MUST be updated in the same change.

### Key Entities

- **Live setting**: a named balancing or operational number the server applies; its type, range,
  default, current value, who applies it (phone, server or both), and its meaning.
- **Player's last app version**: per player, the platform, the app version and when it was last
  seen; the source of the version counts.
- **Drift check result**: the last Remote Config comparison: when it ran, whether it could, and for
  each phone-facing setting the Remote Config default it saw when that differs from the server.
- **Live setting change**: one immutable record of a change or reset: setting, old and new value,
  staff member, time, note, and whether it was an import from env.
- **Store product**: a glossary §3.5 product the server knows: kind (consumable, non-consumable,
  subscription later), platforms, what it grants (BONAT amount and bonus, or an entitlement), active
  flag, display order, best-value flag. No price.
- **Offer**: a time-boxed, prioritized presentation of a store product to the players its rules
  select; its state (scheduled, active, expired).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The operator can change any balancing number and see it applied to new requests on
  staging in under 2 minutes from opening the admin, with no deploy or restart.
- **SC-002**: After this feature, zero balancing numbers the server applies are read from env
  settings or code constants, and the two constitution VIII exceptions (M01, B03) are closed in
  their plans.
- **SC-003**: An app below the minimum version gets the forced update screen on its next launch with
  a network, and none of its writes are applied (100% of its non-exempt calls answer 426 in tests).
- **SC-004**: During a maintenance window, players on a current app see no error state: offline trips
  continue, and 100% of their queued operations are applied once maintenance ends, with none
  duplicated.
- **SC-005**: The shop's pack amounts, bonuses and best-value ribbon can be changed by the operator
  and appear on the next shop open, with no app release.
- **SC-006**: Every offer eligibility rule has tests for a player who meets it and one who doesn't,
  and the offers endpoint answers within the API's normal latency budget at the 100k DAU design
  point (no per-player query growth with the number of offers beyond a small fixed bound).
- **SC-007**: Every live-settings, product and offer change can be traced to a person and a time.

## Assumptions

- **Server-only numbers get no Remote Config key.** The phone never applies them (constitution IV),
  so the server's live setting is their one copy; mobile §14.3 lists them as server-only. The plan's
  Constitution Check confirms this reading of VIII.
- **Most phone-facing settings are a copy the server doesn't apply** (trip timings, reputation
  deltas). They exist for constitution VIII's single list and for B08's replay checks; changing one
  on the server alone changes nothing on phones.
- **Who is exempt from 426.** Sign-in, refresh and the manifest stay open so an old app can reach
  bootstrap and show the update card (M06 R18 handles a 426 from any call anyway).
- **Maintenance is operator-ended.** An end time is information for players, not a timer.
- **B06 grants, B10 defines.** Purchase verification, entitlements and payer status arrive in B06;
  until then payer status is "has not paid" for everyone and `remove_ads` is never owned.
- **The drift check needs a Firebase credential.** The owner creates a read-only Remote Config
  service account for each host and stores it as a secret (an owner action). Until it exists, the
  check reports "not configured" and nothing else fails.
- **Real-money prices** are set by the owner as price tiers in Play Console (an owner action), never
  on the server.
- **Propagation window.** 60 seconds is short enough for a live-ops change and long enough to cache
  settings per process instead of reading the database on every request.
- **iOS** has its own minimum and latest versions from the start, even though iOS builds are
  sideloaded test builds for now.
