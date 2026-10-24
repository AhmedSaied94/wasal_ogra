---

description: "Task list for B02 Accounts and Auth"
---

# Tasks: Accounts and Auth (B02)

**Input**: Design documents from `specs/009-b02-accounts-auth/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Tests are required (constitution XIII). Every phase writes its tests
  first, and they must fail before its implementation tasks start. That is required by the
  constitution for token issuing, renewal, reuse detection, Google verification and link
  resolution (spec FR-042).
- **Real services.** Backend tests run against real PostgreSQL and Valkey. Google's key set is a
  local `ThreadingHTTPServer` fixture with a test RSA key, as B04's `pack_server` is, not a mock.
  Time moves with `time-machine`.
- **Coverage.** At least 80% for the backend (CI gate).

**Organization**:

- **Paths** are from the repository root. Run `uv` commands in `backend/`.
- **One PR** (plan "Delivery"). Phases 3–7 follow the spec's user stories in priority order.
- **Owner tasks** need the owner's accounts or hosts. An agent can't do them alone.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US5 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Dependencies, settings placeholders and test profiles (plan "Technical Context",
research R15, R16).

- [X] T001 Add the dependencies to `backend/pyproject.toml` and lock them (research R16):
  - `[project] dependencies`: `"djangorestframework-simplejwt==5.5.1"` and
    `"PyJWT[crypto]==2.15.1"`;
  - `[dependency-groups] dev`: `"time-machine==3.5.1"`;
  - run `uv lock` and `uv sync`, and commit `backend/uv.lock`. `cryptography` stays at its locked
    `50.0.2`.
- [X] T002 [P] Add B02's variables to `backend/.env.example`, under a comment block that points at
  `specs/009-b02-accounts-auth/contracts/environment.md`:
  - `AUTH_SIGNING_KEYS=dev1:change-me-dev-signing-key-0000000000000000000000000`
  - `AUTH_REFRESH_RETRY_SECONDS=60`, `AUTH_MAX_SESSIONS_PER_PLAYER=10`,
    `AUTH_HTTP_TIMEOUT_SECONDS=5`
  - `GOOGLE_OAUTH_CLIENT_IDS=` (empty: Google linking off in dev until the owner adds the dev
    client id), `GOOGLE_KEYS_CACHE_SECONDS=3600`
  - `THROTTLE_PLAYER_RATE=120/min`, `THROTTLE_ANONYMOUS_RATE=60/hour`,
    `THROTTLE_REFRESH_RATE=30/min`, `THROTTLE_LINK_RATE=10/min`
- [X] T003 [P] Register the hypothesis profiles in `backend/conftest.py`:
  - `ci`: `max_examples=300`, `deadline=None`, `suppress_health_check=[HealthCheck.too_slow]`;
  - `thorough`: `max_examples=10_000`, the same otherwise;
  - load `os.environ.get("HYPOTHESIS_PROFILE", "ci")` (research R15).
  - Extend the `no_throttle` fixture to also set `THROTTLE_PLAYER_RATE`,
    `THROTTLE_ANONYMOUS_RATE`, `THROTTLE_REFRESH_RATE` and `THROTTLE_LINK_RATE` to `None`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: What every story needs:

- the settings and their startup checks;
- the shared header parser and permission;
- the error codes;
- the throttles every endpoint inherits;
- the four models;
- the token classes and the key ring;
- player authentication;
- opening a session.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests (write first, they must fail)

- [X] T004 [P] Extend `backend/tests/test_settings_guards.py` and `backend/tests/test_env.py` for
  `AUTH_SIGNING_KEYS` (contracts/environment.md, research R13). Each case runs in the existing
  subprocess pattern:
  - **Refused, naming the variable but never the value:**
    - missing in `staging` and `prod`;
    - a `change-me` key outside dev and test;
    - a key that base64url-decodes to fewer than 32 bytes;
    - a `kid` that doesn't match `^[a-z0-9-]{1,32}$`;
    - a duplicate `kid`;
    - 0 or 5 entries;
    - a key equal to `SECRET_KEY` outside dev and test.
  - **Accepted:** dev's `change-me` entry.
  - **Range checks:** `AUTH_REFRESH_RETRY_SECONDS` 0–300, `AUTH_MAX_SESSIONS_PER_PLAYER` 1–50,
    `AUTH_HTTP_TIMEOUT_SECONDS` 1–15 and `GOOGLE_KEYS_CACHE_SECONDS` 0–21600 refuse values
    outside them.
  - **Google settings:**
    - `GOOGLE_OAUTH_CLIENT_IDS` is required on staging and prod, and may be empty in dev and test;
    - `GOOGLE_JWKS_URL` must be `https://` outside dev and test.
  - **Rate strings:** each `THROTTLE_*_RATE` is checked with B01's `RATE_PATTERN`.
- [X] T005 [P] Write `backend/apps/common/tests/test_client.py` (research R10, FR-034):
  - **The parser:**
    - accepts `1.0.0`, `1.0.0+2` and `10.20.30+57`;
    - refuses ``, `1.0`, `1.0.0-beta`, `v1.0.0` and `1.0.0+`;
    - `X-Platform` accepts `android` and `ios`, and refuses `Android` and `web`.
  - **The `ClientHeaders` permission,** on a test view: a missing or malformed header gives
    `400 validation_error` with `details.fields["X-Client-Version"]` or `["X-Platform"]`.
  - **The manifest** still answers `200` with neither header (B04 unchanged).
- [X] T006 [P] Extend `backend/apps/common/tests/test_errors.py` (research R8, contracts/api.md
  "Error codes"):
  - DRF `NotAuthenticated` gives `401` with code `token_invalid`, message `Token invalid`, and
    `WWW-Authenticate: Bearer`.
  - The auth exceptions give `401 token_expired` (`Token expired`), `401 token_invalid`, and
    `403 account_deleted` (`Account deleted`).
  - `409 provider_in_use` (`Provider linked to another player`),
    `409 provider_already_linked` (`Another account of this provider is already linked`) and
    `422 provider_token_invalid` (`Provider token could not be verified`) render with their
    `details`.
  - No answer ever carries `not_authenticated` or `authentication_failed`.
- [X] T007 [P] Write `backend/apps/accounts/tests/test_models_players.py` (data-model.md):
  - **The `Device` unique:** a second `Device` with the same `install_id_hash` raises
    `IntegrityError`.
  - **`Identity` uniques:** a second row with the same `(provider, subject)` raises, and so does
    a second `google` row for one player.
  - **Defaults:**
    - `Player`: `status="active"`, `driver_level=1`, `is_tester=False`, `display_name=""`;
    - `PlayerSession`: `status="active"`, `end_reason=""`.
  - **`Player.is_authenticated`** is `True` and is not a column.
  - **The UUIDv7 check:** `call_command("check")` passes `common.E001` for all four models.
- [X] T008 [P] Write `backend/apps/accounts/tests/test_tokens.py` (research R2, R13,
  contracts/tokens.md):
  - **Minted tokens:**
    - access tokens carry `token_type="access"`, `sub`, `sid`, `jti` (a UUIDv7), `iat` and
      `exp` = `iat` + 900 s;
    - refresh tokens carry `token_type="refresh"` and `exp` = `iat` + 30 days;
    - the header is `{"alg": "HS256", "kid": <first ring kid>, "typ": "JWT"}`.
  - **Verification by key:**
    - a token signed by the second ring entry verifies;
    - an unknown `kid`, a missing `kid`, `alg: none`, or a token re-signed with another key is
      invalid.
  - **Expiry:** expired by one second means expired, with no leeway.
  - **Deterministic re-signing:** the same claims and `kid` give byte-identical refresh tokens.
  - **No personal data:** no claim beyond the six listed.
- [X] T009 [P] Write `backend/apps/accounts/tests/test_authentication.py`, on a test-only view
  routed through a test urlconf (FR-013, FR-014, FR-016):
  - **A valid access token:** `request.user` is the `Player`, and `request.auth` is the token.
  - **Expired:** `401 token_expired`.
  - **A refresh token used as access, or an altered token:** `401 token_invalid`.
  - **No header:** `401 token_invalid`.
  - **Player status:**
    - a `pending_deletion` or `deleted` player gives `403 account_deleted` on the very next
      request with an access token issued a minute earlier;
    - a missing player row gives `token_invalid`.
  - **Writes:** a request that only uses an access token writes nothing to `Player` or `Device`
    (FR-018). Assert with `django_assert_num_queries` that there is exactly one query, the player
    lookup.
  - **Staff stay apart:** a staff `User` logged in with Django's test client session gets `401` on
    the view, and a player token gets no admin page (`/admin/` redirects to login).
- [X] T010 [P] Extend `backend/apps/common/tests/test_throttles.py` (research R9, FR-032):
  - **`AddressRateThrottle`** skips a request whose `request.auth` is set. Unauthenticated
    requests are still counted.
  - **`PlayerRateThrottle`:**
    - it is keyed by `player_id`, so two players behind one `X-Forwarded-For` have separate
      budgets;
    - the 121st request in a minute for one player gives `429`.
  - **Both fail open** when the cache raises `RedisError`.
- [X] T011 [P] Write `backend/apps/accounts/tests/test_sessions_open.py` (research R3,
  data-model.md "PlayerSession"):
  - `open_session(player, device)` creates an `active` row whose `current_*` fields match the
    refresh token it returns, with `last_renewed_at` = now and no `previous_jti`;
  - it also updates `last_seen_at`, `client_version` and `platform` on the player and the device
    (FR-018).

### Implementation

- [X] T012 Add the auth readers to `backend/config/env.py` (contracts/environment.md):
  - `signing_keys(name="AUTH_SIGNING_KEYS") -> tuple[SigningKey, ...]`, where `SigningKey` is a
    frozen dataclass of `kid` and `key: bytes`. It parses comma-separated `kid:key` entries, the
    first one signing, and enforces every T004 rule through `self.secret`.
  - `auth() -> AuthConfig`, a frozen dataclass of:
    - `retry_seconds`, `max_sessions`, `http_timeout_seconds`;
    - `google_client_ids: tuple[str, ...]`, `google_jwks_url`, `google_keys_cache_seconds`.

    `google_client_ids` is required outside dev and test, and the URL is read with `self.url`.
- [X] T013 Wire the settings in `backend/config/settings/base.py` and `backend/config/settings/test.py`:
  - **Values:**
    - `AUTH_SIGNING_KEYS = env.signing_keys()`, plus the `AuthConfig` values as `AUTH_*` and
      `GOOGLE_*` names;
    - `ACCESS_TOKEN_LIFETIME = timedelta(minutes=15)` and
      `REFRESH_TOKEN_LIFETIME = timedelta(days=30)`, with a comment citing the constitution
      "Security & privacy";
    - `THROTTLE_PLAYER_RATE`, `THROTTLE_ANONYMOUS_RATE`, `THROTTLE_REFRESH_RATE` and
      `THROTTLE_LINK_RATE` through `env.rate`.
  - **`SIMPLE_JWT`:**
    - `ALGORITHM="HS256"`, `ACCESS_TOKEN_LIFETIME`, `REFRESH_TOKEN_LIFETIME`, `LEEWAY=0`;
    - `USER_ID_FIELD="id"`, `USER_ID_CLAIM="sub"`, `TOKEN_TYPE_CLAIM="token_type"`,
      `JTI_CLAIM="jti"`;
    - `AUTH_TOKEN_CLASSES=("apps.accounts.tokens.PlayerAccessToken",)`, `UPDATE_LAST_LOGIN=False`.

    `rest_framework_simplejwt.token_blacklist` is **not** in `INSTALLED_APPS` (research R1).
  - **`REST_FRAMEWORK`:**
    - `DEFAULT_AUTHENTICATION_CLASSES=["apps.accounts.authentication.PlayerAuthentication"]`;
    - `DEFAULT_PERMISSION_CLASSES=["rest_framework.permissions.IsAuthenticated",
      "apps.common.permissions.ClientHeaders"]`;
    - `DEFAULT_THROTTLE_CLASSES=["apps.common.throttles.AddressRateThrottle",
      "apps.common.throttles.PlayerRateThrottle"]`;
    - the rates under their scopes.
  - **`test.py`:** `setdefault` a fixed test key
    (`AUTH_SIGNING_KEYS=test1:<44 base64url chars>`),
    `GOOGLE_OAUTH_CLIENT_IDS=test-client.apps.googleusercontent.com`,
    `GOOGLE_KEYS_CACHE_SECONDS=0` and `AUTH_HTTP_TIMEOUT_SECONDS=2`.
- [X] T014 [P] Create `backend/apps/common/client.py` (research R10):
  - Move `parse_client_version`, `as_tuple` and `ClientVersion` there from
    `backend/apps/content/services/manifest.py`, which then imports them from `apps.common.client`.
    Update any content test import.
  - Add `parse_platform(value) -> str | None`, accepting only `android` and `ios`.
  - Create `backend/apps/common/permissions.py` with `ClientHeaders`: a DRF `BasePermission`
    whose `has_permission` raises `ValidationError({"X-Client-Version": [...]})` or
    `{"X-Platform": [...]}` for a missing or malformed header.
- [X] T015 [P] Extend `backend/apps/common/errors.py` (research R8):
  - **New `ErrorCode` members:** `TOKEN_EXPIRED` (401), `TOKEN_INVALID` (401),
    `ACCOUNT_DELETED` (403), `PROVIDER_IN_USE` (409), `PROVIDER_ALREADY_LINKED` (409) and
    `PROVIDER_TOKEN_INVALID` (422), with the exact messages from contracts/api.md.
  - **Exceptions:** an `AuthError(exceptions.AuthenticationFailed)` carrying one of the first
    three codes (with status 403 for `account_deleted`), and a `ConflictError(exceptions.APIException)`
    carrying a code and `details`.
  - **The mapping:** `NotAuthenticated` → `TOKEN_INVALID`. Every 401 sets
    `WWW-Authenticate: Bearer`.
  - *As built:* one `ApiError(APIException)` replaces both exceptions (research R8 "As built").
- [X] T016 [P] Extend `backend/apps/common/throttles.py` (research R9):
  - `AddressRateThrottle.allow_request` returns `True` when `request.auth is not None`.
  - Add `PlayerRateThrottle(SimpleRateThrottle)`, scope `player`, rate read from
    `settings.THROTTLE_PLAYER_RATE` on every request (as B01's class does). It applies only when
    `request.auth is not None`, is keyed by `request.user.pk`, and fails open on `RedisError`.
  - Factor the read-the-rate and fail-open logic into a shared base, so the US1–US3 throttles
    reuse it.
- [X] T017 Add the four models to `backend/apps/accounts/models.py`, and generate
  `backend/apps/accounts/migrations/0002_players.py` (data-model.md). `User` is unchanged.
  - **`Player(UUIDv7Model)`:**
    - `status` CharField choices `active` | `pending_deletion` | `deleted`, default `active`,
      `db_index=True`;
    - `display_name` CharField `max_length=32, blank=True`;
    - `country` CharField `max_length=2, blank=True`;
    - `locale` CharField `max_length=16`;
    - `platform` CharField choices `android` | `ios`;
    - `client_version` CharField `max_length=32`;
    - `driver_level` PositiveSmallIntegerField `default=1`, with a check constraint `>= 1`;
    - `is_tester` BooleanField `default=False`;
    - `last_seen_at` DateTimeField;
    - `created_at` (`auto_now_add`) and `updated_at` (`auto_now`);
    - an `is_authenticated` property that returns `True`.
  - **`Device(UUIDv7Model)`:**
    - `install_id_hash` CharField `max_length=64, unique=True`;
    - `player` FK `Player` `on_delete=PROTECT, related_name="devices"`, indexed;
    - `platform` (choices as above), `app_version` CharField `max_length=32`, `last_seen_at`;
    - timestamps.
  - **`Identity(UUIDv7Model)`:**
    - `player` FK `PROTECT`, `related_name="identities"`;
    - `provider` CharField choices `google`;
    - `subject` CharField `max_length=255`;
    - `linked_at`, and timestamps;
    - `UniqueConstraint(provider, subject)` and `UniqueConstraint(player, provider)`.
  - **`PlayerSession(UUIDv7Model)`:**
    - `player` FK `CASCADE` and `device` FK `CASCADE`;
    - `status` choices `active` | `ended`, default `active`;
    - `end_reason` CharField choices `reuse` | `switch` | `limit`, `blank=True`;
    - `ended_at` null;
    - `current_jti` UUIDField, `current_issued_at`, `current_expires_at`, `current_kid` CharField
      `max_length=32`;
    - `previous_jti` UUIDField null, `previous_spent_at` null;
    - `last_renewed_at`, and timestamps;
    - indexes `(player, status, current_expires_at)`, `(status, ended_at)` and
      `current_expires_at`.
- [X] T018 Write `backend/apps/accounts/tokens.py` (research R1, R2, R13):
  - **`KeyRingBackend(TokenBackend)`:**
    - built from `settings.AUTH_SIGNING_KEYS`;
    - `encode(payload, kid=None)` signs with the named key (default: the first), with
      `headers={"kid": kid}`;
    - `get_verifying_key(token)` reads the unverified header's `kid` and returns that key, or
      raises `TokenBackendError` for a missing or unknown one;
    - only `HS256` is accepted.
  - **`PlayerAccessToken(AccessToken)` and `PlayerRefreshToken(Token)`** (`token_type`
    `refresh`, 30-day lifetime) both return the `KeyRingBackend` from `get_token_backend()`.
  - **Mint helpers:** `mint_access(player_id, session_id)` and
    `mint_refresh(player_id, session_id, jti, issued_at, expires_at, kid)`. The second builds its
    claims in one fixed order, so re-minting is byte-identical (research R3).
  - **`decode_refresh(raw, verify_exp=True)`** maps simplejwt and PyJWT errors to `AuthError`:
    expired → `token_expired`, everything else → `token_invalid`.
- [X] T019 Write `backend/apps/accounts/authentication.py` (research R11):
  - `PlayerAuthentication(JWTAuthentication)` overrides:
    - `get_validated_token`: expiry gives `AuthError(token_expired)`, anything else
      `AuthError(token_invalid)`;
    - `get_user`: loads `Player` by the `sub` claim with one query. A missing row is
      `token_invalid`, and `pending_deletion` or `deleted` is `account_deleted`.
  - `authenticate_header` returns `Bearer`.
- [X] T020 Write `backend/apps/accounts/services/sessions.py`, the opening half:
  - `open_session(player, device, *, client) -> IssuedTokens`, where `client` is the parsed
    headers: in the caller's transaction, it creates the `PlayerSession` with the refresh claims
    (a new UUIDv7 `jti`, `iat` now, `exp` + 30 days, the current `kid`), mints both tokens, and
    updates `last_seen_at`, `client_version` and `platform` on the player and the device with
    `update_fields`.
  - `IssuedTokens` is a frozen dataclass of `player_id`, `access`, `refresh`,
    `access_expires_in=900` and `providers`, where `providers` is the player's sorted
    `Identity.provider` values.

**Checkpoint**: The foundation is ready. T004–T011 pass, and B01's and B04's suites still pass.

---

## Phase 3: User Story 1 - The first online launch gets an account without the player noticing (Priority: P1) 🎯 MVP

**Goal**: `POST /v1/auth/anonymous` creates or returns the device's player with a token pair
(FR-001–FR-008, FR-033, research R4).

**Independent Test**: quickstart A2 steps 1–4 and 8. Two install ids make two players, and a
repeat makes none. Ten simultaneous requests with one new id make one player. Each access token
authenticates as its own player on the T009 test view.

### Tests for User Story 1 (write first, they must fail)

- [X] T021 [P] [US1] Write `backend/apps/accounts/tests/test_anonymous.py` (spec US1, contracts/api.md):
  - **Creation:**
    - a new v4 id gives `201`, `created: true`, a `TokenPair` (`player_id`, `access`, `refresh`,
      `access_expires_in: 900`, `providers: []`), and one `Player` and one `Device`;
    - the device's `install_id_hash` is the sha256 hex of the lowercase id, and the raw id appears
      in no column.
  - **Return:**
    - the same id in upper case gives `200`, `created: false`, the same `player_id`, and new
      tokens;
    - with an `Identity(google)` row on that player, the same id still gives that player (FR-005).
  - **A non-active player:** if the player is `pending_deletion` or `deleted`, the answer is `201`
    with a new player. The device now points at it, and the old player's row is unchanged
    (FR-004).
  - **New-player fields (FR-006):**
    - `country` is `EG` for `ar-EG` and empty for `ar`;
    - `driver_level` 1, `display_name` empty, `is_tester` false;
    - `platform` and `client_version` come from the headers.
  - **Refused with `validation_error`:**
    - a v7 id, `not-a-uuid`, a missing field;
    - `platform: web`;
    - a body `platform` different from `X-Platform`;
    - a locale `arabic` or one longer than 16 characters;
    - a missing `X-Client-Version`.
  - **No echo (FR-002):** no error answer contains the submitted value. Check a malformed
    `install_id` such as `not-a-uuid`, a v7 id, and a 5,000-character `install_id`: the response
    body never contains the submitted string, and `details.fields.install_id` holds only the fixed
    message.
  - **Opening sessions:**
    - an existing device whose platform changed has it updated;
    - a second return leaves two `active` `PlayerSession` rows for the device, the first one not
      ended (FR-010). Its renewal is checked in T031, since renewal is US2.
- [X] T022 [P] [US1] Write `backend/apps/accounts/tests/test_anonymous_concurrency.py`, a
  `TransactionTestCase`:
  - 10 threads `POST` one new id at the same moment (a barrier), and exactly one `Player` and
    one `Device` exist afterwards, with every answer naming that player (US1-3);
  - **SC-001:** 1,000 ids × 10 calls each to `players.create_or_return` through a 16-thread pool
    leave exactly 1,000 players.
- [X] T023 [P] [US1] Add to `backend/apps/common/tests/test_throttles.py`: `AnonymousThrottle`
  allows 60 creations per hour from one address. The 61st gives `429 rate_limited` with
  `details.retry_after_s` and `Retry-After`, and creates nothing. Another address is still
  allowed (US1-6).

### Implementation for User Story 1

- [X] T024 [US1] Write `backend/apps/accounts/services/players.py` (research R4):
  - `install_id_hash(install_id: UUID) -> str` is sha256 hex of `str(install_id).lower()`.
  - `create_or_return(install_id, platform, locale, *, client) -> tuple[IssuedTokens, bool]` runs
    in `transaction.atomic()`:
    - `select_for_update` the device by hash;
    - **its player is active:** call `open_session` and return `created=False`;
    - **it isn't:** create a new `Player` (country from the locale region), move the device to it
      with `update_fields=["player", "updated_at"]`, and open a session;
    - **no device yet:** in a savepoint, create the `Player` and the `Device`. On `IntegrityError`
      from the unique hash, roll the savepoint back and re-read the winner's device, then go on
      as above.
- [X] T025 [P] [US1] Write the serializers in `backend/apps/accounts/api/serializers.py`:
  - **`AnonymousRequest`:**
    - `install_id`: a UUIDField whose validator accepts only `version == 4`;
    - `platform`: a ChoiceField of `android` and `ios`;
    - `locale`: a RegexField `^[a-z]{2,3}(-[A-Z]{2})?$`, `max_length=16`.
  - **Fixed error messages that never repeat the input (FR-002).** DRF's defaults for
    `UUIDField` (`“%(value)s” is not a valid UUID.`) and `ChoiceField` (`"%(input)s" is not a valid
    choice.`) echo the value, so every field of `AnonymousRequest`, `RefreshRequest` (T037) and
    `LinkRequest` (T045) sets `error_messages` with no placeholder. For example `install_id`:
    `{"invalid": "Must be a version-4 UUID.", "required": "This field is required."}`. Put the
    message table in one module, `backend/apps/accounts/api/messages.py`, so T037 and T045 reuse
    it.
  - **`TokenPair`** (`player_id`, `access`, `refresh`, `access_expires_in`, `providers`) and
    **`AnonymousTokenPair(TokenPair)`** with `created`.
- [X] T026 [US1] Write `AnonymousView` in `backend/apps/accounts/api/views.py`:
  - `authentication_classes = ()`, `permission_classes = (ClientHeaders,)`,
    `throttle_classes = (AnonymousThrottle,)`, `http_method_names = ("post", "options")`;
  - it checks the body's `platform` equals `X-Platform` (`validation_error` on `platform`),
    calls `players.create_or_return`, and answers `201` or `200`;
  - `extend_schema` documents the two header parameters, both answers and the errors
    `400/406/413/415/429/503` with `ErrorEnvelopeSerializer`, under the tag `auth`.
  - Add `AnonymousThrottle` (scope `anonymous`, keyed by `client_ip`, rate
    `settings.THROTTLE_ANONYMOUS_RATE`) to `backend/apps/common/throttles.py`.
- [X] T027 [US1] Route `path("v1/auth/anonymous", AnonymousView.as_view(), name="auth-anonymous")`
  in `backend/config/urls.py`, before the `v1/` router include. Regenerate the contract with
  `uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn`, and
  commit `contracts/openapi.yaml`.

**Checkpoint**: A phone gets an account. T021–T023 pass. A local `curl` follows quickstart A2-1
to A2-4.

---

## Phase 4: User Story 2 - A session stays alive for as long as the player keeps playing (Priority: P2)

**Goal**: `POST /v1/auth/refresh` rotates, replays within the window, ends a session on reuse, and
caps live sessions. Keys rotate without sign-outs. Old sessions are pruned (FR-009–FR-018,
research R3, R13).

**Independent Test**: quickstart A2 steps 5–8, and T030's 30-day simulation: one session survives
2,880 renewals with one answer in five lost. A token spent long ago ends only its own session.

### Tests for User Story 2 (write first, they must fail)

- [X] T028 [P] [US2] Write `backend/apps/accounts/tests/test_refresh.py` (spec US2,
  contracts/tokens.md "Rotation"):
  - **Rotation:** the current token gives a new pair, the presented `jti` becomes `previous_jti`
    with `previous_spent_at` now, and the new refresh's `exp` is now + 30 days.
  - **Replay:** the previous token 59 s and 60 s after it was spent returns the **byte-identical**
    successor and a new access token, and the row is unchanged.
  - **Reuse:**
    - at 61 s, `401 token_invalid`, the session is `ended` with `end_reason="reuse"`, and its
      current token is then refused too;
    - one `WARNING` record on `wassal.security` with `event=refresh_reuse`, `player_id` and
      `session_id`, and no token or install id in any record (`caplog`).
  - **An older token** (two rotations back) is reuse as well.
  - **Expiry and status:**
    - 30 days after issue, the token gives `401 token_expired`, and the session is lapsed but not
      ended;
    - a `pending_deletion` player gives `403 account_deleted`.
  - **Other refusals:**
    - a missing `refresh`, or a missing header, gives `400`;
    - an access token sent as `refresh` gives `token_invalid`.
  - **Independence:** another device's session of the same player keeps renewing after this one
    ends.
- [X] T029 [P] [US2] Write `backend/apps/accounts/tests/test_refresh_concurrency.py`, a
  `TransactionTestCase`: two threads renew with one token at once. Both get `200` with the same
  refresh token, and the session stays active (spec Edge Cases).
- [X] T030 [P] [US2] Write `backend/apps/accounts/tests/test_session_simulation.py` (SC-002), with
  `time-machine`:
  - 2,880 renewals 15 minutes apart, where every fifth answer is discarded and the same token is
    retried 5 s later;
  - the session is still `active` at the end, and no `refresh_reuse` record was written.
- [X] T031 [P] [US2] Write `backend/apps/accounts/tests/test_session_cap.py` (FR-010, US2-8):
  - two `POST /v1/auth/anonymous` returns with one install id give two sessions, and the first
    one's refresh token still renews after the second sign-in (FR-010, moved here from T021);
  - with `AUTH_MAX_SESSIONS_PER_PLAYER=3`, a 4th sign-in ends the least recently renewed session
    (`end_reason="limit"`), and the other two still renew;
  - lapsed sessions don't count;
  - 10 threads signing in one player at once leave at most 3 live sessions (`TransactionTestCase`).
- [X] T032 [P] [US2] Write `backend/apps/accounts/tests/test_key_rotation.py` (SC-004, US2-7):
  - after a new key is prepended to `settings.AUTH_SIGNING_KEYS`, a refresh token signed with the
    old key renews, and its successor carries the new `kid`;
  - a replay within the window re-signs with the stored old `kid` while it is still in the ring;
  - once the old key is removed, its tokens give `token_invalid`, and `POST /v1/auth/anonymous`
    with the install id returns the same player (FR-005).
- [X] T033 [P] [US2] Add the CGNAT test to `backend/apps/common/tests/test_throttles.py` (SC-008):
  - **Setup:** create the 1,000 players and their sessions with `players.create_or_return`
    (T024) directly, not over HTTP. Through the API from one address they would hit
    `AnonymousThrottle`'s 60/hour.
  - The 1,000 players, all with one `X-Forwarded-For` and `NUM_PROXIES=1`, renew over HTTP within
    one simulated minute, with every limit at its default rate, and every answer is `200`;
  - one session's 31st renewal in a minute gives `429`;
  - tokens that don't verify are limited by address.
- [X] T034 [P] [US2] Write `backend/apps/accounts/tests/test_prune_and_keygen.py`:
  - `prune_sessions` deletes sessions ended or lapsed more than 30 days ago, and keeps newer and
    live ones;
  - the beat row `accounts.prune_sessions` exists after migrations, on the `default` queue;
  - `call_command("auth_signing_key")` prints one line matching `^k\d{8}:[A-Za-z0-9_-]{43}$`,
    which `env.signing_keys` accepts.

### Implementation for User Story 2

- [X] T035 [US2] Complete `backend/apps/accounts/services/sessions.py` (research R3):
  - **`rotate(raw_refresh, *, client) -> IssuedTokens`** runs in `transaction.atomic()` and
    follows research R3's steps 1–6 exactly. It uses `decode_refresh`, `select_for_update` on the
    session, the player status check, and then rotate, replay (re-mint with the stored
    `current_*` claims and `current_kid`, or the current kid if it has been retired) or reuse.
    Reuse calls `end_session(session, "reuse")` and logs the security event.
  - **`open_session`** gains the cap: `select_for_update` on the player, count live sessions, and
    end the least recently renewed one (`limit`) while the count is at least
    `AUTH_MAX_SESSIONS_PER_PLAYER`.
  - **`end_session(session, reason)`** sets `status`, `end_reason` and `ended_at`.
  - **Security events** are logged with `logging.getLogger("wassal.security")`: `refresh_reuse`
    at `WARNING`, `session_limit` at `INFO`, using `extra` ids only (research R14).
- [X] T036 [P] [US2] Add `RefreshThrottle` to `backend/apps/common/throttles.py`, scope
  `refresh`, rate `settings.THROTTLE_REFRESH_RATE`:
  - its cache key is the `sid` from `tokens.decode_refresh(raw, verify_exp=False)` when the
    signature verifies;
  - otherwise it is keyed by `client_ip` under scope `refresh_address`, at B01's
    `THROTTLE_ADDRESS_RATE`.
- [X] T037 [US2] Write `RefreshRequest` in `backend/apps/accounts/api/serializers.py` (`refresh`, a
  CharField with `max_length=4096` and the fixed messages from `api/messages.py`, T025), and `RefreshView` in `backend/apps/accounts/api/views.py`:
  - `authentication_classes = ()`, `permission_classes = (ClientHeaders,)`,
    `throttle_classes = (RefreshThrottle,)`;
  - it answers `200 TokenPair`;
  - `extend_schema` documents the `400/401/403/429/503` errors.

  Route `v1/auth/refresh` in `backend/config/urls.py`, and regenerate `contracts/openapi.yaml`.
- [X] T038 [P] [US2] Write `backend/apps/accounts/tasks.py` and the beat migration:
  - `prune_sessions`: `@shared_task(name="accounts.tasks.prune_sessions", bind=True,
    autoretry_for=(OperationalError,), retry_backoff=True, max_retries=3)`. It deletes sessions
    where `status="ended"` and `ended_at` < now − 30 days, or `current_expires_at` < now − 30
    days, and returns the count.
  - `backend/apps/accounts/migrations/0004_prune_sessions_schedule.py` creates a
    `CrontabSchedule(minute=30, hour=4, timezone="Africa/Cairo")` and the `PeriodicTask` on the
    `default` queue, following B01's heartbeat migration.
- [X] T039 [P] [US2] Write `backend/apps/accounts/management/commands/auth_signing_key.py`:
  - it prints `k<today YYYYMMDD>:<base64url of secrets.token_bytes(32), no padding>`;
  - its help text points at `docs/runbooks/auth-keys.md`;
  - it writes no file.

**Checkpoint**: Sessions renew, replay, end on reuse and stay capped. T028–T034 pass.

---

## Phase 5: User Story 3 - A player links Google to keep their progress (Priority: P3)

**Goal**: `POST /v1/auth/link` verifies a Google ID token and links its subject, with no conflict
yet (FR-020–FR-024, research R6).

**Independent Test**: quickstart A2 steps 9–11. With tokens signed by the test key for the test
client id, a link succeeds and a repeat changes nothing. Each tampered token gives
`422 provider_token_invalid` with its reason.

### Tests for User Story 3 (write first, they must fail)

- [X] T040 [P] [US3] Write `backend/apps/accounts/tests/conftest.py` fixtures:
  - **`google_key`** (session scope): a 2048-bit RSA key from `cryptography`, with `kid="test-g1"`.
  - **`google_jwks`**: a `ThreadingHTTPServer` thread serving `{"keys": [<public JWK>]}` at
    `/oauth2/v3/certs`. It counts requests, can be switched to answer `500` or to sleep past the
    timeout, and sets `settings.GOOGLE_JWKS_URL`.
  - **`make_google_token(sub, **overrides)`**: RS256 with `iss="https://accounts.google.com"`,
    `aud` = the test client id, `iat` now, `exp` + 1 h, `email`, `name` and `picture` filled in.
    Overrides cover every claim and the signing key.
  - **`player_client`**: a client with the two headers and a bearer token from
    `players.create_or_return`.
- [X] T041 [P] [US3] Write `backend/apps/accounts/tests/test_google.py`, for `google.verify_id_token`:
  - **Valid:**
    - a valid token returns only `sub`;
    - both issuer spellings are accepted;
    - `exp` 30 s in the past is still accepted (60 s leeway), and 61 s is not.
  - **Reasons:**
    - `aud` another client → `audience`;
    - `iss` another issuer → `issuer`;
    - signed by another key with the same `kid` → `signature`;
    - `alg: none` → `signature`;
    - HS256 signed with the public key's PEM → `signature`;
    - not a JWT → `malformed`;
    - no `sub` → `malformed`;
    - expired → `expired`.
  - **Key fetching:**
    - an unknown `kid` triggers exactly one refetch;
    - with `GOOGLE_KEYS_CACHE_SECONDS=3600`, two verifications fetch once;
    - a `500` or a timeout with nothing cached raises `DependencyUnavailable`.
- [X] T042 [P] [US3] Write `backend/apps/accounts/tests/test_link.py` (spec US3, contracts/api.md):
  - **Linking:**
    - a new link gives `200`, `{"player_id", "providers": ["google"]}`, and one `Identity` with
      `subject` = `sub`;
    - the token's `email`, `name` and `picture` appear in no column;
    - the same token again gives `200` with no new row and no changed `linked_at`.
  - **Refusals:**
    - a different `sub` for the same player gives `409 provider_already_linked`,
      `details.provider="google"`, with nothing changed;
    - `provider: apple` gives `400`, and so does `google` with `GOOGLE_OAUTH_CLIENT_IDS` empty;
    - `id_token` over 4096 characters gives `400`;
    - `existing_player_id` without `resolve`, or `resolve` without `existing_player_id`, gives
      `400`;
    - a tampered token gives `422 provider_token_invalid` with `details.reason`, and is never a
      401;
    - JWKS down with nothing cached gives `503 dependency_unavailable`;
    - no bearer gives `401 token_invalid`;
    - a `pending_deletion` current player gives `403`.
  - **The limit:** the 11th link in a minute gives `429`.

### Implementation for User Story 3

- [X] T043 [US3] Write `backend/apps/accounts/services/google.py` (research R6):
  - `GoogleKeys` is a module-level `PyJWKClient(settings.GOOGLE_JWKS_URL,
    cache_keys=True, lifespan=max(1, settings.GOOGLE_KEYS_CACHE_SECONDS),
    timeout=settings.AUTH_HTTP_TIMEOUT_SECONDS)`, rebuilt when those settings change in tests.
  - `verify_id_token(raw) -> str` returns `sub`:
    - `jwt.decode` with `algorithms=["RS256"]`, `audience=settings.GOOGLE_OAUTH_CLIENT_IDS`,
      `leeway=60`, and `options={"require": ["exp", "iat", "iss", "aud", "sub"]}`;
    - the issuer must be in `{"accounts.google.com", "https://accounts.google.com"}`;
    - PyJWT errors map to `ProviderTokenInvalid(reason)`, and `PyJWKClientConnectionError` maps
      to `DependencyUnavailable`, which gives `503 dependency_unavailable` through
      `apps.common.errors`;
    - every claim except `sub` is discarded.
- [X] T044 [US3] Write the linking service in `backend/apps/accounts/services/linking.py`, the
  no-conflict paths of research R7 steps 1–4:
  - `link(player, provider, id_token, *, resolve=None, existing_player_id=None, client)`:
    - verify outside the transaction, then in `transaction.atomic()`: `select_for_update` the
      current player and the identity by `(provider, subject)`;
    - **G is already this player's:** return.
    - **The player has another `google` row:** raise `ConflictError(provider_already_linked)`.
    - **No row:** create it, with the unique-index race handled as in T024.
    - **Held by a non-active player:** move it to the current player, with `linked_at` now (FR-030).
    - **Held by an active other player:** raise a `ConflictPending` placeholder that US4
      completes.
  - Log `wassal.security` `link_refused` at `INFO` with the reason.
- [X] T045 [US3] Write the link API:
  - **Serializers** in `backend/apps/accounts/api/serializers.py`:
    - `LinkRequest`: `provider` ChoiceField `google`, refused when `GOOGLE_OAUTH_CLIENT_IDS` is
      empty; `id_token` CharField `max_length=4096`; `resolve` ChoiceField
      `switch_to_existing`|`keep_current`, optional; `existing_player_id` UUIDField, optional;
      `validate` makes the last two required together; every field uses the fixed messages from
      `api/messages.py` (T025), so no error repeats the token or the input;
    - `LinkResult` (`player_id`, `providers`).
  - **`LinkView`** in `backend/apps/accounts/api/views.py` uses the default authentication and
    permissions, with `throttle_classes = (PlayerRateThrottle, LinkThrottle)`.
  - Add `LinkThrottle` (scope `link`, keyed by player) to `backend/apps/common/throttles.py`.
  - Route `v1/auth/link` in `backend/config/urls.py`, document `bearerAuth` and every error in
    `extend_schema`, and regenerate `contracts/openapi.yaml`.

**Checkpoint**: Linking works when there is no conflict. T040–T042 pass, apart from the conflict
cases T046 adds.

---

## Phase 6: User Story 4 - The Google account already has other progress: the player chooses (Priority: P3)

**Goal**: the 409 with two summaries, `switch_to_existing`, `keep_current`, and the guard against
a changed conflict (FR-025–FR-031, research R7).

**Independent Test**: quickstart B4–B6, locally with test tokens. E linked to G and C unlinked;
C links G and gets a 409; each choice puts G, the devices and the sessions where the spec says;
nothing else changes.

### Tests for User Story 4 (write first, they must fail)

- [X] T046 [P] [US4] Write `backend/apps/accounts/tests/test_conflicts.py` (spec US4):
  - **The 409:** with E linked to G, C linking G gives `409 provider_in_use` with
    `details.current` = `{"driver_level", "chapter_id": "ch1_first_job", "bonat": 0}` and
    `details.existing` = the same keys plus `player_id` = E. Nothing changes.
  - **`switch_to_existing`** with that id:
    - `200 TokenPair` whose `player_id` is E;
    - C's session that made the request is `ended` (`switch`), and its refresh is then
      `token_invalid`;
    - the device's `player` is E, and `POST /v1/auth/anonymous` with C's install id now returns E;
    - C's other sessions and devices are untouched.
  - **`keep_current`:** `200`, G's `Identity.player` is C, E has no identities, and E's sessions
    still renew.
  - **Nothing else moves (FR-028):** a snapshot of every `Player` row (minus FR-018's fields) and
    every non-auth table's row count is equal before and after each choice.
  - **A changed conflict (FR-029):**
    - with G moved to F between the 409 and the retry, the retry gives a new 409 naming F;
    - with E `deleted` in between, the retry links G to C with `200`.
  - **Other cases:**
    - `resolve` sent with no conflict is ignored, and the link succeeds;
    - an E that is `pending_deletion` makes G free (US4-7).
  - **All or nothing (FR-031):**
    - patch `sessions.open_session` to raise during `switch_to_existing`: the answer is `500`, and
      the device's `player`, the request's session (still `active`), E's sessions and G's
      `Identity` are exactly as before;
    - patch the identity save to raise during `keep_current`: G still belongs to E, and nothing
      else changed.
- [X] T047 [P] [US4] Write `backend/apps/accounts/tests/test_conflicts_concurrency.py`, a
  `TransactionTestCase`: two players each `keep_current` the other's Google account at the same
  moment. Both finish without a deadlock error, and each subject ends with exactly one holder
  (research R7 lock order).
- [X] T048 [P] [US4] Write `backend/apps/accounts/tests/test_properties.py` (SC-006, FR-042), a
  hypothesis `RuleBasedStateMachine` with up to 4 install ids, 3 Google subjects and a clock
  under `time-machine`. Each example runs inside a transaction that rolls back.
  - **Rules:**
    - `anonymous(install)`;
    - `refresh(session, which ∈ {current, previous, older})`;
    - `advance(seconds ∈ {5, 59, 61, 900, 30 days})`;
    - `link(player, subject)`;
    - `resolve(player, subject, choice)`;
    - `set_status(player, status)`.
  - **Invariants after every step:**
    - each install hash has at most one `Device`;
    - each subject has at most one `Identity`, and at most one active holder;
    - no player has more live sessions than the cap;
    - repeating the last request gives the same status code and body (tokens aside, where
      contracts/tokens.md says so);
    - player fields other than FR-018's never change, except in `set_status`.
  - It runs under the `ci` profile by default, and quickstart A1 runs the `thorough` one.

### Implementation for User Story 4

- [X] T049 [P] [US4] Write `backend/apps/accounts/services/summary.py`:
  - `summarize(player) -> dict` returns `{"driver_level": player.driver_level, "chapter_id":
    "ch1_first_job", "bonat": 0}`;
  - a docstring says B03 replaces the last two from its wallet and story tables (research R7
    hand-over).
- [X] T050 [US4] Complete `backend/apps/accounts/services/linking.py`, research R7 steps 4–5:
  - **Without `resolve`:** raise `ConflictError(provider_in_use, details={"current":
    summarize(C), "existing": {"player_id": str(E.id), **summarize(E)}})`.
  - **With `resolve`:** lock both players in `id` order, then re-check that the holder is still
    `existing_player_id` and still active. If not, answer as without `resolve`, or link.
    - `switch_to_existing`: `end_session(request_session, "switch")`, set `device.player = E`,
      `open_session(E, device)`, and return the `IssuedTokens`.
    - `keep_current`: set `identity.player = C` and `linked_at = now`.
  - Log `wassal.security` `switch` and `keep_current` at `INFO` with the ids (research R14).
- [X] T051 [US4] Update `LinkView` and the serializers:
  - add `ConflictSummary`, `ExistingConflictSummary(ConflictSummary)` with `player_id`, and
    `ConflictDetails`;
  - `LinkView` answers `200 TokenPair` for a switch, and `200 LinkResult` otherwise;
  - document the 409 `provider_in_use` details in `extend_schema`, and regenerate
    `contracts/openapi.yaml`.

**Checkpoint**: Linking is safe. T046–T048 pass, and so does T042, with no conflict placeholder
left.

---

## Phase 7: User Story 5 - Staff look a player up (Priority: P4)

**Goal**: The read-only player admin and the `player_support` group (FR-036, contracts/admin.md,
research R12).

**Independent Test**: quickstart A3. A support member searches a `player_id` and sees what
contracts/admin.md lists, with no secret. Only the tester flag can be saved. A content author has
no Players entry.

### Tests for User Story 5 (write first, they must fail)

- [X] T052 [P] [US5] Write `backend/apps/accounts/tests/test_admin_players.py`, signed in through
  B01's OTP test helper:
  - **A `player_support` member:**
    - an exact-`player_id` search finds the player;
    - the change page shows status, platform, client version, created, last seen, "google" under
      providers, the device rows and a live-session count;
    - the page HTML contains no `install_id_hash` value, no `subject`, and no `jti`.
  - **Saving:**
    - `is_tester=on` saves a `LogEntry`;
    - a POST that also changes `display_name` or `status` leaves them unchanged;
    - the add and delete URLs give `403`.
  - **Other staff:** a `content_author` gets `403` on the changelist, and no app entry.

### Implementation for User Story 5

- [X] T053 [US5] Write `PlayerAdmin` in `backend/apps/accounts/admin.py`:
  - **The list:**
    - `list_display` (`id`, `status`, `platform`, `client_version`, `is_tester`, `created_at`,
      `last_seen_at`), `list_filter` (`status`, `platform`, `is_tester`);
    - `search_fields = ("=id",)`;
    - `actions = None`, and `has_add_permission` and `has_delete_permission` return `False`.
  - **The change page:**
    - `readonly_fields` = every field except `is_tester`, plus computed `providers` and
      `live_sessions`;
    - a read-only `DeviceInline` (`id`, `platform`, `app_version`, `created_at`,
      `last_seen_at`), with no add or delete.

  It is registered on the existing admin site.
- [X] T054 [US5] Write `backend/apps/accounts/migrations/0003_player_support_group.py`: a
  `RunPython` that creates the group `player_support` with `view_player`, `change_player`,
  `view_device` and `view_identity`, after `0002` and `contenttypes`/`auth` (create the
  permissions first, with `create_permissions`). Reversing it deletes the group.

**Checkpoint**: All five stories work independently.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: The privacy scan, the contract test, the docs, the review and the owner's live
checks.

- [X] T055 [P] Write `backend/apps/accounts/tests/test_privacy_scan.py` (SC-007, research R14):
  - link 100 players through the API with tokens carrying a unique `email`, `name` and `picture`,
    with `caplog` at DEBUG;
  - then, for every text column of every table in the database (`information_schema.columns`,
    parameterized queries) and every captured log record, assert that none of the emails, names,
    pictures, raw install ids, access, refresh or Google tokens appears.
- [X] T056 [P] Extend `backend/tests/test_contract.py` (FR-039, research R15):
  - register a schemathesis auth provider that `POST`s `/v1/auth/anonymous` on the live server
    with a fresh v4 id and the two headers, and returns its `access`;
  - the three operations conform, including their documented 401, 403, 409 and 422 answers.
  - *As built:* the test signs in and sets the header itself, since schemathesis applies auth
    providers to its coverage cases at collection, before the live server exists. A case that
    carries the token must not be 401.
- [X] T057 [P] Update `docs/architecture-backend.md` (research R17):
  - §6.2: the two codes.
  - §6.3: `GET /v1/content/manifest` auth "none".
  - §6.4:
    - the install-id sentence (it leads to its device's player, linked or not);
    - `existing_player_id`;
    - `access_expires_in` and `providers`.
  - §6.5: per-player, per-session and 60/hour per-address limits, with the carrier-NAT
    reasoning.
  - §12 "accounts": `Device.install_id_hash`, `Identity` for providers only, and `PlayerSession`
    replacing the blacklist tables.
  - §13: the `kid` key ring and its rotation.
  - §14.2: the install id hash is on the device record.
  - §22.6: resolved, linking to research R5.

  Add the two codes to `specs/002-b01-backend-skeleton/contracts/api.md`'s error table too.
- [X] T058 [P] Update `docs/architecture-mobile.md` §16: the install id is a v4 UUID kept across
  re-installs (research R5), plus the renewal and fallback rules, linking to
  `specs/009-b02-accounts-auth/contracts/tokens.md` "Client obligations". Change the comment in
  `apps/mobile/lib/core/network/http_client.dart` to say the content endpoints stay public
  (B02 FR-035), without changing any code.
- [X] T059 [P] Write `docs/runbooks/auth-keys.md`, and link it from `docs/runbooks/README.md`:
  - **Generating a key:** `docker compose … run --rm api uv run manage.py auth_signing_key`.
  - **Rotating:**
    1. Put the new entry first in `/etc/wassal/<env>.env`, as `root`.
    2. `docker compose … up -d api admin worker beat`.
    3. Check that `/readyz` is 200, and that a renewal's new token header shows the new `kid`.
    4. A reminder 30 days and 15 minutes later to remove the old entry and recreate again.
  - **Emergency revocation:** remove the leaked key at once. Players get back in through their
    install id.
  - **The quickstart B7 latency command,** in full.
- [X] T060 [P] Update `CLAUDE.md`:
  - the overview gains a B02 line (`specs/009-b02-accounts-auth/`: player accounts, sessions,
    Google linking, the player admin);
  - the backend commands table gains `uv run manage.py auth_signing_key` and
    `HYPOTHESIS_PROFILE=thorough uv run pytest apps/accounts/tests/test_properties.py`;
  - a bullet says that every new `/v1` endpoint needs a player token and the two headers, and is
    limited per player, unless its view opts out explicitly.
- [X] T061 [P] Add the "009 B02 accounts and auth" section to `docs/owner-actions.md`, with
  "Before merge" and "After merge" from plan.md "Owner actions", each with its task id, and
  update the "Open now" table.
- [X] T062 Run the full local gate in `backend/` and fix anything it finds:
  - `uv run ruff check . && uv run ruff format --check . && uv run mypy .`;
  - `uv run pytest -n 4 --cov --cov-fail-under=80`;
  - `uv run manage.py makemigrations --check --dry-run`;
  - the OpenAPI drift check from quickstart A1;
  - then `HYPOTHESIS_PROFILE=thorough uv run pytest apps/accounts/tests/test_properties.py` once
    (SC-006). Record its result in the PR.
  - *Result (2026-10-24):* ruff, format, mypy clean; 1,404 tests, 95.6% coverage; no missing
    migration; no contract drift. The thorough run first found a switch from a stale session on
    a device that had moved to another player (the security fix answers it `401`): the state
    machine now expects exactly that. Then 10,000 sequences passed (28 min).
- [X] T063 Run the security review (FR-043, constitution "Review"), with the `security-reviewer`
  agent over the branch diff:
  - the token, session and key code;
  - the Google verification;
  - the throttles;
  - the admin's visibility;
  - logging.

  Fix every CRITICAL and HIGH finding, and list the outcome in the PR.
  - *Outcome (2026-10-24):* no CRITICAL or HIGH. All five MEDIUM and LOW findings were fixed
    test-first: a trailing newline in `install_id` (a 500, now `400`); IPv6 clients counted per
    /64 (research R9); the switch takes only the current player's device and ends all its
    sessions there (R7); Google's key set failing in any way is a `503`, failing fast for 15 s
    (R6); `GOOGLE_KEYS_CACHE_SECONDS` at least 60 outside dev and test.
- [X] T064 Walk through quickstart A2 and A3 by hand on the dev stack, and record the results in
  the PR.
  - *As walked (2026-10-24):* A2-1 to A2-12 and A3-1 to A3-4 gave the expected answers. A2-10
    needs a client id in `.env`; empty, it is the documented `400` "not enabled here". Bringing
    the stack up also found that the image build needed a build-only `AUTH_SIGNING_KEYS` for
    `collectstatic` (fixed in `docker/Dockerfile`).
- [ ] T065 **Owner, before merge:** in Google Cloud, create the project and the Google Auth
  Platform branding (Testing, with the owner's accounts as test users):
  - the server (web) client, with the OAuth Playground redirect URI;
  - Android clients for `com.wassalogra.app.dev`, `.staging` and `com.wassalogra.app`, with their
    SHA-1 fingerprints.

  Put the web client id in `GOOGLE_OAUTH_CLIENT_IDS` (plan "Owner actions").
- [ ] T066 **Owner, before merge:** run `manage.py auth_signing_key` once per environment, and add
  its output as `AUTH_SIGNING_KEYS`, with `GOOGLE_OAUTH_CLIENT_IDS`, to `/etc/wassal/staging.env`
  on the staging host and `/etc/wassal/prod.env` on the prod host (mode `0400`). The keys are
  different per environment.
- [ ] T067 **Owner, after merge:** once staging deploys from `master`, run quickstart Part B
  (B1–B8) and record the results in the PR. Tick B02 in `docs/delivery-plan.md` "Progress".
- [ ] T068 **Owner, before the closed test:** move the Google Auth Platform app to "In
  production", once the domain and the privacy policy exist (`docs/owner-actions.md` "Known for
  later features").

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)** has no dependencies.
- **Foundational (Phase 2)** depends on Setup, and blocks every story.
- **US1 (Phase 3)** depends on Phase 2. It is the MVP.
- **US2 (Phase 4)** depends on Phase 2. Its tests also call `POST /v1/auth/anonymous` to get
  tokens, so in practice it follows US1, though its services don't.
- **US3 (Phase 5)** depends on Phase 2. Its fixtures create players with
  `players.create_or_return` (US1).
- **US4 (Phase 6)** depends on US3 (the linking service), and on US2's `end_session` and the cap
  in `open_session`.
- **US5 (Phase 7)** depends only on Phase 2 (the models). It can run in parallel with US1–US4.
- **Polish (Phase 8)** depends on all stories. T065 and T066 (owner) can start any time, and must
  be done before merge. T067 follows the merge.

### Within phases

- Tests first, and they must fail. Then models, then services, then views and routes, then the
  OpenAPI regeneration.
- `backend/apps/accounts/services/sessions.py` is edited by T020 and then T035, in that order.
- `backend/apps/accounts/services/linking.py`: T044, then T050.
- `backend/apps/common/throttles.py`: T016, then T026, T036 and T045, one at a time.
- `backend/apps/accounts/api/serializers.py` and `views.py`: T025/T026, then T037, T045, T051.
- `contracts/openapi.yaml` is regenerated after each endpoint change (T027, T037, T045, T051), and
  last in T062.

### Parallel opportunities

- **Phase 1:** T002 and T003.
- **Phase 2:** the tests T004–T011 together, then T014, T015 and T016 together, after T012–T013.
- **Phase 3:** T021, T022 and T023 together. T025 alongside T024.
- **Phase 4:** T028–T034 together. T036, T038 and T039 alongside T035.
- **Phase 5:** T040–T042 together.
- **Phase 6:** T046–T048 together. T049 alongside.
- **Phase 7** as a whole can run in parallel with Phases 3–6.
- **Phase 8:** T055–T061 together.

---

## Parallel Example: Foundational tests

```bash
Task: "Extend backend/tests/test_settings_guards.py and test_env.py for AUTH_SIGNING_KEYS (T004)"
Task: "Write backend/apps/common/tests/test_client.py (T005)"
Task: "Extend backend/apps/common/tests/test_errors.py (T006)"
Task: "Write backend/apps/accounts/tests/test_models_players.py (T007)"
Task: "Write backend/apps/accounts/tests/test_tokens.py (T008)"
Task: "Write backend/apps/accounts/tests/test_authentication.py (T009)"
Task: "Extend backend/apps/common/tests/test_throttles.py (T010)"
Task: "Write backend/apps/accounts/tests/test_sessions_open.py (T011)"
```

## Parallel Example: User Story 2 tests

```bash
Task: "Write backend/apps/accounts/tests/test_refresh.py (T028)"
Task: "Write backend/apps/accounts/tests/test_refresh_concurrency.py (T029)"
Task: "Write backend/apps/accounts/tests/test_session_simulation.py (T030)"
Task: "Write backend/apps/accounts/tests/test_session_cap.py (T031)"
Task: "Write backend/apps/accounts/tests/test_key_rotation.py (T032)"
```

---

## Implementation Strategy

### MVP first (User Story 1)

1. Phases 1 and 2: the settings, models, tokens and authentication.
2. Phase 3: `POST /v1/auth/anonymous`.
3. **Stop and validate:** T021–T023 pass, and quickstart A2-1 to A2-4 work. Every phone can get an
   account, which is what B03 builds on.

### Incremental delivery (still one PR)

1. US2: sessions survive and can't be forked. This is needed before any real player depends on a
   session.
2. US3, then US4: linking, then safe conflicts.
3. US5: the admin view, at any point after Phase 2.
4. Phase 8: the docs, the review, the thorough property run, and the owner's live checks.

The PR merges only with all of it, because staging deploys from `master` and the session rules
are security-relevant.

---

## Notes

- `[P]` tasks touch different files and depend on no unfinished task.
- Every task names the spec FR, contract or research section it serves. Read that section before
  starting.
- Never log or store a raw install id, a token, a Google subject (outside `Identity.subject`), or
  anything else from a Google token (FR-023, FR-037).
- Commit after each task or logical group, with Conventional Commits (`feat(accounts): …`,
  `test(accounts): …`).
