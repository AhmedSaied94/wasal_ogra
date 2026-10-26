# Quickstart: Economy Ledger, Bootstrap and Sync (B03)

How to prove the feature works. Part A runs on a developer machine and in CI. Part B runs on staging
after the merge deploys it. Contracts: [api](./contracts/api.md), [operations](./contracts/operations.md),
[fuel](./contracts/fuel.md), [environment](./contracts/environment.md), [admin](./contracts/admin.md).
The model is in [data-model.md](./data-model.md).

## Prerequisites

- B02 is merged (it is) and `uv sync` has run in `backend/`.
- The local stack is up: `docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait`
  (PostgreSQL and Valkey; the tests run against them, never mocks).
- A published pack exists in the dev database for the content checks: the sample pack
  (`uv run manage.py content_import ../content/examples/sample --actor <staff>` then publish, or the
  test fixtures, which build their own).

## Part A: local and CI

### A1. The gates (all in `backend/`)

```bash
uv run ruff check . && uv run ruff format --check .
uv run mypy .
uv run manage.py makemigrations --check --dry-run
uv run pytest -n 4 --cov --cov-fail-under=80
uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn   # then git diff: no change
HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py          # once, before merge
```

Expected: all green. The properties file proves, at 10,000 examples, that
`wallet == sum(ledger)` for both currencies, no balance goes negative, the same batch twice changes
nothing, and no phone-sendable operation adds BONAT.

### A2. The guards on their own

```bash
uv run pytest apps/economy/tests/test_balance_writers.py   # no other writer of a balance
uv run pytest apps/economy/tests/test_tunables_parity.py   # server defaults equal tunables.json
uv run pytest apps/economy/tests/test_fuel_fixtures.py     # fixtures/economy/fuel.json
```

And in `apps/mobile`: `fvm flutter test test/core/economy/fuel_fixtures_test.dart` (the same
fixtures through M05's fuel code).

### A3. The 100-operation batch is cheap

```bash
uv run pytest apps/economy/tests/test_batch_cost.py
```

Expected: the fixture batch of 100 mixed operations runs in at most 40 queries (research R20).

### A4. By hand against the dev stack

```bash
API=http://localhost:8000
H='-H X-Client-Version:1.0.0+1 -H X-Platform:android -H Content-Type:application/json'
INSTALL=$(python3 -c 'import uuid;print(uuid.uuid4())')
TOKEN=$(curl -s $H -d "{\"install_id\":\"$INSTALL\",\"platform\":\"android\",\"locale\":\"ar-EG\"}" $API/v1/auth/anonymous | jq -r .access)

curl -s $H -H "Authorization: Bearer $TOKEN" $API/v1/bootstrap | jq
```

Expected: `wallet.fuel` is 5, `jenehat` and `bonat` 0, `state_version` 0, `comeback.claimable` false.

```bash
TXN=$(uv run python -c 'import uuid_utils;print(uuid_utils.uuid7())')   # in backend/
BODY="{\"base_state_version\":0,\"ops\":[{\"client_txn_id\":\"$TXN\",\"op_type\":\"trip_start\",
 \"occurred_at\":\"$(date -u +%FT%TZ)\",\"payload\":{\"trip_id\":\"<a trip of the pack>\",\"content_version\":1,\"fuel_mode\":\"fuel\"}}]}"
curl -s $H -H "Authorization: Bearer $TOKEN" -d "$BODY" $API/v1/sync | jq
curl -s $H -H "Authorization: Bearer $TOKEN" -d "$BODY" $API/v1/sync | jq     # again
curl -s $H -H "Authorization: Bearer $TOKEN" $API/v1/state | jq
```

Expected: the first answer accepts the start with `fuel` 4 and `state_version` 1. The second answer
has the same `results` and `state_version` stays 1; its `state_stale` is true, because the batch
still says `base_state_version` 0. The state shows an `open_trip`.

A dev database with packs published before B03 answers `content_version_unsupported` until
`uv run manage.py content_index --rebuild` has run in the worker container (B1).

### A5. The admin

Sign in to the dev admin (`http://localhost:8001/admin/`) as a staff user in `economy_ops`
(`create_staff alice --group economy_ops`, then `staff_totp alice`). On the player's page check the
wallet, the ledger and the operations blocks. Run "Adjust balance…" for +10 BONAT with a reason:
the ledger shows an `admin_adjustment` entry and the `WalletAdjustment` record exists. Try −999: it is
refused. Add a name filter entry and see its normalized form.

## Part B: staging, after the merge deploys

### B1. Rebuild the rules index (once, per environment)

```bash
docker compose exec worker uv run manage.py content_index --rebuild
```

Expected: it lists each published version in the window with its trip, price and rules counts, and
a second run changes nothing. Do this on staging first, then on production.

### B2. The live flow from a real phone or curl

Against `https://<staging api host>`: run A4's calls with a debug-build player. Check that the
bootstrap's `content.version` is the staging pack's, a trip start is accepted at that version, a
version older than the window is `content_version_unsupported`, and a version that never existed is
`unknown_content_version`.

### B3. The books balance

```bash
docker compose exec api uv run manage.py economy_check
```

Expected: `economy.wallet_equals_ledger: passed, <n> wallets equal their ledger, 0 players differ`,
exit 0. It runs the same check the
monthly restore drill runs on a restored backup (the drill's `check` step reports it as
`economy.wallet_equals_ledger` too).

### B4. Latency (SC-008)

```bash
uv run python tools/sync_load.py --base https://<staging api host> --players 50 --batches 20
```

Expected: p95 under 200 ms for bootstrap, 400 ms for state, 1 s for a batch of 100. (`backend/tools/sync_load.py` is a task of this
feature; it uses anonymous players that the admin can list and ignore.)

### B5. Flags

Send a trip start with an empty tank (three times in one game day) and a finished 3-star result
faster than `SYNC_FAST_RUN_PERCENT`. In the admin the flags `fuel_overdraft` and `fast_three_star`
appear, the third overdraft is `cap_reached`, and nothing else about the player changed.

## What to do if it fails

- A balance mismatch in B3 is a stop-the-line event: do not deploy again. Take the player ids the
  invariant reports, read their ledger in the admin, and open an incident in
  `docs/runbooks/economy.md`.
- `content_version_unsupported` for the current version means B1 was not run or the pack was
  published before the index existed: run `content_index --rebuild`.
- A flag storm (many `clock_clamped`) means a client clock bug, not cheating: check the app version
  in the details before acting on players.
