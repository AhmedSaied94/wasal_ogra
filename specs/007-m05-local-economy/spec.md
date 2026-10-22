# Feature Specification: Local Economy (M05)

**Feature Branch**: `007-m05-local-economy`

**Created**: 2026-10-21

**Status**: Draft

**Input**: User description: "feature 007 (next in docs/delivery-plan.md)". Feature 007 in
`docs/delivery-plan.md` is M05, step 4: "Local persistence (drift), economy service, fuel". It
depends on M03 (merged in #1). It also builds on M01 (merged in #5), whose `TripResult` it records,
and on M04 (merged in #7), whose content source gives it catalog prices and the active pack
version. Sources: docs/architecture-mobile.md §11 and §13 (with §3, §6, §10, §12 and §14.3);
docs/architecture-backend.md §7 (the op types, the ledger and fuel reconciliation, which B03 will
validate); docs/product-spec.md «الاقتصاد» (with «المساعدات» and «أماكن الإعلانات»); docs/ux-spec.md
«الموقف», «نافذة الإيقاف», «فشل المشوار», «شاشة النتيجة» and «نافذة البنزين». Resolve: mobile §24.5
(does replaying a completed trip cost fuel?), and B03 must agree with the answer. Handed over from M03
(research R1): use drift with the native-assets `sqlite3` 3.x package, not the end-of-life
`sqlite3_flutter_libs`. Handed over from M04 (research, "Handed to later features"): read catalog
prices through the content source, declare the active version in ledger operations, optionally move
`state.json` into `content_cache`, and skip progress that names a trip the active pack doesn't
have. Handed over from M01 (research R10): a resumed trip is still one `trip_start` and one
`trip_result`, and its fuel is untouched. Done when: the wallet, `ledger_ops` and fuel regeneration
all work offline, and no float holds money anywhere.

## Clarifications

### Session 2026-10-22

- Q: Does replaying a trip the player has already completed cost fuel (mobile §24.5)? → A: Yes.
  Every start costs one liter: a new trip, a replay of a completed trip, and a restart («عيد
  المشوار»). Only a revive and a resume after a kill are free, plus the first daily-challenge
  attempt (M13). This matches product-spec «الاقتصاد», the ux-spec's "−١ بنزين" badges and backend
  §7.4, so B03 charges every `trip_start` the same way. The plan's research records this as the
  resolution of mobile §24.5 (FR-029).
- Q: Before the game has the server's time, if a player moves the phone's clock forward, should the
  fuel tank refill for the skipped time? → A: Not while the phone stays on. Trusted time advances
  with the phone's uptime counter, which clock changes don't affect, so moving the clock either
  way while the phone is on changes no liter. Only after a phone restart, when that counter starts
  over, does the economy re-anchor on the device clock, never earlier than the latest trusted time
  it recorded. A forward clock across a restart still refills on the device, and the server's fuel
  reconciliation (B03) catches it. M06 later anchors on the server's time the same way (mobile
  §13) (FR-025, FR-026).
- Q: Should the game's saved progress be left out of Android's automatic backup, so that a
  reinstall or a new phone starts from zero until account linking exists? → A: Yes. The game
  database is left out of device backup and phone-to-phone transfer. Before linking, a reinstall
  gets a new anonymous account (backend §22.6), so restored progress would vanish at the first sync.
  Account linking (M14) carries progress to a new phone, and M06 or M14 revisits this with backend
  §22.6 (FR-006).

## User Scenarios & Testing *(mandatory)*

The people involved:

- **The player**, who earns JENEHAT («الجنيهات») by driving, spends it on the apartment and the
  vehicles, spends BONAT («البونات») on boosters and fuel, and is limited by fuel («البنزين»). The
  player must never lose a balance, be charged twice, or see a number that doesn't add up, online
  or not.
- **The features that change or show balances.** The trip screen (M02) starts trips, uses boosters,
  revives and records results. Home and the result screen (M08) show balances and the fuel gauge.
  Lines and vehicles (M09) and the apartment (M10) buy with JENEHAT. Ads (M11) apply rewards. The
  shop and the fuel sheet (M12) buy with BONAT. They all go through the one economy this feature
  provides, and none of them builds a screen here.
- **The server** (B03, with M06's sync), which arrives later and is the authority. Every change
  recorded here must be one it can validate, and one it can reject.

### User Story 1 - Fuel limits play and refills by itself, offline (Priority: P1)

A player starts a trip and the tank goes down one liter. One liter comes back every 20 minutes, up
to a full tank of 5, whether the game is open, closed or offline. Home shows "٤/٥" with a countdown
to the next liter, and the fuel sheet also shows when the tank will be full. With an empty tank, no
trip starts until a liter comes back, or the player refills with an ad or BONAT.

**Why this priority**: Fuel is the session pacer of the whole economy (product-spec «الاقتصاد»),
and every trip start goes through it. The first playable trip (M02, the next step) needs it, and so
does every screen that shows the "−١ بنزين" badge.

**Independent Test**: With a fake clock and the sample pack, start trips until the tank is empty,
advance time and check every liter and countdown to the second, then close and reopen the app and
check the same values. On a device in airplane mode, an integration test does the same across an
app restart.

**Acceptance Scenarios**:

1. **Given** a new player, **When** the app first opens, **Then** the tank is full (`fuel_max`, 5),
   and no countdown runs.
2. **Given** a tank with at least one liter, **When** a trip starts (a new trip, a replay of a
   completed trip, or a restart), **Then** the tank goes down by exactly one liter, in the same step
   that records the trip's start.
3. **Given** a tank below full, **When** `fuel_regen_minutes` (20) pass, **Then** one liter comes
   back, and so on until the tank is full, while the app is open, closed or offline.
4. **Given** a full tank, **When** a trip starts, **Then** the countdown to the next liter starts at
   that moment. **Given** a tank below full that is already counting, **When** a trip starts,
   **Then** the countdown keeps the time already counted toward the next liter.
5. **Given** any fuel state, **When** a screen asks, **Then** the economy gives the liters, the
   maximum, the time the next liter arrives, and the time the tank will be full (none when it is
   full), so Home, the fuel sheet and the "tank full" notification (M14) agree.
6. **Given** an empty tank and no unlimited-fuel window, **When** a trip start is asked for, **Then**
   it is refused with a reason, and nothing changes.
7. **Given** an empty tank, **When** the player refills with a rewarded ad (`fuel_refill`) or buys a
   full refill (`refuel_full`, 30 BONAT), **Then** the tank becomes full. **When** the player buys
   unlimited fuel (`fuel_unlimited_1h`, 80 BONAT), **Then** every trip started in the next 60
   minutes costs no fuel.
8. **Given** a trip killed mid-way and rebuilt on the next launch (M01 research R10), or a failed
   trip revived, **When** it continues, **Then** no fuel is spent and no new start is recorded.
9. **Given** the phone stays on, **When** its clock is moved forward or back, by hand or by a bad
   network time, **Then** the liters and both countdowns don't change, and time keeps counting as
   it really passes.

---

### User Story 2 - A finished trip pays and counts, offline (Priority: P1)

A player finishes a trip with 2 stars and 85 JENEHAT. The result screen shows the money, the
balance goes up by 85, and the trip now shows its stars. Doubling the pay with a rewarded ad adds
another 85, once. A failed or abandoned trip pays nothing. All of it survives closing the app, and
none of it needs a connection.

**Why this priority**: Earning by playing is the core loop, and the apartment goal only means
something if every pound earned is kept (product-spec «الاقتصاد»). Together with US1, this is the
whole economy of the first playable trip.

**Independent Test**: With a fake content source, record a start and each kind of result (3, 2 and
1 stars, revived, failed, abandoned), then the ×2 reward, and check the JENEHAT balance and the
trip's progress after each, and again after an app restart.

**Acceptance Scenarios**:

1. **Given** a recorded trip start, **When** its result arrives, **Then** the JENEHAT balance grows
   by the result's `earnings_jenehat` (0 for a failed or abandoned trip, M01), and the trip's
   progress is updated in the same step.
2. **Given** a trip's progress, **When** a later run of it finishes, **Then** its best stars and
   best time only ever improve, its play count goes up, and the time of its first completion stays
   as it was.
3. **Given** a result with no recorded start, a second result for the same start, or earnings
   above that trip's `max_earnings_jenehat` or below 0, **When** it is recorded, **Then** it is
   refused, and nothing changes.
4. **Given** a finished trip that paid more than 0, **When** the player watches the `result_double`
   ad, **Then** the balance grows by that trip's earnings once. A second ×2 for the same trip, or a
   ×2 for a failed, abandoned or unpaid trip, is refused.
5. **Given** progress or ownership that names a trip or an item the active pack doesn't have (after
   a fallback to the bundled pack, M04), **When** a screen reads it, **Then** that entry is kept and
   skipped, and the read doesn't fail.

---

### User Story 3 - Spending JENEHAT and BONAT at the catalog price (Priority: P2)

A player buys the old microbus for 1,500 JENEHAT, the «نيش» for the living room with the style they
chose, and a change bag for 10 BONAT. Each price is the one in the content pack the game is using,
never a number written in code. A purchase the player can't afford, or something they already own,
is refused, and nothing is charged. Tapping "buy" twice charges once.

**Why this priority**: The apartment (M10), vehicles (M09), boosters (M02) and the shop (M12) all
spend through this. It is P2 because the first playable trip (M02) needs only fuel and earnings,
but the full game loop (step 7) needs every purchase.

**Independent Test**: With the sample pack's catalog, buy each kind of product (item with a style,
vehicle, chapter goal, booster, refill, unlimited fuel, revive) with enough and with too little
balance, buy the same item twice, and repeat one request with the same id. Check balances,
inventory and ownership after each.

**Acceptance Scenarios**:

1. **Given** a product in the active pack's catalog, **When** the player buys it, **Then** the price
   charged is the catalog's price in the catalog's currency, and the purchase records that price
   and the pack version it came from.
2. **Given** a product with no catalog price in the active pack, **When** it is bought, **Then** the
   purchase is refused as not for sale.
3. **Given** a balance below the price, **When** the player buys, **Then** the purchase is refused
   and no balance goes below 0.
4. **Given** an item, vehicle or chapter goal the player already owns, **When** it is bought again,
   **Then** the purchase is refused.
5. **Given** an item with styles, **When** the player buys it, **Then** the chosen style is recorded
   with the ownership, at the item's one price.
6. **Given** a booster bought with BONAT, **When** the purchase applies, **Then** the inventory of
   that booster grows by one. **When** the booster is used in a trip, **Then** the inventory goes
   down by one, and a use with none left is refused.
7. **Given** a full tank, **When** a full refill is bought, **Then** it is refused, so no BONAT is
   spent for nothing. **Given** an unlimited-fuel window still running, **When** another is bought,
   **Then** the window is extended by 60 minutes from its current end.
8. **Given** the same purchase request sent twice with the same id (a double tap, a retry), **When**
   both arrive, **Then** the player is charged exactly once and both get the same outcome.
9. **Given** any operation, **When** the code is checked, **Then** no operation both takes BONAT and
   gives JENEHAT, and no operation adds BONAT on the device in staging or production builds.

---

### User Story 4 - Nothing is lost or counted twice (Priority: P2)

Phones kill apps, run out of storage, and get updated. Whatever happens, the balances, the
inventory, what the player owns and their progress stay exactly as they were after the last change
that completed. No change is ever half applied, and the balances can always be explained by the
history of changes.

**Why this priority**: Losing a player's savings, or charging them twice, breaks trust in a way no
feature can win back. This story makes US1–US3 safe to ship, and it is testable on its own.

**Independent Test**: Kill the app at each step of each kind of change, fill the storage, and
upgrade the app from the first database version. After each, check that every balance equals its
starting value plus the effects of every recorded change, and that each change is either fully
there or not there at all.

**Acceptance Scenarios**:

1. **Given** any change (a trip start, a result, a purchase, a booster use, a reward), **When** the
   app is killed at any moment of it, **Then** on the next launch it is either fully applied or not
   applied at all.
2. **Given** any sequence of changes, **When** the balances are read, **Then** JENEHAT and BONAT
   each equal their starting value plus the sum of every change that wasn't rejected, and a check
   that recomputes them agrees.
3. **Given** the storage is full, **When** a change is written, **Then** it fails as a whole, nothing
   changes, and the caller gets a reason it can show.
4. **Given** an app update that changes the database, **When** the app launches, **Then** every
   balance, change, booster, ownership and progress entry is still there. **Given** an upgrade that
   fails, **Then** the data stays as it was and the boot screen shows its failure state with a retry
   (M03).
5. **Given** a database the app can't open, or one written by a newer app version, **When** the app
   launches, **Then** it doesn't delete, reset or overwrite it, and the boot screen shows its failure
   state with a retry.
6. **Given** two changes requested at the same moment (a purchase while a result is recorded),
   **When** they apply, **Then** they apply one after the other, each exactly once.

---

### User Story 5 - Every change is ready for the server (Priority: P3)

When accounts and sync arrive (B02, B03, M06), every change made offline since the first launch must
reach the server in order, as an operation it can validate. If the server rejects one, the app must
undo it and everything that depended on it, and if another device has changed the account, the app
must take the server's balances and replay what is still pending on top.

**Why this priority**: Nothing uses it until M06, but the shape of what M05 stores decides whether
M06 can work at all (constitution IV and VI). It is P3 because it has no effect a player sees
before M06; its tests run here.

**Independent Test**: Record a mix of operations, mark some of them rejected the way M06 will, and
check balances, inventory and ownership after each. Replace the starting point with a server
snapshot and check that the pending operations apply on top of it.

**Acceptance Scenarios**:

1. **Given** any change, **When** it is recorded, **Then** it is an operation with a unique,
   client-generated id, one of the server's operation types (backend §7.4), the payload that type
   needs, its effect on each currency, its reason (backend §7.2), the time it happened and the
   active pack version.
2. **Given** operations recorded before any server exists, **When** time passes, **Then** every one
   of them stays pending, in the order it was recorded, and none is dropped.
3. **Given** an operation marked rejected, **When** the balances are read, **Then** its effects are
   gone, and so are the effects of every later operation that depended on it (for example, the use
   of a booster whose purchase was rejected).
4. **Given** a server snapshot of the balances, **When** it replaces the starting point, **Then**
   the balances become the snapshot plus the effects of every operation still pending.

---

### Edge Cases

- **The device clock moves while the phone stays on** (by hand, or a bad network time), with the
  app open or closed. Nothing changes: trusted time follows the phone's uptime counter, not the
  clock (Clarifications).
- **The phone restarts with its clock set back.** The uptime counter starts over, so trusted time
  re-anchors on the clock, but never earlier than the latest moment the economy has recorded: it
  re-anchors at that moment instead. The time the phone was off isn't counted, no liter is taken
  away, and regeneration goes on from there. The fuel the player had is kept, and server time (M06)
  corrects the anchor once it arrives.
- **The phone restarts with its clock set forward.** Before server time exists (M06), the app can't
  tell this from a long time switched off, so the tank refills. The server is the authority on
  fuel: it recomputes fuel from its own clock on every `trip_start` and records an overdraft as a
  soft anomaly (backend §7.5).
- **The time zone changes, or daylight saving starts.** Nothing changes: every time is kept in UTC.
- **The tank is above its maximum**, because the maximum was lowered by a tunable change (or, in
  phase 2, a subscription ended). The extra liters are kept, nothing regenerates until the tank is
  below the maximum, and only trip starts lower it.
- **A tunable changes** (`fuel_max`, `fuel_regen_minutes`). It applies to the time since the last
  recorded operation. Every operation keeps the values it was recorded with, so fuel recorded by an
  operation never changes.
- **A trip start while another trip is unfinished** (started, with no result) is refused. The trip
  screen resumes or abandons the unfinished one first, so at most one trip is unfinished at a time.
- **"عيد المشوار" (restart)** from the pause menu or the failure card records the current trip's
  result as abandoned (or failed), then a new start, which costs a liter, as the ux-spec says.
- **The app is killed between spending a liter and saving the trip's first replay record.** The
  start and the trip's identity (trip id, start id, pack version) are recorded in one step, and the
  economy reports the unfinished start on the next launch, so M02 can resume the trip or record it
  abandoned. The liter isn't refunded, the same as for an abandoned trip.
- **An unlimited-fuel window ends during a trip.** Nothing changes: fuel is decided once, at the
  trip's start.
- **A rewarded refill when the tank is full** is refused, like a bought refill (M11 doesn't offer
  it).
- **The active pack changes between showing a price and buying.** The purchase uses the price of
  the pack active when it applies, and records that version. A switch only happens at launch or on
  arrival at Home (M04), never while a purchase sheet shows.
- **A pack version older than the one a purchase was made with** (a fallback to the bundled pack,
  M04). Past operations keep the version they recorded. New ones record the active version.
- **A device backup or a transfer to a new phone.** The game database is left out of the platform's
  device backup, so a reinstall or a new phone starts fresh, the same as backend §22.6 for a
  re-install without a linked provider. A restored copy would show progress that M06 couldn't tie to
  a player, and the server would then take it away.
- **A year of play** (tens of thousands of operations) reads balances as quickly as the first day.
- **Thousands of operations pending for months**, because the player never goes online. None is
  dropped, and M06 sends them in order.

## Requirements *(mandatory)*

### Functional Requirements

#### The app database

- **FR-001**: The app MUST keep its game state in one database on the device, in the app's private
  storage. This feature creates the parts it needs (mobile §11): the wallet (balances and fuel
  state), the operations, the booster inventory, ownership, and trip progress. Later features add
  their own parts (story, daily state, entitlements, the sync queue) through database upgrades.
- **FR-002**: Every change MUST be written in one atomic step: a kill at any moment leaves either
  the state before the change or the state after it.
- **FR-003**: A database upgrade MUST keep every row. If an upgrade fails, the data MUST stay as it
  was, and the boot screen shows its failure state with a retry (M03).
- **FR-004**: The app MUST NOT delete, reset or overwrite a database it can't open, or one written
  by a newer app version. It shows the boot failure state with a retry instead.
- **FR-005**: Opening the database and reading the balances MUST happen during boot, off the UI
  thread, within the 3 s cold-start budget on the reference device (Galaxy A06).
- **FR-006**: The game database MUST be left out of the platform's device backup and phone-to-phone
  transfer (Clarifications), and a test MUST check the app's backup rules for it. M06 or M14
  revisits this together with backend §22.6.
- **FR-007**: The plan decides whether M04's record of stored packs (`state.json`) moves into the
  database as mobile §11's `content_cache`. If it moves, an app update MUST keep the stored packs
  and their record (M04 FR-028).

#### Money and balances

- **FR-008**: JENEHAT, BONAT and fuel MUST be integers everywhere: in the database, in operations,
  in memory and in tests (constitution II). The existing guard against `double` and `num` money in
  `lib/` MUST cover this feature's code.
- **FR-009**: No balance (JENEHAT, BONAT, fuel, booster inventory) may ever go below 0.
- **FR-010**: A new player MUST start with a full tank (`fuel_max`), 0 JENEHAT, 0 BONAT, no
  boosters, nothing owned and no progress.
- **FR-011**: In staging and production builds, no operation may add BONAT on the device. BONAT
  arrives only from the server (M06), which decides it (constitution IV).
- **FR-012**: No operation may both take BONAT and give JENEHAT, and nothing may sell JENEHAT
  (constitution IV). A test MUST check every operation type for this.

#### Operations

- **FR-013**: Every change to a balance, the fuel state, the inventory, ownership or progress MUST
  be one operation applied through the one economy service. Nothing else may write those parts of
  the database, and a test MUST scan the code for direct writes (the client side of constitution
  IV's direct-`Wallet`-write scan).
- **FR-014**: Each operation MUST record a client-generated UUIDv7 id, its operation type (backend
  §7.4), the payload that type needs, its effect on each currency, its reason (backend §7.2), the
  trusted time it happened (FR-025), the active pack version, and its sync status (pending,
  accepted or rejected).
- **FR-015**: Operations MUST be append-only. Only their sync status may change (US5).
- **FR-016**: Applying an operation whose id is already recorded MUST change nothing and return the
  outcome of the first one (constitution VI).
- **FR-017**: Operations MUST apply one at a time, in the order they are requested.
- **FR-018**: The JENEHAT and BONAT balances MUST always equal the starting point (FR-010, or the
  last server snapshot, FR-047) plus the effects of every operation since that isn't rejected. The
  stored balances are updated in the same step as each operation, and a check that recomputes them
  from the operations MUST agree.
- **FR-019**: A refused operation MUST record nothing and return a reason code (for example
  `insufficient_funds`, `not_for_sale`, `already_owned`, `no_fuel`, `tank_full`, `unknown_trip`,
  `trip_unfinished`, `no_trip_start`, `result_exists`, `earnings_out_of_bounds`, `none_left`,
  `already_doubled`), for the calling screen to show and M15 to report. Codes MUST NOT contain
  content or personal data.

#### Fuel

- **FR-020**: Fuel MUST stay between 0 and the maximum, `fuel_max` (5), except in the case of
  FR-024. The subscriber's larger tank (`fuel_max_subscriber`) arrives with M17.
- **FR-021**: Below the maximum, one liter MUST come back every `fuel_regen_minutes` (20) of trusted
  time. Spending a liter below the maximum keeps the time already counted toward the next one. At
  the maximum the countdown stops, and spending from the maximum starts it at that moment.
- **FR-022**: Regeneration MUST be computed from the stored fuel state and the trusted time, so it
  works with the app closed, after restarts and offline, with no background work (constitution
  budgets).
- **FR-023**: The economy MUST expose the liters, the maximum, the time the next liter arrives and
  the time the tank will be full (none when full), and update them as time passes.
- **FR-024**: Fuel above the maximum MUST be kept. Nothing regenerates until it is below the
  maximum, and only a trip start lowers it.
- **FR-025**: The economy MUST read time from one trusted-time source. Trusted time is an anchor
  plus the time the phone's uptime counter has counted since the anchor was taken. The anchor is
  the server's time once M06 provides one, and the device clock until then. The anchor survives
  the app closing, and is retaken on the device clock only when the phone has restarted (its uptime
  counter has started over). Times are in UTC.
- **FR-026**: Changing the device clock while the phone stays on MUST NOT change fuel or its
  countdowns. When a re-anchor after a phone restart would put trusted time earlier than the latest
  time the economy has recorded, trusted time MUST NOT go back: it re-anchors at that latest time
  instead, so the time the phone was off isn't counted, no liter is added or removed for it, and
  regeneration goes on from there.
- **FR-027**: A change to `fuel_max` or `fuel_regen_minutes` MUST apply to the time since the last
  recorded operation. The time up to each operation keeps the values that operation was recorded
  with, so the fuel any operation recorded never changes.

#### Trips

- **FR-028**: A trip start MUST be refused when the trip isn't in the active pack, when another
  trip is unfinished, or when the tank is empty and no unlimited-fuel window is running. Otherwise
  it records a `trip_start` (trip id, active pack version, fuel mode `fuel` or `unlimited`) and, in
  the same step, spends one liter unless an unlimited-fuel window is running at that moment.
- **FR-029**: Replaying a trip the player has already completed MUST cost one liter, like any other
  start, and pays its earnings like any other run (Clarifications; resolves mobile §24.5).
- **FR-030**: A revive and a resume after a kill MUST NOT spend fuel or record a new start (M01
  research R10). A restart («عيد المشوار») records the current trip's result, then a new start,
  which costs a liter.
- **FR-031**: The economy MUST expose the unfinished trip start, if any (trip id, start id, pack
  version), so the trip screen can resume it or record it abandoned (Edge Cases).
- **FR-032**: A trip result MUST be refused unless it belongs to the unfinished start and is the
  first result for it, and unless its `earnings_jenehat` is between 0 and the `max_earnings_jenehat`
  of the trip that start recorded. Otherwise it records a `trip_result` with the whole `TripResult`
  (mobile §7.2), adds its earnings to JENEHAT, and updates the trip's progress, all in one step.
- **FR-033**: Each trip's progress MUST keep its best stars, its best time (the shortest duration
  among its finished runs), its number of plays and the time it was first completed. Best values
  never get worse.
- **FR-034**: Progress and ownership that name a trip or an item the active pack doesn't have MUST
  be kept, and readers MUST skip them rather than fail (M04 hand-over).

#### Rewards from ads

- **FR-035**: A `result_double` reward MUST apply only to the latest result, once, and only when that
  trip finished and paid more than 0. It adds JENEHAT equal to that trip's earnings and references
  its start. A ×2 for any earlier trip is refused: the result screen offers it only for the trip just
  played (ux-spec «شاشة النتيجة»).
- **FR-036**: A `fuel_refill` reward MUST fill the tank to the maximum, and MUST be refused when the
  tank is full.
- **FR-037**: `trip_revive` and `traffic_jam` rewards MUST be recorded, referencing the trip's start,
  with no effect on balances, so the caps can count them (backend §7.4). The daily caps and the ad
  calls themselves are M11's.

#### Spending

- **FR-038**: A purchase MUST take its price and currency only from the active pack's catalog, for
  its SKU kind and id, never from the caller (constitution VII). A SKU with no catalog price is
  refused as not for sale. The operation records the price and the pack version.
- **FR-039**: A JENEHAT purchase (`spend_jenehat`) MUST cover items (with the chosen style, when the
  item has styles), vehicles and chapter goals. It MUST be refused when the balance is below the
  price or the player already owns the SKU, and otherwise records the ownership in the same step.
- **FR-040**: A BONAT purchase (`spend_bonat`) MUST cover boosters (the inventory grows by one), the
  full refill (the tank becomes full; refused when full), unlimited fuel (a 60-minute window from
  now, or from the end of the window already running) and the revive (referencing the failed trip's
  start). It MUST be refused when the local BONAT balance is below the price (constitution IV:
  optimistic up to the last known balance).
- **FR-041**: A booster use (`use_booster`) MUST be refused when none is left. Otherwise it lowers
  that booster's inventory by one and references the trip's start.

#### Reading and layering

- **FR-042**: The economy MUST expose the balances, the fuel state, the inventory, ownership,
  progress and the unfinished start as values that update after every operation and as time passes,
  for the screens of M02 and M08–M12.
- **FR-043**: The economy's rules (validation, effects, the projection and fuel regeneration) MUST
  live in the domain layer, free of Flutter and plugin imports (constitution I, mobile §6). They read
  time through a clock interface and content through M04's `ContentSource`.

#### Ready for sync

- **FR-044**: Each operation MUST carry everything its `POST /v1/sync` payload needs (backend §7.3,
  §7.4), so M06 sends it unchanged, in the order it was recorded.
- **FR-045**: Until M06, every operation MUST stay pending indefinitely, and none may be dropped.
- **FR-046**: Marking an operation rejected MUST remove its effects from the balances, the fuel
  state, the inventory, ownership and progress, together with the effects of every later operation
  that depended on it. Marking one accepted changes nothing the player sees.
- **FR-047**: The starting point of the balances MUST be replaceable by a server snapshot, with every
  pending operation applied on top of it (mobile §12, step 6).

#### Testing and screens

- **FR-048**: Tests MUST cover every operation type's accepted and refused cases, idempotency, a kill
  at each step of each operation, a property test of FR-018 over random sequences of operations
  (including rejections and snapshots), fuel regeneration with fake clocks (including clock changes
  forward and back with and without a phone restart, a full tank, a tank above the maximum and a
  tunable change), a database upgrade from this
  feature's first version, and an offline integration test across an app restart. New code MUST
  reach at least 80% line coverage (constitution XIII).
- **FR-049**: This feature adds no screen. The boot screen's failure state is M03's, and the
  existing goldens stay as they are.

### Key Entities

- **Wallet**: the player's JENEHAT and BONAT balances and fuel state, kept up to date by every
  operation. JENEHAT and BONAT always equal the starting point plus the operations since.
- **Fuel state**: the liters, the time the countdown to the next liter started, the end of any
  unlimited-fuel window, the latest trusted time recorded, and the trusted-time anchor. The current
  liters and countdowns are computed from it and the trusted time.
- **Operation**: one append-only, client-identified change, in the server's vocabulary: id, type,
  payload, effect on each currency, reason, time, pack version and sync status.
- **Starting point**: what the balances are computed from: the new player's state (FR-010), later
  replaced by the server's snapshot (M06).
- **Booster inventory**: how many of each booster the player holds.
- **Ownership**: the items (with their chosen style), vehicles and chapter goals the player owns.
- **Trip progress**: per trip, the best stars, best time, plays and first completion.
- **Unfinished trip start**: the one trip that has started without a result, with its trip id,
  start id and pack version.
- **Trusted time**: an anchor (the server's time from M06, or the device clock until then) plus the
  phone's uptime since the anchor. Clock changes don't move it, a phone restart re-anchors it, and
  it never goes back.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a property test of at least 1,000 random sequences of operations, rejections and
  snapshots, JENEHAT and BONAT equal the starting point plus the non-rejected operations after every
  step, in 100% of runs.
- **SC-002**: Killing the app at each step of each operation type leaves the operation fully applied
  or not applied at all on the next launch, in 100% of runs.
- **SC-003**: Over a simulated 7 days of trip starts, refills and clock changes, the liters, the next
  liter's time and the full-tank time match the regeneration rule to the second at every check, and
  a clock change while the phone stays on moves none of them, in 100% of cases.
- **SC-004**: The same operation requested twice (or 100 times) with the same id charges the player
  exactly once, in 100% of runs.
- **SC-005**: On the Galaxy A06, opening the database and reading the balances adds at most 200 ms
  to cold start, and still does with 50,000 recorded operations (years of daily play). The cold
  start to Home stays within 3 s.
- **SC-006**: On the Galaxy A06, a purchase, a trip start or a result is reflected in the balances a
  screen reads within 100 ms of being requested, so it feels instant.
- **SC-007**: A player who plays only offline keeps every balance, booster, ownership and progress
  entry across app restarts and an app update, in the integration test and on the reference device.
- **SC-008**: Zero money values held in anything but an integer, as checked by the existing guard
  over the whole of `lib/`.

## Assumptions

- **Dependencies.** M03, M01 and M04 are merged. B02, B03 and M06 are not, so there is no server, no
  account and no server time yet. Everything here works with none of them, and M06 later sends the
  operations recorded here.
- **The server is the authority.** B03 validates every operation against its own state, catalog and
  clock. The checks here keep the device consistent and spare the player a rejection; they don't
  replace the server's.
- **Time before M06.** With no server time, trusted time is anchored on the device clock and then
  follows the phone's uptime counter, so the clock is read only at a phone restart, and never moves
  trusted time back (FR-025, FR-026). A clock set forward across a restart refills the tank on the
  device, and the server's own fuel reconciliation (backend §7.5) catches it. This is the rule
  constitution VI sets since 1.3.0: the device clock only takes a new anchor, and M06 anchors on
  server time once it exists.
- **BONAT on the device.** Staging and production builds never add BONAT locally (FR-011), so their
  BONAT balance stays 0 until M06 brings the server's. The plan may give dev builds a way to set
  balances for manual testing.
- **Unlock order is checked by its owners.** Whether a line, vehicle, trip or chapter is unlocked is
  a progression rule of M08–M10. They check it before they ask the economy, which checks only the
  catalog, the balances, ownership and fuel.
- **No screens.** The top bar, the fuel sheet, the result screen's ×2, the booster tray and the shop
  are M02 and M08–M12. The shop's 3-second "رجّع" undo for small BONAT purchases (ux-spec «الشرا»)
  is M12's: it applies the purchase only after the undo window has passed.
- **Not in this feature.** The daily challenge's free first attempt (`fuel_mode: challenge`, M13);
  the tutorial's gift refill (M07, which needs an operation B03 accepts); daily rewards, tasks and
  story progress (M10, M13); the driver level; entitlements and the subscriber tank (M06, M17); the
  daily ad caps (M11); sending operations and handling the server's answers (M06).
- **Tunables.** This feature uses the existing `fuel_max`, `fuel_max_subscriber` and
  `fuel_regen_minutes`. If the plan adds a balancing number, it adds it to mobile §14.3 and the
  tunables file in the same change, and B10 gets its server copy (constitution VIII). The 60-minute
  unlimited-fuel window is the product's definition of `fuel_unlimited_1h` (glossary §3.3).
- **Hand-overs to B03**, which must agree with these rules: every start costs a liter, replays
  included (FR-029, mobile §24.5); the countdown rule of FR-021; a tank
  above the maximum is kept (FR-024; backend §7.5's `min(fuel_max, …)` would lower it); a full
  refill is refused on a full tank; a second unlimited-fuel purchase extends the window from its end;
  and backend §7.2's reason list has no reason for a chapter-goal purchase or for unlimited fuel, so
  the plan proposes names for both.
- **Hand-overs to M02**: start trips, record results and use boosters through the economy; charge a
  revive only when the engine reports the trip revivable (and not at the command cap, M01 research
  R9); record a booster use only after the engine accepts the booster command.
- **Stack.** The database is drift (constitution, locked stack) with the native-assets `sqlite3` 3.x
  package, not `sqlite3_flutter_libs` (M03 research R1).
- **Out of scope**: every screen; sync, bootstrap and identity (M06); ads (M11); real-money purchases
  (M12); daily rewards, tasks and the challenge (M13); story progress (M10); the garage's upgrades
  and cosmetics (phase 2).
