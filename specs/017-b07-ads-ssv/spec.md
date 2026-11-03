# Feature Specification: Ads — AdMob SSV Callback, Reward Polling and Caps (B07)

**Feature Branch**: `017-b07-ads-ssv`

**Created**: 2026-11-03

**Status**: Draft

**Input**: User description: "017 — next feature in docs/delivery-plan.md". In `docs/delivery-plan.md`
step 8, spec 017 is B07: "Ads: AdMob SSV callback, reward polling, caps", which depends on B03.
Sources: `docs/architecture-backend.md` §3.4 (ad placements and their caps), §6.3 (`GET /v1/ads/ssv`,
`GET /v1/ads/rewards/{nonce}`), §7.2 (ledger reason `ssv_grant`, source `ssv`), §7.4 (`ad_reward`),
§8.4 (AdMob server-side verification), §12 (`AdReward`) and §23 (SSV only for server-granted
rewards); the phone side in `docs/architecture-mobile.md` §15.1; the banner in
`docs/design/HANDOFF.md` (Home row 6, the offline state row 7, `States`); the product spec's
«أماكن الإعلانات» (حصّالة الصبح: جنيهات وبونات، مرة في اليوم). Handed over from B03 (research
"Handed to later features"): the SSV grant for `morning_piggy` calls `apply_entry`. Handed over from
B10 (research "Handed to later features"): B07's caps go in the live-settings registry as
`applied_by: both` and are read from the snapshot; a scheduled job that writes uses
`skip_in_maintenance`. The core-r1 draft leaves the piggy's amounts out ("B10 sizes it"), and B10
didn't, so this feature sizes them. Done when (step 8, together with B10 and M11): every placement
works with its caps enforced on the device and on the server; `morning_piggy` is granted only
through SSV.

## Clarifications

### Session 2026-11-03

- Q: What does one morning piggy give at launch (the core-r1 draft left it to B10, which didn't
  size it)? → A: 30 JENEHAT and 2 BONAT, as server-only live settings (FR-019).
- Q: When the piggy's reward arrives after the app has stopped asking, is the player told on their
  next session? → A: Yes. Bootstrap lists the granted piggy rewards the app hasn't confirmed as
  shown; the app shows a "your piggy reward arrived" card and confirms, so each shows once
  (FR-017).
- Q: Is the operator alerted to a burst of forged or badly signed callbacks? → A: Yes. Sentry, which
  emails the operator, gets an alert when badly signed callbacks pass 20 in an hour, or when Google's
  verifier keys can't be fetched; single failures are only counted (FR-007).
- Q: How long are callback records that granted nothing kept? → A: 90 days, deleted by a daily job
  that skips during maintenance; granted records are kept with the ledger (FR-006, FR-024). To keep
  that safe, a callback more than 7 days old is refused `expired` (FR-006a).

## User Scenarios & Testing *(mandatory)*

Players meet this feature as «حصّالة الصبح» on Home: they watch one rewarded ad a day and get
JENEHAT and BONAT. BONAT is value the server alone grants (constitution IV), so this reward cannot
be applied by the phone the way the other rewarded placements are. Instead Google's ad network calls
the server to confirm the ad was watched, the server grants, and the app asks the server whether the
grant has arrived. The direct users are:

- **The player**, who taps the banner, watches the ad, and sees the wallet go up.
- **The app** (M11), which tags the ad with the player and a one-time reference, then asks for the
  result.
- **Google AdMob**, which calls the server once the ad is watched.
- **The live-ops operator**, who sizes the reward and the cap without a release, and checks what was
  granted.

### User Story 1 - The morning piggy pays out after the ad (Priority: P1)

A player opens the game in the morning and taps «حصّالة الصبح». They watch the ad to the end.
Within a few seconds the result card shows the JENEHAT and BONAT they got, and the wallet pills go
up. Tomorrow the banner is back; for the rest of today it isn't.

**Why this priority**: It is the only placement that grants BONAT, and the step's "done when" asks
that it is granted only through server verification. Without it the banner cannot ship.

**Independent Test**: Send a correctly signed callback (from a recorded test key) for a known
player with placement `morning_piggy` and a fresh reference, then ask for that reference as that
player: the answer is "granted" with the amounts, the player's wallet and ledger show both credits,
and `wallet == sum(ledger)` holds.

**Acceptance Scenarios**:

1. **Given** a player who hasn't had today's piggy, **When** a validly signed callback names them
   and placement `morning_piggy`, **Then** the server credits the configured JENEHAT and BONAT in
   one transaction, records the reward against the callback's transaction id and reference, and
   answers 200.
2. **Given** that grant, **When** the app asks for the reference as the same player, **Then** the
   answer is "granted" with the amounts granted and the player's wallet after the grant.
3. **Given** the callback hasn't arrived yet, **When** the app asks for the reference, **Then** the
   answer says it isn't known yet, so the app keeps asking on its schedule (1 s, 2 s, 4 s) and then
   tells the player the reward will arrive.
4. **Given** a grant that arrived after the app stopped asking, **When** the app next starts a
   session or syncs, **Then** the wallet it receives includes the grant, and bootstrap lists the
   reward (amounts and time) as not yet shown, so the app can tell the player it arrived.
5. **Given** a granted reward the app has shown (from the lookup or from bootstrap), **When** the
   app confirms it was shown, **Then** bootstrap no longer lists it; confirming again, or
   confirming a reference that isn't the player's granted reward, changes nothing.
6. **Given** a player whose piggy was granted today, **When** the app starts a session, **Then**
   bootstrap says the piggy isn't available until the next game day; on the next game day it says
   it is.

---

### User Story 2 - Forged, repeated or extra callbacks grant nothing (Priority: P1)

Someone who finds the callback address sends it hand-made requests to mint BONAT. Separately,
AdMob retries a callback it already delivered, and a player with two phones watches the piggy on
both on the same morning. None of these grant more than one piggy a day per player.

**Why this priority**: The endpoint is public and mints the premium currency. A hole here breaks
server authority over value (constitution IV) and idempotency (constitution VI), which allow no
exceptions.

**Independent Test**: Replay the recorded valid callback (duplicate), flip one character in it
(tampered), sign it with an unknown key, and send a second valid callback with a new transaction id
the same game day: only the first grants, the ledger has exactly two entries, and each request got
the answer the requirements set.

**Acceptance Scenarios**:

1. **Given** a callback whose signature doesn't verify against Google's published keys, or that has
   no signature, **When** it arrives, **Then** nothing is granted or recorded as a reward, the
   answer is a refusal, and the attempt is logged without the query's personal values.
2. **Given** a callback with a transaction id already recorded, **When** it arrives again, **Then**
   nothing more is granted and the answer is 200, so AdMob stops retrying.
3. **Given** a player already granted today's piggy, **When** a second valid callback arrives for
   them the same game day, **Then** it is recorded as refused for the cap, nothing is granted, the
   answer is 200, and asking for its reference says "refused: daily cap reached".
4. **Given** a valid callback whose reference was already used by another recorded reward, **When**
   it arrives, **Then** it is recorded as refused and nothing is granted.
5. **Given** a valid callback that names an unknown player, a player pending deletion or deleted,
   or no player at all (AdMob's console test sends one), **When** it arrives, **Then** it answers
   200, records it as unattributed, and grants nothing.
6. **Given** a valid callback whose placement isn't `morning_piggy`, **When** it arrives, **Then**
   it answers 200, is recorded as refused, and grants nothing: the other placements stay
   phone-applied through sync.
7. **Given** player A's reference, **When** player B asks for it, **Then** the answer is the same as
   for an unknown reference.

---

### User Story 3 - The operator sizes the piggy and the caps without a release (Priority: P2)

After the closed test the owner sees that BONAT runs short and raises the piggy's BONAT. They change
it in the admin's live settings, and the next callback grants the new amount. They can also open
the list of recorded ad rewards to see who got what, and which callbacks were refused and why.

**Why this priority**: Constitution VIII requires every balancing number to be a live setting with
one server copy, and B10 asked B07 to put its caps in the registry. The reward itself works with
defaults, so this comes after the grant.

**Independent Test**: Change the piggy's BONAT amount in the admin, send a valid callback: the grant
uses the new amount. Set the piggy's daily cap to 0: the next callback is refused for the cap.

**Acceptance Scenarios**:

1. **Given** the live settings, **When** the operator changes the piggy's JENEHAT, BONAT or daily
   cap, **Then** callbacks processed from at most 60 seconds later use the new values, and the
   change is in the setting's history.
2. **Given** the piggy's daily cap, **When** the app reads its tunables, **Then** it has the same
   default as the server, and CI fails if the bundled default and the server default differ.
3. **Given** a staff member with the live-ops permission, **When** they open the ad rewards list,
   **Then** they can filter it by player, placement, status and day, and nothing in it can be
   edited or deleted from the admin.

---

### User Story 4 - Every placement's caps hold on the server (Priority: P2)

The step's "done when" asks that each placement in glossary §3.4 is capped on the server too. B03
already refuses the phone-applied placements over their caps; this story proves all six together
against the live numbers, so a later change can't drop one unnoticed.

**Why this priority**: It closes the step's acceptance across the three features, but most of the
behaviour exists, so it is mainly a guarantee.

**Independent Test**: One test per placement drives it one past its cap with the live settings at
their defaults and with a changed value, and checks the refusal.

**Acceptance Scenarios**:

1. **Given** each phone-applied placement (`result_double`, `fuel_refill`, `trip_revive`,
   `traffic_jam`), **When** the phone reports one more than its cap, **Then** sync refuses it with
   the reason B03 defined, and the refill's daily cap and the traffic jam's per-trip cap follow
   their live settings.
2. **Given** a sync op that claims `morning_piggy`, **When** it arrives, **Then** it is refused
   `server_only`, as today.
3. **Given** `interstitial_between_trips`, which grants nothing, **When** anything reaches the
   server about it, **Then** nothing is granted; its rules are the app's (M11).

---

### Edge Cases

- Google's key list can't be fetched (network, outage) when a callback needs a key the server
  doesn't hold: the callback is answered with a temporary error, so AdMob retries later, nothing is
  recorded, and the operator is alerted (FR-007).
- A callback names a key id the cached list doesn't have (Google rotated keys): the server refreshes
  the list once before deciding, and at most once a minute for unknown ids, so forged key ids can't
  make it hammer Google.
- The ad is watched at 23:59 Cairo time and the callback arrives after midnight: the game day is the
  one in force when the callback is processed (backend §22.2), so it counts for the new day.
- Two callbacks for the same player arrive at the same moment: the wallet lock serializes them, and
  exactly one is granted.
- `custom_data` is missing, isn't the expected shape, or its reference isn't a UUID; or any field
  is missing, isn't a number where one is expected, or is longer than the server keeps: a validly
  signed callback is answered 200 and recorded as refused (malformed), with over-long text cut;
  nothing is granted, and no signed input can make the server fail and AdMob retry.
- A validly signed callback has no transaction id (or an over-long one): it can't be recorded, so
  it is answered 200, logged as malformed, and grants nothing.
- Maintenance is on: the callback still verifies and grants, because the player has already watched
  the ad and AdMob may not retry for long; maintenance pauses the game's writes from players and
  scheduled jobs, not confirmations of something that already happened (see Assumptions).
- The app asks for a reference many times quickly: the reward lookup is rate-limited per player like
  other reads, and a lookup never writes.
- The app asks for a reference it never used (a bug, or a guess): the same "not known yet" answer.
- The player's account is deleted later: their reward rows go with the player's other data in B09.
- AdMob retries a callback for longer than expected, or someone replays an old one after its refused
  record was cleaned up: a callback more than 7 days old is refused `expired` and grants nothing
  (FR-006a).

## Requirements *(mandatory)*

### Functional Requirements

#### The callback

- **FR-001**: The server MUST expose the AdMob server-side verification callback at
  `GET /v1/ads/ssv`, needing no player sign-in, and accept AdMob's query parameters (`ad_network`,
  `ad_unit`, `custom_data`, `reward_amount`, `reward_item`, `timestamp`, `transaction_id`,
  `user_id`, `signature`, `key_id`).
- **FR-002**: The server MUST verify the callback's signature over the query string that precedes
  `signature`, as Google specifies, using Google's published verifier keys, and MUST refuse any
  callback that has no signature, an unknown key after a refresh, or a signature that doesn't
  verify.
- **FR-003**: The server MUST cache Google's verifier keys for 24 hours, refresh them when a callback
  names an unknown key id, and refresh at most once per minute for unknown ids.
- **FR-004**: When the keys can't be obtained, the callback MUST get a temporary error answer and
  MUST NOT be recorded, so AdMob can retry it.
- **FR-005**: Every validly signed callback MUST be answered 200, whatever its outcome (granted,
  duplicate, refused, unattributed), so AdMob doesn't retry it.
- **FR-006**: Each validly signed callback MUST be recorded once, keyed by its transaction id, with
  the player (when known), placement, reference, reward, key id, outcome and time; a callback whose
  transaction id is already recorded MUST change nothing. Granted records MUST be kept as long as
  the ledger; records that granted nothing MUST be deleted 90 days after they were written by a
  daily job.
- **FR-006a**: A validly signed callback whose AdMob `timestamp` is more than 7 days old MUST be
  answered 200, recorded as refused (`expired`) and grant nothing, so a callback whose refused
  record was deleted can never be replayed into a grant.
- **FR-007**: A refused or invalid callback MUST be logged with its outcome and without the player
  id or reference in clear in the log line, and refused signatures MUST be counted. When badly
  signed callbacks pass 20 in a rolling hour, and whenever Google's verifier keys can't be fetched,
  the server MUST report it to Sentry (which emails the operator), at most once per hour per kind;
  a single failure is only counted.

#### The grant

- **FR-008**: A validly signed callback MUST grant only when all hold: `user_id` names an active
  player; `custom_data` holds placement `morning_piggy` and a UUID reference not used by any other
  recorded reward; the player has fewer piggy grants this game day than the daily cap.
- **FR-009**: A grant MUST credit the configured JENEHAT and BONAT through the economy's single
  entry point, in one transaction under the player's wallet lock, as ledger entries with reason
  `ssv_grant`, source `ssv` and a reference to the reward record, and MUST bump the player's state
  version.
- **FR-010**: A callback that doesn't grant MUST record why: `duplicate_reference`, `cap_reached`,
  `not_server_placement`, `malformed`, `expired`, or `unattributed` (unknown, pending-deletion, deleted or
  empty player). A malformed field MUST never make the callback fail (5xx); a callback with no usable
  transaction id is answered 200, logged as malformed and not recorded (FR-006 can't key it).
- **FR-011**: The amounts granted MUST come from the server's live settings at processing time; the
  callback's `reward_amount` and `reward_item` MUST be recorded but MUST NOT decide the amount.
- **FR-012**: The game day for the cap MUST be the server's game day (`Africa/Cairo`) at processing
  time.
- **FR-013**: The piggy's JENEHAT and BONAT MUST be at least 0 each and not both 0; JENEHAT MUST
  stay JENEHAT and BONAT MUST stay BONAT (no conversion).

#### Asking for a reward

- **FR-014**: The server MUST expose `GET /v1/ads/rewards/{nonce}` to the signed-in player, answering
  for a reference recorded for that player: "granted" with the JENEHAT and BONAT granted and the
  wallet after the grant; or "refused" with the reason.
- **FR-015**: For a reference not recorded, recorded for another player, or recorded unattributed,
  the answer MUST be the same "not known" answer, revealing nothing about other players.
- **FR-016**: Asking MUST never write, and MUST be rate-limited like the player's other reads.
- **FR-017**: Bootstrap MUST tell the app whether the morning piggy is available to the player on
  the current game day (fewer grants today than the cap), and list the player's granted piggy
  rewards not yet confirmed as shown, each with its reference, JENEHAT, BONAT and grant time.
- **FR-017a**: The signed-in player MUST be able to confirm that the app showed a granted reward,
  by reference. The confirmation MUST be idempotent, MUST only mark the player's own granted
  rewards, and MUST answer the same for a reference that isn't one; it changes no balance. The app
  confirms whether it showed the reward from the lookup or from bootstrap.

#### Caps and live settings

- **FR-018**: The piggy's daily cap MUST be a live setting applied by both sides (default 1,
  matching glossary §3.4), added to the registry and to the app's bundled tunables with the same
  default; the existing CI check that compares both-sides defaults MUST cover it.
- **FR-019**: The piggy's JENEHAT and BONAT MUST be server-only live settings, with defaults
  of 30 JENEHAT and 2 BONAT (about one daily task's worth, keeping BONAT scarce: +14 a week),
  retuned after the closed test without a release.
- **FR-020**: Every cap in glossary §3.4 that has a number MUST be read from the live-settings
  snapshot, not from the environment or a constant: the refill ad's daily cap, the traffic jam
  ads per trip, and the piggy's daily cap. The "once per trip" caps of `result_double` and
  `trip_revive` are rules, not tunables (B10 FR-029).
- **FR-021**: The server's tests MUST drive every rewarded placement one past its cap and check the
  refusal, so the step's "caps on the server" holds across B03, B10 and B07.
- **FR-022**: A sync op that claims `morning_piggy` MUST stay refused `server_only`.

#### Operations

- **FR-023**: The admin MUST list recorded ad rewards to staff with the live-ops permission,
  filterable by player, placement, outcome and game day, read-only (no add, edit or delete).
- **FR-024**: The callback MUST work while maintenance is on (it confirms a watched ad). The daily
  cleanup job of FR-006 MUST use `skip_in_maintenance`, deleting nothing on a skipped run, and MUST
  never delete a granted record.
- **FR-025**: The API contract (`contracts/openapi.yaml`) and the architecture docs (backend §8.4,
  §12; mobile §15.1 where it names the answer) MUST describe the callback's answers, the reward
  lookup's answers and bootstrap's piggy field.

### Key Entities

- **Ad reward**: one validly signed AdMob callback. Transaction id (unique), player (optional),
  placement, reference (unique when present), the callback's reward amount and item, key id,
  outcome (granted or a refusal reason), the ledger entries it made (when granted), game day,
  created time, and the time the app confirmed it shown (granted rewards only). Only the shown time
  is ever set after the record is written.
- **Verifier key set**: Google's published public keys by key id, with the time they were fetched.
- **Live settings added**: the piggy's daily cap (both sides), the piggy's JENEHAT and BONAT
  (server only).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In tests with recorded callbacks, 100% of validly signed piggy callbacks for an
  eligible player grant exactly once, and 0% of tampered, unsigned, unknown-key, duplicate,
  over-cap, wrong-placement or unattributed callbacks grant anything.
- **SC-002**: A property test over random sequences of callbacks (duplicates, concurrent arrivals,
  game-day boundaries) keeps `wallet == sum(ledger)` and at most the daily cap of piggy grants per
  player per game day.
- **SC-003**: On staging, with a real test ad, the player sees the granted reward within 7 seconds
  of closing the ad (the app's last ask) in at least 9 of 10 tries.
- **SC-004**: A change to any of the three new live settings takes effect for callbacks processed at
  most 60 seconds later, with no restart.
- **SC-005**: The callback answers within 1 second for 95% of requests when the keys are cached.
- **SC-006**: Every rewarded placement in glossary §3.4 has a server test that refuses it one past
  its cap.
- **SC-007**: In tests, 21 badly signed callbacks within an hour produce exactly one operator
  alert, and 20 produce none.

## Assumptions

- Only `morning_piggy` uses server verification (backend §23 decision log); the other rewarded
  placements stay phone-applied `ad_reward` sync ops, whose validation B03 built. The AdMob console
  sets the callback URL only on the piggy's ad unit, which is an owner action recorded in
  `docs/owner-actions.md`.
- The interstitial grants nothing, and its rules (every 3 trips, grace of 10, not after a rewarded
  ad, not for `remove_ads`) are the app's, from tunables that already exist; the server has nothing
  to enforce for it.
- The callback grants during maintenance: B10's maintenance stops player writes (unsafe methods) and
  write jobs, and AdMob's retry window is short, so refusing would lose rewards the player already
  earned. The database stays up during maintenance.
- The reference (`nonce`) is made by the app per ad and isn't registered beforehand: the signed
  callback is what proves the ad was watched, and the reference only lets the app find its result.
- An unattributed callback isn't granted later even if the player appears, because a player id
  that doesn't exist at processing time can't be trusted.
- Google's verifier-key address and format are as Google documents them for AdMob SSV; the plan's
  research confirms the current details and the test vectors.
- B09 deletes or anonymizes a deleted player's ad rewards with the rest of their data; this feature
  only records them.
- The app's side (tagging the ad, asking, the banner, the not-ready and offline states, consent) is
  M11's; this feature only states what the server answers.
- No new money type, no engine rule and no content-schema change.
