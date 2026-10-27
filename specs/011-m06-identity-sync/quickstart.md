# Quickstart: Identity, Bootstrap and Sync (M06)

How to check that M06 works: the automated checks first, then the scenarios on a device against
the local stack and staging. Contracts: [account](./contracts/account.md),
[sync](./contracts/sync.md), [server states](./contracts/server-states.md),
[CI checks](./contracts/ci-checks.md).

## Prerequisites

- The repo set up as in `CLAUDE.md`: `fvm`, `uv`, Docker, and `packages/content_models` built.
- For Part B: an Android phone over adb (the owner's Redmi Note 7) with Google backup on
  (Settings › Google › Backup), and a second phone or an emulator.

## Part A: automated

From `apps/mobile`:

```bash
fvm flutter pub get && fvm dart run build_runner build -d
fvm dart run drift_dev make-migrations          # once, after the v3 tables (commit its output)
fvm flutter analyze --fatal-infos
fvm flutter test --coverage --exclude-tags backend
fvm dart run tool/check_coverage.dart --min 80
```

Expected: everything passes, including the guards in contracts/ci-checks.md, the property test
(1,000 sequences, SC-003), the v2 → v3 migration test and the goldens in server-states.md.

Against the local stack (contracts/ci-checks.md "The `sync-e2e` job"):

```bash
cd backend && cp -n .env.example .env
docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait
uv run manage.py shell < ../apps/mobile/test/backend/seed_backend.py
cd ../apps/mobile && WASSAL_E2E_API=http://localhost:8000 fvm flutter test --tags backend test/backend
```

Expected: the three scenarios pass. Every operation is on the server exactly once (SC-004), the
stale path converges, and an ended session recovers.

## Part B: on a device

Run the dev build against the local stack (`adb reverse tcp:8000 tcp:8000`,
`fvm flutter run --flavor dev`), unless the step says staging.

| # | Steps | Expected |
| --- | --- | --- |
| 1 | Fresh install, airplane mode on. Open the app, play a trip. | No wait on Loading; the trip plays; Home shows the offline banner (SC-001). |
| 2 | Airplane mode off. Watch the debug card on Home. | Within 10 s an account exists, the pending count falls to 0, the state version moves, the banner hides (SC-002). |
| 3 | Kill and reopen. | Same player id (debug card); no second account in the admin. |
| 4 | Play 3 trips offline, buy a booster, turn the network on, and turn it off again in the middle of the send. Then on. | The admin shows each operation once; the phone's balances equal the admin's wallet (SC-004). |
| 5 | On a second device, sign the same player in (restore the install id, or `switch_to_existing` once M14 exists; until then, use the e2e's second session) and play a trip. Back on the first phone, resume. | The first phone takes the server's state; its own pending operations stay applied once. |
| 6 | Staff adjustment of +20 BONAT in the admin. Resume the app. | BONAT +20 on the phone after the bootstrap and sync. |
| 7 | Uninstall and reinstall (Google backup on). Open with the network on. | Loading waits ≤ 3 s, then the debug card shows the same player and the earlier progress (SC-006). |
| 8 | Same as 7 with the network off; then turn it on. | No wait; progress arrives later; `progressRestored` is logged on the debug card. |
| 9 | Make the server refuse a spend: spend BONAT offline on phone A after spending it on phone B. Sync A. | The booster goes back on A; one toast «رصيدك اتظبط على آخر حساب»; nothing on the trip screen. |
| 10 | Start a trip and sync from the debug card while it runs (open it from Home first, then start the trip). | Nothing is sent while the trip screen shows; the queue goes out on the result screen. |
| 11 | Set `CLIENT_MIN_VERSION=9.0.0` in `backend/.env`, restart the api, resume the app. | The blocking update card; back does nothing; the button opens the Play listing. Restore the value. |
| 12 | Set `CLIENT_LATEST_VERSION=9.0.0` only. | The update card with «بعدين»; closing it hides it until the next newer version. |
| 13 | End the player's sessions on the local stack (B02's admin is read-only): `docker compose … exec api uv run manage.py shell`, then mark every `PlayerSession` of the player ended. Wait 15 min (the access token outlives its session until it expires), then resume the app. | The renewal answers `token_invalid`; the app signs in again with its install id, same player, no player action (SC-007). |
| 14 | `adb logcat` during steps 2–13 on the staging build. | No token, refresh token or install id in the log (SC-008). |
| 15 | iOS, after merge: sideload the dev IPA built against staging (T093, `docs/runbooks/ios-test-build.md`), open it online, and note the player id on the status card. Delete the app, sideload it again, and open it online. | The same player id on the status card within 10 s of being online (SC-006). |

Maintenance (`503 maintenance`) has no server switch until B10. It is checked against the fake
server in Part A and on the design goldens.

## Done when

- [ ] Part A passes, in CI too (`app` and `sync-e2e` jobs).
- [ ] Part B steps 1–14 pass on the Redmi Note 7, and steps 2, 7 and 14 also on a staging build.
- [ ] After merge, as owner-actions.md lists:
  - step 15 on an iPhone;
  - the cold start on the Galaxy A06 (`tool/perf/cold_start.sh com.wassalogra.app.dev 10`, median
    ≤ 3,000 ms), and one first open of a returning player, at most 3 s longer (SC-001).
- [ ] The owner approved the toast's line and the «بعدين» button (owner-actions.md).
- [ ] The docs listed in research R25 are updated.
