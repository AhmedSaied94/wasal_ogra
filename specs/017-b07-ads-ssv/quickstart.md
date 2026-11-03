# Quickstart: B07 validation

How to prove the feature works. Commands run from `backend/` (backend/CLAUDE.md "Commands").
Shapes are in [contracts/api.md](./contracts/api.md); the table in [data-model.md](./data-model.md).

## Prerequisites

1. **Owner, before the deploy:** in the Firebase console, add the Remote Config parameter
   `ads_morning_piggy_daily_cap` with default `1` on both projects, or B10's drift check reports it.
2. The dev stack is up (`docker compose … up -d --wait`) and migrated; `uv sync` done.

## 1. The suites

```bash
uv run ruff check . && uv run ruff format --check .
uv run mypy .
uv run pytest -n 4 --cov --cov-fail-under=80
uv run manage.py makemigrations --check --dry-run
uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn && git diff --exit-code ../contracts/openapi.yaml
HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py apps/ads/tests/test_properties.py
```

Expected: green; `apps/ads/services` at 100% of lines. The ads tests sign callbacks with a P-256
key generated per test session and serve its public key from a local server (the `admob_keys`
fixture, like B02's `google_jwks`).

## 2. A grant end to end (dev)

The dev `.env` has `ADS_VERIFIER_KEYS_URL=file:///app/.dev/admob_verifier_keys.json`. The first
run of `ads_dev_callback` creates the dev key and that file (both gitignored), then restart the API
container once so it reads the new key list.

1. Create a player (`POST /v1/auth/anonymous`) and keep its `player_id` and token.
2. `uv run manage.py ads_dev_callback --user <player_id>` → prints the reference and
   `200 {}` (it signed the callback with the dev key and sent it to `http://localhost:8000`).
3. Run it again with `--nonce <reference> --transaction-id <the printed one>` → `200 {}` and no
   second grant (the duplicate).
4. `GET /v1/ads/rewards/<reference>` as the player → `granted`, 30 JENEHAT, 2 BONAT, and the wallet.
5. `GET /v1/bootstrap` → `ads.morning_piggy.available: false`, the reward in `unseen`.
6. Sync `ad_reward_seen` with the reference → accepted; bootstrap's `unseen` is `[]`.
7. `uv run manage.py economy_check` → no mismatch.

## 3. Refusals

With `ads_dev_callback`: `--tamper` (403 `signature_invalid`); `--user <player_id>` again the same
day (200; lookup says `refused`, `cap_reached`); `--user <a random UUID>` (200; lookup 404);
`--age-days 8` for a second player (200, `expired`); `--placement result_double` (200,
`not_server_placement`). The admin's ad rewards list shows each row with its outcome.

## 4. Live settings

In the admin, set `ads_morning_piggy_bonat` to 5; a minute later run `ads_dev_callback --user
<a third player>` → 5 BONAT granted. Try 0 for both amounts → refused with "The morning piggy must give
something."

## 5. Alerts

With Sentry pointed at a test project, run `ads_dev_callback --tamper` 21 times within an hour →
exactly one "AdMob SSV: refused signatures" event.

## 5a. Timing

`uv run pytest apps/ads/tests/test_timing.py -s` prints the callback and lookup p95 (SC-005:
under 1 s and at most 100 ms).

## 6. Staging, with a real ad (owner, after the deploy)

1. In the AdMob console, set the SSV callback URL `https://api-staging.<domain>/v1/ads/ssv` on the
   piggy's rewarded ad unit only, and press **Verify URL** → the console reports success; the admin
   shows an `unattributed` row.
2. With the M11 build (or a debug build that shows the piggy ad), watch the ad on the test phone →
   the reward appears within 7 seconds in at least 9 of 10 tries (SC-003).
3. Copy one real callback's query from the admin row's details into
   `apps/ads/tests/fixtures/real_callback.json` with that day's key list, so CI also verifies a
   Google-signed callback (research R1).
