# Feature Specification: Accounts and Auth (B02)

**Feature Branch**: `009-b02-accounts-auth`

**Created**: 2026-10-24

**Status**: Draft

**Input**: User description: "009". In `docs/delivery-plan.md` step 6, spec 009 is B02: "Accounts and
auth: anonymous accounts, refresh rotation, Google/Apple linking and conflicts", which depends on B01.
Sources: `docs/architecture-backend.md` §6 and §13, with §12 "accounts", §14 and §22.6, and the
client side in `docs/architecture-mobile.md` §12 and §16. To resolve: backend §22.6 (a re-install
without a linked provider creates a new player), together with M06. Handed over from B01
(`specs/002-b01-backend-skeleton/research.md` R3, R4): how a `Player` authenticates, and per-player
throttles for authenticated traffic, minding carrier-grade NAT. Handed over from B04 (FR-033): whether
the content manifest needs a player token. Done when (step 6, together with B03 and M06): the first
online launch creates an anonymous account in the background.

## Clarifications

### Session 2026-10-24

- Q: Backend §22.6: a player who never linked Google re-installs the app or clears its data. Do they
  get their progress back? → A: Yes, on the same phone. The app keeps the install id where a
  re-install doesn't wipe it, so the same player comes back without linking (FR-008).
  - This is M06's work. The server needs nothing beyond FR-005, and the app database still stays out
    of device backup (M05).
  - M06's research checks what each platform allows. Where it can't keep the id, the re-install gets
    a new player, and linking Google is the way back.
- Q: A phone still has its install id but its session has lapsed, and its player has linked Google.
  Does the install id still bring the player back? → A: Yes. The install id leads to whichever
  player its device belongs to, linked or not, until a switch or a deletion (FR-005).
  - This replaces backend §6.4's "while it is not linked to a provider".
  - Accepted risk: a copied install id opens the account. Accounts hold no personal data, and nothing
    in them can be moved to another account.
- Q: When a phone signs in again with its install id, does that end the phone's older sessions? →
  A: No. Older sessions stay alive until they lapse, 30 days after their last renewal. The server
  keeps at most a fixed number of active sessions per player (a server setting; the plan picks the
  default, around 10) and ends the oldest beyond it (FR-010).
  - Two phones that share a restored install id never sign each other out.

## User Scenarios & Testing *(mandatory)*

Players never see this feature directly. Its direct user is **the app**, acting for the player: M06
creates the account and keeps the session alive, and M14 adds linking to Settings. The other users
are **the operator**, who rotates the signing key and looks players up in the admin, **support
staff**, and **the later backend features** (B03 sync, B06 purchases, B07 ads, B08 the daily
challenge, B09 deletion, B11 push), which all need to know which player is calling.

What the player gets from it:

- They never register. The account appears on the first online launch, with no screen and no wait,
  and play never depends on it (constitution V).
- They are never signed out by a dropped connection or a server key change.
- Linking Google keeps their progress when they change phones. When a Google account already
  belongs to other progress, nothing is merged, duplicated or dropped without asking: the player
  chooses which progress to keep (backend §6.4).

### User Story 1 - The first online launch gets an account without the player noticing (Priority: P1)

On its first launch with a network, the app sends its install id (a random id it generated on its
first open), its platform and its locale. The server creates an anonymous player and answers with
the player's id and a token pair. When the same install id comes again, the server answers with the
same player and a new pair. The player sees nothing, and offline play never waits for any of it.

**Why this priority**: Every server-backed feature after B02 (sync, BONAT, purchases, ads, the daily
challenge, push, deletion) needs to know which player is calling. Without an account, nothing the
player does reaches the server.

**Independent Test**: Send the creation request twice with one install id and once with another,
then call an endpoint that needs a player token with each access token. There are two players, not
three, and each token is accepted as its own player.

**Acceptance Scenarios**:

1. **Given** no player has install id X, **When** the app sends X with platform `android` and locale
   `ar-EG`, **Then** a new active player is created with that platform and locale, and the answer
   (201) carries its `player_id`, an access token, a refresh token and `created: true`.
2. **Given** player P was created from X and is active, **When** the app sends X again, **Then** the
   answer (200) names P, with a new token pair and `created: false`, and no player is created. This
   holds whether or not P has linked Google (FR-005).
3. **Given** 10 requests with the same new install id arrive at the same moment, **Then** exactly one
   player exists afterwards, and every answer names it.
4. **Given** P's account is pending deletion or deleted, **When** the app sends X, **Then** a new
   player is created for X, and P is neither returned nor changed.
5. **Given** the install id isn't a well-formed random id, or the platform isn't `android` or `ios`,
   or the `X-Client-Version` or `X-Platform` header is missing or malformed, **Then** the request is
   refused with `validation_error` and nothing is created.
6. **Given** one network address has reached its limit for account creation, **When** another
   request comes from it, **Then** it is refused with `rate_limited` and a retry time, and nothing is
   created. The app keeps playing offline and tries again later.

---

### User Story 2 - A session stays alive for as long as the player keeps playing (Priority: P2)

Access tokens last 15 minutes and refresh tokens 30 days (constitution, "Security & privacy"). Each
renewal spends the refresh token and returns a new pair, so a player who opens the game at least once
every 30 days is never signed out. Mobile networks drop answers, so a renewal whose answer the app
never received can be repeated for a short time and gives the same result. An old refresh token used
again after that has been copied, so that device's session ends.

**Why this priority**: Without renewal, every player would need a new account after 15 minutes.
Without rotation and reuse detection, a copied refresh token would keep working for 30 days.

**Independent Test**: Renew one session 2,880 times (30 simulated days at one renewal every
15 minutes), losing one answer in five and retrying it. The session survives. Then present a refresh
token that was spent long ago: that device's session ends, and the same player's session on another
device does not.

**Acceptance Scenarios**:

1. **Given** refresh token R1, **When** the app renews, **Then** it gets a new access token and a new
   refresh token R2, valid for 30 days from now, and R1 is spent.
2. **Given** R1 was spent within the retry window (FR-011), **When** R1 comes again, **Then** the
   answer carries the same R2, with a working access token, and the session continues.
3. **Given** R1 was spent before the retry window, **When** R1 comes again, **Then** it is refused
   with `token_invalid`, and that session ends: R2 and everything renewed from it stop working. The
   player's sessions on other devices keep working.
4. **Given** an access token older than 15 minutes, **When** it is used, **Then** the request is
   refused with `token_expired`. **Given** a token that was altered, signed by an unknown key, or of
   the wrong kind (a refresh token used as an access token, or the reverse), **Then** it is refused
   with `token_invalid`.
5. **Given** a refresh token older than 30 days, **When** it is used, **Then** it is refused with
   `token_expired`. The app gets back into the account through its install id (User Story 1, FR-005).
6. **Given** P's account becomes pending deletion, **When** any of P's tokens is used, even an access
   token issued a minute earlier, **Then** the request is refused with `account_deleted` (403).
7. **Given** the operator rotates the signing key, **Then** tokens signed with the previous key keep
   working until they expire, new tokens are signed with the new key, and no player is signed out.
8. **Given** a phone signs in again with its install id, **Then** its earlier sessions keep working
   until they lapse. **Given** the player already has the maximum number of active sessions
   (FR-010), **When** one more sign-in comes, **Then** the least recently renewed session ends, and
   the others keep working.

---

### User Story 3 - A player links Google to keep their progress (Priority: P3)

From Settings (M14), the player signs in with Google, and the app sends Google's ID token. The server
checks that the token is genuine, issued for this game and still current. It keeps only Google's
account number for the player, and answers with the player's linked providers. From then on, that
Google account brings this player back on any phone (User Story 4).

**Why this priority**: Linking is what protects progress across a phone change, but it is optional:
a player who never links still plays everything. Accounts and sessions (P1, P2) come first.

**Independent Test**: With ID tokens signed the way Google signs them, for the game's client id, link
a player, then send the same token again. Then send a token issued for another app, an expired one
and one with a bad signature.

**Acceptance Scenarios**:

1. **Given** P has no Google link, and Google account G belongs to no player, **When** P sends a
   valid ID token for G, **Then** P is linked to G, and the answer lists `google` among P's
   providers. The server keeps G's account number and nothing else from the token: no email address,
   name or picture.
2. **Given** P is linked to G, **When** P sends a token for G again, **Then** the answer is 200 and
   nothing changes.
3. **Given** P is linked to G, **When** P sends a token for a different Google account G2, **Then**
   it is refused with a conflict code the plan adds to backend §6.2 (FR-040), and P stays linked to G.
4. **Given** a Google token that is expired, issued for another app or by another issuer, badly
   signed, or malformed, **Then** it is refused with a provider-token code the plan adds to §6.2, and
   nothing changes. It is never `token_invalid`, which would tell the app that its own session is
   broken.
5. **Given** Google's signing keys can't be fetched and none are held from before, **Then** the
   request is refused with `dependency_unavailable` (503), and nothing changes.
6. **Given** `provider: apple`, **Then** the request is refused with `validation_error` until Sign in
   with Apple arrives in phase 3 (FR-021).

---

### User Story 4 - The Google account already has other progress: the player chooses (Priority: P3)

When Google account G is already linked to another player E, the server doesn't link. It answers
409 `provider_in_use` with a short summary of both players (backend §6.4). The app shows both (M14),
and the player picks one, which the app sends back with the same request:

- `switch_to_existing`: this phone signs in to E. This is also how a player gets their progress back
  on a new phone.
- `keep_current`: G moves to the current player C. E keeps all its data, but G no longer signs in
  to it.

Accounts are never merged, so nothing can be counted twice.

**Why this priority**: Together with User Story 3, it is what makes linking safe.

**Independent Test**: Create E linked to G on one device, and C unlinked on another. Link G from C,
then retry once with each choice, each from a fresh copy of that state. Check where G, the devices
and the sessions end up, and that no other data of either player changed.

**Acceptance Scenarios**:

1. **Given** E is linked to G and C is not, **When** C links G, **Then** the answer is 409
   `provider_in_use` with `details.current` and `details.existing`, each holding at least the driver
   level, the current chapter and the BONAT balance (§6.4) as the server knows them now. Nothing
   changes.
2. **When** C retries with `resolve: "switch_to_existing"`, **Then** the answer carries E's
   `player_id`, a new token pair for E and E's providers. This device's session as C ends, and this
   device now belongs to E, so its install id leads to E from then on (FR-005). C's data stays as
   it was.
3. **When** C retries with `resolve: "keep_current"`, **Then** G is linked to C, E no longer has G,
   and the answer lists C's providers. E's other data, its devices and its sessions are untouched.
4. **Given** either choice, **Then** no balance, purchase, progress or ownership moves between C and
   E.
5. **Given** the conflict changed between the 409 and the retry (G now belongs to another player, or
   E has been deleted), **Then** the server doesn't act on a choice the player made about something
   else. It answers a new 409 with the new summaries, or links G when there is no conflict any more.
6. **Given** `resolve` is sent when there is no conflict, **Then** it is ignored and G is linked as in
   User Story 3. **Given** an unknown `resolve` value, **Then** the request is refused with
   `validation_error`.
7. **Given** E is pending deletion or deleted, **Then** G counts as free, and it is linked to C with
   no conflict.

---

### User Story 5 - Staff look a player up (Priority: P4)

Support and the operator find a player in the admin by `player_id`, and see their status, platform,
app version, when they were created and last seen, their linked providers (by name only) and their
devices. They can mark a player as a tester. They can't see tokens, install ids or provider account
numbers, and can't change anything else.

**Why this priority**: It helps support and testing, but no player depends on it.

**Independent Test**: As staff with the player permission and as staff without it, open a player.
Check what is shown, and that only the tester flag can be changed.

**Acceptance Scenarios**:

1. **Given** staff with the player permission, **When** they search for a `player_id`, **Then** they
   see that player's status, platform, app version, created and last-seen times, providers and
   devices, and no token, install id or provider account number.
2. **Given** the same staff, **When** they mark the player as a tester, **Then** the flag is saved
   and the change is recorded in the admin's history. No other field can be edited.
3. **Given** staff without the player permission, **Then** players don't appear in their admin.

---

### Edge Cases

- **Two renewals of one refresh token at once** (two parts of the app racing): both get the same
  successor (FR-011), and the session doesn't end.
- **Ops sent after a switch.** After `switch_to_existing`, the app may still hold operations it
  recorded as C.
  - The server never moves them to E.
  - Sent with C's access token while it still works (at most 15 minutes, see below), they apply to
    C.
  - After that, renewing C's ended session is refused with `token_invalid`, so they can't be sent
    at all.
  - The app (M06) must send its pending operations before it links.
- **A wrong phone clock** changes nothing: token lifetimes are counted on the server. Google token
  times are checked with a small allowance for the difference between Google's clock and the
  server's.
- **One player on two phones.** Each phone has its own session. Reuse detection or a switch on one
  doesn't end the other's.
- **An access token after its session ended** (by reuse detection or a switch) may keep working
  until its 15 minutes run out. That is the access lifetime the constitution sets. Deletion is the
  exception: it takes effect at once (FR-014).
- **The same install id with a different platform** (not expected to happen): it is still the same
  device, and its platform is updated.
- **One install id on two phones.** Where the platform carries the kept install id to a new phone
  (FR-008) while the old one is still in use, both phones lead to the same player and share one
  device record. Each gets its own session, neither signs the other out (FR-010), and B03's
  stale-state path (`GET /v1/state`) keeps them in step.
- **Staff and player credentials never mix.** A player token doesn't open the admin, and a staff
  sign-in doesn't call the player API (FR-016).
- **No signing key.** Outside dev and test, a missing, empty or placeholder signing key stops the
  process at startup, like every B01 secret (`specs/002-b01-backend-skeleton/contracts/environment.md`).
- **The cache is down.** The limits fail open, as in B01 (research R4). Whatever the retry window
  needs must not let a spent refresh token be used twice to fork a session, cache or not; the plan
  decides where it lives. The database down is `dependency_unavailable` (B01).
- **Mass account creation** from many addresses: B02 grants no currency, so an empty account is worth
  nothing. B03's starting balances are bounded, and later features flag abuse.
- **A player who never synced can still link.** The summary then shows the server's starting values,
  so the app (M06, M14) sends pending operations first, and the player compares real numbers.
- **An abandoned player** (left behind by `switch_to_existing`, or by a lost install id) stays as it
  is. Nothing signs in to it any more. Its cleanup belongs to the data inventory (B09).

## Requirements *(mandatory)*

### Functional Requirements

#### Anonymous accounts

- **FR-001**: `POST /v1/auth/anonymous` MUST take an `install_id`, a `platform` (`android` |
  `ios`) and a `locale`, and answer with the `player_id`, an access token, a refresh token and
  `created` (backend §6.4): 201 when a player was created, 200 when an existing one was returned. It
  needs no player token.
- **FR-002**: The install id MUST be a random UUID that the app generates on its first open (mobile
  §16). The server MUST store it only as a one-way hash, and MUST never log it, return it or show it
  in the admin.
- **FR-003**: An install id MUST lead to at most one player at a time, also when several requests
  with it arrive at once.
- **FR-004**: A player who is pending deletion or deleted MUST never be returned. Their install id
  then gets a new player, and the old player is left unchanged.
- **FR-005**: The install id MUST return the active player its device belongs to, whether or not
  that player has linked Google. Only a switch (FR-026), which moves the device to another player, or
  the player's deletion (FR-004) changes where it leads. This replaces §6.4's "while it is not linked
  to a provider" (Clarifications 2026-10-24). A lapsed session therefore comes back without a prompt,
  and linking adds a way back on other phones, not extra protection on this one.
- **FR-006**: A new player MUST start active, with the request's platform and locale, the country
  taken from the locale's region when it has one (no lookup of the network address), the first
  driver level, the tester flag off, and no display name. The player names their driver in M07, and
  B03's `settings_update` op stores it. B02 MUST grant no currency and create no wallet: B03 creates
  the starting state.
- **FR-007**: The server MUST keep one device record per install id: its player, platform, app
  version and when it was last seen. A player may have several devices.
- **FR-008**: A re-install on the same phone MUST bring the same player back without linking, by
  keeping the install id where a re-install doesn't wipe it (backend §22.6, Clarifications
  2026-10-24). This is the app's part (M06): the server needs nothing more than FR-005, and the app
  database stays out of device backup (M05). Where a platform can't keep the id, which M06's research
  checks, the re-install gets a new player, and linking Google is the way back.

#### Tokens and sessions

- **FR-009**: An access token MUST last 15 minutes and a refresh token 30 days from when it was
  issued. `POST /v1/auth/refresh` MUST spend the refresh token it receives and return a new pair, so
  each renewal starts a new 30 days (constitution, "Security & privacy").
- **FR-010**: A session MUST be the chain of refresh tokens that starts with one sign-in on one device
  (account creation, an install-id return, or a switch) and continues through every renewal.
  Sessions are independent: a new sign-in doesn't end the device's earlier sessions, which lapse
  30 days after their last renewal. A player MUST have at most a fixed number of active sessions (a
  server setting; the plan picks the default, around 10). A sign-in beyond it ends the player's
  least recently renewed session.
- **FR-011**: A refresh token presented again within a short retry window after it was spent MUST
  get the same successor refresh token and a working access token, without starting a second chain.
  The window is a server setting, measured in seconds; the plan picks its default. It covers lost
  answers and two renewals racing.
- **FR-012**: A spent refresh token presented after the retry window MUST be refused with
  `token_invalid`, and MUST end its whole session. The reuse MUST be recorded as a security event
  that names the player and the session, and nothing personal.
- **FR-013**: Refusals MUST tell the app what to do next: `token_expired` (401) for a token past its
  lifetime, so the app renews or comes back through its install id; `token_invalid` (401) for an
  altered, unknown, wrong-kind or ended token; `account_deleted` (403) for a player pending deletion
  or deleted.
- **FR-014**: Every request with a player token MUST check the player's status, so a player who is
  pending deletion or deleted is refused from their next request on, not when their access token
  expires.
- **FR-015**: Tokens MUST carry no personal data: only the player, the token's kind, its session, the
  signing key's id and its times.
- **FR-016**: Player tokens and staff accounts MUST stay apart. A player token MUST never open the
  admin or carry a staff permission, and a staff sign-in MUST never authenticate a player API call.
- **FR-017**: The signing key MUST come from the environment's secrets, separate from the framework's
  own secret key, and carry an id. The operator MUST be able to rotate it without signing anyone out:
  the new key signs from then on, and earlier keys still verify until the operator retires them, at
  the earliest one refresh lifetime (30 days) after they stopped signing. Outside dev and test, a
  missing or placeholder key MUST stop the process at startup.
- **FR-018**: Issuing or renewing tokens MUST update the player's and the device's last-seen time and
  app version (from `X-Client-Version`). A request that only uses an access token MUST NOT write
  them, so normal traffic adds no writes.
- **FR-019**: From B02 on, every player endpoint MUST require a player token unless the API contract
  says otherwise. The exceptions are the health checks, the store and ad callbacks, account creation,
  renewal and the content manifest (FR-034).

#### Linking Google

- **FR-020**: `POST /v1/auth/link` MUST take a `provider`, the provider's `id_token` and an optional
  `resolve` (`switch_to_existing` | `keep_current`), and MUST need a player token (backend §6.4).
- **FR-021**: In the MVP, `provider` MUST accept only `google`. Sign in with Apple is phase 3
  (`docs/delivery-plan.md` "After the MVP"), when iOS launches publicly, and needs a paid Apple
  Developer account. Until then, `apple` is refused with `validation_error`. The contract MUST leave
  room for it, so adding it later doesn't break an app built today.
- **FR-022**: A Google ID token MUST be verified before anything changes: its signature against
  Google's published keys, its issuer, its audience (the game's own client ids for that environment),
  its expiry and its issue time, with a small allowance for clock difference. Google's keys MAY be
  held for as long as Google says they stay valid.
- **FR-023**: From a verified token, the server MUST keep only Google's account number (the subject).
  It MUST NOT store or log the token, the email address, the name or the picture (constitution:
  no email, phone number or real name).
- **FR-024**: A player MUST have at most one linked account per provider, and a provider account MUST
  belong to at most one active player. Linking the account a player already has MUST change nothing.
  Linking a different account of a provider the player already has MUST be refused (User Story 3).
- **FR-025**: When the provider account belongs to another active player and `resolve` is absent, the
  server MUST answer 409 `provider_in_use` with a summary of the current and the existing player,
  holding at least the driver level, the chapter and the BONAT balance (backend §6.4). The summary
  shows what the server holds at that moment. Until B03, the values it doesn't hold yet are the
  starting ones. The summaries MUST hold nothing personal.
- **FR-026**: `switch_to_existing` MUST end this device's session as the current player, move this
  device to the existing player, and answer with a new token pair for the existing player. The
  current player's data, other devices and other sessions MUST stay as they were.
- **FR-027**: `keep_current` MUST move the provider account to the current player and answer with
  the current player's providers. The existing player MUST keep all its data, devices and sessions,
  and lose only that provider account.
- **FR-028**: Linking and resolving MUST never merge players or move a balance, ledger entry,
  purchase, entitlement, progress or ownership between them. They change only links, devices and
  sessions.
- **FR-029**: A retry with `resolve` MUST act only on the conflict the player was shown. If the
  provider account has since moved to another player, or the existing player is no longer active, the
  server MUST answer a new 409 with fresh summaries, or link when there is no conflict any more.
- **FR-030**: A provider account whose player is pending deletion or deleted MUST count as free.
- **FR-031**: Each link or resolve MUST apply completely or not at all.

#### Limits and request headers

- **FR-032**: Requests with a player token MUST be limited per player, never per network address,
  because carrier-grade NAT puts many Egyptian mobile players behind one address (B01 research R4).
  The default is backend §6.5's 120 per minute per player. Renewal MUST be limited per session or per
  player too, not per address.
- **FR-033**: Account creation MUST be limited per network address. Backend §6.5's 10 per hour per
  address is the starting point, but the plan sets the number with carrier-grade NAT in mind and
  records why. A refusal never blocks play: the account is created in the background, and the app
  tries again later (constitution V).
- **FR-034**: The auth endpoints, and every endpoint that needs a player token, MUST require
  `X-Platform` (`android` | `ios`) and `X-Client-Version` (`MAJOR.MINOR.PATCH[+BUILD]`) (backend
  §6.1), and refuse a missing or malformed one with `validation_error`. Refusing old app versions
  (`426 client_outdated`) is B10's.

#### The content manifest

- **FR-035**: The content manifest MUST stay readable without a player token, as B04 left it
  (FR-033 there). The pack files it points to are public on the edge anyway, and content updates
  must not wait for an account to exist (constitution V). Backend §6.3 changes the manifest's auth to
  "none".

#### Admin

- **FR-036**: The admin MUST offer staff with a player permission a read-only player view, searchable
  by `player_id`: status, platform, locale, app version, created and last-seen times, the names of
  linked providers, and devices (platform, app version, last seen). The tester flag is the only
  editable field. Tokens, install ids and provider account numbers MUST NOT be shown.

#### Privacy and logging

- **FR-037**: Logs, error reports and security events MUST NOT contain tokens, install ids, provider
  account numbers or anything from a provider's token. Players appear in them only by `player_id`.
- **FR-038**: The data inventory (backend §14.2) MUST stay true: B02 stores the player id, the
  install id's hash and the Google account number, and nothing else that identifies a person.

#### Contract, docs and tests

- **FR-039**: The three endpoints, with every answer and error they can give, MUST be in the
  committed `contracts/openapi.yaml`, and the contract tests MUST cover them.
- **FR-040**: Every new error code MUST be added to backend §6.2 before it ships (B01's rule). B02
  adds at least a code for a provider token that fails verification, and one for linking a second
  account of a provider the player already has.
- **FR-041**: The PR MUST update the architecture docs: backend §6.2, §6.3 (the manifest's auth),
  §6.4 (the install id leads to its device's player, linked or not), §6.5 (the limits the plan
  sets), and §12 "accounts" and §13 if the design changes them; §22.6 as resolved; and mobile §16
  (the install id kept across a re-install).
- **FR-042**: Tests MUST be written first for token issuing, renewal, reuse detection and Google
  token verification (constitution XIII). They MUST include:
  - property tests over random sequences of creation, renewal, linking and resolving, which check that
    an install id leads to at most one player, a provider account belongs to at most one active
    player, a repeated request gives the same outcome, and nothing but links, devices and sessions
    ever changes;
  - Google tokens signed by a test key, both valid and tampered (wrong signature, audience, issuer,
    expiry);
  - real PostgreSQL and Valkey, not mocks.
- **FR-043**: The change MUST get a security review before merge, since it changes auth
  (constitution, "Review").

### Key Entities *(include if feature involves data)*

- **Player**: one game account. Status (active, pending deletion, deleted), platform, locale,
  country, driver level, display name (empty until B03 stores one), tester flag, first install and
  last-seen times, app version. Owns the other entities. B03 attaches the wallet and progress to it.
- **Identity**: a provider account that signs in to a player: Google's account number in the MVP.
  One per provider per player; one active player per provider account. Room is left for Apple
  (phase 3), which also needs Apple's revocation token for B09.
- **Device**: one installation of the app: its player, the install id's hash, platform, app version
  and last-seen time. The install id is the anonymous way in, so the device record is the
  anonymous identity (plan research R4).
- **Session**: the chain of refresh tokens from one sign-in on one device. It is active, lapsed
  (30 days without renewal) or ended (renewal reuse, a switch, deletion, or the per-player limit).
  It remembers its last spent token and successor for the retry window, and when it was last renewed.
- **Signing key**: a key with an id that signs or verifies tokens. It is current, still verifying, or
  retired.
- **Conflict summary** (not stored): what the player sees to choose between two players: driver level,
  chapter, BONAT balance.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every first online launch that reaches the server gets an account from one request. In
  a test where 1,000 install ids each send 10 requests at once, exactly 1,000 players exist
  afterwards.
- **SC-002**: Over 30 simulated days, with a renewal every 15 minutes and one answer in five lost and
  retried, no session ends and no player has to get back in another way.
- **SC-003**: A copied refresh token used after the retry window ends its session at its first use
  in every test case, while the same player's other sessions keep working.
- **SC-004**: Rotating the signing key signs out no player.
- **SC-005**: No request is accepted from a player after their account becomes pending deletion.
- **SC-006**: Across 10,000 random sequences of creation, renewal, linking and resolving, no provider
  account ever belongs to two active players, no install id leads to two players, and no player data
  other than links, devices and sessions changes.
- **SC-007**: After a test run that links 100 players, a scan of the database, the logs and the error
  reports finds no email address, name, picture, install id or token.
- **SC-008**: 1,000 players sharing one network address keep their sessions through an hour of normal
  play with no refusal caused by sharing it.
- **SC-009**: On staging, 95% of account creations and renewals are answered within 150 ms, and 95%
  of links within 1 s once Google's keys are held.
- **SC-010**: The contract tests exercise every documented answer of the three endpoints, and the
  committed contract matches the code.

## Assumptions

- **Dependencies.** B01 is merged: the stack, the error envelope, the address throttle, request ids,
  the staff accounts and the startup checks on secrets. B04 is merged, with its public manifest.
- **What follows.**
  - B03 (spec 010) creates each player's wallet and starting state, fills the conflict summaries'
    wallet and progress values, and puts bootstrap, state and sync behind player tokens.
  - M06 (spec 011) generates the install id, creates the account in the background on the first
    online launch, keeps the tokens in secure storage (constitution), renews them, comes back through
    the install id, and sends pending operations before it links.
  - M14 builds «اربط حسابك» in Settings and the screen where the player compares the two summaries
    and chooses (`docs/design/HANDOFF.md` §11 `Settings`; the `/settings/account` route has no
    artboard).
- **Apple.** Sign in with Apple waits for phase 3, with the public iOS launch and Apple purchases
  (`docs/delivery-plan.md` "After the MVP"). The project has no paid Apple Developer account yet
  (`docs/runbooks/ios-test-build.md`), and iOS test builds stay anonymous until then. The App Store
  asks for it next to Google sign-in when iOS ships publicly.
- **Owner actions.** Google sign-in needs the game's OAuth clients in Google Cloud for each
  environment: an Android client per flavor (its package name and signing certificate fingerprint)
  and the server client id that tokens are issued for. Staging and production each need their signing
  key in the host's env file. The plan lists the steps, and `/speckit-implement` adds them to
  `docs/owner-actions.md`.
- **Out of scope.** Unlinking a provider and signing out (the ux-spec has neither); account deletion
  and the support code (B09); push tokens (B11); refusing old app versions and maintenance mode (B10);
  device attestation (phase 3, backend §22.7); Sign in with Apple (phase 3); cleaning up abandoned
  players (B09's data inventory).
- **Display names.** The display name and its profanity filter belong to B03's `settings_update` op.
- **Country.** It comes from the locale's region. The network address is never looked up.
