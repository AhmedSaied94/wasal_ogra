# Research: Ads — AdMob SSV Callback, Reward Polling and Caps (B07)

Decisions behind [plan.md](./plan.md). Each one: the decision, why, and what else was weighed.
Spec references are to [spec.md](./spec.md).

## R1. Verifying the callback's signature

- **Decision:** verify on the raw query string, never on re-parsed parameters. The signed message
  is `request.META["QUERY_STRING"]` up to, not including, `&signature=`; `signature` and `key_id`
  are AdMob's last two parameters, and anything after `key_id` makes the callback invalid. The
  signature is ECDSA P-256 with SHA-256, DER-encoded, in URL-safe base64 without padding (pad
  before decoding). The public keys come from Google's AdMob verifier key list (default
  `https://www.gstatic.com/admob/reward/verifier-keys.json`, shape
  `{"keys": [{"keyId": <int>, "pem": "-----BEGIN PUBLIC KEY-----…", "base64": "…"}]}`), loaded with
  `cryptography`'s `load_pem_public_key`. `key_id` is an integer; a non-integer is an invalid
  callback.
- **Why:** re-encoding parsed values changes bytes (`+` versus `%20`, parameter order), and the
  signature covers bytes. `cryptography` is already installed through `PyJWT[crypto]`, so there is
  no new package (backend §2 lists PyJWT + cryptography for exactly this).
- **Alternatives:** Google's Tink library (the reference verifier is Java, and Python Tink is a
  large native dependency for one check); verifying on `request.GET` (breaks on encoding).
- **To confirm during implementation:** the key list URL and shape against Google's current AdMob
  SSV page, and one real callback recorded from staging (owner action, quickstart step 6) kept as a
  fixture with the key set of that day.

## R2. Holding Google's keys

- **Decision:** `apps/ads/services/keys.py`, one key set per process, modelled on B02's
  `accounts/services/google.py`: kept `ADS_KEYS_CACHE_SECONDS` (86 400); an unknown `key_id`
  refetches at most once per `REFRESH_COOLDOWN_SECONDS` (60, FR-003); after a failed fetch the
  process answers 503 at once for 15 s instead of holding a worker on the timeout; keys already
  held keep serving during an outage. HTTP through `requests` with `ADS_HTTP_TIMEOUT_SECONDS` (5).
- **Why:** the callback is rare (one per player a day), each gunicorn worker refetching once a day
  is negligible, and B02's shape already passed review for the same failure modes. A per-process
  cache needs no Valkey round trip on the request path.
- **Alternatives:** a shared key set in Valkey (one more dependency on the path for no gain at this
  volume); a Celery job that prefetches keys (a rotated key still needs the on-demand refetch).

## R3. The callback endpoint

- **Decision:** `GET /v1/ads/ssv` in a new `apps/ads` app (backend §5 already names it), a DRF
  `APIView` that opts out of every player default: no authentication, no `ClientHeaders`, no
  `CurrentClient` (AdMob sends no app version), and its own `SsvThrottle` per client address at
  `THROTTLE_SSV_RATE` (`600/min`) instead of the address limit (120/min), so a burst of real
  callbacks from Google's few addresses is never refused. Answers:
  - **200** `{}` for every validly signed callback (FR-005);
  - **403** `signature_invalid` for no signature, a bad signature, an unknown key after a refresh,
    or parameters after `key_id` (a new code in backend §6.2);
  - **503** `dependency_unavailable` when the keys can't be had (FR-004); nothing is recorded;
  - **429** `rate_limited` from the throttle; AdMob retries.
  Maintenance needs nothing: B10's `NotInMaintenance` passes safe methods, and the view lists no
  maintenance check (FR-024).
- **Why:** a webhook has no player and no app headers; refusing it with 426 or 401 would lose real
  rewards. B10's default permissions are per view, so opting out is explicit and visible in review.
- **Alternatives:** a plain Django view (loses the error envelope and drf-spectacular's schema);
  POST (AdMob only calls with GET).

## R4. One transaction per callback

- **Decision:** `apps/ads/services/ssv.py` `process(query) -> Outcome`:
  1. verify (R1); refuse before touching the database;
  2. parse `custom_data` (JSON, `{"placement": str, "nonce": uuid}`), `user_id`, `timestamp`
     (milliseconds). A validly signed callback with no `transaction_id` (or one longer than 128
     characters) can't be keyed: it is answered 200, logged with outcome `malformed`, and not
     recorded. Any other field that is missing, unparseable (`timestamp`, `reward_amount`, `key_id`
     not integers) or longer than its column makes the outcome `malformed`: the row is written
     with the over-long text values cut to their column length (`custom_data` 512, `ad_unit` and
     `reward_item` 64, `ad_network` 32), `reward_amount` 0, `callback_at` NULL. So no signed input
     can raise a database error and make AdMob retry (analysis U1, U2). `expired` applies only to a
     parsed `timestamp`;
  3. in `transaction.atomic()`: if a row with this `transaction_id` exists, answer 200 (duplicate);
     otherwise decide the outcome in this order: `malformed` → `expired` (a parsed timestamp more than 7 days before now,
     FR-006a) → `unattributed` (no active player for `user_id`) →
     `not_server_placement` → for an attributed callback, `ledger.lock_wallet(player)` first, then
     `duplicate_reference` → `cap_reached` → `granted`;
  4. a grant writes one `ledger.apply_now` per non-zero amount (the ledger refuses a 0 delta),
     reason `ssv_grant`, source `ssv`, `ref_type="ad_reward"`, `ref_id=<reward id>`, moves
     `state_version` by one as `adjustments.adjust` does, and creates the `AdReward`;
  5. an `IntegrityError` on `transaction_id` (two deliveries at once) rolls back the savepoint and is
     answered as a duplicate; nothing was granted, because the grant and the row commit together.
- **Why:** the wallet lock is what serializes two grants for one player (spec edge case), and it is
  the same lock sync takes, so a callback and a sync batch never interleave on one wallet. Checking
  the cheap refusals before the lock keeps unattributed floods off player rows.
- **Alternatives:** a Celery task per callback (an extra hop for a fast write, and the 200 would
  have to be sent before the grant is known); a `DayCounter` kind for the cap (pruned at 40 days and
  owned by sync's batch state; counting `AdReward` rows needs no second table).

## R5. The reference (`nonce`) and its uniqueness

- **Decision:** `AdReward.nonce` is a nullable UUID with a partial unique constraint (`nonce IS NOT
  NULL`). A callback whose reference is already held is recorded with `nonce = NULL`, outcome
  `duplicate_reference`, and the reference kept in `custom_data` for staff. The lookup by reference
  therefore always finds the first callback's row.
- **Why:** FR-008 needs "a reference not used by any other recorded reward", and the lookup needs at
  most one row per reference. After the 90-day cleanup a refused row's reference is free again,
  which is harmless: the app makes a new one per ad.
- **Alternatives:** a unique reference on every row (the duplicate couldn't be recorded at all).

## R6. The game day and the daily cap

- **Decision:** the cap counts `AdReward` rows with outcome `granted`, placement `morning_piggy`, the
  player and `game_date = gameday.game_date(now)` (B03's `Africa/Cairo` helper), under the wallet
  lock, against `ads_morning_piggy_daily_cap` from the snapshot. `game_date` is stored on every row
  at processing time (FR-012).
- **Why:** server time is the authority for daily resets (constitution VI); AdMob's `timestamp` is
  only used for the 7-day expiry.

## R7. The "shown" confirmation as a sync operation

- **Decision:** a new sync operation `ad_reward_seen` with payload `{"nonce": uuid}`, registered in
  `apps/economy/services/ops/ads.py` beside `ad_reward`. It is always accepted with an empty result:
  it marks the player's granted, not-yet-shown reward with that reference, and does nothing for any
  other reference (FR-017a answers the same). `BatchState` gains a lazily loaded set of the player's
  unseen granted references, `mark_reward_seen(nonce)`, and a flush that sets `shown_at` with one
  `UPDATE … WHERE player = … AND nonce IN (…) AND shown_at IS NULL`. It does not count as a
  mutation, so `state_version` doesn't move and no other device is told its state is stale.
- **Why:** constitution VI requires a `client_txn_id` and `ProcessedOp` for every state-changing
  request; sync already gives both, works offline (the app queues it), and keeps handlers away from
  the ORM (B03 research R5, enforced by `test_balance_writers.py`).
- **Alternatives:** `POST /v1/ads/rewards/{nonce}/seen` (would need its own `client_txn_id` and
  `ProcessedOp` handling, duplicating sync); marking shown when the lookup answers "granted" (a GET
  that writes, and the app may never have drawn the card).

## R8. Bootstrap's `ads` block

- **Where it lives:** `apps/ads/services/status.py`, `piggy_block(player, game_date, cap)`, which
  imports only `ads.models`: bootstrap passes its own game day and the snapshot's cap, so `economy`
  never imports an `ads` module that imports `economy` (analysis I1).
- **Decision:** bootstrap gains a required `ads` object:
  `{"morning_piggy": {"available": bool, "unseen": [{"nonce", "jenehat", "bonat", "granted_at"}]}}`.
  `available` is today's granted count below the cap; `unseen` lists at most 5 granted rewards with
  `shown_at IS NULL`, newest first. Two indexed queries, outside the wallet lock.
- **Why:** HANDOFF row 6 shows the banner only when the piggy is available, and the late-reward card
  needs the amounts. The app ignores unknown fields, so older apps are unaffected.
- **Alternatives:** a separate `GET /v1/ads/status` (one more request at every launch).

## R9. The reward lookup

- **Decision:** `GET /v1/ads/rewards/{nonce}` with every player default (token, headers, per-player
  throttle). 200 `{"status": "granted", "jenehat", "bonat", "granted_at", "wallet"}` or
  `{"status": "refused", "reason"}` for a row with that reference and this player; **404
  `not_found`** otherwise (not yet arrived, another player's, unattributed, or never used). The
  wallet is B03's `wallets.answer`, recounted to now. A malformed reference (not a UUID) is also
  404. It never writes (FR-016).
- **Why:** "not known yet" is the normal case while polling, and 404 is what mobile §15.1's poll
  already expects; one answer for every not-yours case reveals nothing (FR-015).

## R10. Live settings

- **Decision:** three keys in `apps/liveops/registry.py`:
  - `ads_morning_piggy_daily_cap`: int, default 1, range 0–10, `applied_by: both` (FR-018). Added
    to `apps/mobile/assets/config/tunables.json` (1) and mobile §14.3; B10's parity test covers it.
  - `ads_morning_piggy_jenehat`: int, default 30, range 0–10 000, server.
  - `ads_morning_piggy_bonat`: int, default 2, range 0–100, server.
  - a cross-setting `Rule` over the two amounts: "The morning piggy must give something." (FR-013).
  `sync_registry_rows` creates the rows on migrate; no data migration.
- **Why:** constitution VIII and B10's hand-over. The amounts are server-only because the phone
  never applies them; it learns them from the lookup and bootstrap (IV).
- **Consequence:** a both-sides key needs its Remote Config key, or B10's daily drift check reports
  it to Sentry. Adding `ads_morning_piggy_daily_cap = 1` in the Firebase console is an owner action
  before the deploy (quickstart step 1).

## R11. Alerts on forged callbacks and key failures

- **Decision:** `apps/ads/services/alerts.py`. Each refused signature increments a Valkey counter in
  the current 5-minute bucket (`cache.incr`, 2-hour expiry); the rolling hour is the sum of the last
  12 buckets (`cache.get_many`). Passing 20 calls `sentry_sdk.capture_message("AdMob SSV: refused
  signatures", level="warning", fingerprint=[...])`, guarded by `cache.add("ads:alert:signature",
  1, 3600)` so it fires at most once an hour. A failed key fetch alerts the same way under its own
  guard. Sentry's alert rule emails the operator, as for B10's drift (FR-007).
- **Why:** no new infrastructure; Valkey is already the throttle store, and Sentry is the
  operator's one inbox. Twelve buckets approximate a rolling hour to within 5 minutes, which is
  enough for a threshold of 20.
- **Alternatives:** a Sentry event per failure (noisy, and quota on the free plan); Prometheus
  (none deployed).

## R12. Keeping and cleaning the records

- **Decision:** a daily Celery task `apps.ads.tasks.prune_ad_rewards` at 04:30 Cairo, scheduled by a
  data migration like B10's, wrapped in `liveops.tasks.skip_in_maintenance` (FR-024). It deletes
  rows whose outcome isn't `granted` and whose `created_at` is more than 90 days ago, in batches of
  5 000. `AdReward` uses a queryset whose `delete()` refuses granted rows, and whose `update()`
  allows only `shown_at`, so nothing else can edit a record.
- **Why:** the clarification (90 days) and B10's job rule; granted rows back ledger entries and stay.

## R13. What is logged

- **Decision:** logger `apps.ads`, one line per callback: `outcome`, `key_id`, `ad_unit`,
  `reward_item`, a 12-character SHA-256 prefix of the transaction id, and never `user_id`, the
  reference or the raw query. B03's privacy scan test is extended to `apps/ads`. Sentry's `scrub`
  already drops query strings.
- **Why:** FR-007 and backend §14's data inventory; the hash still lets staff match a log line to a
  row.

## R14. The admin

- **Decision:** `AdRewardAdmin`, read-only (no add, change or delete permission is ever granted;
  `has_*_permission` return False), list filters on placement, outcome and game day, search by
  player id and transaction id. A migration grants `live_ops` and `economy_ops` `view_adreward`.
  The player page (`economy/player_page.py`) links to the player's rewards.
- **Why:** FR-023; `economy_ops` handles balance questions, which is where a missing piggy shows up.

## R15. Proving every placement's cap

- **Decision:** `apps/ads/tests/test_placement_caps.py`, one parametrized test per placement in
  glossary §3.4: the four phone-applied ones through sync (B03's handlers), `morning_piggy` through
  the callback, each one past its cap with the snapshot at its default and at a changed value
  (FR-021). `interstitial_between_trips` is asserted absent from both paths.

## Handed to later features

- **M11:** set SSV options on the piggy's rewarded ad (`userId = player_id`, `customData =
  {"placement":"morning_piggy","nonce":"<uuid4>"}` as compact JSON); poll the lookup at 1 s, 2 s,
  4 s and treat 404 as "not yet"; show the banner only when `ads.morning_piggy.available`; show the
  late-reward card for each `unseen` entry, then queue `ad_reward_seen` (also after showing a
  grant from the lookup); replace the wallet from the lookup's `wallet`. The AdMob console's callback
  URL is set only on the piggy's ad unit.
- **B09:** delete or anonymize a deleted player's `AdReward` rows (`player` is `PROTECT`).
- **M15:** report the lookup's give-up rate (analytics), which SC-003 measures by hand for now.
