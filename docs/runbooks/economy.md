# Economy

The players' balances, the sync of their offline play, the flags that note odd play, and the
staff corrections. Every balance change is a ledger entry; the wallet is their sum. Nothing here
edits a balance or a ledger row directly.

Background: `specs/010-b03-ledger-sync/` (research R7–R13, R19; contracts/admin.md,
contracts/environment.md). Every command below runs over the VM's WireGuard, as in
[staff-accounts.md](staff-accounts.md). The examples use production; for staging, use
`10.67.0.1`, `staging` and `wassal-staging-…`.

```bash
ssh ubuntu@10.66.0.1
TAG="$(cat /var/lib/wassal/prod/release)"
STACK="/var/lib/wassal/prod/deploy/$TAG"
dc() { sudo RELEASE_TAG="$TAG" docker compose -p wassal-prod -f "$STACK/compose.yml" --env-file "$STACK/env/prod.env" "$@"; }
```

## Before B03's first deploy

1. The `SYNC_*` and `ECONOMY_*` variables have defaults equal to the app's, so the env file needs
   none of them. Set one only to change it (contracts/environment.md lists them all).
2. After the deploy, write the rules index of the packs published before B03, once per environment,
   staging first. Only the worker mounts the packs directory:

   ```bash
   sudo docker exec wassal-prod-worker-1 python manage.py content_index --rebuild
   ```

   It lists each published version in the support window with its trip, price and rules counts. A
   second run changes nothing. Until it runs, sync answers `content_version_unsupported` for those
   versions.
3. Check the books (see below), and create the `economy_ops` members with
   `$ADMIN create_staff <name> --group economy_ops`, as in [staff-accounts.md](staff-accounts.md)
   (which also covers their second factor). `player_support` members see the economy too.

## Checking the books

```bash
sudo docker exec wassal-prod-admin-1 python manage.py economy_check
```

Expected: `economy.wallet_equals_ledger: passed, <n> wallets equal their ledger, 0 players differ`,
exit 0. The monthly restore
drill runs the same check on the restored backup ([restore.md](restore.md)).

### A wallet differs from its ledger

This is a stop-the-line event: something wrote a balance outside the ledger, which the code and its
scan test forbid.

1. Stop deploying. Leave the current release running; play goes on, and each batch still writes
   ledger entries.
2. Note the player ids the check prints (`<n> players differ: <ids>`; never balances).
3. For each, open the player in the admin: the Wallet block and the Recent ledger block, then
   "The full ledger". The wallet should equal the sum of the entries per currency.
4. Find what wrote the wallet: the last release's changes to `backend/apps/economy/`, a manual
   database session, a restore. Fix the cause before anything else.
5. Correct each wallet with an adjustment (below), reason `ledger mismatch <incident date>`, so
   wallet and ledger agree again with a record of it. Run `economy_check` again.
6. Write down what happened and why in the incident note.

## Flags

A flag notes soft odd play. The operation was accepted; nothing about the player changed. Flags
are one row per player, kind and game day (Cairo), with `details.count` counting the occurrences.
Leagues (phase 3) will exclude players with open flags.

| Kind | Raised when | Usually means |
| --- | --- | --- |
| `fuel_overdraft` | a trip start with an empty tank (allowed twice a game day; the third is refused `cap_reached`) | a phone whose fuel count ran ahead of the server's, mostly a clock a few minutes fast |
| `fast_three_star` | a finished 3-star run under `SYNC_FAST_RUN_PERCENT` % of the trip's last station time (95) | a very good player, or a tampered result; look at `details.duration_ms` against `last_station_ms` |
| `trip_rate` | more accepted trip starts in a game day than `SYNC_TRIPS_PER_DAY_FLAG` (400) | a bot, or a test account left playing |
| `txn_payload_mismatch` | an operation id sent again with another type or payload | a client bug, or tampering |
| `clock_clamped` | an `occurred_at` moved more than `SYNC_CLOCK_CLAMP_FLAG_MINUTES` (10) by the clamps | a phone with a wrong clock. Many at once: a client bug; check the app version before acting on players |

To review: Admin → Economy → Player flags (the list shows open flags by default; search by an
exact player id). Select flags, action "Mark reviewed", and write what you found and decided (up
to 200 characters). A review records you and the time, and is final.

## Adjusting a balance

For a refund, a support gesture or a correction. Needs the `economy_ops` group.

1. Admin → Accounts → Players, search the exact player id, open the player.
2. "Adjust balance…" (top right). Choose JENEHAT or BONAT, a signed amount (negative takes away)
   and a reason the next person will understand, such as `refund: purchase lost on 2026-11-02`.
3. Submit: the page shows the balance before and after. Tick the confirmation and submit again. A
   result below 0 is refused.

It writes one ledger entry (`admin_adjustment`, source `admin`) and one adjustment record (you,
the player, the amount, the reason), both permanent. A mistake is undone by another adjustment.
The player's phone is told to refresh at its next sync. There is no way to move value between
currencies or players, by design.

## Tuning the flag thresholds

`SYNC_FAST_RUN_PERCENT` (95) and `SYNC_TRIPS_PER_DAY_FLAG` (400) are guesses until the closed test
shows real play. After the first weeks:

1. Read the open `fast_three_star` flags. If honest players are flagged (good players, normal
   `count`, nothing else odd), lower `SYNC_FAST_RUN_PERCENT` by 5. It can't go below
   `SYNC_MIN_DURATION_PERCENT` (85, the hard bound: runs under it are refused); startup refuses
   that.
2. If `trip_rate` flags only test accounts, leave it; if real players reach it, raise it.
3. Edit `/etc/wassal/<env>.env` (`sudoedit`), then `dc up -d --force-recreate api worker`, and
   check `/readyz`. Flags already raised stay; the new value applies from the next batch.

These are server-only numbers with no Remote Config key until B10 moves them to `LiveSetting`
(constitution VIII, tracked in the B03 plan).

## Retention and growth

- `economy.tasks.prune` runs daily at 04:45 Cairo time. It deletes processed operations older than
  `SYNC_OP_RETENTION_DAYS` plus one day (181; an operation id older than the retention is refused
  `op_expired`, so none applies twice, and the extra day covers ids dated up to a day ahead), trip runs older than 90 days and day counters older than 40 days. Ledger entries,
  progress, ownership and inventory are never deleted.
- At about 100k daily players, `economy_processedop` (~50 GB at 180 days) and `progress_triprun`
  need partitioning by time, with a composite key (research R11, R12). Plan it before then; at
  10k it is a few GB and the daily prune is enough.
