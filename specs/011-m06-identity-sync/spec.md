# Feature Specification: Identity, Bootstrap and Sync (M06)

**Feature Branch**: `011-m06-identity-sync`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "start 011 (next feature per docs/delivery-plan.md)". In
`docs/delivery-plan.md` step 6, spec 011 is M06: "Identity, bootstrap, sync queue", which depends on
M05, B02 and B03. Sources: `docs/architecture-mobile.md` §12 (sync) and §16 (identity), with
§11, §13 and §14.1; the server side in `docs/architecture-backend.md` §6.4, §6.5 and §7; B02's
`contracts/tokens.md` "Client obligations"; B03's `contracts/api.md` and `contracts/operations.md`;
and the design `States` 1, 7 and 8 (offline, update required, maintenance), with
`docs/design/README.md`. To resolve: the device side of backend §22.6, which B02 research R5 left to
M06 (how the install id survives a re-install on each platform). Handed over from M05: send
`pendingOps` in `seq` order, apply each answer (`markAccepted`, `markRejected`), replace the base
(`replaceBase`), anchor trusted time on the server's (`anchorOnServer`), revisit the backup
exclusion, keep the sync calls away from screens, and queue lifecycle resyncs behind requests.
Handed over from M04: force a pack check when bootstrap reports a newer content version. Handed
over from B02: the install id, the background account, token storage and renewal, signing in again,
`account_deleted`, sending pending operations before linking, a `player_id` that changes, and the
bearer token on every call but the content ones. Handed over from B03: batches of 100 with
`base_state_version`, `state_stale`, the answer's wallet and `fuel_updated_at`, `content_version`
in the payload, the three quiet rejections, `server_time`, and at most one `comeback_gift` in the
outbox. Done when (step 6, with B02 and B03): the first online launch creates an anonymous account
in the background; offline trips sync without duplicates; the stale-state path works.

## Clarifications

### Session 2026-10-27

- Q: When someone re-installs the game on the same phone, should the very first open wait briefly
  for their progress before choosing between the intro and Home? → A: Yes. On the first open only,
  and only with a network, the Loading screen waits up to 3 s for the account and the player's
  progress. A returning player lands on Home; a new player's answer ends the wait at once. Progress
  that arrives later is M07's to handle (FR-003, FR-027).
- Q: Should a forced update still block a later launch with no network? → A: No. The block shows
  only when a live answer in this session says so. An offline launch plays on, and the block comes
  back at the next server contact (FR-029).
- Q: Should M06 build the request that links a Google account, leaving M14 only the Google sign-in
  and the screens? → A: Yes. M06 builds the link request, its outcomes, the retry with the player's
  choice, and the switch's token and state rules. M14 builds Google sign-in, «اربط حسابك», the
  two-summary choice and its warning (FR-012).
- Q: While the player is on the trip screen (a trip running or paused), should the app hold all
  syncing until they leave it? → A: Yes. Nothing is sent and no answer is applied while the trip
  screen is shown; the queue goes out when the player leaves it. Account creation and the bootstrap
  may still run in the background (FR-018).
- Q: When the server refuses something played offline and a visible balance changes, what does the
  player see? → A: One short, neutral toast per sync, in the design's toast style, saying the
  balance was updated from the server; nothing when no visible balance changed. The plan proposes
  the Arabic line for the owner's approval (FR-025).

## User Scenarios & Testing *(mandatory)*

The player rarely sees this feature. They see three messages (offline, update required,
maintenance) and, once in a while, a balance that corrects itself after a sync. Everything else
happens in the background. Its other users are **the later features**, which all rely on it: M07
(the name and the tutorial gift), M08 (Home and its states), M10 (story progress and family
requests), M11 (ad rewards), M12 (the shop), M13 (the daily loop and the comeback gift), M14
(linking Google and deleting the account) and M15 (reporting refusals). The last user is **the
tester** on internal builds, who needs to see where the account and the queue stand.

What the player gets from it:

- Nothing to sign up for. The game works from the first second, with or without a network, and the
  account appears by itself the first time the phone reaches the server.
- Every trip, purchase and booster played offline reaches the server once, in the order it was
  played, whenever the network comes back.
- Re-installing the game on the same phone brings the same progress back, without linking anything.
- BONAT bought or granted by the server shows on the phone, and a spend the server refuses is undone
  quietly, never with an alarming message.
- Honest messages when something is off: offline, an update needed, the server under maintenance.
  Trips keep working through all three, except a forced update.

### User Story 1 - An account appears in the background and stays (Priority: P1)

On the first open, the app makes an install id for this phone and keeps it somewhere a re-install
doesn't erase. The first time the phone reaches the server, the app creates an anonymous account
with it, without a screen or a question, and without holding up play. From then on, the app keeps the session alive by
itself: it renews the short-lived access in time, recovers from a lost answer, and signs in again
with the install id when a session ends. A re-install on the same phone gets the same player back.

**Why this priority**: Every server call the game makes from now on needs the account. Without it,
nothing syncs, no BONAT arrives, and nothing later in the plan can be built.

**Independent Test**: On a fresh install with the network off, play the first trip; then turn the
network on. An account exists on the server within seconds and no screen appeared. Restart the app:
no second account. Uninstall and reinstall on the same phone: the server sees the same player.

**Acceptance Scenarios**:

1. **Given** a fresh install with no network, **When** the player opens the app and plays the first
   trip, **Then** nothing asks for an account, and no screen waits for the network.
2. **Given** the phone has never had an account, **When** it first reaches the server, **Then** the
   app creates an anonymous account with this phone's install id in the background, and the player
   sees nothing.
3. **Given** the phone has an account, **When** the app restarts, **Then** it uses the session it
   has and creates no new account.
4. **Given** the access is about to expire, **When** the app is about to call the server, **Then**
   it renews first. **Given** a renewal whose answer was lost, **Then** the app retries with the
   same refresh token within a minute and gets the same successor, so the session continues.
5. **Given** the server refuses the session (a renewal answers `token_invalid` or `token_expired`),
   **When** the app next needs the server, **Then** it signs in again with the install id, gets the
   same player back, and goes on.
6. **Given** account creation is refused for rate (`429`), **Then** the app waits the time the
   server gives, tries again later, and play goes on meanwhile.
7. **Given** the app is uninstalled and installed again on the same phone (iOS, or Android with
   Google Play services), **When** it reaches the server, **Then** the same player comes back.
8. **Given** any build, **Then** the tokens and the install id never appear in logs, crash reports,
   analytics or the preference store.

---

### User Story 2 - Offline progress reaches the server once, in order (Priority: P1)

M05 records every trip start, result, purchase, booster use and ad reward on the phone as a pending
operation. This feature sends them to the server in the order they were recorded, applies the
server's answer to each, and takes the server's wallet as the new truth. A lost answer is sent
again, and the server's stored answers come back, so nothing is counted twice. An operation the
server refuses is undone on the phone, along with everything that depended on it.

**Why this priority**: This is the step's "done when", and the promise of offline play (constitution
V): a week of play on a bus with no signal must arrive on the server whole, once.

**Independent Test**: Against the local backend stack, play three trips and buy a booster with the
network off, then turn it on. The server holds each operation once, and the phone's balances equal
the server's. Repeat with the network cut halfway through the send: same outcome, no duplicates.

**Acceptance Scenarios**:

1. **Given** operations recorded offline and an account, **When** the phone is online, **Then** the
   app sends them in the order they were recorded, in batches of at most 100, and applies each
   answer: an accepted operation is marked synced, a rejected one is marked with its reason and
   undone on the phone.
2. **Given** a batch whose answer never arrived, **When** the app sends again, **Then** it sends
   the same operations with the same ids, gets the stored answers, and nothing is counted twice.
3. **Given** an answer has been applied, **Then** the phone's JENEHAT, BONAT and fuel equal the
   answer's wallet with the still-pending operations applied on top, and the countdown to the next
   liter follows the server's countdown start.
4. **Given** the server rejects an operation (BONAT the server doesn't have, a trip it says is
   locked), **Then** its effects are undone on the phone, operations that depended on it fall out
   too, and, if a balance the player can see changed, one neutral toast says the balance was
   updated from the server.
5. **Given** an operation rejected as `op_expired`, `content_version_unsupported` or
   `unknown_content_version`, **Then** it is undone the same way, with nothing alarming shown.
6. **Given** an operation that reads the content pack (a trip start, a purchase), **Then** it is
   sent with the content version it was recorded with, not the one active now.
7. **Given** 5,000 pending operations, **When** the phone comes online, **Then** all are sent
   within the server's batch, size and rate limits, while the player plays on.
8. **Given** a trip is on screen, **Then** no batch is sent and no server answer changes the phone's
   state until the player leaves the trip screen.

---

### User Story 3 - The phone stays in step with the server (Priority: P2)

At launch, on return to the foreground and when the network comes back, the app asks the server
where the player stands (bootstrap). It takes the server's time as its trusted time, keeps what the
server says about entitlements, the daily state, the comeback gift and app versions, and notices
when the server is ahead: another phone synced, staff adjusted the wallet, or the phone was just
re-installed. Then it fetches the player's full state, replaces its own with it, and keeps the
operations it hasn't sent yet on top.

**Why this priority**: Without it, BONAT never reaches the phone, two phones drift apart, and a
re-installed phone shows an empty game for a player who has progress.

**Independent Test**: Change a player's state from a second device (or with a staff balance
adjustment). On the next launch, the first phone shows the server's numbers, and the operations it
had pending are still applied once.

**Acceptance Scenarios**:

1. **Given** an account, **When** the app launches, returns to the foreground or regains the
   network, **Then** it asks the server for the bootstrap snapshot in the background, and anchors
   its trusted time on the server's time.
2. **Given** the server answers a batch with `state_stale` (another phone synced first), **Then**
   the app fetches the full state, replaces its own with it, and re-applies its still-pending
   operations on top.
3. **Given** nothing is pending and the server's state version is ahead of the one the phone last
   took, **Then** the app fetches the full state too.
4. **Given** BONAT granted by the server (a room's completion reward, a staff adjustment, later a
   purchase), **Then** the phone shows it after the next bootstrap or sync.
5. **Given** the bootstrap reports a content version newer than the active pack, **Then** a pack
   check runs at once, without waiting for M04's 15-minute spacing, and the pack switches by M04's
   rules (at launch or on arrival at Home, never during a trip).
6. **Given** the phone's clock is wrong, **When** it first reaches the server, **Then** fuel and
   time follow the server's time from then on, and trusted time never moves backward.
7. **Given** a fresh install for a player who already has progress (a re-install), with a network,
   **When** the app first opens, **Then** the Loading screen waits up to 3 s, the account and the
   player's state come back, and the app opens on Home with their progress instead of the intro.
   **Given** the state arrives after the 3 s, **Then** the phone takes it once the trip screen
   isn't showing, keeps what was played since the install on top, and tells the later features
   that progress was restored.
8. **Given** the phone is offline, **Then** the entitlements, daily state, comeback flag and
   profile from the last bootstrap are still readable, as last known values.

---

### User Story 4 - Offline, update required and maintenance are shown honestly (Priority: P2)

Three of the design's shared states belong to this feature (`States` 1, 7 and 8). The offline
banner sits at the top of Home while the phone can't reach the server, and says trips work and
progress will be saved. The update card blocks the game when the server says this version is too
old, with one button to the store. The maintenance card replaces the banner area on Home while the
server is closed for writes, and says trips work offline.

**Why this priority**: These are the only parts of the feature the player sees. They must be right,
but the game is playable without them.

**Independent Test**: With a fake server, trigger each state and compare it with its artboard (a
golden beside `docs/design/png/States.png` and a layout test against `docs/design/boxes/States.json`,
in RTL with both digit styles). Turn the network off on Home: the banner appears; turn it on: the
banner goes once bootstrap and sync succeed.

**Acceptance Scenarios**:

1. **Given** the phone has no network or can't reach the server, **When** the player is on Home,
   **Then** the offline banner shows at the top, and trips and every offline feature keep working.
   **When** the network is back and bootstrap and sync succeed, **Then** the banner hides by itself.
2. **Given** the bootstrap says the update is forced, or any call answers `426 client_outdated`,
   **Then** a blocking update card covers the screen (boot or Home), with one button that opens the
   store listing, no close button, and system back does nothing.
3. **Given** the server's latest version is newer than the app's but not forced, **Then** an update
   card with a close button shows once for that version, and the game goes on when it is closed.
4. **Given** the server answers `503 maintenance`, **Then** Home shows the maintenance card in the
   banner area, with the return time when the server gives one and the line without it when it
   doesn't, trips keep working offline, and pending operations wait. **When** a later call
   succeeds, **Then** the card goes.
5. **Given** several states at once, **Then** the update card blocks everything, and the offline
   banner wins over the maintenance card.
6. **Given** a trip is running, **Then** none of these interrupts it: an update card waits until
   the player leaves the trip screen.
7. **Given** each state, **Then** it is drawn in RTL with both digit styles, with the design's
   copy, roles for assistive technology, touch targets of at least 44×44 and text of at least 12 pt.

---

### User Story 5 - Account changes never mix two players' progress (Priority: P3)

The phone's player can change: after M14's "switch to the existing account" when linking Google,
or when the server gives this phone a new player because its old one was deleted. The app then
treats it as a different account. It never sends the old player's pending operations with the new
player's tokens, and it replaces its state with the new player's. Before a link, it sends everything
pending, so the two progress summaries M14 shows compare real numbers. If the server says the
account is deleted, the app stops calling the server for it.

**Why this priority**: Linking (M14) and deletion (M14, B09) come later in the plan, but the token
and state rules they rely on are this feature's, and a mistake here would hand one player's
currency to another.

**Independent Test**: With a fake server, sign in, record operations, then make the next sign-in
answer with another player. The old operations are never sent for the new player, and the phone
shows the new player's state. Start a link with operations pending: they are sent first.

**Acceptance Scenarios**:

1. **Given** a sign-in answers with a player other than the stored one, **Then** the app drops the
   old player's pending operations without sending them, replaces its state with the new player's
   state from the server, and stores the new player as the phone's.
2. **Given** a later feature starts a link (M14), **Then** the app first sends every pending
   operation and reports whether it managed to, then links; a conflict comes back with both
   progress summaries and the other player's id, and the retry with the player's choice follows.
3. **Given** the player chose to switch to the existing account, **Then** the app stores the new
   tokens and player, and applies scenario 1.
4. **Given** a link refused because Google's token is invalid, **Then** the app never renews its own
   session because of it.
5. **Given** the server answers `403 account_deleted`, **Then** the app stops calling the server for
   that account, play goes on with what is on the phone, and later features (M14, B09) decide what
   the screen shows.
6. **Given** operations recorded before the phone ever had an account, **Then** they belong to the
   first account the phone signs into, and are sent for it.

---

### User Story 6 - Testers can see where the account and the queue stand (Priority: P3)

On dev and staging builds, a status card on the playtest Home shows the account and sync status: a
short form of the player id, the linked providers, how many operations are pending, the state
version, when the last sync ran and how it ended, and the last error code. A "sync now" action
sends the queue at once. It sits on Home rather than in the trip's debug panel, because nothing
syncs while the trip screen shows.

**Why this priority**: Testing sync on a real phone without it means reading the server's admin.
It speeds up the owner's live checks, but players never see it.

**Independent Test**: On a staging build, look at Home's status card, play a trip offline, and see
the pending count rise; go online and tap "sync now"; see it fall to 0 and the state version move.

**Acceptance Scenarios**:

1. **Given** a dev or staging build, **When** the tester looks at Home's status card, **Then** it shows
   the account and sync status listed above, and never a token or the install id.
2. **Given** a production build, **Then** none of it is reachable.

---

### Edge Cases

- **A week offline from the first open.** The tutorial trips and everything after them are kept and
  sent in order when the phone first reaches the server, right after the account is created. They
  belong to that account.
- **A slow network on the first open.** The Loading screen gives up after 3 s and onboarding starts.
  If the player turns out to have progress, it arrives later and M07 decides what onboarding does.
  A connection that fails outright ends the wait at once.
- **The account is created while a trip runs.** That's fine: creation runs in the background. The
  queue waits until the player leaves the trip screen.
- **The app is killed in the middle of a sync.** Answers not yet applied are lost with the process.
  The next sync sends the same operations again and gets the stored answers. An answer is applied
  completely or not at all.
- **Two triggers at once** (the app returns to the foreground as the network comes back). One sync
  runs at a time; the second trigger joins it or runs right after.
- **A player request while an answer is being applied** (a purchase tapped as a sync finishes). The
  two run one after the other, never interleaved, and neither is lost.
- **A batch too big for the server** (`413 payload_too_large`, or `batch_too_large`). The app sends
  smaller batches. Trip results can be up to 8 KB each, so 100 of them can exceed the server's size
  limit.
- **A malformed batch** (`400 validation_error`), which only a bug in the app can cause. If the
  server names one operation, that operation is set aside as rejected (`validation_error`), undone,
  and recorded for reporting (M15), so the rest of the queue flows. If it names none, the queue holds
  until the next launch, and play goes on.
- **Rate limits** (`429`). The app waits the time the server gives before sending again.
- **The server is down, slow or unreachable.** The queue stays as it is, the app tries again later
  with growing waits, and Home shows the offline banner. Nothing else changes for the player.
- **BONAT spent on this phone that the server doesn't have** (a second phone spent it first). The
  spend is rejected and undone: the booster bought with it goes away, and a use of it in a trip is
  rejected as `none_left`. The trip's result stays. The player sees the neutral toast.
- **The server's fuel differs from the phone's** (an overdraft accepted while offline, a wrong
  clock). The phone takes the server's tank and countdown.
- **An unfinished trip on the server that this phone has no record of** (started on another phone).
  It isn't offered for resuming here. The next trip start on this phone closes it as abandoned, as
  the server does.
- **The server's state names a trip or an item the active pack doesn't have** (an older bundled
  pack). It is kept, and the screens skip it.
- **A re-install on Android without Google Play services, or after a factory reset with no
  backup.** The install id is gone, so the phone gets a new player. Linking Google (M14) is the way
  back to the old one.
- **A backup restored to a new phone while the old one is still in use.** Both phones carry the same
  install id and reach the same player, each with its own session, and the stale-state path keeps
  them in step.
- **The comeback gift is claimable, and a claim is already waiting to be sent.** No second claim is
  made, even though the server keeps answering "claimable" until the first claim has synced.
- **The update is forced and the phone then goes offline.** The block is shown when a live answer
  says so. A later launch with no network plays on, and the block comes back the next time the
  server says so. Operations recorded meanwhile wait, and sync after the update.
- **Maintenance while a link or a purchase is attempted** (M12, M14). Those features show their own
  failure; this feature reports the maintenance state they read.
- **An operation older than the server keeps** (180 days pending). The server rejects it as
  `op_expired`, and the phone undoes it quietly. A phone offline for six months loses that play,
  as B03 decided.
- **The disk is full when an answer is applied.** Nothing is applied; the next sync sends the same
  operations again.
- **The server's starting state for a new player differs from the phone's** (a tank size changed
  in between). The server's wins at the first sync.

## Requirements *(mandatory)*

### Functional Requirements

#### The install id and the account

- **FR-001**: On the first open, the app MUST create a version-4 install id once, without the
  network, and keep it where a re-install on the same phone doesn't erase it: on iOS, a store that
  survives the app's deletion and stays on this device; on Android, a store that survives a
  re-install and may follow a restored backup to a new phone, with the platform's backup of that one
  value as the fallback. The plan picks the mechanism for each platform (resolving the device side
  of backend §22.6, B02 research R5).
- **FR-002**: The install id MUST be sent only to account creation (`POST /v1/auth/anonymous`), and
  MUST NOT be logged, shown or reported.
- **FR-003**: The app MUST create the anonymous account in the background the first time the server
  is reachable, and MUST NOT make boot, a trip or any screen wait for it (constitution V), with one
  exception: the first open's bounded wait of FR-027. The first trip stays playable within 20 s of
  the first open, with or without a network.
- **FR-004**: A failed account creation MUST be retried later with growing waits, and a `429` after
  the `retry_after_s` the server gives. Play goes on meanwhile.
- **FR-005**: The tokens MUST be kept only in secure storage, the access and refresh tokens stored
  together before any other call uses them. They MUST NOT reach the preference store, logs, crash
  reports or analytics, and a test MUST check it (constitution, Security & privacy).
- **FR-006**: The app MUST follow B02's renewal rules (`contracts/tokens.md` "Client obligations"):
  - renew before a call when the access has about 60 s left, using `access_expires_in` from the
    answer, never the token's contents;
  - run one renewal at a time;
  - retry a renewal whose answer was lost with the same refresh token, within 60 s;
  - on `401 token_expired`, renew; on `401 token_invalid`, renew once;
  - when the renewal itself answers `token_expired` or `token_invalid`, sign in again with the
    install id.
- **FR-007**: On `403 account_deleted`, the app MUST stop calling player endpoints for that account,
  keep play going on the phone, and expose the state so M14 and B09 can decide the screen.
- **FR-008**: Every call to the server MUST carry the player's token and the two headers
  (`X-Client-Version`, `X-Platform`), except the content manifest and the pack downloads, which stay
  public (B02 FR-035).
- **FR-009**: The app MUST keep the player's profile as the server last gave it (player id, linked
  providers, display name, driver level), readable offline by later features.

#### Account changes

- **FR-010**: Operations recorded before the phone ever had an account MUST belong to the first
  account the phone signs into.
- **FR-011**: When a sign-in answers with a player other than the stored one, the app MUST treat it
  as a different account: drop the old player's pending operations without sending them (keeping
  their count for reporting), replace the phone's state with the new player's state from the server,
  and store the new player and tokens.
- **FR-012**: The app MUST offer later features (M14) a link request that first sends every pending
  operation and reports whether it managed to, then links. Its outcomes: linked; a conflict, with
  both progress summaries and the other player's id; Google's token refused; or no network. The
  retry with the player's choice (keep this account, or switch to the existing one) sends the other
  player's id back. A switch applies FR-011. A refused Google token MUST NOT make the app renew its
  own session. The Google sign-in that produces the token, and every linking screen, are M14's
  (Clarifications).

#### Bootstrap and trusted time

- **FR-013**: With an account, the app MUST ask the server for the bootstrap snapshot at launch
  (after startup, in the background), on return to the foreground and when the network comes back.
  The plan sets the least time between two requests.
- **FR-014**: The app MUST anchor trusted time on the server's time from the bootstrap (and from the
  full state when it fetches one), through M05's anchor. Trusted time MUST NOT move backward
  (constitution VI).
- **FR-015**: The app MUST keep the latest bootstrap's entitlements, daily state, comeback flag and
  app-version block on the phone, readable offline as last known values. Entitlements are a
  read-only cache of the server's (constitution IV).
- **FR-016**: When the bootstrap reports a content version newer than the active pack, the app MUST
  run a pack check at once, ignoring M04's 15-minute spacing. Switching packs keeps M04's rules.

#### Sending operations

- **FR-017**: The app MUST send pending operations in the order they were recorded, in batches of
  at most 100 and within the server's size limit, each batch with the state version the phone last
  took from the server.
- **FR-018**: One sync MUST run at a time. A sync MUST start when an account becomes available, at
  launch, on return to the foreground, when the network comes back, shortly after new operations are
  recorded, and when the player leaves the trip screen. It MUST NOT run in the background, since the
  app does no background work besides notifications (constitution, performance budgets). While the
  trip screen is shown, with the trip running or paused, nothing MUST be sent and no answer MUST be
  applied; account creation and the bootstrap may still run (Clarifications).
- **FR-019**: Each operation MUST be sent with its id, its type, the trusted time it was recorded at
  (UTC), and its payload. Every operation that reads the pack MUST carry in its payload the content
  version it was recorded with (B03, backend §7.4). The phone's own bookkeeping (deltas, fuel
  numbers, bounds) MUST NOT be sent.
- **FR-020**: A batch whose answer is lost or failed MUST be sent again with the same operations and
  ids. A network failure MUST NOT change the queue.
- **FR-021**: The app MUST apply each answer:
  - an accepted operation is marked synced;
  - a rejected one is marked with its reason and undone through M05's fold, so operations that
    depended on it fall out too;
  - the answer's wallet replaces the base the phone folds from, with its countdown start
    (`fuel_updated_at`) as M05's, and the answer's state version becomes the phone's.
- **FR-022**: Applying an answer MUST be one atomic step with the phone's state, run one after the
  other with the player's requests, never interleaved (M05's review). The calls that apply answers
  MUST be reachable by the sync alone, never by screens.
- **FR-023**: When an answer says `state_stale`, or when nothing is pending and the server's state
  version is ahead of the phone's, the app MUST fetch the full state, replace its base with it
  (wallet, inventory, ownership, trip progress, the unfinished trip, the last result) and re-apply
  its still-pending operations on top.
- **FR-024**: The app MUST handle every refusal of a whole request:
  - `413 payload_too_large` or `400 batch_too_large`: send smaller batches;
  - `400 validation_error` naming an operation: set that operation aside as rejected
    (`validation_error`), undo it and record it for reporting; naming none: hold the queue until the
    next launch;
  - `429`: wait the time the server gives;
  - a server error, a timeout or no network: try again later with growing waits;
  - `401`: FR-006; `403 account_deleted`: FR-007; `503 maintenance`: hold the queue and show the
    maintenance state (FR-031); `426 client_outdated`: show the update state (FR-029).
- **FR-025**: When a rejection changes a balance the player can see (JENEHAT, BONAT, fuel, boosters)
  or takes away something owned, the app MUST show one short, neutral toast, in the design's toast
  style, saying the balance was updated from the server, at most once per sync. It names no item
  and makes no apology. Nothing is shown when no visible balance changed. `op_expired`,
  `content_version_unsupported` and `unknown_content_version` get nothing beyond that toast (B03
  hand-over). The plan proposes the Arabic line, and the owner approves it (Clarifications).
- **FR-026**: An unfinished trip in the server's state that this phone has no record of MUST NOT be
  offered for resuming. The next trip start closes it as abandoned, as the server does. Ids in the
  server's state that the active pack lacks MUST be kept and skipped by readers.
- **FR-027**: On the first open of an install, and only when the phone has a network, the Loading
  screen MUST wait up to 3 s for the account and, for a player who already has progress, their
  state (Clarifications). An answer that the player is new ends the wait at once. If the state
  arrives in time, the app takes it (FR-023) and boot goes to Home instead of onboarding. If it
  arrives after the 3 s, the app takes it the same way once the trip screen isn't showing
  (FR-018), and tells later features that progress was restored, so the onboarding (M07) can
  react. Every later launch, and a first open without a network, doesn't wait.

#### The comeback gift

- **FR-028**: When the latest bootstrap says the comeback gift is claimable, the app MUST let later
  features (M13's `Returning`) claim it. A claim fills the tank (even a full one) and adds one
  `change_bag` on the phone at once, works offline, and is sent as a `comeback_gift` operation. No
  second claim may be made while one is pending, even though the server keeps answering "claimable"
  until the first one has synced. The gift adds no BONAT (M05's direction rule still holds).

#### The three states

- **FR-029**: When a live answer in this session says the update is forced (the bootstrap's
  `force_update`, or `426 client_outdated`), the app MUST show the blocking update card (`States`
  7) over boot or Home: one button opening the store listing, no close button, system back doing
  nothing. A launch with no network MUST NOT show it from memory (Clarifications).
- **FR-030**: When the server's latest version is newer than the app's and the update isn't forced,
  the app MUST show the update card with a close button, once per newer version.
- **FR-031**: When the server answers `503 maintenance`, Home MUST show the maintenance card
  (`States` 8) in the banner area: with the return time when the answer gives one (B10 adds it), and
  without the time otherwise. Trips and offline features keep working, the queue waits, and the
  next resume tries again. The card goes when a call succeeds.
- **FR-032**: While the phone has no network, or its last attempt to reach the server failed for a
  network reason, Home MUST show the offline banner (`States` 1). It hides when the network is back
  and the bootstrap and a sync have succeeded. The same online state MUST be readable by later
  features for their «محتاج نت» chips.
- **FR-033**: Precedence MUST be: the update card blocks everything; the offline banner wins over
  the maintenance card. None of them may interrupt a trip on screen: the update card waits until the
  player leaves the trip screen.
- **FR-034**: Each state MUST use the design's shared components and copy (`OfflineBanner`,
  `AppDialog` content, `StatusCard`), with its text in the app's string files. Each MUST have a
  sample, goldens in both digit styles beside `docs/design/png/States.png`, and a layout test
  against `docs/design/boxes/States.json` within ±2 pt, in RTL (HANDOFF §10). Banners and cards
  are `status` for assistive technology, touch targets are at least 44×44 and text at least 12 pt.
- **FR-035**: Home is still M03's placeholder, so the banner and the maintenance card go on it. M08
  rebuilds Home (`HomeStates`) with the same components and triggers.

#### Privacy, storage and security

- **FR-036**: The game database MUST stay out of the device backup and phone-to-phone transfer,
  as M05 decided. The install id is the only value carried across a re-install (resolving M05's
  hand-over to revisit it). A test MUST check the backup rules.
- **FR-037**: What this feature stores on the phone (the profile, the sync bookkeeping, the last
  bootstrap) MUST survive app updates and follow the database's upgrade rules (M05 FR-003).
- **FR-038**: Every call this feature makes MUST follow the app's one rule for addresses: HTTPS
  only, with plain HTTP allowed only in dev builds and only to the developer's own machine
  (constitution 1.2.0).

#### Internal builds

- **FR-039**: On dev and staging builds, a status card on the playtest Home MUST show the account
  and sync status (User Story 6) and offer "sync now". It MUST NOT show a token or the install id, and production
  builds MUST NOT include it.

#### Testing

- **FR-040**: Tests MUST cover every answer path against a fake server: account creation, renewal
  (including the lost answer and the race), signing in again, a changed player, account deleted,
  every batch outcome and refusal in FR-024, the stale path, and the three states.
- **FR-041**: A property test MUST run random sequences of offline play, lost answers, retries,
  rejections and stale answers against a model of the server, and check after the queue drains that
  the phone equals the server and that no operation applied twice (constitution VI).
- **FR-042**: An integration test MUST run against the local backend stack (B02, B03): offline play
  then sync with no duplicates, the stale path from a second session, and a re-sign-in after a
  session ends. Line coverage stays at 80% or more (constitution XIII).

### Key Entities

- **Install id**: a random version-4 id made once per install and kept across re-installs on the
  same phone where the platform allows it. It is this phone's credential with the server, and is
  never shown or logged.
- **Session**: the pair of tokens the server issued at the last sign-in or renewal, with how long the
  access lasts. Kept in secure storage only.
- **Player profile**: the player id this phone belongs to, the linked providers, the display name
  and the driver level, as the server last gave them.
- **Pending operation**: an M05 operation the server hasn't answered yet. It is sent as it was
  recorded, and its row's sync status and reason are the only things this feature changes.
- **Sync bookkeeping**: the state version the phone last took from the server, the player that
  version belongs to, and when the last sync ran and how it ended.
- **Bootstrap snapshot**: the latest bootstrap's entitlements, daily state, comeback flag, content
  version and app-version block, with the time it was received.
- **Full state**: the server's snapshot of the player at one state version, which replaces the
  phone's base (wallet, inventory, ownership, trip progress, the unfinished trip, the last result).
- **Connection state**: whether the phone can reach the server now, which the offline banner and
  the later features' «محتاج نت» chips read.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the network on or off, the first trip is playable within 20 s of the first open.
  Cold start to Home stays under 3 s on the Galaxy A06 with the network on, off, or the server down:
  only the first open waits for the network, and never more than 3 s.
- **SC-002**: With the network on, the account exists on the server within 10 s of the first open,
  or of the first moment the server is reachable, and no screen appeared.
- **SC-003**: In at least 1,000 random runs of offline play, lost answers, retries, rejections and
  stale answers, after the queue drains the phone's JENEHAT, BONAT, fuel, boosters, ownership and
  trip progress equal the server's, and no operation was applied twice, in 100% of runs.
- **SC-004**: Against the local backend, 50 trips and purchases recorded offline and sent with the
  network cut at random points end with each operation on the server exactly once and the balances
  equal, in 100% of runs.
- **SC-005**: A backlog of 5,000 operations of ordinary play (trip results the size the engine
  writes them, about 1 KB) is fully answered within 2 minutes of a normal connection, while the
  player keeps playing. No backlog is ever refused for rate or size, even with every trip result at
  its 8 KB maximum, which only makes it slower.
- **SC-006**: A re-install on the same phone (iOS, and Android with Google Play services) brings the
  same player and their progress back within 10 s of being online, on every test device. With a
  normal connection, its first open goes straight to Home with that progress, without the intro.
- **SC-007**: In every tested case of an expired access, a lost renewal answer, two renewals racing,
  an ended session and a retired signing key, the next call succeeds with the same player and no
  action from the player.
- **SC-008**: Zero tokens or install ids in logs, crash reports, analytics or the preference store,
  checked by a test and by reading a staging build's logs.
- **SC-009**: Each of the three states matches its artboard: every box within ±2 pt, both digit
  styles, and the goldens reviewed beside the design's PNG.
- **SC-010**: Zero trips interrupted by a sync, a state replacement or a state card, in the tests
  and on the reference device.

## Assumptions

- **Dependencies.** M05, B02 and B03 are merged, so the economy, the accounts and the sync endpoints
  exist. M07–M15 are not: the name, the tutorial gift, story progress, ad rewards, the shop, the
  daily loop, the `Returning` dialog, linking screens and deletion come later and use what this
  feature offers.
- **Resolved here without the owner** (the owner settled the rest in Clarifications):
  - **A malformed operation is set aside** (FR-024) rather than blocking the queue forever: it can
    only come from a bug in the app, and every later operation would wait behind it.
  - **An optional update shows once per version** (FR-030). The design draws only the forced card,
    so the optional one is the same card with a close button.
- **Server answers not live yet.** The server doesn't answer `503 maintenance` or `426` until B10,
  its entitlements are neutral until B06, and its daily state until B08. The app handles all of them
  now, tested against a fake server, and the maintenance card shows no return time until B10 adds
  one (HANDOFF §9.3 #8).
- **The store listing.** The update button opens the game's Play Store listing on Android. iOS has
  no App Store listing yet (no paid Apple account), so the plan picks what the iOS button opens
  until there is one.
- **The server's starting state.** B03 creates a new player's wallet like M05's new player (a full
  tank, nothing else). If they ever differ, the server's wins at the first sync.
- **Parts of the full state with no table on the phone yet** (story, grants, stats) are left for
  the features that add those tables (M07, M10, M13). They extend the state replacement then.
- **Time.** Trusted time keeps M05's rules: the uptime counter advances the anchor, and the server's
  time becomes the anchor whenever the app receives one. The iOS uptime source is M14's and phase
  3's (M05 hand-over).
- **Handed to later features**:
  - **M07**: the "progress was restored" signal for progress that arrives after the first open's
    3 s wait (FR-027); the tutorial gift operation and the name, which are its own.
  - **M08**: Home's `HomeStates` with the offline banner and the maintenance card (FR-035).
  - **M13**: the `Returning` dialog, which claims the comeback gift (FR-028).
  - **M14**: the linking screens on FR-012, and what `account_deleted` shows (FR-007).
  - **M15**: reporting rejections, set-aside operations, dropped operations of an old player, and
    renewal failures.
- **Out of scope**: Google sign-in and the linking screens (M14); account deletion (M14, B09); push
  tokens (M14, B11); syncing settings such as the digit style (M14); ads (M11); purchases (M12); the
  daily loop and the `Returning` dialog (M13); story progress and family requests (M10); analytics
  (M15); Sign in with Apple and device attestation (phase 3).
