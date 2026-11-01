# Quickstart: Checking B10

Run from `backend/` with the dev stack up (`backend/CLAUDE.md`, "Commands"). The API is on
`localhost:8000`, the admin on `localhost:8001/admin/`. `$TOKEN` is a player's access token from
`POST /v1/auth/anonymous`; `H` is the two client headers.

```bash
H=(-H "X-Client-Version: 1.2.4" -H "X-Platform: android" -H "Authorization: Bearer $TOKEN")
uv run manage.py create_staff ops --group live_ops && uv run manage.py staff_totp ops
```

## 1. Settings apply without a restart (US1)

1. In the admin, Live settings: `fuel_overdraft_per_day` shows 2, default 2, `server`.
2. Change it to 1 with a note. Its history shows you, the time, 2 → 1.
3. Within 60 s, a sync batch with two empty-tank `trip_start`s on one game day: the second is
   `cap_reached` (B03's fixture builder in `apps/economy/tests/helpers.py`).
4. Try `fuel_max_subscriber = 3` while `fuel_max` is 5: refused with "The subscriber's tank can't be
   smaller than the normal tank."
5. Reset `fuel_overdraft_per_day`: back to 2, with a `reset` record.
6. Log in as a `player_support` user: no live-ops pages.

Expected in CI: `uv run pytest apps/liveops` passes, including `test_tunables_parity.py`.

## 2. Old apps are asked to update (US2)

1. App versions page: the dev players per version. Propose `min_client_version_android = 1.3.0`:
   it shows how many it would block. Confirm.
2. `curl "${H[@]}" localhost:8000/v1/bootstrap` → 200, `client.force_update: true`.
3. `curl "${H[@]}" -X POST -d '{"ops": []}' -H 'Content-Type: application/json' localhost:8000/v1/sync`
   → 426 `client_outdated`, `details.min_version` "1.3.0".
4. The same with `X-Client-Version: 1.3.0`, and with `X-Platform: ios` at 1.2.4: no 426.
5. Set the minimum back to 1.0.0.

## 3. The shop's catalog (US3)

1. `curl "${H[@]}" localhost:8000/v1/offers` (with 1.3.0 or the minimum back at 1.0.0) → four
   products: 60, 300 + 30, 800 + 120 (best value), `remove_ads`; `offers: []`; no price anywhere.
2. Deactivate `bonat_pack_s` in the admin; within 60 s it is gone from the answer. Reactivate.
3. Try to mark `bonat_pack_m` best value too: refused.

## 4. Maintenance (US4)

1. `uv run manage.py maintenance on --actor ops --until <now + 20 min, UTC> --note "quickstart"`.
2. Within 60 s: sync → 503 `maintenance` with `details.until`; bootstrap and offers → 200.
3. On the phone (Redmi over adb, `docs/runbooks` dev setup): Home shows the maintenance card with the
   end time in local time; a trip plays offline.
4. `celery call economy.tasks.prune` in the worker: its log line says `task_skipped_maintenance`.
5. `uv run manage.py maintenance off --actor ops`: the phone's next sync goes through; the admin
   history shows both switches as `command`.

## 5. Offers (US5)

1. Create offer `qs_eg_new` for `remove_ads`, rules
   `[{"rule": "country_in", "countries": ["EG"]}, {"rule": "days_since_install", "min": 0, "max": 6}]`.
2. An `ar-EG` player created today sees it; a player whose `created_at` is 8 days ago (shell) or whose
   locale is `ar-SA` doesn't.
3. Save a rule `{"rule": "vip"}`: refused naming `vip`.
4. Set `ends_at` to a minute ago: it disappears at once; `celery call liveops.tasks.expire_offers`
   marks it `expired`.

## 6. The Remote Config check

1. With both Firebase variables empty: `celery call liveops.tasks.check_remote_config` → a
   `not_configured` row.
2. On staging, after the owner action (the read-only service account): a run shows `ok`. Change
   `fuel_max` to 6 on the server only, run again: `drift` row, the admin marks `fuel_max`, and Sentry
   gets one warning event naming it. Set it back.

## 7. The whole suite

```bash
uv run ruff check . && uv run ruff format --check . && uv run mypy .
uv run pytest -n 4 --cov --cov-fail-under=80
uv run manage.py makemigrations --check --dry-run
uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn && git diff --exit-code ../contracts/openapi.yaml
HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py
```
