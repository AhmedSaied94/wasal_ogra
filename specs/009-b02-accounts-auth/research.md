# Research: Accounts and Auth (B02)

Phase 0 of [plan.md](./plan.md). Each section records a decision, why it was made, and what was
rejected. The spec's three clarifications (2026-10-24) are inputs here, not open questions:

- the install id survives a re-install on the same phone (FR-008);
- it leads to its device's player, linked or not (FR-005);
- sessions stay alive until they lapse, with a cap per player (FR-010).

Backend §22.6 is resolved in R5. Nothing in the Technical Context is left as NEEDS CLARIFICATION.

## R1 How a `Player` authenticates (B01 hand-over, research R3)

- **Decision:**
  - `apps.accounts.Player` is a model of its own. It is not `AUTH_USER_MODEL`, which stays B01's
    staff `User`.
  - Player tokens use **simplejwt** (`djangorestframework-simplejwt`, locked by the constitution)
    for what it does well:
    - its `Token` classes (claims, lifetimes, `jti`, type checks);
    - its `TokenBackend` over PyJWT;
    - its `JWTAuthentication` request flow.
  - Three subclasses adapt it:
    - `KeyRingBackend` (a `TokenBackend`) writes a `kid` header and verifies with the key that
      `kid` names (R13);
    - `PlayerAccessToken` and `PlayerRefreshToken` use that backend and carry the session id
      (R2);
    - `PlayerAuthentication` (a `JWTAuthentication`) turns a valid access token into the
      `Player`, checks the player's status, and sets `request.user` to the player and
      `request.auth` to the token.
  - It becomes `DEFAULT_AUTHENTICATION_CLASSES`. B01 left that list empty, with
    `IsAuthenticated` as the default permission, so every view that needs no token already
    opts out explicitly (health, manifest), and every new view needs a player token (FR-019).
  - `Player.is_authenticated` is a constant `True` property, which is all DRF's
    `IsAuthenticated` reads.
- **Sessions and spent tokens live in our own table, `PlayerSession`** (R3), not in simplejwt's
  `token_blacklist` app:
  - The blacklist app keys its rows on `AUTH_USER_MODEL`, which is the staff user here.
  - It doesn't model a chain of tokens, so it can't end "everything renewed from this sign-in"
    (FR-012).
  - It can't answer a repeated renewal with the same successor (FR-011).
  - It can't count a player's live sessions (FR-010).

  The session table blacklists on use as constitution 1.5.0 words it:
  - a spent refresh token never yields a new successor;
  - within the retry window it gets back the same successor it was already given;
  - after the window, it is refused and ends the chain.

  The `token_blacklist` app is not installed. Backend §12's line "Refresh-token rotation and blacklist
  use simplejwt's token blacklist tables" changes to the session table (FR-041).
- **Staff stay apart (FR-016).** The API urlconf has no session or basic authentication, so a staff
  login never authenticates `/v1`. The admin urlconf routes no `/v1`, and the admin uses Django
  sessions with OTP, which a player token can't produce. `PlayerAuthentication` resolves only
  `Player` rows. No token type exists for staff.
- **Alternatives rejected:**
  - Making `Player` the `AUTH_USER_MODEL`, or extending `User`: it mixes staff and players in one
    table, with permissions, passwords and admin access a player must never have.
  - Opaque random refresh tokens: they would work as well, but §6.4 and the glossary say
    `<jwt>`, and a signed token lets the server refuse garbage before it touches the database.
  - Writing JWT handling by hand on PyJWT: the constitution locks simplejwt.
  - Firebase Auth: backend §23 already rejected it.

## R2 Tokens

- **Decision:**
  - **HS256** with a 256-bit key from the key ring (R13). Only this service signs and verifies its
    tokens, so an asymmetric key buys nothing.
  - **Lifetimes, fixed by the constitution:** access 15 min, refresh 30 days from issue. They are
    named constants with the constitution as their source, not settings.
  - **Claims, both kinds:** `token_type` (`access` | `refresh`), `sub` (the `player_id`), `sid`
    (the session id), `jti` (a UUIDv7), `iat`, `exp`. The header carries `kid`.
  - Nothing personal goes in a token (FR-015). The `kid` and `sid` are opaque.
  - **Verification:** signature by `kid`, `exp` with 0 s leeway (the server signs and checks with
    its own clock), and `token_type`. A refresh token used as an access token, or the reverse, is
    `token_invalid`.
  - **Access tokens are stateless**, apart from the player status check (R11). An ended session's
    access token can live out its 15 minutes, which the spec accepts (Edge Cases). Deletion takes
    effect at once through the status check (FR-014).
  - The response also carries `access_expires_in` (seconds), so the app needn't decode the token,
    and `providers`, so the app knows after a sign-in whether Google is linked (contracts/api.md).
- **Alternatives rejected:**
  - RS256 or EdDSA: they only add key-pair handling.
  - A leeway on our own tokens: it would only stretch the constitution's lifetimes.

## R3 Sessions: rotation, the retry window, reuse, the cap

- **Decision:** one `PlayerSession` row per sign-in (creation, an install-id return, a switch).
  - The row stores the claims of the **current** refresh token (`jti`, `iat`, `exp`, `kid`) and of
    the **previous** one (`jti`, and when it was spent). It never stores a token.
  - **Renewal** (`POST /v1/auth/refresh`) runs in one transaction, holding a
    `SELECT … FOR UPDATE` lock on the session row:
    1. Verify the token (R2). A bad signature or type gives `token_invalid`, an expired one
       `token_expired`.
    2. Load and lock the session named by `sid`. If it is missing or ended, `token_invalid`.
    3. If its player isn't active, `account_deleted`.
    4. **Current token:** rotate. The new `jti`, `iat` and `exp` (now + 30 days) become current,
       the old `jti` becomes previous, and `last_renewed_at` is now. Answer with the new pair.
    5. **Previous token, spent no longer than `AUTH_REFRESH_RETRY_SECONDS` ago:** a replay.
       Re-sign the current claims, which gives a byte-identical refresh token (HS256 is
       deterministic, and one function always builds the claims in the same order), plus a new
       access token. Nothing changes in the row.
    6. **Anything else** (an older token, or the previous one after the window): reuse. End the
       session with reason `reuse`, write the security event (R14), and answer `token_invalid`.
  - **Two renewals racing** with the same token: the second waits for the lock, then finds that
    token as previous and inside the window, so step 5 applies. Both get the same successor.
  - **The retry window:** default **60 s**, a setting from 0 to 300 s.
    - It covers a lost answer retried with the app's backoff, and two parts of the app racing.
    - A longer window only delays detection. Someone who stole the token gets the same successor
      as the owner, and the next renewal by either one makes the other's a reuse.
    - A retry later than the window costs little: the session ends, and the app gets back in with
      its install id (FR-005).
  - **Lapse:** a session whose current token has expired is lapsed. It is not stored as a status:
    `current_expires_at < now` says it, so nothing needs a sweep to be correct.
  - **The cap (FR-010):** `AUTH_MAX_SESSIONS_PER_PLAYER`, default **10**, from 1 to 50.
    - Opening a session locks the player row (`SELECT … FOR UPDATE`) and counts its live sessions
      (active and not lapsed). When the count reaches the cap, the least recently renewed one ends
      with reason `limit`.
    - Ten covers a player's phones plus the sessions a few lost-token returns leave behind. The
      ended session's phone gets back in through its install id.
  - **Everything is in PostgreSQL**, so a cache outage can't let a spent token fork a session
    (spec Edge Cases).
  - **Pruning:** a daily beat task, `accounts.tasks.prune_sessions` on the `default` queue, deletes
    sessions that ended or lapsed more than 30 days ago. After that, their tokens can't verify
    anyway, because the keys that signed them may have been retired (R13).
- **Alternatives rejected:**
  - Returning a *new* successor on a replay: it would fork the chain into two valid branches.
  - Storing the successor token so a replay can return it: it would keep a bearer secret at rest.
  - The window in Valkey: a cache restart would turn replays into reuse, or worse.
  - One session per device: rejected by the owner in Clarifications. Two phones sharing a restored
    install id would sign each other out.

## R4 Install ids and devices

- **Decision:**
  - **Format:** a version-4 UUID, written in the canonical lowercase form. Anything else, a v7
    included, is `validation_error`.
    - v4 has 122 random bits.
    - A v7 spends 48 bits on a timestamp, which weakens a long-lived credential (R5, FR-005).
  - **Stored as `sha256(canonical form)`**, as 64 hex characters, unique.
    - With 122 random bits, a plain hash can't be reversed by guessing.
    - A keyed hash would make every device record depend on one more secret that can never
      rotate.
  - The raw id is never logged, returned or shown (FR-002).
  - **The anonymous identity is the device record.** `Device(install_id_hash unique, player)`
    replaces backend §12's `Identity(provider="anonymous")`.
    - FR-005 makes the install id lead to its *device's* player, and a switch *moves* the device
      (FR-026), so a second row holding the same hash could only drift from it.
    - `Identity` keeps the providers: `google` now, `apple` in phase 3.
    - "Linked" means the player has at least one `Identity`.
    - §12 changes accordingly (FR-041).
  - **Account creation** (`POST /v1/auth/anonymous`), in one transaction:
    - **No device with that hash:** create the player and the device inside a savepoint. If a
      concurrent request inserted the same hash first, the unique index refuses the insert, the
      savepoint rolls back (the player with it), and the code reads the winner's device. This
      gives exactly one player per install id under any race (FR-003, SC-001).
    - **The device exists and its player is active:** answer 200 with that player and a new
      session (FR-005). The device's platform and app version are updated, even if the platform
      differs (spec Edge Cases).
    - **The device exists but its player is pending deletion or deleted:** create a new player and
      move the device to it (FR-004). The old player is otherwise untouched.
- **Alternatives rejected:**
  - Keeping a separate anonymous `Identity`: two records for one fact.
  - An advisory lock on the hash: the unique index already settles the race.

## R5 A re-install without linking (resolves backend §22.6)

- **Decision (owner, Clarifications 2026-10-24):** the same phone gets the same player back
  without linking.
  - **The server already does its part:** the install id is a device credential (R4, FR-005).
  - **The app keeps the install id where a re-install doesn't wipe it.** That is M06's work, and
    its research picks the mechanism per platform:
    - **iOS:** the keychain, which keeps items after the app is deleted, with an access setting
      that keeps them on this device only.
    - **Android:** Google Play services' Block Store, which keeps a small value across a
      re-install and can carry it to a new phone restored from backup. The fallback is Android's
      backup of that one value. The app database stays out of backup, as M05 decided.
    - **Where neither works:** the re-install gets a new player, and linking Google is the way
      back. This includes a factory reset with no backup, and a device without Play services.
  - **Two phones with one install id** (a backup restored to a new phone while the old one is
    still in use) lead to the same player. Each gets its own session (R3), and B03's stale-state
    path keeps them in step (spec Edge Cases).
- **Alternatives rejected:**
  - Accepting a new player on every re-install (backend §22.6's proposal): a player who bought
    BONAT and re-installs without linking would lose them.
  - A hardware identifier (Android ID): it is a device identifier for the Data safety form, and it
    changes on a factory reset anyway.

## R6 Verifying Google ID tokens

- **Decision:**
  - **PyJWT's `PyJWKClient`** (PyJWT[crypto], which simplejwt already needs) reads Google's key set
    at `https://www.googleapis.com/oauth2/v3/certs`, through a small `GoogleKeys` service.
    - The keys stay cached in each process for `GOOGLE_KEYS_CACHE_SECONDS` (default 3600).
    - An unknown `kid` refreshes the set once, so Google's key rotation is picked up straight
      away.
    - *As built (security review):* every way of not getting usable keys (unreachable, not JSON,
      not a key set, no signing key) is `503 dependency_unavailable`, never a 500 or a reason
      blamed on the token. PyJWKClient fetches under a lock, so after a failed fetch the process
      answers 503 at once for 15 s instead of making each waiting link sit out the timeout. Keys
      already cached keep serving. `GOOGLE_KEYS_CACHE_SECONDS` is at least 60 outside dev and test.
    - *As built:* at most once per 30 s per process (`REFRESH_COOLDOWN_SECONDS`, PyJWKClient's
      cooldown). Tokens naming made-up `kid`s would otherwise make every request fetch from
      Google. Google publishes a key well before signing with it, so the cooldown never delays a
      real rotation.
    - Fetches time out after `AUTH_HTTP_TIMEOUT_SECONDS` (default 5).
    - Google publishes each key well before it signs with it and keeps it for days, so an hour's
      cache is inside what Google says stays valid (FR-022).
  - **Checks**, all before anything changes:
    - `alg` must be `RS256`, and the signature is checked with the key the `kid` names;
    - `iss` is `accounts.google.com` or `https://accounts.google.com`;
    - `aud` is one of `GOOGLE_OAUTH_CLIENT_IDS`;
    - `exp` and `iat` hold, with a 60 s leeway for the difference between Google's clock and ours;
    - `sub` is present.
  - **Which client id is the audience:** the server client id (a web client), which Credential
    Manager on Android puts in `aud` when the app asks for an ID token for it. `azp` is not
    checked: Google's guidance checks `aud`, and the live check's OAuth Playground tokens
    (quickstart) carry the web client as `azp`.
  - **A failed check** answers `422 provider_token_invalid`, with `details.reason` ∈ `expired`,
    `audience`, `issuer`, `signature`, `malformed` (R8). The token itself is never echoed or
    logged.
  - **Google's keys can't be fetched and none are cached:** `503 dependency_unavailable`, and
    nothing changes.
  - **Only `sub` is kept** (FR-023). `email`, `name` and `picture` are dropped as soon as the token
    is decoded, and never logged or stored.
  - **No nonce in the MVP.** Google issues an ID token for our server client id only to an Android
    app registered in the same Cloud project, with its package name and signing certificate. A
    stolen token would have to come from the player's own phone or from TLS. A nonce needs an
    extra round trip and an endpoint. Phase 3's device attestation is the stronger answer.
  - **Configuration:**
    - `GOOGLE_OAUTH_CLIENT_IDS` is required on staging and prod. Client ids are not secrets.
    - In dev and test it may be empty, and then `provider: google` is `validation_error`
      ("not enabled here"). Tests set a test client id.
- **Alternatives rejected:**
  - `google-auth`'s `verify_oauth2_token`: it fetches the certificates on every call unless it is
    given a caching HTTP session, which is one more dependency. B06 adds `google-auth` for the Play
    Developer API, where it is needed.
  - Google's `tokeninfo` endpoint: a network round trip per link, and Google itself advises
    against it for production.

## R7 Linking and conflicts

- **Decision:** `POST /v1/auth/link` runs in one transaction (FR-031):
  1. Verify the Google token (R6), outside the transaction: it may fetch keys.
  2. Lock the current player C (from the access token).
  3. Find G's `Identity`, locked with `SELECT … FOR UPDATE`. When there is none, the insert below
     relies on the unique index, as in R4.
  4. **Decide:**
     - G is C's: answer 200, no change (FR-024).
     - C already has a different Google account: answer `409 provider_already_linked`.
     - G has no holder, or its holder isn't active: link G to C (create the row, or move it), and
       answer 200 (FR-030, US4-7).
     - G belongs to another active player E, and there is no `resolve`: answer
       `409 provider_in_use` with both summaries and E's `player_id`.
     - There is a `resolve`: it MUST come with the `existing_player_id` from that 409. If G's
       holder is no longer that player, or is no longer active, the server answers as if
       `resolve` were absent: a new 409, or a plain link (FR-029). Players are locked in id order,
       so two crossed links can't deadlock.
       - `switch_to_existing`: end the request's session (reason `switch`), move its device to E,
         and open a new session for E on that device (cap check on E). Answer with E's
         `player_id`, providers and token pair (FR-026).
         - *As built (security review):* every live session of C's on that device ends, not only
           the request's, since the device is E's now. The device row is locked, and it moves
           only from C. A repeat of the same switch finds it already E's and answers again. A
           device that went to anyone else answers `token_invalid`, so an access token that
           outlived its session can't take the phone on to a third player.
       - `keep_current`: move the identity row to C. Answer with C's providers (FR-027).
  5. Nothing else is written (FR-028): no player field apart from those FR-018 updates on a token
     issue, no currency, no progress.
- **The conflict guard is E's `player_id`, not an opaque token.**
  - The person proved they control G, which is the account that opens E, so the id tells them
    nothing new.
  - It is not personal data.
  - A signed conflict token would need its own lifetime and key.

  This adds `existing_player_id` to §6.4's retry body (contracts/api.md).
- **The summary** comes from one function, `accounts.services.summary.summarize(player)`, so B03
  can fill it from its own tables (hand-over).
  - **Until then:** `driver_level` from `Player`, `chapter_id` `ch1_first_job` (the glossary's
    first chapter) and `bonat` 0, which are the starting values (FR-025).
  - The existing player's summary adds its `player_id` (above). Nothing else is personal.
- **Alternatives rejected:**
  - Merging players: forbidden (§6.4).
  - Resolving against whoever holds G at retry time: the player would act on a summary they never
    saw.
  - Ending E's sessions on `keep_current`: E may be in use on another phone the person still has.
    The spec keeps them.

## R8 Error codes

- **Decision:** these are added to backend §6.2 and to B01's `contracts/api.md` table (FR-040):

  | HTTP | `code` | When |
  | --- | --- | --- |
  | 409 | `provider_already_linked` | The player already has a different account of that provider |
  | 422 | `provider_token_invalid` | The provider's ID token fails verification (`details.reason`) |

- **Codes §6.2 already has:** `token_expired`, `token_invalid` (401), `account_deleted` (403), and
  `provider_in_use` (409).
- **Mapping in `apps.common.errors`:**
  - DRF's `NotAuthenticated` (no `Authorization` header) becomes `401 token_invalid`, with
    `WWW-Authenticate: Bearer`.
  - `AuthenticationFailed` raised by our code carries its own code: `token_expired`,
    `token_invalid`, or `account_deleted`, which uses status 403.
  - Without this, B01's handler would send DRF's own `not_authenticated` and
    `authentication_failed`, which §6.2 doesn't list.
- **Why 422 for a bad provider token:** a 401 would tell the app that its own session is broken,
  and send it into renewal (spec US3-4). 422 is §6.2's group for valid requests the server won't
  act on.
- *As built:* one `ApiError(APIException)` carries any of these codes, with its own status and
  `details`, in place of `AuthError(AuthenticationFailed)` and `ConflictError`. DRF turns an
  `AuthenticationFailed` into a 403 on a view with no authenticators, and the anonymous and
  refresh views have none.
- **Alternatives rejected:**
  - A separate `not_authenticated` code: the app does the same thing in both cases (renew, else
    sign in with its install id).

## R9 Rate limits (B01 hand-over, research R4)

- **Decision:** four throttle classes in `apps/common/throttles.py`, each rate a setting (DRF rate
  strings). These are server protections, not game tunables, so they are environment settings
  with no Remote Config key (constitution VIII, as in B04).

  | Class | Scope | Key | Default | Applies to |
  | --- | --- | --- | --- | --- |
  | `AddressRateThrottle` (B01) | `address` | client address | `120/min` | Unauthenticated requests only. It now skips any request with `request.auth` set. |
  | `PlayerRateThrottle` | `player` | `player_id` | `120/min` (§6.5 default) | Every request authenticated as a player. It joins `DEFAULT_THROTTLE_CLASSES`, so every later endpoint is limited per player (FR-032). |
  | `RefreshThrottle` | `refresh` | the `sid` of a refresh token whose signature verifies; otherwise the client address | `30/min` | `POST /v1/auth/refresh` |
  | `AnonymousThrottle` | `anonymous` | client address | `60/hour` | `POST /v1/auth/anonymous` |
  | `LinkThrottle` | `link` | `player_id` | `10/min` | `POST /v1/auth/link`, besides `player` |

- **Account creation at 60/hour per address, not §6.5's 10.** Egyptian carriers put many
  subscribers behind each public address (carrier-grade NAT, B01 R4).
  - **What a request costs:** a few rows. B02 grants no currency, and B03's starting balances are
    bounded.
  - **Launch-day estimate:** about 10,000 installs an hour nationwide at the 100k DAU design point.
    Spread over a few thousand carrier addresses, that is a handful per address per hour, and 60
    leaves a wide margin for one busy address.
  - **What it must cover:** returns through the install id count too, so 60 also covers phones
    whose sessions lapsed.
  - **What one address can still do:** at most 1,440 empty accounts a day.
  - §6.5 is updated with these numbers and the reasoning (FR-041).
- **Renewals are keyed by session, never by address.** 1,000 players behind one address renew in
  the same minute without one refusal (SC-008). The per-session limit of 30/min allows the retries
  and races of R3 with room to spare. A request whose token doesn't verify is limited by address,
  so garbage can't spend players' budgets.
- **Fail open on a cache outage**, as B01's throttle does.
- *As built (security review):* the address limits count an IPv6 client by its /64, the block a
  phone or home network gets and picks its addresses from. Counted per address, a client could
  take a fresh one for every request. IPv4 addresses count as they are. The admin lockout keeps
  exact addresses.
- **Alternatives rejected:**
  - Keeping §6.5's 10/hour: it risks refusing real players behind a busy carrier address.
  - Limiting creation by install id: a fresh install id per request gets around it, and the
    address limit already bounds that.

## R10 Request headers (FR-034)

- **Decision:**
  - One parser, `apps/common/client.py` (moved from `apps/content/services/manifest.py`, which
    imports it from there): `X-Client-Version` is `MAJOR.MINOR.PATCH` with an optional `+BUILD`,
    and `X-Platform` is `android` | `ios`.
  - A DRF permission, `ClientHeaders`, refuses a missing or malformed value with
    `400 validation_error`, with `details.fields` naming the header.
  - It joins `DEFAULT_PERMISSION_CLASSES` next to `IsAuthenticated`. Every player endpoint inherits
    it, and the three auth views use it directly, since they set their own permissions.
  - Health and the manifest keep `AllowAny`, so the manifest's B04 behaviour is unchanged.
  - On `POST /v1/auth/anonymous`, the body's `platform` must equal `X-Platform`.
  - Issuing or renewing tokens records both values on the player and the device (FR-018). Other
    requests write nothing.
- **Alternatives rejected:** middleware, which would also see health checks, store callbacks and
  the admin.

## R11 The player status check (FR-014)

- **Decision:** `PlayerAuthentication` loads the `Player` by primary key on every request: one
  indexed query.
  - **Active:** the request continues.
  - **Pending deletion or deleted:** `403 account_deleted`.
  - **Missing** (a hard-deleted id): `token_invalid`.

  B09 changes the status. B02 only reads it.
- **Alternatives rejected:** caching the status in Valkey. Invalidating it correctly costs more
  than the query, and B03's endpoints load the player anyway.

## R12 The admin player view (FR-036)

- **Decision:**
  - `PlayerAdmin` on B01's OTP admin site:
    - search by exact `player_id`;
    - filters by status, platform and tester;
    - every field read-only except `is_tester`;
    - read-only inlines for devices (platform, app version, last seen; no hash) and identities
      (provider, linked at; no subject);
    - a computed count of live sessions;
    - no add or delete.
  - A data migration creates the group **`player_support`** with `view_player`, `change_player`,
    `view_device` and `view_identity`.
  - Saving the tester flag writes Django's `LogEntry`, which is the admin's history (US5-2).
  - Without the group, staff don't see players at all (US5-3).
- **Alternatives rejected:**
  - Staff actions such as ending sessions: no requirement asks for one, and the install id would
    bring the phone straight back anyway (FR-005).

## R13 Signing keys and rotation (FR-017)

- **Decision:**
  - **One secret variable**, `AUTH_SIGNING_KEYS`, holds a comma-separated list of `kid:key`
    entries. The first entry signs, and every entry verifies.
  - **Startup checks** in `config/env.py`, through B01's typed reader:
    - required in every environment;
    - `kid` matches `^[a-z0-9-]{1,32}$` and is unique;
    - each key is base64url and decodes to at least 32 bytes;
    - at most 4 entries;
    - outside dev and test, no placeholder, and no key equal to `SECRET_KEY` (FR-017).
  - **Dev and test:**
    - `.env.example` holds a `change-me` dev entry;
    - test settings set a fixed test key;
    - the settings-guard tests cover each refusal.
  - **`manage.py auth_signing_key`** prints a fresh entry (`k<YYYYMMDD>:<32 random bytes,
    base64url>`). It writes no file.
  - **Rotation, in the runbook `docs/runbooks/auth-keys.md`:**
    1. Put the new entry first in `/etc/wassal/<env>.env`.
    2. Recreate the `api` container (`docker compose up -d api`).
    3. 30 days and 15 minutes later, remove the old entry and recreate it again.

    Retiring a key early signs no one out for long: its tokens become `token_invalid`, and the
    phones get back in through their install id (FR-005).
  - **A replay** (R3) re-signs with the `kid` stored on the session, as long as that key is still
    in the ring. Otherwise it signs with the current key and records it.
- **Alternatives rejected:**
  - One key, with rotation by redeploy: it signs every player out.
  - Keys in the database: it adds a staff UI and a backup risk for a step taken once or twice a
    year.
  - Deriving the key from `SECRET_KEY`: rotating either would rotate both.

## R14 Privacy, logging and security events (FR-012, FR-037, FR-038)

- **Decision:**
  - **What is never logged:** install ids, tokens (ours or Google's), provider subjects,
    `email`, `name` and `picture`.
    - B01 already scrubs bodies, headers and cookies from logs and Sentry.
    - The new code logs only `player_id`, `session_id`, `device_id` and an outcome code.
  - **The reuse event:** one `WARNING` line on the `wassal.security` logger, `event=refresh_reuse`,
    with `player_id`, `session_id` and the session's age. A warning is not an error, so it stays
    out of Sentry. B03's `PlayerFlag` does not exist yet, and a reuse is not a gameplay anomaly
    anyway.
  - **Other `wassal.security` lines (INFO):**
    - `session_limit` (a session ended by the cap);
    - `switch` and `keep_current` (who moved where, by id);
    - `link_refused` (with the reason).
  - **Data inventory (backend §14.2):** unchanged in kind. B02 stores the `player_id`, the install
    id's hash and Google's subject id, which are rows already in the table. "Install id hash" now
    lives on the device record.
  - **SC-007's scan:** a test links 100 players with tokens that carry an `email`, `name` and
    `picture`, then searches every table's text columns and the captured log output for those
    values, for the raw install ids and for the token strings. It expects no match.

## R15 Testing (FR-042, constitution XIII)

- **Decision:**
  - **Test first** for token issuing, renewal (with the replay window and reuse), the cap, Google
    verification and link resolution.
  - **Real PostgreSQL and Valkey**, as every backend test (B01).
  - **Google tokens:**
    - a session fixture makes an RSA key and signs tokens with it;
    - a local `ThreadingHTTPServer` serves the JWKS, as B04's `pack_server` does, with
      `GOOGLE_JWKS_URL` pointed at it;
    - tampered cases: a wrong key, a wrong `aud`, a wrong `iss`, expired, `alg: none`, HS256 with
      the public key as the secret, and a malformed token;
    - fetch cases: a timeout, a 500, and an unknown `kid` that triggers one refresh.
  - **Time:** `time-machine` moves both `datetime` and `time.time`, which simplejwt and PyJWT read.
    - It drives the 30-day, 2,880-renewal simulation, with one answer in five dropped and retried
      (SC-002).
    - It also covers window edges at 59, 60 and 61 s, and lapse at exactly 30 days.
  - **Property tests:** a hypothesis `RuleBasedStateMachine` over anonymous, refresh (current,
    replayed or stale), link (with each `resolve`) and status changes.
    - **Invariants:**
      - each install id has at most one device;
      - each Google subject belongs to at most one active player;
      - repeating a request gives the same outcome;
      - no player field outside FR-018's changes;
      - no player has more live sessions than the cap.
    - **Profiles:** `ci` with 300 examples, in the normal run, and `thorough` with 10,000
      (`HYPOTHESIS_PROFILE=thorough`), run once before merge for SC-006 (quickstart).
  - **Concurrency:** `TransactionTestCase` tests start 10 threads at once with one install id
    (SC-001, per install id), and two renewals of one token.
  - **CGNAT:** 1,000 players with one `X-Forwarded-For` renew within one minute, with every answer
    200 (SC-008).
  - **Contract:**
    - B01's schemathesis test covers the three endpoints;
    - an auth hook gets a real token from `/v1/auth/anonymous` on the live server, so the link
      endpoint's checks run past the 401;
    - the documented 401, 403, 409 and 422 shapes are checked too.
  - **Coverage:** at least 80% (CI gate), aiming above 90% for `apps/accounts/services`.
- **Alternatives rejected:** `freezegun`. It patches less (`time.time` only partly), and it is
  slower with Django.

## R16 Dependencies and versions

| Package | Version | Released | Why |
| --- | --- | --- | --- |
| `djangorestframework-simplejwt` | `5.5.1` | 2025-07-21 | Locked by the constitution. Its newest release; supports Django ≥ 4.2 and DRF ≥ 3.14. |
| `PyJWT[crypto]` | `2.15.1` | 2026-09-28 | simplejwt's JWT layer, and the Google token check (R6). The `crypto` extra brings `cryptography`, already locked at `50.0.2`. |
| `time-machine` (dev) | `3.5.1` | 2026-09-08 | R15. Wheels for x86-64 and aarch64, on Python 3.13. |

`google-auth` is not added (R6). Every version is older than two weeks. They are pinned in
`pyproject.toml` and locked in `uv.lock`.

## R17 Docs to update in this feature (FR-041)

- **Backend doc:**
  - §6.2: the two new codes.
  - §6.3: the manifest's auth becomes "none" (FR-035).
  - §6.4:
    - the install id leads to its device's player;
    - `existing_player_id` on a retry;
    - the token response's `access_expires_in` and `providers`.
  - §6.5: the new limits and why.
  - §12 "accounts":
    - `Device` holds the install id's hash;
    - `Identity` is for providers only;
    - `PlayerSession` replaces the blacklist tables.
  - §13: key rotation by `kid` ring.
  - §14.2: where the install id's hash lives.
  - §22.6: resolved.
- **Mobile doc:** §16, the install id kept across a re-install, and the client's part of the
  session rules (contracts/tokens.md "Client obligations").
- **Repository:**
  - `CLAUDE.md`: the B02 overview line, and the commands `auth_signing_key` and the thorough
    property run.
  - `docs/delivery-plan.md`: the B02 progress line.
  - `docs/owner-actions.md`: the B02 section.
  - `docs/runbooks/auth-keys.md`: new.
  - `docs/runbooks/README.md`: link it.
  - `.env.example`: the new variables.

## Handed to later features

- **B03 (spec 010):**
  - Fill `accounts.services.summary.summarize` from the wallet and story tables.
  - Put bootstrap, state and sync behind `PlayerAuthentication`, the default.
  - Create each player's wallet and starting state.
  - Store `display_name` through `settings_update`.
- **M06 (spec 011):**
  - Generate a v4 install id, and keep it across re-installs (R5).
  - Create the account in the background.
  - Keep tokens in `flutter_secure_storage`.
  - Renew when `access_expires_in` runs out, and retry a lost renewal within 60 s.
  - On `token_invalid` or `token_expired`, sign in again with the install id.
  - On `account_deleted`, stop and leave it to B09's flow.
  - Send pending ops before linking.
  - Handle a `player_id` that changes after a switch.
  - Add the bearer token to every call except the manifest and pack downloads, which stay
    public. The shared HTTP client's comment changes.
- **M14:**
  - «اربط حسابك».
  - The two-summary choice, which sends `existing_player_id` back with `resolve`.
  - A clear warning that the progress not chosen can't be reached again.
- **B09:**
  - Set `pending_deletion` and `deleted`, which B02 already enforces (R11).
  - Clean up devices, identities and sessions on deletion.
  - Decide what happens to abandoned anonymous players (spec Assumptions).
- **B10:** refuse old app versions (`426`) from the same parsed `X-Client-Version` (R10).
- **Phase 3:**
  - Sign in with Apple, a new `provider` value. The `Identity` row gains Apple's revocation token
    for B09.
  - Device attestation could add a nonce to linking.
