# Feature Specification: Economy Ledger, Bootstrap and Sync (B03)

**Feature Branch**: `010-b03-ledger-sync`

**Created**: 2026-10-25

**Status**: Draft

**Input**: User description: "010". In `docs/delivery-plan.md` step 6, spec 010 is B03: "Economy ledger,
bootstrap, state, sync engine, op validators, fuel reconciliation, flags", which depends on B02 and
B04. Sources: `docs/architecture-backend.md` §7 (sync protocol and ledger), §12 (data model: economy
and progress), §13 (anti-cheat) and §6.4 (bootstrap), and the client side in
`docs/architecture-mobile.md` §12 and §13. To resolve (delivery plan, step 6): backend §22.2 (the
game-day timezone); that B03 matches M05's answer to mobile §24.5; and, from the design (HANDOFF
§9.3 #8), how the comeback gift (`Returning`) and the family-request rewards (`Requests`) are
granted, since no operation does it yet, and where the longest streak and the trip count come from.
Handed over from B01: register the `economy.wallet_equals_ledger` invariant with the restore drill
and add the direct-`Wallet`-write scan to CI. Handed over from B02: fill the conflict summaries from
the wallet and story tables, create each player's wallet and starting state, put the three endpoints
behind player tokens, and store `display_name` through `settings_update`. Handed over from M05: the
fuel rules (backend §7.5), the reasons `chapter_purchase` and `fuel_unlimited_purchase`, the revive's
`ref`, chapter ownership, fuel for replays, `fuel_refill` without a `ref`, and a gift operation for
the tutorial's refill. Done when (step 6, together with M06): offline trips sync without
duplicates; `wallet == sum(ledger)` and idempotency are covered by property tests; the stale-state
path (`GET /v1/state`) works.

## Clarifications

### Session 2026-10-25

- Q: Should B03 also build `claim_daily_reward` and `claim_task`, or leave them to B08/M13? → A:
  Leave them to B08/M13. B03 rejects both with `unknown_op_type` (a single-operation rejection), and
  the state's longest streak stays 0 until the daily loop exists (FR-037).
- Q: Is a room's or chapter's completion BONAT granted automatically or claimed by the player? → A:
  Automatically, by the server, when the operation that completes it is processed (FR-028). No
  claim operation exists for it, and M10 shows the reward as pending until the next sync.
- Q: How old a content version may a phone declare and still have its operations accepted? → A: The
  current version, and any version published within the last 45 days (a server setting; "production
  floor version" was dropped in planning, research R2). Older ones are rejected with `content_version_unsupported` (FR-014).
- Q: How many comeback gifts can a player get? → A: One per return, and at least 30 game days since
  the last one (a server setting), so a weekly visitor can't turn it into a weekly refill (FR-026).
- Q: Where does the display name's profanity list come from? → A: A list the operator edits in the
  admin (staff permission, audited), starting from a seed list. A change takes effect without a
  release (FR-023, FR-045).

## User Scenarios & Testing *(mandatory)*

Players never see this feature directly either. Its direct user is **the app**, acting for the
player: M06 will send what the player did offline, read the server's answer and replace its own
numbers with it. The other users are **the operator**, who checks that the books balance and
reviews suspicious play, **support staff**, who look a player's wallet up and correct it, and **the
later backend features** (B06 purchases, B07 ads, B08 the daily challenge, B10 live-ops, B12 and the
phase 3 features), which all change balances and must do it the one way this feature defines.

What the player gets from it:

- Nothing they did offline is lost or counted twice. They can play a week on a bus with no signal,
  and the next time the phone reaches the server every trip, purchase and booster is there once.
- Their BONAT is safe. Nobody can edit a number on a phone and get premium currency, and the
  apartment's JENEHAT can't be inflated either: what the phone proposes is checked against what the
  game allows.
- Honest play is never punished. A phone with a slow clock, a trip played while the signal dropped,
  an ad watched twice by accident: these are accepted, or noted quietly, never turned into a lost
  trip or a frozen account.
- A second phone, or a re-install after linking Google, shows the same progress.

### User Story 1 - Trips played offline reach the server once and in order (Priority: P1)

The app sends the operations it recorded since the last sync, in the order the player did them: a
trip start (which spends a liter), the trip's result (which earns JENEHAT and records the stars), a
purchase. The server applies them in that order in one go and answers for each: accepted, or
rejected with a reason. It also answers with the player's wallet as it now stands. Sending the same
batch again, because the answer was lost on a bad network, changes nothing and gets the same
answers.

**Why this priority**: This is the whole point of the server-backed economy. M06, every purchase,
the daily loop and every ad reward ride on it, and a double-counted trip or a lost purchase is the
failure players notice first.

**Independent Test**: Send a batch of `trip_start` + `trip_result` + a purchase, then send the same
batch again, then send it a third time with one more operation appended. The wallet moves once for
the first three operations, and the third request applies only the new one.

**Acceptance Scenarios**:

1. **Given** a player with a full tank, **When** a batch carries a `trip_start`, a `trip_result`
   with 3 stars and 46 JENEHAT within the trip's bound, and nothing else, **Then** both are
   accepted, the tank has one liter less, JENEHAT is up by 46, the trip's best stars and plays are
   recorded, and the answer carries the new wallet and `state_version`.
2. **Given** that batch was applied, **When** the same batch arrives again, **Then** every answer is
   the stored one, nothing changes, and `state_version` doesn't move.
3. **Given** a batch whose second operation is rejected, **When** it is processed, **Then** the
   first and third are still applied, and the answer lists each outcome in order.
4. **Given** the same batch arrives twice at the same moment, **Then** it is applied once, and both
   answers carry the same results.
5. **Given** a `trip_result` whose `trip_start_txn` names a start that was rejected, **Then** the
   result is rejected with `dependency_rejected`, and no JENEHAT is granted.
6. **Given** a `trip_result` with `earnings_jenehat` above the trip's `max_earnings_jenehat`,
   or stars outside 0–3, or a duration that is impossible for the trip, **Then** it is rejected with
   a reason and grants nothing. A second result for the same start is rejected too.
7. **Given** a batch of 101 operations, or one over the size limit, or a body that isn't a
   well-formed batch, **Then** the whole request is refused with `batch_too_large`,
   `payload_too_large` or `validation_error`, and nothing is applied.
8. **Given** a request with no player token, an expired one, or a token of a player pending
   deletion, **Then** it is refused as for any other `/v1` endpoint (B02), and nothing is applied.

---

### User Story 2 - BONAT and JENEHAT can't be made up on the phone (Priority: P1)

JENEHAT is proposed by the phone and checked by the server against what the game allows: a trip's
bound, the catalog's price for the content version the phone declares, unlock order, ownership.
BONAT is decided by the server alone. A BONAT spend is checked against the server's balance, and
the phone rolls back if the server says no. No operation turns BONAT into JENEHAT, and none adds
BONAT to a balance on the phone's say-so.

**Why this priority**: BONAT is bought with real money (constitution IV). A hole here costs money,
and it can't be closed after launch without wronging players.

**Independent Test**: For every operation type, send it with each field wrong in turn (price off by
1, a SKU not in the catalog, a currency swapped, an item already owned, a chapter not unlocked).
Each is rejected, and the ledger doesn't change.

**Acceptance Scenarios**:

1. **Given** a player with 12 BONAT, **When** a `spend_bonat` for a 20-BONAT item arrives, **Then**
   it is rejected with `insufficient_funds`, the balance stays 12, and a `use_booster` for that
   booster, with none in stock, is rejected with `none_left`. A revive naming a rejected start is
   rejected with `dependency_rejected`.
2. **Given** a `spend_jenehat` whose `price` differs from the catalog's price in the declared
   `content_version`, **Then** it is rejected with `price_mismatch`. Equal to the catalog's price,
   with the item not owned and the prerequisites met, it is accepted, JENEHAT goes down and the
   ownership is recorded.
3. **Given** a vehicle, item or chapter already owned, or one whose line or chapter isn't unlocked,
   **When** it is bought again, **Then** it is rejected (`already_owned`, `not_unlocked`).
4. **Given** any batch, **Then** no accepted operation adds BONAT except the server's own grants
   (FR-024 to FR-028), and none lowers one currency while raising the other.
5. **Given** an `ad_reward` for `morning_piggy`, **Then** it is rejected with `server_only`: only
   the ad network's own callback grants that (B07).
6. **Given** an `ad_reward` for `result_double` for a trip whose result was already doubled, or for
   a failed trip, **Then** it is rejected and grants nothing. For `fuel_refill` on a full tank it is
   rejected with `tank_full`, and past its daily cap with `cap_reached`.
7. **Given** a `use_booster` with none in stock, **Then** it is rejected with `none_left`.
8. **Given** a declared `content_version` that was never published, or one older than the server
   still accepts (FR-014), **Then** every operation that needs the catalog or the trip list is
   rejected with `unknown_content_version` or `content_version_unsupported`, and nothing is applied.

---

### User Story 3 - The app starts a session knowing where it stands (Priority: P2)

At launch, and when the network returns, the app asks for a snapshot: who the player is, their
wallet, what they own as entitlements, the server's time, the version of the state, the current
content version, whether the app is too old, and what is waiting for them today. A brand-new player
has a wallet and a starting state from this first call, with no extra step.

**Why this priority**: Without it the app has no server time to anchor on, no BONAT balance to
show, and no way to know a newer content pack exists. It is small, and everything in M06 starts
from it.

**Independent Test**: Create a player with B02, call bootstrap, and check the wallet, the state
version and the time. Call it again after a sync, and check that the version and the wallet moved.

**Acceptance Scenarios**:

1. **Given** a player created by B02 who has never synced, **When** the app calls bootstrap,
   **Then** the answer carries a wallet with a full tank, 0 JENEHAT and 0 BONAT, no unlimited window,
   a `state_version` of 0 and the server's time. A second call returns the same values and creates
   nothing new.
2. **Given** a player with synced progress, **Then** bootstrap carries their display name, driver
   level, country, linked providers, wallet, entitlements, and the version of the state.
3. **Given** the published content has moved past the version the app has, **Then** bootstrap's
   `content` block names the current version, and the app can fetch the manifest.
4. **Given** the player has been away for 7 game days or more, hasn't claimed the comeback gift
   for this return, and had no comeback gift in the last 30 game days, **Then** bootstrap says the gift is claimable (FR-026).
5. **Given** features that don't exist yet (entitlements from purchases, the daily challenge and
   reward), **Then** their blocks are present with neutral values (`remove_ads: false`, no
   subscription, no season passes, `challenge_available: false`), so the answer's shape doesn't
   change when those features arrive.
6. **Given** the app is below the minimum version, **Then** bootstrap still answers 200 with
   `force_update: true`, so the app can show its update screen (backend §6.5). The settings behind
   the flag are B10's; until then the minimum is the lowest version and nobody is forced.

---

### User Story 4 - A second phone, or a stale phone, catches up (Priority: P2)

A player who plays on two phones, or whose phone was away while another one synced, sends a batch
based on an old `state_version`. The server still checks every operation against its own state, and
answers `state_stale: true`. The app then fetches the full snapshot, replaces its local numbers
with it, and replays whatever it hasn't sent yet.

**Why this priority**: Without this, linking Google on a new phone (B02) would show an empty
game. It also makes the server's wallet the one the app converges to after any disagreement.

**Independent Test**: Sync a batch from "phone A", then sync a batch from "phone B" whose
`base_state_version` is the old one. B's operations are checked against A's results, B gets
`state_stale: true`, and the snapshot it then fetches contains both phones' effects.

**Acceptance Scenarios**:

1. **Given** the server's version is 42, **When** a batch arrives with `base_state_version` 41,
   **Then** its operations are validated against the current state (not 41's), and the answer sets
   `state_stale: true`.
2. **Given** a player with progress, **When** the app asks for the state, **Then** the answer holds
   everything the app's local economy keeps: wallet (with fuel and the unlimited window), booster
   inventory, owned vehicles, items (with variants), chapters and upgrades, each trip's best stars,
   best time and plays, the story (chapters, scenes seen, rooms and requests done), the player's
   settings and display name, and the profile stats (FR-037). It also holds the `state_version` it
   describes.
3. **Given** a trip started on phone A whose result hasn't arrived, **When** phone B asks for the
   state, **Then** the open start is visible as such, and phone B can't claim a result for it.
4. **Given** a snapshot, **Then** it holds no other player's data and nothing personal beyond what
   the player entered.

---

### User Story 5 - Fuel agrees with the server's clock, and offline play is tolerated (Priority: P2)

Fuel regenerates a liter every 20 minutes up to the tank's size. The phone counts it offline; the
server recounts it from its own clock whenever a trip starts. A phone that is a little ahead,
behind or optimistic is accepted. A phone that keeps starting trips with an empty tank is not.

**Why this priority**: Fuel is the pacing of the whole game and the reason people pay (BONAT for a
refill, an ad). It must be strict enough to mean something and loose enough that nobody honest is
turned away.

**Independent Test**: Replay the worked examples of M05's fuel contract
(`specs/007-m05-local-economy/contracts/fuel-and-time.md`) as operations with `occurred_at` times:
the server's tank and countdown equal the app's in every case.

**Acceptance Scenarios**:

1. **Given** a full tank of 5 and a `trip_start` at 09:00, **Then** the tank is 4, counting from
   09:00. A second start at 09:07 makes it 3, still counting from 09:00. At 09:45 the tank is 5.
2. **Given** an empty tank and no unlimited window, **When** a `trip_start` arrives, **Then** it is
   accepted with the tank at 0 and a `fuel_overdraft` flag is recorded (FR-030). The player's
   trip stands.
3. **Given** two overdrafts already in the game day, **When** a third arrives, **Then** it is
   rejected with `cap_reached`, and its result with `dependency_rejected`.
4. **Given** a `spend_bonat` for a full refill on a full tank, **Then** it is rejected with
   `tank_full` and no BONAT is spent. A refill on a part-full tank fills it to the maximum.
5. **Given** a one-hour unlimited purchase, **Then** the window runs 60 minutes from the end of one
   still running or from now, and a `trip_start` in `unlimited` mode inside it costs no liter.
   Outside any window, `unlimited` mode is rejected.
6. **Given** `fuel_max` is lowered (or a subscriber's larger tank ends) below the liters held,
   **Then** the liters are kept and nothing regenerates until the tank is below the maximum.
7. **Given** a replay of a completed trip, **Then** it costs a liter like any start (mobile §24.5).
8. **Given** a batch synced hours after it was played, **Then** fuel is recounted along the
   operations' own times, never past the server's now (FR-016), so a late sync neither invents
   liters nor takes them away.

---

### User Story 6 - Gifts and rewards the game promises are granted by the server (Priority: P3)

Four things the game promises have no operation yet (HANDOFF §9.3 #8): the tutorial's gift
refill, the comeback gift for a player who has been away, the BONAT a bride's family pays for a
finished request, and the BONAT for completing a room or a chapter. Each is decided by the
server, once, from data it holds. The app asks, the server checks and grants, and the answer
shows what was granted.

**Why this priority**: M07 (tutorial), M10 (apartment, requests) and M13 need them, but the economy
works without them. They also add the only server-granted BONAT besides purchases and ads, so
they need the same care.

**Independent Test**: Claim each once and again. The first grants exactly what the content or
settings say, the second grants nothing and answers `already_granted`. Claim without meeting the
condition: rejected.

**Acceptance Scenarios**:

1. **Given** a player who has never had it, **When** the app claims the tutorial gift, **Then** the
   tank is filled to the maximum, once per player. A second claim is rejected with
   `already_granted`.
2. **Given** a player away for 7 game days or more with no comeback gift in the last 30 game days,
   **When** they claim the comeback gift, **Then**
   the tank is filled and one change bag is added to the inventory. A second claim in the same
   return is rejected with `already_granted`; a claim by a player who wasn't away is `not_eligible`.
3. **Given** a family request whose item (and variant, when it names one) the player owns, **When**
   they claim it, **Then** the request's BONAT reward from the content pack is granted once.
   Claiming without owning the item is `not_eligible`; claiming twice is `already_granted`.
4. **Given** a purchase that completes a room, or the operation that completes a chapter, **Then**
   the room's or chapter's completion BONAT from the content pack is granted once, when that
   operation is processed.
5. **Given** any of these, **Then** each grant is a ledger entry with its own reason, and the
   amounts come from the content pack or the server's settings, never from the request.

---

### User Story 7 - Suspicious play is noted, and staff can look and correct (Priority: P3)

When something is odd but possible, the server accepts it and writes a flag: a fuel overdraft, a
3-star run much faster than the solver says is plausible, more trips than a day allows. Staff
review flags in the admin. Staff can look at a player's wallet and ledger, and can correct a
balance with a reason that is recorded. Nobody else can.

**Why this priority**: The soft rules are what keeps honest offline play from being punished
(constitution V). Flags make the soft side visible without making it a punishment.

**Independent Test**: Sync a run faster than the plausibility threshold but not impossible, and one
below the impossible bound. The first is accepted with a flag; the second is rejected.

**Acceptance Scenarios**:

1. **Given** an accepted anomaly, **Then** a `PlayerFlag` exists with its kind and details, shown in
   the admin's review queue, filterable by kind and by reviewed or not.
2. **Given** staff with the right permission, **When** they mark a flag reviewed with a resolution,
   **Then** it records who and when, and it leaves the open queue.
3. **Given** staff with the wallet permission, **When** they adjust a player's JENEHAT or BONAT by
   a signed amount with a reason, **Then** one ledger entry (`admin_adjustment`) is written through
   the same path as any other change, the audit log records who and why, and the balance can't go
   below 0.
4. **Given** staff without that permission, **Then** they see the wallet and ledger read-only.
5. **Given** a flagged player, **Then** nothing about their play changes yet: flags only inform
   (leagues, phase 3, will use them to exclude players).

---

### Edge Cases

- **A batch with no operations.** Answered 200 with the current wallet and version, changing
  nothing. The app uses it as a cheap "where do I stand".
- **An operation type the server doesn't know, or hasn't built yet** (`claim_daily_reward`,
  `claim_task`, until B08 and M13): rejected with `unknown_op_type` for that operation only, stored
  like any outcome, and the rest of the batch goes on. A poison operation never blocks the queue.
- **An operation whose payload is malformed** (a missing key, a wrong type, a float where an
  integer is required): rejected with `validation_error` for that operation only.
- **The same `client_txn_id` with a different type or payload.** The stored outcome is returned,
  nothing is applied, and a flag records the mismatch. A client never reuses an id for a different
  intent, so this is a bug or tampering.
- **Operations out of order in time.** Array order is the order of application. `occurred_at` that
  goes backward is clamped for fuel (FR-016) and noted, not rejected.
- **`occurred_at` in the future.** Clamped to the server's now for fuel, so it gains nothing.
- **A phone whose clock is wrong.** The app's trusted time (M05) keeps `occurred_at` honest. If it
  is not, the clamps make the worst case "the server's now", never more.
- **A `trip_start` with no `trip_result`** (the app was killed, the trip abandoned). The start
  stays open until a result arrives. A later `trip_start` for the same player is accepted and the
  older open start is closed as abandoned, so a lost result never blocks play.
- **A result for a trip in an older content version.** Checked against that version's trip
  (`rev` and bound), as the app played it.
- **Two phones sync at the same moment.** The batches are applied one after the other for that
  player. Neither loses an update, and no balance goes negative.
- **A trip the pack no longer lists** (a later version removed it). A trip id is permanent
  (backend §3.6), so old starts and results stay valid against the version they declare.
- **A very large first sync after weeks offline.** The app sends it in batches of at most 100;
  each is atomic, and a failure in batch N leaves batches before it applied.
- **The sync rate limit is reached.** `rate_limited` with a retry time. The app keeps playing and
  sends later (constitution V).
- **A player is pending deletion or deleted.** All three endpoints refuse (B02 enforces it), and no
  grant, gift or claim is possible.
- **The database or cache is unreachable.** `dependency_unavailable` (B01). A batch is never
  half-applied: it is one transaction.

## Requirements *(mandatory)*

### Functional Requirements

#### Endpoints and access

- **FR-001**: The server MUST offer three endpoints under `/v1`, behind player tokens, the two client
  headers and the per-player throttle, as every new endpoint is (B02 FR-032–FR-035):
  `GET /v1/bootstrap`, `GET /v1/state` and `POST /v1/sync`. Their payloads are backend §6.4 and §7.3,
  as this spec and its contracts refine them.
- **FR-002**: `POST /v1/sync` MUST be limited to 60 requests per minute per player, besides the
  default (backend §6.5, "Later"). `rate_limited` carries a retry time.
- **FR-003**: Every answer MUST use the error envelope with codes from backend §6.2. Every code this
  feature adds (FR-017) MUST be listed there before it ships.
- **FR-004**: The OpenAPI contract MUST describe the three endpoints, every operation payload, and
  every rejection reason, and the committed `contracts/openapi.yaml` MUST match the code.

#### The ledger

- **FR-005**: Every change to JENEHAT or BONAT MUST be an append-only ledger entry written through
  one function, with the wallet updated in the same transaction. Nothing else may write a wallet
  balance. An entry holds the player, currency, signed amount, balance after, reason, a reference,
  the operation that caused it (if any) and its source (`client_op`, `purchase`, `ssv`, `system`,
  `admin`).
- **FR-006**: For every player and each of the two currencies, the wallet balance MUST equal the sum
  of that player's ledger entries. A balance MUST NOT go below 0.
- **FR-007**: Ledger entries MUST NOT be updated or deleted, except when a player's account is
  anonymized (B09).
- **FR-008**: The ledger's reasons MUST be backend §7.2's, which already include M05's
  `chapter_purchase` and `fuel_unlimited_purchase`, plus two new ones for the BONAT this feature
  grants: `request_reward` and `story_reward`. They are added to §7.2 with this feature. The tutorial
  and comeback gifts change fuel and inventory only, so they write no ledger entry.
- **FR-009**: The one function in FR-005 MUST be the way every later feature changes a balance
  (B06 purchases, B07 SSV grants, B08 challenge rewards, B10, B12 and phase 3). A test MUST scan the
  backend for any other writer of a wallet balance and fail CI on one.
- **FR-010**: The invariant "wallet equals the sum of the ledger" MUST be registered with the
  restore drill (`economy.wallet_equals_ledger`), so every monthly drill on a restored backup checks
  it (B01 FR-040).
- **FR-011**: Creating a player's wallet and starting state MUST need no step of its own: the
  first call to any of the three endpoints creates it under the player's lock if missing, with a
  full tank, 0 JENEHAT, 0 BONAT, no inventory, no ownership, and a `state_version` of 0 (M05 FR-010).

#### The sync engine

- **FR-012**: A batch MUST hold at most 100 operations and at most 256 KB, and be processed in array
  order, as one atomic unit, serialized per player so two batches of one player never interleave.
  A rejected operation MUST NOT stop the batch (constitution VI).
- **FR-013**: Every state-changing operation MUST carry a `client_txn_id` (UUIDv7), and its outcome
  MUST be stored. An operation whose id was seen MUST return the stored outcome without applying
  anything. Applying the same batch twice MUST give the same state as applying it once.
- **FR-014**: Catalog prices, trip definitions, unlock rules and rewards MUST come from the
  published pack of the `content_version` the operation declares. A version the server never
  published is rejected (`unknown_content_version`). A version older than a server setting allows
  is rejected (`content_version_unsupported`). A version is supported while it is the current
  one or was published within the last 45 days (a server setting), as far as the server keeps its
  lookups (research R2).
  So an honest player offline for weeks isn't caught, and a modified app can't buy at prices
  older than the window.
- **FR-015**: `state_version` MUST increase by one for each batch that changed anything, and not
  otherwise. When `base_state_version` differs from the version before the batch, the operations
  MUST still be validated against the server's state, and the answer MUST set `state_stale: true`.
  `occurred_at` MUST NOT decide validity, except through the clamps in FR-016.
- **FR-016**: Fuel MUST be recounted along the operations' own times: each operation's time is the
  `occurred_at` it declares, kept between the previous operation's time and the server's now. A
  time that goes backward or into the future is clamped and noted, never rejected. The server's
  clock is the only authority for how far the timeline can reach (constitution VI).
- **FR-017**: A rejected operation's reason MUST be a stable lowercase snake-case code with no
  personal data, and M05's code MUST be reused where it means the same (`insufficient_funds`,
  `already_owned`, `tank_full`, `none_left`, `already_revived`, `result_exists`, `no_trip_start`,
  `trip_mismatch`, `stars_out_of_bounds`, `earnings_out_of_bounds`, `unknown_sku`, `not_for_sale`).
  New ones: `price_mismatch`, `not_unlocked`, `cap_reached`, `dependency_rejected`,
  `unknown_op_type`, `op_expired`, `unknown_content_version`, `content_version_unsupported`, `already_granted`,
  `not_eligible`, `server_only`, `validation_error`.
- **FR-018**: An operation whose payload names an earlier operation (a result on its start, a
  revive, an in-trip ad or a booster use on its trip start) MUST be rejected with
  `dependency_rejected` when that earlier one was rejected. A booster use carries no link to its
  purchase, so with the purchase rejected it meets an empty stock (`none_left`).

#### Operations

- **FR-019**: The server MUST validate and apply these operation types, with backend §7.4's rules as
  this spec refines them: `trip_start`, `trip_result`, `ad_reward` (`result_double`, `fuel_refill`,
  `trip_revive`, `traffic_jam`), `spend_jenehat` (item, vehicle, chapter, upgrade), `spend_bonat`
  (booster, fuel, revive, fuel_unlimited, cosmetic), `use_booster`, `story_progress`,
  `settings_update`, and the three grants in FR-025 to FR-027.
- **FR-020**: `trip_start` MUST check that the trip exists in the declared pack, that its line,
  vehicle and previous trip are unlocked as the pack defines, and the fuel rules (FR-029–FR-033).
  `trip_result` MUST check a matching accepted start, one result per start, stars 0–3, earnings
  between 0 and the trip's `max_earnings_jenehat` (0 for a failed or abandoned trip), and a duration
  not below the hard bound of 0.85 × the trip's last station time.
- **FR-021**: `spend_jenehat` and `spend_bonat` MUST check the price against the declared pack's
  catalog, the currency the catalog prices that kind in, ownership, prerequisites (chapter, line)
  and, for BONAT, the server's own balance. A revive MUST name its trip start, apply once per
  trip, and only to an open trip.
- **FR-022**: `ad_reward` MUST check the placement's cap (glossary §3.4: `result_double` and
  `trip_revive` and `traffic_jam` once per trip, `fuel_refill` three per game day) and apply the
  effect the placement defines. `morning_piggy` MUST always be refused (`server_only`).
  `fuel_refill` carries no `ref`. This feature records the ad's cap only; the SDK and its daily
  placement caps are M11's and B07's.
- **FR-023**: `settings_update` MUST accept a display name within the length limits and passing the
  profanity filter, and a settings object of known keys with bounded values. It MUST NOT accept
  anything that changes a balance, level or ownership. The name limits and the filter's list are
  server settings the operator can change; the filter's list is edited in the admin (FR-045).

#### Grants decided by the server

- **FR-024**: The server MUST be the only source of BONAT besides purchases (B06) and ad callbacks
  (B07). No client operation adds BONAT to a balance. The grants below take their amounts from the
  pack or the settings, never from the request.
- **FR-025**: *Tutorial gift.* An operation `tutorial_gift` MUST fill the tank to the maximum, once
  per player. Further claims are `already_granted`.
- **FR-026**: *Comeback gift.* The server MUST record when each session starts (each bootstrap) and
  the one before it. A player whose gap is at least a server setting (default 7 game days) MAY claim
  an operation `comeback_gift` once for that return: tank to the maximum and one `change_bag`, and
  only if at least a second server setting (default 30 game days) has passed since the player's
  last comeback gift. Bootstrap MUST say whether it is claimable. A claim without the gap, or inside
  the 30 days, is `not_eligible`; a second claim for the same return is `already_granted`.
- **FR-027**: *Family requests.* An operation `claim_request` naming a request of the declared pack
  MUST grant its `reward_bonat` once per player when the player owns the request's item (and its
  variant, when it names one). Anything else is `not_eligible` or `already_granted`.
- **FR-028**: *Room and chapter completion.* When an accepted operation completes a room (the
  player owns every item of it) or a chapter (its goal and scenes, as the pack defines), the
  server MUST grant that room's or chapter's `completion_bonat` once, in the same batch and
  transaction, with reason `story_reward`. The operation's answer MUST say what was granted.

#### Fuel

- **FR-029**: The server MUST keep, per player, the liters, the moment of the last recount, the end
  of any unlimited window, and the tank's size. On every `trip_start` and every refill it MUST
  recount first: one liter per `fuel_regen_minutes` (default 20) since the last recount, up to the
  tank's size, counting from the moment the tank last dropped below full, exactly as M05's fuel
  contract defines.
- **FR-030**: A start with no liters and no unlimited window MUST be accepted with the tank at 0 and
  a `fuel_overdraft` flag. The third overdraft in one game day MUST be rejected with `cap_reached`.
- **FR-031**: The tank's size MUST be `fuel_max` (default 5), or `fuel_max_subscriber` (7) when the
  player's entitlements carry the `fuel_max_bonus` flag. Until B06 and B12 exist, entitlements are
  empty and the size is 5. Liters above a lowered maximum are kept (M05 FR-024).
- **FR-032**: A full refill (`ad_reward` `fuel_refill`, `spend_bonat` `fuel` / `refuel_full`) MUST
  be refused with `tank_full` on a full tank, so no BONAT or ad is spent for nothing. A
  one-hour unlimited purchase MUST add 60 minutes from the end of a window still running, or from
  now. `unlimited` mode MUST be accepted only inside a window; `challenge` mode is B08's.
- **FR-033**: Every start MUST cost a liter in `fuel` mode, replays of completed trips included.
- **FR-034**: The server's values for the tank's size, the subscriber's tank, the regeneration time
  and the daily fuel-refill ad cap MUST equal the app's bundled tunables by default, and a check in
  CI MUST fail when they differ (constitution VIII). The other balancing numbers (the overdraft
  limit, the comeback gaps, the anti-cheat thresholds) are server-only: the phone never reads them,
  so they are server settings with defaults, listed as server-only in mobile §14.3. Making all of
  them live-editable is B10's (plan, Complexity Tracking).

#### State, bootstrap and the summaries

- **FR-035**: `GET /v1/bootstrap` MUST answer as in the user story 3, always 200 for a valid player
  (even when the app is too old), with: `server_time`, the player, the wallet, entitlements (the
  neutral shape in story 3), `state_version`, the current `content` version and manifest path, the
  `client` block, and `daily`.
- **FR-036**: `GET /v1/state` MUST answer as in story 4, describing exactly one `state_version`,
  complete enough that the app can replace its local starting point (M05 `replaceBase`) and replay
  its still-pending operations on top.
- **FR-037**: The profile stats MUST be part of the state: the number of trips played (accepted
  trip results, abandoned ones included), the sum of best stars, and the longest streak ever. The longest streak is
  0 until the daily reward exists (B08, M13), and the field is already there.
- **FR-038**: The conflict summaries B02 shows when a Google account already has progress MUST
  hold the player's real driver level, chapter and BONAT, replacing B02's starting values.
- **FR-039**: The state MUST hold nothing about other players. A snapshot MUST be cacheable by the
  app and safe to log in the app's own debug panel: no tokens, no install id, no provider data.

#### Flags, review and admin

- **FR-040**: A soft anomaly MUST be accepted and recorded as a flag with a kind and details. The
  kinds are at least: `fuel_overdraft`, `fast_three_star` (faster than the plausible threshold but
  above the hard bound), `trip_rate` (more trips in a game day than a day allows), and
  `txn_payload_mismatch`. The thresholds are server settings.
- **FR-041**: The admin MUST offer the flag queue (filter by kind and reviewed state; review with a
  resolution, recording who and when) to staff with a flag permission, and a read-only wallet and
  ledger view per player to staff with a player permission.
- **FR-042**: The admin MUST let staff with a wallet permission adjust a balance by a signed amount
  with a required reason. It MUST write one `admin_adjustment` entry through FR-005's function, and
  the audit log MUST record who, what and why. It MUST refuse a result below 0. The audit log is
  the append-only adjustment record (staff user, player, currency, signed amount, reason, ledger
  entry, time) and, for a flag review, the reviewer, time and resolution stored on the flag, which
  cannot be changed once set. The name filter's edits are in the admin's change history.

#### Data lifecycle

- **FR-043**: The record of each trip played (`TripRun`) MUST be kept 90 days and then dropped;
  trip progress, ownership, inventory and the ledger MUST be kept.
  Processed operations MUST be kept 180 days (a server setting) and then dropped. So that a pruned
  id can never be applied twice, an operation whose `client_txn_id` (a UUIDv7, which carries its
  creation time) is older than that period MUST be rejected with `op_expired`.
- **FR-044**: The data stored for the economy MUST hold no personal data beyond the display name
  the player chose, and logs and error reports MUST NOT contain a wallet, a payload or an id of a
  provider account.
- **FR-045**: The admin MUST let staff with a name-filter permission add, edit and remove entries
  of the profanity list `settings_update` checks, with each change in the audit log. The list MUST
  start with a seed list, and a name matching an entry (after the normalizing the plan defines for
  Arabic spellings) MUST be rejected with `validation_error`.

### Key Entities

- **Wallet**: a player's current JENEHAT and BONAT, fuel (liters, last recount, unlimited window)
  and the `state_version`. One per player; only the ledger function changes the currencies.
- **Ledger entry**: one signed change of one currency, with the balance after it, a reason, a
  reference and its source. Append-only.
- **Processed operation**: the stored outcome of one `client_txn_id` of one player (type, status,
  reason, the result returned), which makes a repeat harmless.
- **Inventory**: a player's count of each booster.
- **Ownership**: what a player owns: vehicles, upgrades, cosmetics, items (with the chosen variant)
  and chapters.
- **Trip progress**: per player and trip, the best stars, the best time, the plays and when first
  completed. **Trip run**: one played trip, kept 90 days.
- **Story state**: per player and chapter, the status, the scenes seen and what was completed. It
  includes the family requests already claimed.
- **Daily state**: the current and longest streak and the game date of the last claim. Present now
  for the stats; B08 and M13 fill it.
- **Player flag**: a soft anomaly (kind, details, when) with its review (who, resolution).
- **Grant record**: which one-time gifts and rewards a player has had (tutorial, each comeback,
  each request, each room and chapter), so none is granted twice.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Across 1,000 simulated players who each play 20 trips offline, send them in several
  batches, lose one answer in five and resend, every player ends with the same wallet, progress and
  ownership as one clean run, with no operation applied twice.
- **SC-002**: Across 10,000 random sequences of operations, the wallet equals the sum of the ledger
  in both currencies after every batch, no balance is ever below 0, and applying any batch a
  second time leaves the state unchanged.
- **SC-003**: Across the same sequences, BONAT is never increased by an operation a phone can send
  other than the three server grants, and no sequence lowers one currency while raising the other.
- **SC-004**: Two phones of one player syncing in parallel (200 concurrent batches in a test) lose
  no update, apply no operation twice, and leave no negative balance.
- **SC-005**: Every worked example of M05's fuel contract gives the same liters, countdown and
  window on the server as on the app.
- **SC-006**: An honest offline run of 30 game days of normal play (a realistic generated session
  mix, with clock-skewed phones) is accepted without one hard rejection, and produces only the
  flags the soft rules define.
- **SC-007**: For every operation type, a test that corrupts each field in turn (price, SKU,
  currency, ownership, trip, cap, reference) is rejected every time and changes no balance.
- **SC-008**: On staging, 95% of bootstrap calls are answered within 200 ms, 95% of state calls
  within 400 ms, and 95% of batches of 100 operations within 1 s.
- **SC-009**: The monthly restore drill reports the `economy.wallet_equals_ledger` invariant
  passing, and CI fails on any other writer of a wallet balance.
- **SC-010**: The contract tests exercise every documented answer and every rejection reason of the
  three endpoints, and the committed contract matches the code.
- **SC-011**: Every staff adjustment has an adjustment record and every flag review has its reviewer,
  time and resolution (the audit log of FR-042), each with who, what and why, and none can be
  edited afterwards.

## Assumptions

- **Dependencies.** B02 is merged (accounts, sessions, the player authentication and the per-player
  throttle, the summary seam). B04 is merged (published packs by version, the catalog, trips, lines,
  chapters, rooms, family requests, with their rewards and prices). B05's solver exists, and the
  plausibility threshold for `fast_three_star` can use its par times.
- **What follows.**
  - M06 (spec 011) calls the three endpoints, applies each answer (`markAccepted`, `markRejected`,
    `replaceBase`, `anchorOnServer`), pulls the state when it is stale, and moves those calls to a
    sync-only interface.
  - M07 sends `tutorial_gift`, `settings_update` (name) and the first trips. M10 sends
    `story_progress` and `claim_request`. M08 and M12 read the wallet. M11 sends `ad_reward`. M13
    sends `claim_daily_reward` and `claim_task` once B08 and M13 define their rules.
  - B06, B07, B08, B10 and B12 grant through FR-005's function; none writes a wallet.
- **Resolved here, from the delivery plan's list.**
  - *Game-day timezone (backend §22.2):* `Africa/Cairo` for every region in the MVP, as a server
    setting. A game day is Cairo's calendar day. It decides the fuel overdraft count, the `fuel_refill`
    cap and the comeback gap.
  - *Fuel rules (mobile §24.5):* B03 matches M05: every start costs a liter, replays included.
  - *The grants (HANDOFF §9.3 #8):* three new operations, `tutorial_gift`, `comeback_gift` and
    `claim_request`, plus automatic room and chapter completion rewards (FR-025 to FR-028). All are
    decided by the server from the pack and the settings.
  - *Longest streak and trip count:* the state's profile stats (FR-037).
  - The owner confirmed the deferral of `claim_daily_reward` and `claim_task` and the automatic room
    and chapter rewards in the 2026-10-25 clarification session. The timezone, the three grant
    operations and the fuel rules are still decisions made without the owner.
- **Not built here.** `claim_daily_reward` and `claim_task` (the streak table and the task counters
  belong with the daily loop, B08 and M13, which also resolve HANDOFF §9.3 #6); `morning_piggy` and
  the ad network callback (B07); purchase verification and entitlements (B06); the live settings,
  offers, `426 client_outdated` and the maintenance end time (B10); the daily challenge and its
  `challenge` fuel mode (B08); leagues that exclude flagged players (phase 3); account deletion and
  anonymizing the ledger (B09).
- **Fuel is not a ledger currency.** The ledger covers JENEHAT and BONAT. Fuel is an energy value
  the server recounts, kept in the wallet's state and in the operations' records, as M05 keeps it
  apart from the two currencies. The plan confirms this against backend §12.
- **Settings.** Until B10's live settings exist, the server keeps its values (tank size,
  regeneration, caps, comeback gap, name limits, thresholds) as configuration with the app's
  defaults (FR-034). The display name is 2–20 characters by default, and the profanity filter is a
  list the operator maintains in the admin (FR-045).
- **No personal data.** The economy tables hold a player id and game values. The display name is
  the only text a player enters.
- **Owner actions.** None expected before merge; the plan may add a production data check after the
  first deploy. `/speckit-implement` adds anything to `docs/owner-actions.md`.
