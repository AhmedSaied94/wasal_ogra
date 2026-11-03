---

description: "Task list for B07 Ads: AdMob SSV callback, reward polling and caps"
---

# Tasks: Ads — AdMob SSV Callback, Reward Polling and Caps (B07)

**Input**: Design documents from `specs/017-b07-ads-ssv/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- **Mandatory, and first.** Constitution XIII: webhook verification and ledger writers are
  test-first. Every phase writes its tests first, and they must fail before its implementation
  tasks start.
- **Real services.** PostgreSQL and Valkey from the dev stack, never database mocks. Time moves with
  `time-machine`. Google's key list is the one thing replaced: the `admob_keys` fixture serves a
  session-generated P-256 public key from a local HTTP server (the pattern of B02's `google_jwks` in
  `backend/apps/accounts/tests/conftest.py`).
- **Coverage.** At least 80% for the backend (CI gate), and 100% of lines in
  `backend/apps/ads/services/`.

**Organization**:

- **Paths** are from the repository root. Run `uv` commands in `backend/`.
- **One PR.** Phases 3–6 follow the spec's user stories in priority order.
- **Owner tasks** need the owner's consoles or hosts. An agent can't do them alone.
- **Constraints are quoted** from `data-model.md` and the contracts. Do not loosen them.
- **Amounts**: the piggy's defaults are the spec's FR-019 (30 JENEHAT, 2 BONAT), not a board's
  sample; no other price or name from the pack is involved.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US4 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the app, its environment variables and the new error code (plan "Project Structure",
research R2, R3, contracts/environment.md).

- [X] T001 Create the app skeleton `backend/apps/ads/` (`__init__.py`, `apps.py` with label `ads`,
  empty `models.py`, `services/__init__.py`, `api/__init__.py`, `tests/__init__.py`,
  `tests/fixtures/`, `migrations/__init__.py`) and add `"apps.ads"` to `INSTALLED_APPS` in
  `backend/config/settings/base.py` after `"apps.economy"`, with the comment "`ads` imports
  `economy` and `liveops`; `economy` imports only `ads.models` and `ads.services.status`, which
  never import `economy` (B07 plan, boundaries)".
- [X] T002 [P] Add the four variables of contracts/environment.md to `backend/config/env.py` and
  `backend/config/settings/base.py`: `ADS_VERIFIER_KEYS_URL` (default
  `https://www.gstatic.com/admob/reward/verifier-keys.json`; "Must be `https` outside dev and test
  (the settings check refuses `http`)"), `ADS_KEYS_CACHE_SECONDS` (default `86400`, range
  60–604 800), `ADS_HTTP_TIMEOUT_SECONDS` (default `5`, range 1–30) and `THROTTLE_SSV_RATE`
  (default `600/min`, DRF rate string, added to `DEFAULT_THROTTLE_RATES` as scope `ssv`). List them
  in `backend/.env.example` and `backend/docker/env/{prod,staging}.env` (defaults), and in
  `specs/002-b01-backend-skeleton/contracts/environment.md`. Extend `backend/tests/test_env.py` with
  the ranges and the `http` refusal outside dev and test.
- [X] T003 [P] Add the `docs/architecture-backend.md` §6.2 row first (B01's rule): `403
  signature_invalid`, "A webhook's signature is missing or doesn't verify". Then add
  `SIGNATURE_INVALID = "signature_invalid"` to `ErrorCode`, `MESSAGES` ("Signature invalid") and
  `STATUSES` (403) in `backend/apps/common/errors.py`, with a case in
  `backend/apps/common/tests/test_errors.py` that the code renders the envelope with 403.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the reward table, signature verification against Google's keys, the test signing
tools and the three live settings. Every story needs them.

### Tests (write first, they must fail)

- [X] T004 [P] Write `backend/apps/ads/tests/conftest.py`: a session-scoped P-256 private key; an
  `admob_keys` fixture that serves `{"keys": [{"keyId": <int>, "pem": "<PEM>", "base64":
  "<base64 DER>"}]}` from a `ThreadingHTTPServer` on 127.0.0.1, sets `settings.ADS_VERIFIER_KEYS_URL`,
  can rotate keys, fail (500), return garbage, and count fetches, and calls `keys.reset()` on
  teardown; and a `backend/apps/ads/tests/signing.py` helper `signed_query(**params) -> (query,
  nonce)` that builds AdMob's parameter order (`ad_network`, `ad_unit`, `custom_data`,
  `reward_amount`, `reward_item`, `timestamp`, `transaction_id`, `user_id`, then `signature`,
  `key_id`), with `custom_data` URL-encoded compact JSON `{"placement":"morning_piggy","nonce":
  "<uuid4>"}` by default, and signs everything before `&signature=` with ECDSA SHA-256, DER,
  URL-safe base64 without padding.
- [X] T005 [P] Write `backend/apps/ads/tests/test_verify.py` for `apps.ads.services.ssv.verify(raw_query)`
  (research R1): a signed query verifies; changing any byte before `&signature=` fails; no
  `signature`, no `key_id`, a non-integer `key_id`, a signature that isn't base64, and any parameter
  after `key_id` each fail; padded and unpadded signatures both verify; `+` versus `%20` in
  `custom_data` is verified as sent (re-encoding would break it); a key id the server doesn't hold
  triggers one refetch, then fails if still unknown.
- [X] T006 [P] Write `backend/apps/ads/tests/test_keys.py` for `apps.ads.services.keys` (research R2,
  FR-003, FR-004): keys are fetched once and held `ADS_KEYS_CACHE_SECONDS`; an unknown key id
  refetches at most once per 60 s (`REFRESH_COOLDOWN_SECONDS`), counted by the fixture; after a
  failed fetch (500, timeout, not JSON, no `keys`, a bad PEM) the next 15 s raise
  `KeysUnavailable` without fetching; keys already held keep verifying while the source fails.
- [X] T007 [P] Write `backend/apps/ads/tests/test_models.py` for `AdReward` (data-model.md): a second
  row with the same `transaction_id` raises `IntegrityError` ("unique(`transaction_id`)"); two rows
  with the same non-null `nonce` raise, two with `nonce = NULL` don't ("unique(`nonce`) where `nonce
  IS NOT NULL`"); a non-granted row with `jenehat` or `bonat` > 0 is refused
  (`ad_reward_amounts_only_when_granted`); a granted row without a player is refused
  (`ad_reward_granted_has_player`); `shown_at` on a non-granted row is refused
  (`ad_reward_shown_only_when_granted`); the queryset's `update()` accepts only `shown_at`, its
  `delete()` refuses when any selected row is `granted`, and `save()` on an existing row refuses
  changes to any field but `shown_at`.
- [X] T008 [P] Extend `backend/apps/liveops/tests/test_registry.py` (and the parity test B10 added
  for `tunables.json`) with the three keys of data-model.md "Live settings":
  `ads_morning_piggy_daily_cap` int, default 1, range 0–10, `applied_by: both`, equal to
  `tunables.json`; `ads_morning_piggy_jenehat` int, default 30, range 0–10 000, server;
  `ads_morning_piggy_bonat` int, default 2, range 0–100, server; and the rule
  `morning_piggy_gives_something` refusing both amounts at 0 with "The morning piggy must give
  something." while accepting either alone at 0.

### Implementation

- [X] T009 Write `AdReward` and `AdRewardQuerySet` in `backend/apps/ads/models.py` exactly as
  data-model.md: `UUIDv7Model`; `transaction_id` `CharField(128)` unique; `player` FK
  `accounts.Player`, null, `PROTECT`, `related_name="ad_rewards"`; `placement` `CharField(32)`,
  blank; `nonce` `UUIDField`, null; `custom_data` `CharField(512)`, blank; `ad_network`
  `CharField(32)`, blank; `ad_unit` `CharField(64)`, blank; `reward_amount` `IntegerField`;
  `reward_item` `CharField(64)`, blank; `key_id` `BigIntegerField`; `callback_at` `DateTimeField`,
  null; `outcome` `CharField(24)` with choices `granted`, `duplicate_reference`, `cap_reached`,
  `not_server_placement`, `malformed`, `expired`, `unattributed`; `jenehat` and `bonat`
  `PositiveIntegerField` default 0; `game_date` `DateField`; `created_at` `DateTimeField`;
  `shown_at` `DateTimeField`, null; the five constraints and the three partial indexes
  (`ad_reward_daily_cap`, `ad_reward_unseen`, `ad_reward_prune`) with the names in data-model.md.
  Generate `backend/apps/ads/migrations/0001_initial.py`. Make T007 pass.
- [X] T010 Write `backend/apps/ads/services/keys.py` (research R2): `KeysUnavailable`;
  `public_key(key_id: int) -> EllipticCurvePublicKey | None` holding one key set per process for
  `ADS_KEYS_CACHE_SECONDS`, refetching on an unknown id at most once per
  `REFRESH_COOLDOWN_SECONDS = 60`, failing fast for `FAILED_FETCH_SECONDS = 15` after a failed fetch,
  fetching with `requests.get(..., timeout=ADS_HTTP_TIMEOUT_SECONDS)` and `load_pem_public_key`;
  `reset()` for tests. Model the shape and docstrings on `backend/apps/accounts/services/google.py`.
  Make T006 pass.
- [X] T011 Write `verify(raw_query: str) -> VerifiedQuery` in `backend/apps/ads/services/ssv.py`
  (research R1): split at the last `&signature=`; require the remainder to be exactly
  `signature=<sig>&key_id=<int>`; pad and URL-safe-base64-decode the signature; verify ECDSA
  SHA-256 with `keys.public_key`; raise `SignatureInvalid` for every failure and let
  `KeysUnavailable` through; parse the signed part with `urllib.parse.parse_qs` only after it
  verifies. Make T005 pass.
- [X] T012 [P] Add the three keys and the rule to `backend/apps/liveops/registry.py` (R10): the cap
  beside `ads_fuel_refill_daily_cap` with `applied_by=BOTH`, `meaning="Morning piggy ads per game
  day"`; the two amounts in the server-only block with meanings "Morning piggy JENEHAT" and "Morning
  piggy BONAT"; the `Rule`. Add `"ads_morning_piggy_daily_cap": 1` to
  `apps/mobile/assets/config/tunables.json` next to `ads_fuel_refill_daily_cap`. Make T008 pass.

**Checkpoint**: a signed query verifies, the table exists, the settings are live.

---

## Phase 3: User Story 1 - The morning piggy pays out after the ad (Priority: P1) 🎯 MVP

**Goal**: a validly signed piggy callback grants once; the app can ask for the result; bootstrap
says whether the piggy is available and lists unshown rewards; the app can mark one shown.

**Independent Test**: spec US1: a signed callback for a known player and a fresh reference → the
lookup answers `granted` with 30/2 and the wallet; ledger and wallet agree.

### Tests for User Story 1 (write first, they must fail)

- [X] T013 [P] [US1] Write `backend/apps/ads/tests/test_grant.py` (US1 AS1, FR-008, FR-009, FR-011,
  FR-012): a signed piggy callback for an active player answers `200 {}`; the player gets exactly
  one `LedgerEntry` per currency with `reason = ssv_grant`, `source = ssv`, `ref_type = "ad_reward"`,
  `ref_id = <AdReward.id>`, deltas 30 and 2; `state_version` moves by one; the `AdReward` row has
  `outcome = granted`, `jenehat = 30`, `bonat = 2`, `game_date` = Cairo's date at processing time;
  `reward_amount = 999` in the callback changes nothing; with the BONAT setting at 0 only the
  JENEHAT entry is written (the ledger refuses a 0 delta); `economy_check` finds no mismatch; a
  player with no wallet yet gets one created.
- [X] T014 [P] [US1] Write `backend/apps/ads/tests/test_ssv_api.py` (contracts/api.md, R3): the view
  needs no token and no `X-Client-Version`/`X-Platform`, answers with an outdated version header
  absent, and answers while maintenance is on (`maintenance_enabled = true`) with a grant; a
  validly signed callback is `200 {}` whatever the outcome; the body never differs by outcome.
- [X] T015 [P] [US1] Write `backend/apps/ads/tests/test_rewards_api.py` (US1 AS2–AS3, FR-014–FR-016,
  R9): `GET /v1/ads/rewards/{nonce}` as the owner of a granted reward → 200 `{"status": "granted",
  "jenehat": 30, "bonat": 2, "granted_at", "wallet"}` where `wallet` equals B03's
  `wallets.answer` recounted to now; a `cap_reached`, `not_server_placement` or `expired` row →
  200 `{"status": "refused", "reason": ...}`; unknown reference, another player's, an unattributed
  row's, and a non-UUID path → 404 `not_found`, identical bodies; it needs the player defaults
  (401 without a token); it writes nothing (assert no query other than SELECT with
  `CaptureQueriesContext`).
- [X] T016 [P] [US1] Extend `backend/apps/economy/tests/test_bootstrap.py` (US1 AS4–AS6, FR-017, R8):
  the required `ads.morning_piggy` block; `available` true with no grant today, false after one, true
  again the next Cairo game day (time-machine across midnight), true with cap 2 after one grant;
  `unseen` lists granted rewards with no `shown_at`, newest first, at most 5, each `{nonce, jenehat,
  bonat, granted_at}`; refused rows never appear; bootstrap's query count grows by at most 2.
  Also write `backend/apps/ads/tests/test_boundaries.py` (plan "Architecture boundaries",
  analysis I1): an AST scan fails if `apps/ads/models.py` or `apps/ads/services/status.py` imports
  anything under `apps.economy`, and if any `apps/economy` module imports an `apps.ads` module other
  than those two.
- [X] T017 [P] [US1] Write `backend/apps/economy/tests/test_op_ad_reward_seen.py` (FR-017a, R7):
  `ad_reward_seen` with the player's granted unseen reference → accepted, `grants: []`, `shown_at`
  set, `state_version` unchanged, bootstrap no longer lists it; again with the same reference (new
  `client_txn_id`) → accepted, no change; a replay of the same `client_txn_id` returns the stored
  result; another player's reference, a refused row's, and an unknown one → accepted, nothing
  changed; a missing or non-UUID `nonce` → `validation_error` as for every op payload.

### Implementation for User Story 1

- [X] T018 [US1] Write `process(raw_query: str, *, now) -> Outcome` in
  `backend/apps/ads/services/ssv.py` (research R4–R6) for the grant path and its order: verify;
  parse `custom_data` (JSON object with `placement` str and `nonce` UUID), `user_id`, `timestamp`
  (ms); in `transaction.atomic()`: an existing `transaction_id` → duplicate (no row); otherwise
  decide in data-model.md's "Outcome decision order" (`expired` → `malformed` → `unattributed` →
  `not_server_placement` → `ledger.lock_wallet(player)` → `duplicate_reference` → `cap_reached` →
  `granted`), read the cap and the amounts from one `apps.liveops.settings.current()` snapshot,
  write one `ledger.apply_now` per non-zero amount (`reason=LedgerEntry.Reason.SSV_GRANT`,
  `source=LedgerEntry.Source.SSV`, `ref_type="ad_reward"`, `ref_id=str(reward_id)`), move
  `state_version` by one (as `apps/economy/services/adjustments.py` does), and create the row with
  a pre-generated `uuid7()` id; catch `IntegrityError` on `transaction_id` inside a savepoint and
  answer duplicate. Store `nonce` NULL for `duplicate_reference` and `malformed` (research R5).
  Make T013 pass.
- [X] T019 [US1] Write `SsvView` and the throttle in `backend/apps/ads/api/views.py` and
  `backend/apps/ads/throttles.py` (R3): `authentication_classes = []`, `permission_classes = []`,
  `throttle_classes = [SsvThrottle]` (per `address_bucket(client_ip(request))`, scope `ssv`,
  rate setting `THROTTLE_SSV_RATE`); pass `request.META["QUERY_STRING"]` to `ssv.process`; map
  `SignatureInvalid` → `ApiError(ErrorCode.SIGNATURE_INVALID)`, `KeysUnavailable` →
  `ApiError(ErrorCode.DEPENDENCY_UNAVAILABLE)`, anything else → `Response({})`. Add
  `path("v1/ads/ssv", ...)` (name `ads-ssv`) to `backend/config/urls.py` with
  `extend_schema` describing every query parameter and the 200/403/429/503 answers. Make T014 pass.
- [X] T020 [US1] Write `backend/apps/ads/services/rewards.py`, `backend/apps/ads/services/status.py`
  and `RewardView` (R8, R9): `rewards.lookup(player, nonce) -> dict | None` (only rows of that
  player with a non-null `nonce`; the wallet from `economy.services.wallets.answer`);
  `status.piggy_block(player, game_date, cap) -> dict`, importing only `apps.ads.models`, with
  `available` (granted count on `game_date` below `cap`) and `unseen` (`UNSEEN_LIMIT = 5`, newest
  first);
  `RewardView` at `path("v1/ads/rewards/<str:nonce>", ...)` (name `ads-reward`) with the player
  defaults, 404 `not_found` for `None` or a non-UUID; serializers in
  `backend/apps/ads/api/serializers.py`. Make T015 pass.
- [X] T021 [US1] Add the `ads` block to `backend/apps/economy/services/bootstrap.py` (`"ads":
  {"morning_piggy": status.piggy_block(player, game_date(now), snapshot["ads_morning_piggy_daily_cap"])}`,
  outside the wallet lock, reusing the game day and the snapshot bootstrap already has) and to its
  serializer/schema in `backend/apps/economy/api/serializers.py` and `schema.py` as a required
  field. Make T016 (both files) pass.
- [X] T022 [US1] Add the `ad_reward_seen` operation (R7): in `backend/apps/economy/services/batch.py`
  `_unseen_rewards: set[UUID] | None` (lazy: the player's granted references with `shown_at IS
  NULL`), `_seen_new: set[UUID]`, `mark_reward_seen(nonce) -> bool` (never `_touch()`, so not a
  mutation), and `_flush_seen()` called from `flush()` running one `AdReward.objects.filter(player=…,
  nonce__in=…, shown_at__isnull=True).update(shown_at=self.now)`; in
  `backend/apps/economy/services/ops/ads.py` `@register("ad_reward_seen", payload={"nonce":
  Field(UUID)})` returning `[]` after `state.mark_reward_seen`. Keep the handler free of the ORM
  (`test_balance_writers.py` checks). Make T017 pass.

**Checkpoint**: quickstart §2 works on the dev stack.

---

## Phase 4: User Story 2 - Forged, repeated or extra callbacks grant nothing (Priority: P1)

**Goal**: every refusal path of FR-002–FR-010 and FR-006a, the logging rules, and the operator
alert.

**Independent Test**: spec US2: duplicate, tampered, unknown-key and second-same-day callbacks →
one grant, two ledger entries, each request answered as contracts/api.md says.

### Tests for User Story 2 (write first, they must fail)

- [X] T023 [P] [US2] Write `backend/apps/ads/tests/test_refusals.py` (US2 AS1–AS7, FR-005, FR-006,
  FR-006a, FR-008, FR-010), one case each, asserting the answer, the row (or its absence) and no
  ledger entry: tampered, unsigned, unknown key → 403 `signature_invalid`, no row; the same
  callback twice → 200, one row, one grant; a second transaction id the same game day → 200,
  `cap_reached`, lookup says refused; a reused reference with a new transaction id → 200, row
  `duplicate_reference` with `nonce` NULL, the lookup still finds the first row; `user_id` empty,
  unknown, pending deletion and deleted → 200, `unattributed`, `player` NULL; placement
  `result_double` → 200, `not_server_placement`; `custom_data` missing, not JSON, not an object,
  or a non-UUID nonce → 200, `malformed`; `timestamp` 7 days + 1 ms old → 200, `expired`, and
  exactly 7 days old → granted; keys unavailable → 503 `dependency_unavailable`, no row. Malformed
  input never answers 5xx (data-model.md "Malformed input is stored, never rejected by the
  database"; analysis U1, U2): `timestamp` missing or `abc` → 200, `malformed`, `callback_at`
  NULL (not `expired`); `reward_amount` `1.5` → 200, `malformed`, `reward_amount` 0; `custom_data`
  of 600 characters, `ad_unit` and `reward_item` of 100, `ad_network` of 50 → 200, `malformed`,
  stored cut to 512, 64, 64 and 32; no `transaction_id`, or one of 129 characters → 200, no row,
  one `apps.ads` log line with outcome `malformed`.
- [X] T024 [P] [US2] Write `backend/apps/ads/tests/test_concurrency.py` (spec edge case, R4) with two
  threads on real PostgreSQL (`transaction=True`): the same transaction id delivered twice at once
  → one row, one grant, both answered 200; two transaction ids for one player at once with cap 1
  → one `granted`, one `cap_reached`.
- [X] T025 [P] [US2] Write `backend/apps/ads/tests/test_alerts.py` (FR-007, R11, SC-007): 20 refused
  signatures within an hour send no Sentry event, the 21st sends exactly one with level
  `warning` and the ads fingerprint, the 40th sends none (once an hour), and an hour later the
  window restarts; a key fetch failure sends one event under its own guard; use a Sentry transport
  stub and the real Valkey cache.
- [X] T026 [P] [US2] Write `backend/apps/ads/tests/test_logging.py` and extend
  `backend/apps/economy/tests/test_privacy_scan.py` to `apps/ads` (FR-007, R13): every callback logs
  one `apps.ads` line with `outcome`, `key_id`, `ad_unit`, `reward_item` and a 12-character SHA-256
  prefix of the transaction id; no log record, and no Sentry event, contains the `user_id`, the
  reference or the raw query.
- [X] T027 [P] [US2] Write `backend/apps/ads/tests/test_properties.py` (SC-002) with hypothesis: random
  sequences of signed callbacks over 3 players (repeats, new transaction ids, reused references,
  unknown players, clock moves across Cairo midnight) keep `wallet == sum(ledger)` per currency,
  at most `ads_morning_piggy_daily_cap` grants per player per game day, and the same final state
  when the whole sequence is replayed.

### Implementation for User Story 2

- [X] T028 [US2] Complete the refusal branches in `backend/apps/ads/services/ssv.py` so T023, T024 and
  T027 pass: `EXPIRY_DAYS = 7` against a parsed `callback_at`; `Player.is_active` for attribution;
  the placement check; every parsing failure (`custom_data`, `timestamp`, `reward_amount`, an
  over-long field) as `malformed`, with text cut to its column length, `reward_amount` 0 and
  `callback_at` NULL as data-model.md says; no usable `transaction_id` answered 200, logged
  `malformed` and not recorded; the savepoint race.
- [X] T029 [US2] Write `backend/apps/ads/services/alerts.py` (R11): `signature_refused()` increments
  the current 5-minute bucket key (`cache.incr`, 2-hour expiry) and, when the sum of the last 12
  buckets passes `ALERT_SIGNATURE_THRESHOLD = 20`, calls `sentry_sdk.capture_message("AdMob SSV:
  refused signatures", level="warning", fingerprint=["ads", "ssv-signature"])` guarded by
  `cache.add("ads:alert:signature", 1, ALERT_WINDOW_SECONDS)`; `keys_unavailable()` does the same
  with "AdMob SSV: verifier keys unavailable" and its own guard. Call them from the view's error
  mapping. Make T025 pass.
- [X] T030 [US2] Add the per-callback log line in `backend/apps/ads/services/ssv.py` (logger
  `apps.ads`, R13) and nothing else that names the player. Make T026 pass.

**Checkpoint**: quickstart §3 and §5 hold.

---

## Phase 5: User Story 3 - The operator sizes the piggy and the caps without a release (Priority: P2)

**Goal**: the live settings apply within a minute; staff see every reward read-only; refused records
are cleaned after 90 days.

**Independent Test**: spec US3: change the BONAT amount → the next callback grants it; cap 0 →
`cap_reached`; the admin list filters and can't edit.

### Tests for User Story 3 (write first, they must fail)

- [X] T031 [P] [US3] Write `backend/apps/ads/tests/test_live_settings.py` (US3 AS1, SC-004): change
  `ads_morning_piggy_bonat` to 5 through `apps.liveops.services.settings_admin` and, after the
  snapshot's refresh (time-machine past `LIVEOPS_REFRESH_SECONDS`), the next grant is 5 BONAT; cap
  0 → `cap_reached`; a callback reads one snapshot (patched counter as in B10's
  `test_a_batch_reads_one_snapshot`).
- [X] T032 [P] [US3] Write `backend/apps/ads/tests/test_admin.py` (US3 AS3, FR-023,
  contracts/admin.md): a `live_ops` and an `economy_ops` member can open the list and a detail,
  filter by placement, outcome and game day, and search by exact player id and transaction id; no
  user, superuser included, gets the add, change or delete pages (403) or a delete action; a
  `content_author` and a `player_support` member get 403; the detail links the grant's ledger
  entries; the player page links to the player's rewards.
- [X] T033 [P] [US3] Write `backend/apps/ads/tests/test_prune.py` (FR-006, FR-024, R12): rows that
  granted nothing older than 90 days are deleted, younger ones and every `granted` row stay; with
  maintenance on, the task deletes nothing and logs `task_skipped_maintenance`; the
  `PeriodicTask` exists at 04:30 `Africa/Cairo` and B10's scheduled-jobs test sees it wrapped.

### Implementation for User Story 3

- [X] T034 [US3] Write `backend/apps/ads/admin.py` (`AdRewardAdmin`, read-only:
  `has_add_permission`, `has_change_permission` and `has_delete_permission` return False; list
  columns, filters, date hierarchy and exact searches of contracts/admin.md; links to the ledger
  entries by `ref_type`/`ref_id`), add the "Ad rewards" link and today's piggy status to
  `backend/apps/economy/player_page.py`, and write
  `backend/apps/ads/migrations/0002_view_permissions.py` granting `view_adreward` to `live_ops` and
  `economy_ops` (reversible). Make T032 pass.
- [X] T035 [US3] Write `backend/apps/ads/tasks.py` `prune_ad_rewards` (Celery, `bind=True`, wrapped in
  `liveops.tasks.skip_in_maintenance`, `RETENTION_DAYS = 90`, batches of 5 000 by `id`) and
  `backend/apps/ads/migrations/0003_prune_schedule.py` creating the `PeriodicTask` at 04:30
  `Africa/Cairo` (pattern of `backend/apps/liveops/migrations/0006_offer_schedule.py`). Make T033
  pass.
- [X] T036 [US3] Confirm T031 passes with no code beyond T012 and T018; if it doesn't, fix
  `ssv.process` to read the snapshot once per callback.

**Checkpoint**: quickstart §4 holds; the admin shows the rows of §3.

---

## Phase 6: User Story 4 - Every placement's caps hold on the server (Priority: P2)

**Goal**: one test per placement in glossary §3.4 drives it one past its cap (FR-020–FR-022).

**Independent Test**: `uv run pytest apps/ads/tests/test_placement_caps.py`.

### Tests for User Story 4 (write first, they must fail)

- [X] T037 [US4] Write `backend/apps/ads/tests/test_placement_caps.py` (R15), parametrized:
  `result_double` (second for the same result → `already_doubled`), `trip_revive` (second on one
  trip → `already_revived`), `traffic_jam` (one past `traffic_jam_ads_per_trip` at its default 1 and
  at 2 → `cap_reached`), `fuel_refill` (one past `ads_fuel_refill_daily_cap` at 3 and at 1 →
  `cap_reached`), all through `POST /v1/sync`; `morning_piggy` through the callback at cap 1 and 2;
  `ad_reward` with `morning_piggy` → `server_only`; no code path accepts
  `interstitial_between_trips` (the sync op answers `unknown_sku`, the callback
  `not_server_placement`).

### Implementation for User Story 4

- [X] T038 [US4] Fix whatever T037 finds in `backend/apps/economy/services/ops/ads.py` or
  `backend/apps/ads/services/ssv.py`; if nothing fails once written, record that in the PR (the
  test is the deliverable).

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T039 [P] Regenerate the contract: `uv run manage.py spectacular --file ../contracts/openapi.yaml
  --validate --fail-on-warn`; check it shows `GET /v1/ads/ssv` (no security), `GET
  /v1/ads/rewards/{nonce}`, the bootstrap `ads` block as required, `ad_reward_seen` in the sync op
  schema and `signature_invalid`; run schemathesis over it (`backend/tests/test_contract.py`
  covers new paths; for the callback, whose signature it can't make, accept 403 as a documented
  answer rather than excluding the path).
- [X] T040 [P] Update `docs/architecture-backend.md`: §6.3 (unchanged paths; note the throttle),
  §6.4 (the bootstrap `ads` block, the lookup's answers), §7.4 (`ad_reward_seen` row), §8.4 (the
  outcome order, 200/403/503, the 7-day expiry, the alerts, what is recorded), §11.2 (the cleanup
  job), §12 (`AdReward` fields as data-model.md; the link to the ledger is `ref_type`/`ref_id`, not a
  `ledger_entry` FK), §14.2 (the data inventory row for ad rewards: player id, kept with the ledger
  when granted, 90 days otherwise).
- [X] T041 [P] Update `docs/architecture-mobile.md`: §14.3 (add `ads_morning_piggy_daily_cap` = 1;
  correct the stale sentence that the backend keeps `fuel_max` … `ads_fuel_refill_daily_cap` as env
  settings: they are live settings since B10), §15.1 (`customData` as compact JSON, the lookup's 404
  meaning "not yet", the bootstrap block, `ad_reward_seen` after showing a reward).
- [X] T042 [P] Update `docs/runbooks/monitoring-setup.md` (the Sentry alert rule on fingerprint
  `ads`/`ssv-signature` and the keys alert) and add a "A player says the morning piggy didn't pay"
  entry to `docs/runbooks/economy.md` (find the row by player in the admin; outcomes and what each
  means; never grant by hand except through a staff adjustment with the reason).
- [X] T043 [P] Add a line under B10's Complexity Tracking entry in
  `specs/016-b10-catalog-offers/plan.md`: "B07 adds `ads_morning_piggy_jenehat` and
  `ads_morning_piggy_bonat` under this entry (specs/017-b07-ads-ssv/plan.md)."
- [X] T044 [P] Update `backend/CLAUDE.md`: B07 in "What's built", the four environment variables,
  the `admob_keys` fixture and `signing.py` helper; add 017 B07 to the features list in the root
  `CLAUDE.md`.
- [X] T045 [P] Update `docs/delivery-plan.md`: add research's "Handed to later features" to the M11,
  B09 and M15 entries, and tick `017-b07-ads-ssv` in Progress after merge.
- [X] T046 Add B07's section to `docs/owner-actions.md` and keep "Open now" current (T053–T056).
- [X] T047 Run the full gates in `backend/`: `uv run ruff check . && uv run ruff format --check .`,
  `uv run mypy .`, `uv run manage.py makemigrations --check --dry-run`,
  `uv run pytest -n 4 --cov --cov-fail-under=80`, the OpenAPI drift check, and confirm 100% line
  coverage of `apps/ads/services/`. Fix what fails.
- [X] T048 Run the thorough property passes once (the economy is touched):
  `HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py
  apps/ads/tests/test_properties.py`; record the result in the PR.
- [X] T049 Security review: run the **security-reviewer** agent over `apps/ads`, the `economy` edits
  (bootstrap, batch, the op) and the URL and throttle settings. Fix every CRITICAL and HIGH finding.
  Cover at least: verification on the raw query and before any database access, trailing
  parameters, replay (unique id, 7-day expiry after cleanup), the cap under concurrency, that the
  lookup and the 200 body reveal nothing, the key fetch's timeout and fast-fail, the logs, and that
  `ads_dev_callback` and the `file://` key URL can't run outside dev and test.
- [X] T050 [P] Write `backend/apps/ads/tests/test_timing.py` (SC-005, plan "Performance Goals"),
  part of the normal suite (no marker: `--strict-markers` is on and none is registered): with the
  keys held, 100 signed callbacks for distinct players and 100 lookups through the test client on
  the real PostgreSQL and Valkey; assert the callback p95 < 1 s and the lookup p95 ≤ 100 ms, and
  print both so T047's run records them.
  After the staging deploy, T055 repeats the measurement there with real callbacks.
- [X] T051 Write the dev-only command `backend/apps/ads/management/commands/ads_dev_callback.py`
  (plan "Structure Decision", analysis C2): it refuses to run unless the environment is `dev` or
  `test`; on first use it creates a P-256 key at `backend/.dev/admob_dev_key.pem` and writes
  `backend/.dev/admob_verifier_keys.json` in AdMob's key-list shape; it reuses
  `apps/ads/tests/signing.py`'s signing (move it to `apps/ads/services/dev_signing.py` if the
  command can't import test code); options `--user <player_id>`, `--placement`, `--nonce`,
  `--transaction-id`, `--age-days`, `--tamper`, `--api <url>` (default `http://localhost:8000`);
  it prints the reference and the API's status and body. Teach `apps/ads/services/keys.py` to read
  a `file://` URL only in dev and test, and the settings check to refuse `file://` (and `http://`)
  elsewhere. Add `backend/.dev/` to `.gitignore`, and
  `ADS_VERIFIER_KEYS_URL=file:///app/.dev/admob_verifier_keys.json` to `backend/.env.example`'s dev
  block. Tests: the command refuses outside dev and test, and in test it produces a callback the
  view grants.
- [X] T052 Walk quickstart §1–§5 end to end on a clean dev stack with `ads_dev_callback`, and fix any
  step that doesn't match, in the document or the code.
- [ ] T053 **Owner, before the deploy.** In the Firebase console, add the Remote Config parameter
  `ads_morning_piggy_daily_cap` with default `1` to both projects (otherwise B10's drift check
  alerts). (The Complexity Tracking entry was approved on 2026-11-03, before implementation.)
- [ ] T054 **Owner, after merge.** In Sentry, add an alert rule that emails on the fingerprints
  `ads`/`ssv-signature` and `ads`/`ssv-keys` for both environments.
- [ ] T055 **Owner, after the staging deploy.** In the AdMob console, set the SSV callback URL
  `https://api-staging.<domain>/v1/ads/ssv` on the morning piggy's rewarded ad unit only and press
  **Verify URL**: the console reports success and the admin shows an `unattributed` row. With a
  build that shows the piggy ad, watch it on the test phone and check SC-003 (reward within 7 s, 9
  of 10), and note the callback's server time from the access log for SC-005. Copy one real callback's query and that day's key list into
  `backend/apps/ads/tests/fixtures/real_callback.json` (the agent adds the test that verifies it).
- [ ] T056 **Owner, before M11's release.** Set the production callback URL
  `https://api.<domain>/v1/ads/ssv` on the production piggy ad unit and press **Verify URL**.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)** → **Foundational (Phase 2)** → the stories.
- **US1 (Phase 3)** needs Phase 2. It is the MVP.
- **US2 (Phase 4)** needs T018 and T019 (the processing path and the view).
- **US3 (Phase 5)** needs T009 and T018; T034 and T035 can start after T009.
- **US4 (Phase 6)** needs T018 and T019.
- **Polish (Phase 7)** needs everything it documents; T055's fixture test follows the owner's copy.

### Within phases

- Tests first, failing, then models, services, views and admin.
- Migrations in `backend/apps/ads/migrations/` are numbered in the order written above.

### Parallel opportunities

- T002 and T003 in Setup.
- T004–T008 (foundational tests) together; T012 beside T009–T011.
- Each story's test tasks together (T013–T017; T023–T027; T031–T033).
- US3's admin and prune work (T034, T035) beside US2 once T009 exists.
- T039–T045 and T050 in Polish; T051 before T052.

---

## Parallel Example: Foundational tests

```text
Task: "T004 conftest.py + signing.py"
Task: "T005 test_verify.py"
Task: "T006 test_keys.py"
Task: "T007 test_models.py"
Task: "T008 registry tests"
```

## Parallel Example: User Story 2 tests

```text
Task: "T023 test_refusals.py"
Task: "T024 test_concurrency.py"
Task: "T025 test_alerts.py"
Task: "T026 test_logging.py + privacy scan"
Task: "T027 test_properties.py"
```

---

## Implementation Strategy

### MVP first (User Story 1)

1. Phases 1–2, then US1.
2. Stop and check: quickstart §2 works and `economy_check` is clean.

### Incremental delivery (still one PR)

1. US2 (the refusals are what make the endpoint safe to expose; never deploy US1 without it).
2. US3 (settings, admin, cleanup), then US4 (the cap guarantee).
3. Polish, the review, then the owner tasks.

## Notes

- [P] tasks touch different files and depend on nothing incomplete.
- Commit after each task or logical group.
- Every balance change goes through `apps.economy.services.ledger`; the AST scan must stay green.
