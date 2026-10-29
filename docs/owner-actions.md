# Owner actions

This file lists the work only you can do: accounts, consoles, secrets, devices, and checks against the
live host. Each feature gets a section when its `/speckit-implement` finishes. Tick an item when it's
done, or say so and Claude ticks it.

The detailed steps stay in each feature's `tasks.md`, quickstart and runbooks. This file says what is
left, in what order, and where to look.

- **Before merge** items block the feature's PR.
- **After merge** items are checks on the live system. The feature is ticked in
  [delivery-plan.md](delivery-plan.md#progress) once they pass.
- When a check fails, tell Claude what you saw. The fix goes in a follow-up PR.

## Open now

| Feature | Before merge | After merge | State |
| --- | --- | --- | --- |
| [001 M03 app shell](#001-m03-app-shell) | none | 2 device checks | Merged in #1 |
| [002 B01 backend skeleton](#002-b01-backend-skeleton) | 10 | 8 | Merged in #2 on 2026-10-19. Live checks open. |
| [003 B04 content pipeline](#003-b04-content-pipeline) | 4 | 6, then 5 after B05 | PR 1 merged in #3, PR 2 in #4. |
| [004 M01 trip engine](#004-m01-trip-engine) | none | none | Merged in #5. |
| [005 B05 solver and parity](#005-b05-solver-and-parity) | none | 4, the last with B04's 3–7 | Merged in #6 on 2026-10-21. |
| [006 M04 content loader](#006-m04-content-loader) | 1 | 1 now, 2 after production's first promotion | Merged in #7 on 2026-10-21. |
| [007 M05 local economy](#007-m05-local-economy) | 1 | 3 | Merged in #8 on 2026-10-22. |
| [008 M02 trip screen](#008-m02-trip-screen) | 4 | 2 | Merged in #9 on 2026-10-23. The A06 run and the device runs are open. |
| [008.5 M21 design refresh](#0085-m21-design-refresh) | 7 | 2 | Merged in #10 on 2026-10-23, before its owner checks: all 7 are still open. |
| [009 B02 accounts and auth](#009-b02-accounts-auth) | 2 | 2, plus 1 before the closed test | Merged in #15 on 2026-10-26. T065: the project, the web client and the Firebase apps are done (2026-10-25). T066 is open, and a deploy fails without it. |
| [010 B03 ledger and sync](#010-b03-ledger-and-sync) | 1 | 2, plus 1 after the closed test starts | Merged in #16 on 2026-10-26. The approval of its one constitution deviation is open. |
| [011 M06 identity and sync](#011-m06-identity-and-sync) | 2 | 4 | Merged in #17 on 2026-10-27. Its before-merge checks are still open. |
| [012 M07 onboarding](#012-m07-onboarding) | 4 | 4 | Built and tested on 2026-10-27, on branch `012-m07-onboarding`. The drawings were done on 2026-10-28. |
| [012.5 M22 animated scenes](#0125-m22-animated-scenes) | 5 | 4 | Built and tested on 2026-10-28, on branch `012.5-m22-animated-scenes`. Two art questions are open (before merge, 3 and 4). |
| [013 M08 Home, pre-trip card and result](#013-m08-home-pre-trip-card-and-result) | 4 | 2 | Built and tested on 2026-10-28, on branch `013-m08-home-result`. The strings and the design departures wait for your approval. |

## Every month

This starts once production is live (B01). The restore drill runs by itself on the 1st at 05:00 Cairo
time, on the staging VM. The routine keeps the free accounts and their guarantees alive
([B01 quickstart](../specs/002-b01-backend-skeleton/quickstart.md#monthly-operating-routine-operator)):

- Check that this month's drill line passed: `/var/lib/wassal/drill-results.jsonl`, on the staging
  VM.
- Sign in to the OCI console, and check that both instances run. Oracle may suspend a tenancy left
  idle for 30 days.
- Sign in to Healthchecks.io. It deletes accounts with no login for a year.
- In each B2 account (production's and staging's), check that the caps are still USD 0 and storage
  is well under 10 GB. If anything in the console changed, run
  `uv run tools/b2_setup.py [--env staging] --daily-bucket <daily> --weekly-bucket <weekly> --check`
  from `backend/`, once per environment.
- Check that no service shows a charge.

## 001 M03 app shell

Merged in #1 on 2026-10-18. Two checks on a real device are left
([tasks.md](../specs/001-m03-app-shell/tasks.md)).

- [ ] **T091 Manual scenarios.** Walk scenarios 1–10 in
  [quickstart.md](../specs/001-m03-app-shell/quickstart.md) with `fvm flutter run --flavor dev` on an
  emulator or a phone.
- [ ] **T092 Galaxy A06 performance.** With `apps/mobile/tool/perf/`:
  - build the `prod` release APK and run `tool/perf/cold_start.sh com.wassalogra.app 10`. The median
    must be ≤ 3000 ms;
  - run the white-frame recording check from the quickstart.

  The PR is already merged, so put both outputs in a follow-up issue. Then remove the "Still to do"
  note from M03's line in the delivery plan's Progress list.

## 002 B01 backend skeleton

Built and tested on 2026-10-18, on branch `002-b01-backend-skeleton`
([tasks.md](../specs/002-b01-backend-skeleton/tasks.md),
[quickstart](../specs/002-b01-backend-skeleton/quickstart.md)).

On 2026-10-19 the design moved to one VM per environment (constitution v1.1.0, tasks.md Phase 10):

| | prod VM | staging VM |
| --- | --- | --- |
| Reserved public IP | `193.122.74.125` | `141.147.129.92` |
| VCN private IP | `10.0.0.28` | `10.1.0.216` |
| WireGuard `wg0` | `10.66.0.1` | `10.67.0.1` |
| State | Created, not provisioned (T104) | Provisioned with the one-VM script, to redo (T103) |

Claude changes the code and the runbooks (T092–T102, T107). Your part is T103–T106 below. They
replace T054 and part of T061, which are kept below, struck out, for the record.

### Before merge, in this order

This follows the setup order in [runbooks/README.md](runbooks/README.md#first-time-setup): the
staging VM first, then the prod VM.

- [ ] **Commit and push the branch.** Ask Claude, or run `/speckit-git-commit`. The CI workflows only
  run once the branch is on GitHub.
- [ ] **T005 Backblaze spike.** You need the B2 admin key for this. Follow the steps in T005, which
  use a throwaway script and a scratch bucket. Record the results in
  [research.md](../specs/002-b01-backend-skeleton/research.md) R9, replacing its **[verify in
  spike]** item.
  - If B2's calls differ from what `backend/tools/b2_setup.py` assumes, ask Claude to adjust the
    script and its tests.
  - **The day after**, once the 1-day lock ends, delete the scratch bucket's versions, the bucket
    and both scratch keys (T005 step 5).
- [ ] **Outside services.** Follow [monitoring-setup.md](runbooks/monitoring-setup.md). Keep each
  value in your password manager until T103 and T104 put it in each VM's env files:
  - Healthchecks.io: 6 checks. If you already made five, rename `host-monitor` to
    `host-monitor-prod` and add `host-monitor-staging` (T106);
  - Sentry: done on 2026-10-19. Organization `saied-store-div` (US region, by your choice) and
    project `wassal-backend` exist, and test errors from the web and worker processes arrived. Its
    DSN goes in `SENTRY_DSN` in `/etc/wassal/staging.env` on the staging VM and
    `/etc/wassal/prod.env` on the prod VM.

  UptimeRobot waits until production serves (T106).
- [ ] **T084 Backblaze B2.**
  - Turn on MFA, and set USD 0 caps on storage and on Class A, B and C transactions.
  - Keep the admin key in your password manager. It never goes on either VM.
  - Run `uv run tools/b2_setup.py --daily-bucket <name> --weekly-bucket <name>` from `backend/`.
    Keep the lines it prints in your password manager. T104 puts the backup lines in
    `/etc/wassal/prod-backup.env` on the prod VM, and T103 the drill lines in
    `/etc/wassal/prod-drill.env` on the staging VM.
  - Record the account's region in research.md R9 "Data location".
- ~~**T054 Provision the host.**~~ *Superseded on 2026-10-19 by T103 (staging VM) and T104 (prod
  VM).* What it already did on the staging VM still counts:
  - Oracle's real `rules.v4` and `rules.v6`, saved before the first render, are the test fixtures
    in `backend/docker/host/tests/fixtures/`;
  - `iptables -S` before the first render is in research.md R13.

  Its other records moved: `iptables -S` after (T103, T104), the latency baseline (T104), and the
  setup time, now one per VM (T103, T104).
- [ ] **T103 Re-provision the staging VM as `staging`.** The one-VM script left it with `wg0` on
  `10.66.0.1` (no peers), no `/etc/wassal/host.env`, and the backup, drill and host-monitor timers
  all on. Public SSH is still open, since it was never finalized. Do this once Claude has finished
  T092–T099: the script must know `--env`.
  1. Note the state before, for R13:

     ```bash
     ssh ubuntu@141.147.129.92
     sudo ls -l /etc/wassal /var/lib/wassal
     systemctl list-timers 'wassal-*'
     sudo iptables -S INPUT
     ```

  2. From the repository root on your machine, copy the updated scripts:
     `rsync -a --delete backend/docker/ ubuntu@141.147.129.92:wassal-docker/`.
  3. On the VM, stop the old tunnel and move its files aside. It has no peers, so nothing is lost:

     ```bash
     sudo systemctl disable --now wg-quick@wg0
     sudo mv /etc/wireguard/wg0.conf /root/wg0.conf.10-66
     sudo mv /etc/wassal/wg-server.env /root/wg-server.env.10-66
     ```

     Move `/etc/wassal/wg-peers.tsv` aside too, if it exists. If `/etc/wassal/edge.env` exists, it
     has the one-VM variables (`PROD_API_HOST`, …) and `ADMIN_BIND_IP=10.66.0.1`: move it aside as
     well, and write a new one in step 7. The script refuses to start while either the old
     `wg0.conf` or that `edge.env` is in place, and changes nothing.
  4. Run `sudo ./wassal-docker/host/provision.sh --env staging --public-ip 141.147.129.92`. It
     prints `staging host, WireGuard 10.67.0.1, timers …`, and later
     `disabling wassal-backup@prod.timer: it doesn't run on the staging host`.
  5. Confirm:
     - `sudo cat /etc/wassal/host.env` says `WASSAL_ENV=staging` and `WG_ADDRESS=10.67.0.1`;
     - `ip -4 -o addr show wg0` shows `10.67.0.1/24`;
     - `systemctl list-timers 'wassal-*'` lists only `wassal-restore-drill@prod.timer` and
       `wassal-host-monitor.timer` (plus `wassal-backup@staging.timer` once B04's host scripts are
       on the VM), and `systemctl is-enabled wassal-backup@prod.timer` says `disabled`;
     - `sudo iptables -S INPUT` shows a single rule set: one `-j REJECT`, at the end, and the
       project's rules on `10.67.0.x`. The old script's `netfilter-persistent reload` had appended
       a second set, which the full restore replaces;
     - `sudo cat /etc/sudoers.d/wassal-deploy` allows `--only staging` only.
  6. Act on every `WARNING` line, following provision-host.md
     ["Removing leftovers from the one-host design"](runbooks/provision-host.md#removing-leftovers-from-the-one-host-design).
     Expect `/var/lib/wassal/prod`, and `prod.env`, `prod-db.env` or `prod-backup.env` if you
     filled them. Re-run the script until it warns about nothing.
  7. Record `sudo iptables -S` (after) in research.md R13, closing its **[verify on host]** for this
     VM. The "before" is the one T054 recorded. Then continue provision-host.md §4–7 for staging:
     `edge.env`, `staging.env`, `staging-db.env` and `prod-drill.env`; your peer on `10.67.0.1`;
     `--finalize`; TCP 22 out of the staging VCN's security list.
  8. Once your new tunnel works, delete `/root/wg0.conf.10-66` and `/root/wg-server.env.10-66`
     (they hold the old server key). Remove any old tunnel to this VM from your devices, the
     hand-made `10.20.0.x` one included.
  9. Time steps 4 onwards until staging serves `/healthz` (after the merge, T062), and add how long
     creating the VM took. That sum is staging's setup time for SC-009 (≤ 4 h).
- [ ] **T104 Provision the prod VM** (`193.122.74.125`, private `10.0.0.28`). Follow
  [provision-host.md](runbooks/provision-host.md) with the prod values, after T103. Start the clock
  at §1.
  - §1: the VM exists, so check it: 1 OCPU / 6 GB, a 100 GB boot volume, its own VCN, the reserved
    IP attached. Its security list allows TCP 80, 443 and UDP 51820 from anywhere, and TCP 22 from
    your address only.
  - §2: the console password, and the serial-console test.
  - §3: `sudo ./wassal-docker/host/provision.sh --env prod --public-ip 193.122.74.125`. Compare its
    `/var/lib/wassal/oracle-rules.v4` and `.v6` with the fixtures (the `diff` commands in §3), and
    record any difference in R13, with `iptables -S` before and after.
  - §4: `edge.env` (`PUBLIC_BIND_IP=10.0.0.28`, `ADMIN_BIND_IP=10.66.0.1`,
    `API_HOST=api.193-122-74-125.sslip.io`, `ADMIN_HOST=admin.10-66-0-1.sslip.io`), `prod.env`,
    `prod-db.env` and `prod-backup.env`. Not `host-monitor.env` yet.
  - §5–7: your peer on `10.66.0.1`, beside your staging tunnel; `--finalize`; TCP 22 out of the
    prod VCN's security list.
  - §10: the time from §1 to production serving `/healthz` (after the `v0.1.0` tag, T062), plus
    how long creating the VM took; and the latency baseline from Egypt once production serves.
- [ ] **T061 Deploy access** ([deploy-and-rollback.md](runbooks/deploy-and-rollback.md)):
  - create the GitHub Environments `staging` and `production`. Production deploys tags matching
    `v*` only. Required reviewers on production are recommended;
  - ~~add `WG_CONFIG`, `DEPLOY_SSH_KEY` and `DEPLOY_KNOWN_HOSTS` to each environment;~~
  - ~~add the two deploy peers and keys on the host (provision-host.md §8).~~ *Superseded by T105:
    each VM has its own deploy peer and key.*
- [ ] **T105 Deploy secrets, one VM per Environment.** After T103, T104 and T061, follow
  [provision-host.md §8](runbooks/provision-host.md#8-deploy-peers-and-keys) on each VM. Replace
  any values the Environments already hold:
  - on the staging VM, over `10.67.0.1`: `sudo wg-peer add deploy-staging deploy-staging`, the key
    limited to `--only staging`, and `ssh-keyscan -t ed25519 10.67.0.1`. The three secrets go in
    the `staging` Environment. Its `WG_CONFIG` has `Endpoint = 141.147.129.92:51820` and
    `AllowedIPs = 10.67.0.1/32`;
  - on the prod VM, over `10.66.0.1`: the same with `deploy-prod`, `--only prod` and `10.66.0.1`,
    into `production`. Its `WG_CONFIG` has `Endpoint = 193.122.74.125:51820` and
    `AllowedIPs = 10.66.0.1/32`.

  The workflows already deploy staging to `deploy@10.67.0.1` and production to `deploy@10.66.0.1`
  (T100).
- [ ] **T039 Prove the CI gates.** Cut a scratch branch from the B01 branch, open a PR from it, and
  make each change below in turn. Revert each change after its run. Every run must finish within
  15 min. Put the run links in the B01 PR description.
  - A model in `backend/apps/common/models.py` without `UUIDv7Model`: `test` fails.
  - A field without a migration: `contract` fails.
  - A changed health response without regenerating `contracts/openapi.yaml`: `contract` fails.
  - Tests deleted until coverage drops below 80%: `test` fails.
  - A committed `AKIA…`-style key: `gitleaks` fails.
  - A change to `apps/mobile/` only: `backend` succeeds, with its jobs skipped.
- [ ] **T040 Repository settings** ([ci-checks.md](../specs/002-b01-backend-skeleton/contracts/ci-checks.md)):
  - make `backend` and `gitleaks` required status checks on `master`, alongside the mobile checks.
    They can be selected once they have run on a PR;
  - turn on push protection (Settings → Advanced Security).

Then merge the PR. The merge deploys the staging VM.

### After merge

Run each scenario on the VM named in the Host column of the
[quickstart's scenario table](../specs/002-b01-backend-skeleton/quickstart.md#production-validation-scenarios-us3us6)
(T108). "each" means once on both VMs.

- [ ] **T062 Deploys.**
  - The merge deploys the staging VM (scenario 10). Its first deploy fails with exit 4: make the
    image public ([deploy-and-rollback.md](runbooks/deploy-and-rollback.md#one-time-setup) step 3),
    then re-run the failed `deploy-staging` job.
  - Tag `v0.1.0` on `master`, which deploys the prod VM.
  - Walk scenarios 11–15:
    - the two staging rehearsals, while polling production's `/healthz`, to show it isn't touched;
    - a tag on a branch commit is refused;
    - a rollback takes ≤ 10 min;
    - a deploy causes ≤ 30 s of downtime.
  - Two merges within a minute deploy one after the other.

  Record the results in the PR or a follow-up issue.
- [ ] **T055 Production checks.** First create your admin account in each environment, with
  `--superuser`, and install both VMs' admin CA roots on your device: the second root is the
  staging VM's ([runbooks/README.md](runbooks/README.md#4-first-deploys) step 7). Then walk
  scenarios 1–9 and 23, with 3, 4 and 23 on each VM:
  - HTTPS and HSTS from mobile data, and the 308 redirect;
  - an outside port scan; the admin unreachable off WireGuard;
  - OTP and lockout over WireGuard; removing a peer;
  - API and admin host separation, and the 413;
  - each VM holds only its own environment, and refuses the other `--env`.
- [ ] **T106 Monitoring per VM.** Its first step can be done before merge, with the other checks.
  - Healthchecks.io has 6 checks, `host-monitor-prod` (the old `host-monitor`) and
    `host-monitor-staging` among them.
  - Once the merge has deployed staging: on the staging VM, create `/etc/wassal/host-monitor.env`
    with `host-monitor-staging`'s URL and the thresholds, with `BACKUP_STORAGE_ALERT_BYTES=8000000000`
    (B04: staging checks its own backups, in its own B2 account), and test it
    ([monitoring-setup.md](runbooks/monitoring-setup.md#healthchecksio-dead-mans-switches)).
  - Once `v0.1.0` has deployed production: the same on the prod VM, with `host-monitor-prod`'s URL
    and `BACKUP_STORAGE_ALERT_BYTES=8000000000`.
  - UptimeRobot: one monitor, on `https://api.193-122-74-125.sslip.io/healthz`, and none for
    staging. Save a dated copy of its terms.
- [ ] **T070 Monitoring.** Once T106 is done, walk scenarios 16–18 on the prod VM:
  - Sentry issues are tagged with the environment and release, with no IP, cookies or headers;
  - the uptime alert arrives within 10 min;
  - the heartbeat alert arrives within 20 min.

  Then force a host-monitor failure on each VM with a one-off `DISK_ALERT_PERCENT=1` run, and
  confirm both emails arrive.
- [ ] **T085 Backups.** Walk scenarios 19–21:
  - a manual backup, on the prod VM;
  - the backup key is refused a version delete and a listing on the prod VM, and a re-upload keeps
    the original version (listed with the drill key on the staging VM);
  - an on-demand drill on the staging VM passes and leaves nothing behind.

  Add the drill's restore time to the prod VM's setup time (T104). The sum must be ≤ 4 h. The
  staging VM's setup time (T103) must be ≤ 4 h on its own.
- [ ] **T091 Cross-cutting checks.**
  - After a reboot, each VM serves again within 5 min (scenario 22).
  - SC-002's 100 requests, on both API hostnames.
  - Your first monthly routine (above) shows USD 0 on every service.
- [ ] **Tick B01** in the [delivery plan's Progress list](delivery-plan.md#progress) once T062, T055,
  T106, T070, T085 and T091 pass.
- [ ] **About 17 days after the first backup** (scenario 24):
  - the first day's pair is gone from the daily bucket (listed with the drill key on the staging
    VM);
  - `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check` passes.

  This doesn't hold up ticking B01. If it fails, the lifecycle rules get fixed in a follow-up.

### Local cleanup, any time

These are leftovers from Claude's test runs:

- `docker exec wassal-dev-postgres-1 rm /tmp/restore-e2e.dump /tmp/restore-e2e.list`
- `docker image rm wassal-backend:drill-e2e ghcr.io/ahmedsaied94/wassal-backend:v0.0.99`

## 003 B04 content pipeline

PR 1 (schemas and generated models) merged in #3 on 2026-10-19. PR 2 (the admin, validation, pack
builds, publishing, promotion and staging backups) was built and tested on 2026-10-19, on branch
`003-b04-content-pipeline`
([tasks.md](../specs/003-b04-content-pipeline/tasks.md),
[quickstart](../specs/003-b04-content-pipeline/quickstart.md),
[content-publishing.md](runbooks/content-publishing.md)).

Until B05 ships the solver, staging can author, import, build and validate, but refuses every
publish (FR-022). So nothing reaches production before B05.

### Before merge, in this order

The merge deploys the staging VM, and a B04 release refuses to start without its packs directory
and its `CONTENT_*` values. So the staging VM gets both first.

- [x] **T105 Security review.** Claude ran it on 2026-10-19: no CRITICAL or HIGH findings. The
  MEDIUM ones (zip entries, the floor file's lock) and three recommendations (the audit log's
  database trigger, no caching of `/packs/` 404s, an unknown schema major on promotion) are fixed.
- [x] **The B2 storage alert** (decided 2026-10-20). Staging's backups use a second B2 account, so
  each environment has its own free 10 GB and each VM keeps `BACKUP_STORAGE_ALERT_BYTES=8000000000`.
- [ ] **Staging VM: host scripts and edge.** From this branch, follow
  [deploy-and-rollback.md "Updating the edge or the host scripts"](runbooks/deploy-and-rollback.md#updating-the-edge-or-the-host-scripts)
  on the staging VM: `rsync` `backend/docker/`, then `sudo ./wassal-docker/host/provision.sh`.
  Confirm:
  - `stat -c '%u %a' /var/lib/wassal/packs` says `10001 755`;
  - `systemctl list-timers 'wassal-*'` now also lists `wassal-backup@staging.timer`. Its runs are
    skipped until `staging-backup.env` exists;
  - `curl -sI https://staging-api.141-147-129-92.sslip.io/packs/core-1.json.gz` answers `404` with
    `cache-control: no-store`.
- [x] **Staging's `CONTENT_*` values** (done 2026-10-20). Add to `/etc/wassal/staging.env`
  ([contracts/environment.md](../specs/003-b04-content-pipeline/contracts/environment.md)):

  ```text
  CONTENT_ROLE=source
  CONTENT_PACKS_DIR=/var/lib/wassal/packs
  CONTENT_PACKS_PUBLIC_URL=https://staging-api.141-147-129-92.sslip.io/packs/
  CONTENT_VERSION_FLOOR_URL=https://api.193-122-74-125.sslip.io/packs/
  ```

  `CONTENT_SOLVER_STAGE` stays unset (`none`) until B05.

Then merge PR 2. The merge deploys the staging VM.

### After merge

- [ ] **Staging serves B04.** `curl -s https://staging-api.141-147-129-92.sslip.io/v1/content/manifest`
  gives `{"version":0,"packs":[]}`. Staging's builds also need production's floor file, so they
  fail with `version_floor_unavailable` until the prod VM runs B04 (next item).
- [ ] **Prod VM, before the tag that includes B04.** The same two steps as on staging:
  - the host scripts and the edge, then confirm `/var/lib/wassal/packs` (`10001 755`);
  - in `/etc/wassal/prod.env` (done 2026-10-20, ahead of time):

    ```text
    CONTENT_ROLE=target
    CONTENT_PACKS_DIR=/var/lib/wassal/packs
    CONTENT_PACKS_PUBLIC_URL=https://api.193-122-74-125.sslip.io/packs/
    CONTENT_PROMOTION_SOURCE_URL=https://staging-api.141-147-129-92.sslip.io/packs/
    ```

  Then tag the release. Check that `curl -s https://api.193-122-74-125.sslip.io/packs/core.floor.json`
  gives `{"max_version":0,"pack_id":"core"}`, and that a staging build now gets past numbering.
- [ ] **Staging backups** (FR-039c, quickstart "After B05" item 2, which doesn't need B05):
  1. Healthchecks.io: create `backup-staging`, period 1 day, grace 2 h
     ([monitoring-setup.md](runbooks/monitoring-setup.md#healthchecksio-dead-mans-switches)).
  2. B2, in staging's own account (its MFA, USD 0 caps and admin key first): run
     `uv run tools/b2_setup.py --env staging --daily-bucket wassal-staging-backup-daily --weekly-bucket wassal-staging-backup-weekly`
     from `backend/` ([monitoring-setup.md "Backblaze B2"](runbooks/monitoring-setup.md#backblaze-b2-backups)
     step 8). It creates both buckets with Object Lock and their retention, and a write-only key
     on `staging/`.
  3. On the staging VM, create `/etc/wassal/staging-backup.env` (mode `0400`) from its output, with
     `backup-staging`'s ping URL.
  4. Check that each VM's `host-monitor.env` has `BACKUP_STORAGE_ALERT_BYTES=8000000000`.
  5. Run one backup at once:
     `sudo systemctl start wassal-backup@staging && journalctl -u wassal-backup@staging -n 20`.
     `backup-staging` turns green, and a `staging/YYYY/MM/DD/…` pair is in the daily bucket.
- [ ] **Content groups.** On staging, give authors `content_author` and publishers
  `content_publisher`. On production, give publishers `content_publisher`. Use `create_staff
  <name> --group <group>` for new staff, or the user's page in the admin
  ([content-publishing.md](runbooks/content-publishing.md)).
- [ ] **Authors' devices.** Add each author's device to staging's private network, with the admin
  CA root ([private-network.md](runbooks/private-network.md#peers)).
- [ ] **Import the sample content on staging** (optional). Content packs → "Import zip", with a
  zip of `content/examples/sample`, then build. The build ends `draft` with `V-V1` until the
  speech lines are reviewed, and stays unpublishable until B05.

### After B05

These come after [B05's step 4](#after-merge-3), which publishes the first pack on staging. Walk
[quickstart "After B05"](../specs/003-b04-content-pipeline/quickstart.md#after-b05-live-checks-on-the-hosts)
items 3–7 (T107). Then tick B04 in the
[delivery plan's Progress list](delivery-plan.md#progress).

- [ ] **3. Publish on staging.** The pack's URL shows the immutable cache header from an outside
  network, and the body's sha256 matches.
- [ ] **4. Promote.** Production's manifest offers the same version and `sha256` within a minute.
- [ ] **5. Export to the repository.** Unzip the export into `content/source/` in a PR. CI
  validates it and runs the schema-diff check from then on.
- [ ] **6. Staging recovery (once).** On a scratch staging rebuild, follow
  [restore.md "Restore staging"](runbooks/restore.md#restore-staging), then build. The content is
  back, and the new version is above production's.
- [ ] **7. Cost.** After a month, OCI and B2 show USD 0, and the edge logs show `/packs/` downloads.

### Local, any time

- Claude recreated the dev stack on 2026-10-19 with `WASSAL_DEV_PG_PORT=5433`, a rebuilt image and
  the edge, because a native PostgreSQL holds port 5432 on this machine. Since 2026-10-29 5433 is
  `compose.dev.yml`'s default and `.env.example`'s, so there is nothing to export.
- Dev packs now live on the `packs` Docker volume. The T106 smoke left a `smoke-author` staff user,
  the imported sample and published pack 2 in the dev database. `docker compose … down -v` wipes
  them with everything else.

## 004 M01 trip engine

Built and tested on 2026-10-20, on branch `004-m01-trip-engine`
([tasks.md](../specs/004-m01-trip-engine/tasks.md),
[quickstart](../specs/004-m01-trip-engine/quickstart.md)). It is a pure-Dart package with its
fixtures, so it needs no account, console, secret, device or live host.

### Before merge

Nothing is left for you.

- [x] **T117 The constitution VIII exception.** Approved on 2026-10-20 and recorded in
  [plan.md](../specs/004-m01-trip-engine/plan.md) "Complexity Tracking": the backend's copy of the
  20 new tunables waits for B10's `LiveSetting`. B10's "Handed over from M01" item in
  [delivery-plan.md](delivery-plan.md) ends it.

### After merge

Nothing. The replay budget (SC-004) is measured on the CI runner, not on a device. Tick M01 in the
[delivery plan's Progress list](delivery-plan.md#progress) when the PR merges.

## 005 B05 solver and parity

Built and tested on 2026-10-21, on branch `005-b05-solver-parity`
([tasks.md](../specs/005-b05-solver-parity/tasks.md),
[quickstart](../specs/005-b05-solver-parity/quickstart.md)). It adds `tools/solver`, the real
solver stage, which is now the default on staging and production, and the admin's trip preview.

### Before merge

Nothing is left for you. The staging and production env files leave `CONTENT_SOLVER_STAGE` unset,
so they get the real stage.

### After merge

Run these over each VM's WireGuard. Then tick B05 in the
[delivery plan's Progress list](delivery-plan.md#progress).

- [ ] **1. Production first.** Deploy production with this release before the first promotion of a
  pack that carries a solver warning. An older production refuses such a pack.
- [ ] **2. The bench on staging (SC-005, SC-007).** Run
  `sudo docker exec wassal-staging-worker-1 wassal-solver bench --digest`. The last line's digest
  equals the one in the `solver` job's log for the merge commit, and the `total:` line is under 30
  minutes. Send Claude the total: it sets the effort budget from staging's real speed
  (research R19).
- [ ] **3. A preview on staging (SC-006).** In staging's admin, open `line_hay.01` and click **Run
  the solver**. Within 60 s, a reload shows `solved`, a score in band 0–30 and the timeline.
- [ ] **4. The first publish (SC-012).** Build the sample pack on staging. Its solver stage is
  `passed` or `warning`, with a result for every trip on the pack's page. Publish it, then walk
  [B04's "After B05"](#after-b05) items 3–7.

### Local, any time

- On 2026-10-21 Claude rebuilt the dev image and brought the stack up again, still with
  `WASSAL_DEV_PG_PORT=5433`. The dev database now holds the current sample, packs 3–9 built with
  the real stage, and pack 6 published. `docker compose … down -v` wipes them.
- The dev `.env` keeps `CONTENT_SOLVER_STAGE=stand_in`, so builds queued from the dev admin skip
  the solver. Set it to `solver`, or leave it unset, to try the real stage locally.

## 006 M04 content loader

Built and tested on 2026-10-21, on branch `006-m04-content-loader`
([tasks.md](../specs/006-m04-content-loader/tasks.md),
[quickstart](../specs/006-m04-content-loader/quickstart.md)). The app now loads content packs: the
one bundled in the build, and newer ones it downloads from the manifest. The app version is
`1.0.0+2`.

### Before merge

- [ ] **Quickstart scenarios 2 and 3 on a phone or an emulator (T064).** No device was attached
  when Claude built M04, so only the automated scenarios (1, 4 and 5) have run. With a dev build
  (`fvm flutter run --flavor dev` in `apps/mobile`):
  - **2, offline:** turn on airplane mode, clear the app's storage and open it. The boot screen
    hands over to الموقف, and `flutter logs` shows `content: active v1 (bundled) in <ms> ms`.
  - **3, a new pack from the local stack:** start the stack, run `adb reverse tcp:8000 tcp:8000`,
    and publish version 2 of the sample from the dev admin, as
    [the quickstart](../specs/006-m04-content-loader/quickstart.md#3-a-new-pack-arrives-from-the-local-stack-us2)
    says. Clear the app's storage, open it, and go from الموقف to الخطوط and back: the logs show
    `content: active v2 (stored)`. Reopening within 15 minutes makes no request.
- [x] **T066 The constitution amendment to 1.2.0** (plain HTTP in the dev flavor only, to
  `localhost`, `127.0.0.1` and `10.0.2.2`). Approved on 2026-10-21. The Sync Impact Report comment at
  the top of `.specify/memory/constitution.md` comes out before the commit.

### After merge

Then tick M04 in the [delivery plan's Progress list](delivery-plan.md#progress).

- [ ] **1. T062, timing on the Galaxy A06 (SC-002, SC-003).** Run quickstart scenario 6 in profile
  mode:

  ```bash
  cd apps/mobile
  fvm flutter drive --profile --flavor dev \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/content_load_perf_test.dart
  ```

  The MVP-size pack decodes in ≤ 500 ms and the 2 MiB pack in ≤ 1.5 s. Then measure the cold start
  with `tool/perf/cold_start.sh com.wassalogra.app.dev 10`: the median stays ≤ 3,000 ms. Put the two
  decode medians and the cold-start median in a follow-up issue, and tick this item.
- [ ] **2. After production's first promotion: bundle it.** Follow
  [the runbook's §3](runbooks/content-publishing.md#3-bring-the-content-back-into-the-repository):
  export the pack into `content/source/`, run `bundle release`, and commit the export and the three
  asset files in one PR. Until then every staging and prod build stops at `checkBundledPack`, which
  is expected. Once it merges, make the first staging build.
- [ ] **3. After the next staging publish: the live update (SC-006).** With that staging build
  installed, publish a newer pack on staging. Reopen the app (or wait 15 minutes and bring it back
  to the foreground), then leave Home and come back. The staging app has downloaded the pack and
  switched to it at Home. On a debug build, `adb logcat | grep wassal.content` shows no failure
  event.

With the first real MVP pack, measure the cold start again on a prod build (item 1's command,
with `--flavor prod` and the prod package name).

## 007 M05 local economy

Built and tested on 2026-10-22, on branch `007-m05-local-economy`
([tasks.md](../specs/007-m05-local-economy/tasks.md),
[quickstart](../specs/007-m05-local-economy/quickstart.md)). The app now keeps its economy offline
in a drift database: the operation log and its balances, fuel, trusted time, purchases at the
catalog price, and what M06's sync will call. Constitution 1.3.0 (amended 2026-10-22) clarifies
Principle VI's time clause.

### Before merge

- [ ] **Quickstart scenario 3 on a phone or an emulator (T066).** No device or emulator was
  available when Claude built M05, so only the automated scenarios (1 and 2) have run. In
  airplane mode, with a dev build:

  ```bash
  cd apps/mobile
  fvm flutter test integration_test/economy_offline_test.dart --flavor dev
  ```

  The test deletes the app's database, plays three trips, buys `salon.sitara`, restarts the app
  and finds everything unchanged.
- [x] **The constitution amendment to 1.3.0** (Principle VI: trusted time from an anchor advanced
  by the phone's uptime). Approved in M05's clarification on 2026-10-22. The Sync Impact Report
  comment at the top of `.specify/memory/constitution.md` came out before the commit.

### After merge

All three on the Galaxy A06 (T067). Then tick M05 in the
[delivery plan's Progress list](delivery-plan.md#progress).

- [ ] **1. Timing (quickstart scenario 5, SC-005, SC-006).** In profile mode:

  ```bash
  cd apps/mobile
  fvm flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/economy_perf_test.dart --flavor dev --profile
  ```

  With 50,000 seeded operations, opening the database and reading the balances takes ≤ 200 ms,
  and each kind of operation applies in ≤ 100 ms. The test prints the medians. Then
  `tool/perf/cold_start.sh com.wassalogra.app.dev 10`: the cold start stays ≤ 3,000 ms. Put the
  medians in a follow-up issue.
- [ ] **2. The clock can't be moved (quickstart scenario 4).** Spend a liter, note the next-liter
  time, set the phone's clock 3 hours ahead with the phone on and reopen the app: nothing changes.
  Set the clock back, restart the phone and wait 20 minutes: one liter came back. M02's trip
  screen spends the liter (open a trip from the playtest list on Home), so this check can run once
  M02 merges. Until then, `trusted_clock_test.dart` and `fuel_service_test.dart` cover it with fakes.
- [ ] **3. Backup exclusion (quickstart scenario 6).** `adb shell bmgr backupnow
  com.wassalogra.app.dev`, then restore (Android's "Test backup and restore" steps): the app
  starts as a new player, with a full tank and 0 JENEHAT, while the digit setting comes back.

## 008 M02 trip screen

Built and tested on 2026-10-22, on branch `008-m02-trip-screen`
([tasks.md](../specs/008-m02-trip-screen/tasks.md),
[quickstart](../specs/008-m02-trip-screen/quickstart.md)). The trip is playable: the Flame scene with
stand-in passengers until the Rive file arrives, the dashboard and its help, the events, the failure
card with the BONAT revive, the resume at launch, and the playtest tools on dev and staging.
Constitution 1.4.0 (amended 2026-10-22) places the pause button in the top bar and makes over-change
silent during a trip.

### Before merge, in this order

- [ ] **1. The character file (T059).** Make `apps/mobile/assets/rive/passenger.riv` to
  [contracts/rive-character.md](../specs/008-m02-trip-screen/contracts/rive-character.md) (artboard
  `Passenger`, its state machine and view model with `mood`, `talking`, `asleep`, `headphones`,
  `alight`, `shirt`, `accessory`). Make it yourself rather than remixing a community file (those are
  CC BY 4.0). Export it from a Cadet plan or higher, so it has no splash, and name the plan in the
  PR. Then, in `apps/mobile`:

  ```bash
  fvm dart run rive_native:setup --verbose --clean --platform linux
  fvm flutter test test/features/trip/rive_character_contract_test.dart
  fvm flutter test --update-goldens test/features/trip/rive_character_goldens_test.dart
  ```

  The two `rive`-tagged tests fail until the file is there; everything else passes with
  `fvm flutter test --exclude-tags rive`. Commit the file and the goldens the second test writes.

  *Done on 2026-10-23, except naming the plan: Claude made the file with Rive's MCP in the owner's
  Rive account (still named "Untitled" there) and committed it with its 14 goldens. Name the plan
  in the PR, then tick this.*

  *Superseded by 008.5: `passenger.riv` and its tests are gone; the owner's `wassal.riv` replaces it
  (M21 item 1).*
- [ ] **2. The frame rate on the Galaxy A06 (T065, quickstart "Owner checks" 1 and 2).** Once the
  file is in, with the phone on `adb`:

  ```bash
  cd apps/mobile
  fvm dart run rive_native:setup --platform android
  tool/perf/trip_fps.sh com.wassalogra.app.dev line_gamaa.02
  ```

  Pass: average ≥ 55 fps, no one-second window below 45 fps, memory under 300 MB, a drawer tap in
  the hand within 100 ms, and the first frame within 1 s. Paste the summary in the PR. If it
  misses 45 fps, tell Claude: research R1 lists the mitigations, in order.
- [ ] **3. The device runs Claude couldn't do.** No phone or emulator was available, so these
  integration tests have only run as widget tests. On a dev build, on a phone or an emulator:

  ```bash
  cd apps/mobile
  fvm flutter test integration_test/trip_offline_test.dart --flavor dev    # T044, in airplane mode
  fvm flutter test integration_test/trip_relaunch_test.dart --flavor dev   # T054
  ```

  Then the quickstart's scenarios 1–9 by hand (T099): a trip offline, interruptions, leaving and
  restarting, passengers and choices, the events, the help, failing, the playtest tools, and
  accessibility.
- [x] **4. Remove the Sync Impact Report** comment at the top of `.specify/memory/constitution.md`
  before the commit (the 1.4.0 amendment).

### After merge

Then tick M02 in the [delivery plan's Progress list](delivery-plan.md#progress).

- [ ] **1. Download size (T100).** Build the release app bundle and check the arm64 download:
  `bundletool get-size total`. It must stay under 80 MB; `rive_native` adds about 8 MB
  (research R2).
- [ ] **2. Playtest (T101, SC-009).** Five testers from outside the team play `line_hay.01` on a
  staging build, without instructions. Record who finishes it and who replays by choice.

## 008.5 M21 design refresh

Built and tested on 2026-10-23, on branch `008.5-m21-design-refresh`
([tasks.md](../specs/008.5-m21-design-refresh/tasks.md),
[quickstart](../specs/008.5-m21-design-refresh/quickstart.md)). Everything built so far is in the
«كرتون ناعم» design: the generated tokens and shared components, the bottom nav, sheets and dialogs,
the `Loading` boot screen, the trip screen and its cards, and every person, vehicle and UI animation
from `assets/rive/wassal.riv`, with the static SVGs as the fallback. The launcher icon is direction
أ. Each artboard has its golden, its layout test and a compare image.

### Before merge, in this order

- [ ] **1. The Rive file (T110, contracts/rive-characters.md "Open").** It stays on Rive's free
  plan (your decision of 2026-10-23, research R15). The free export's splash artboards stay in the
  file, and the app never draws them. In your Rive account:
  - add the Boolean `reducedMotion` to the `Passenger` view model (true holds the z's, sweat,
    sparks, hearts and notes still), and say whether you want a `skinTone` colour;
  - replace `apps/mobile/assets/rive/wassal.riv` with the export, then, in `apps/mobile`:

    ```bash
    fvm dart run rive_native:setup --verbose --clean --platform linux
    fvm flutter test --tags rive
    fvm flutter test --update-goldens test/features/trip/rive_art_goldens_test.dart
    ```

  - review the sheets it writes in `test/features/trip/goldens/rive_*.png` (each look in seven
    poses at 84 and 52.5 pt, the six characters, the vehicles, the UI loops), and commit them with
    the file;

  Until then, under reduced motion people are drawn with the static art; nothing else changes.
- [ ] **2. Frame rate and memory on the Galaxy A06 (T111, quickstart "Owner checks" 2).** With the
  phone on `adb`:

  ```bash
  cd apps/mobile
  fvm dart run rive_native:setup --platform android
  tool/perf/trip_fps.sh com.wassalogra.app.dev line_gamaa.02
  ```

  Pass: average ≥ 55 fps, no one-second window under 45 fps, memory under 300 MB; record the p90
  frame time. If it misses on the `rive` tier, switch the debug panel's «الرسم» to `near_rive`, run
  it again, and tell Claude both results: they go in research.md R18, and `near_rive` becomes the
  default.
- [ ] **3. Cold start on the A06 (T124, SC-006).** `tool/perf/cold_start.sh com.wassalogra.app.dev 10`:
  no white frame, and Home within 3 s. Paste the output in the PR.
- [ ] **4. Side by side (T126, SC-010).** Run, in `apps/mobile`:

  ```bash
  fvm flutter test test/design test/goldens/design --dart-define=DESIGN_COMPARE=true
  ```

  and open each image in `apps/mobile/build/design_compare/` (ten artboards, both digit styles).
  Accept each, or list what to change. The expected differences are in
  [design-checks.md](../specs/008.5-m21-design-refresh/contracts/design-checks.md#what-a-golden-may-differ-in)
  and the PR.
- [ ] **5. Short screens (plan.md, Complexity Tracking).** Approve, or not, that on screens shorter
  than `inset + 764` pt (such as 360×640) the dashboard's top rows sit above the bottom third, until
  M07's short-screen layout. On the reference frame and the A06 every control is in the bottom
  third.
- [ ] **6. The launcher icon (T131).** On a dev build on the A06, check the icon on the home screen
  in each shape the launcher offers (circle, squircle, rounded square), and the themed (monochrome)
  icon with Android's themed icons on.
- [ ] **7. The device runs Claude couldn't do.** No phone or emulator was available. Run
  quickstart.md's scenarios on a dev build.

### After merge

Then tick Step 5.5 in the [delivery plan's Progress list](delivery-plan.md#progress) with the PR
number.

- [ ] **1. Download size (T125, SC-009).** Build the release app bundle
  (`fvm flutter build appbundle --flavor prod --release`) and check the arm64 download with
  `bundletool get-size total`: under 80 MB.
- [ ] **2. The Play listing (T131).** Upload `docs/design/brand/store_icon_512.png` as the app icon
  and `docs/design/brand/feature_graphic_1024x500.png` as the feature graphic in the Play Console's
  store listing.

## 009 B02 accounts and auth

Built and tested on 2026-10-24, on branch `009-b02-accounts-auth`
([tasks.md](../specs/009-b02-accounts-auth/tasks.md),
[quickstart](../specs/009-b02-accounts-auth/quickstart.md)). Players get an account from their
install id, sessions with rotating refresh tokens, Google linking with its conflict choice, and a
read-only player page in the admin for the `player_support` group. Everything the app does with it
comes in M06.

### Before merge, in this order

Both go in before the first deploy that carries B02. Without them the settings check stops the new
release at the migrate step, and the deploy keeps the previous one.

- [ ] **1. Google Cloud (T065).** The project is the Firebase project `wassal-ogra` (number
  197022799720), so Firebase and the sign-in clients share it. In "Google Auth Platform"
  (<https://console.cloud.google.com/auth/overview?project=wassal-ogra>):
  - **Branding:** the app name and a support email. Leave the app in **Testing**, with your Google
    accounts as test users, until the real domain exists (item 3 below).
  - **The server (web) client**, done on 2026-10-25:
    `197022799720-tdrrsi23dpbiqtombflevorurpv2c2aa.apps.googleusercontent.com`, the value of
    `GOOGLE_OAUTH_CLIENT_IDS` on staging and prod. Add the OAuth Playground
    (`https://developers.google.com/oauthplayground`) to its authorized redirect URIs, for the live
    check. Its secret stays in your password manager: no host needs it.
  - **The Android clients**, which the app's Google sign-in needs (B02 needs only the web client).
    Each takes one package and one SHA-1, and Firebase doesn't create them: add them under
    "Clients". `com.wassalogra.app.dev` and `com.wassalogra.app.staging` with the debug keystore's
    SHA-1 (`15:91:09:F4:48:9B:F9:CF:42:2F:EB:11:4D:EF:60:2D:45:79:68:DD`, which signs every build
    today), then `com.wassalogra.app` with Play App Signing's SHA-1 once Play Console has it, plus
    one with the upload key's if you install builds you signed yourself.
  - **The iOS clients**, one per bundle ID (`com.wassalogra.app.dev`, `.staging`,
    `com.wassalogra.app`), before iOS sign-in. Until they exist, Firebase's
    `GoogleService-Info.plist` has no `CLIENT_ID`.
  - Done on 2026-10-25: the six Firebase apps (Android and iOS; dev, staging and prod), with the
    debug key's SHA-1 and SHA-256 on the dev and staging Android apps. Their config files go into
    the repo with the feature that adds Firebase to the app.
- [ ] **2. Each VM's env file (T066).** Follow
  [auth-keys.md "Before B02's first deploy"](runbooks/auth-keys.md#before-b02s-first-deploy): make
  one key per environment with `uv run manage.py auth_signing_key` (in `backend/` on your machine),
  then add `AUTH_SIGNING_KEYS` and `GOOGLE_OAUTH_CLIENT_IDS` (the web client id) to
  `/etc/wassal/staging.env` on the staging VM and `/etc/wassal/prod.env` on the prod VM. The two
  keys must differ. Keep both in your password manager.
  - Each file holds **one entry**, its own environment's key. A key in both files makes prod accept
    staging's tokens, and two entries made the same day share a `kid`, which startup refuses.
  - Check each VM without printing a key. The first line prints one label, and the second gives a
    different sum on each VM:

    ```bash
    sudo sed -n 's/^AUTH_SIGNING_KEYS=//p' /etc/wassal/<env>.env | tr ',' '\n' | cut -d: -f1
    sudo sed -n 's/^AUTH_SIGNING_KEYS=//p' /etc/wassal/<env>.env | sha256sum
    ```

### After merge

- [ ] **1. The live checks on staging (T067).** Once staging deploys from `master`, run
  [quickstart Part B](../specs/009-b02-accounts-auth/quickstart.md#b-live-on-staging-owner), B1 to
  B8. B7 (latency) and B8 (key rotation) follow [auth-keys.md](runbooks/auth-keys.md). Paste the
  results in the PR, then tick `009-b02-accounts-auth` in the
  [delivery plan's Progress list](delivery-plan.md#progress) with the PR number.
- [ ] **2. Key rotation reminders.** A yearly calendar reminder per environment for
  [auth-keys.md "Rotating"](runbooks/auth-keys.md#rotating). Each rotation sets its own second
  reminder, 30 days and 15 minutes later.

### Before the closed test

- [ ] **Google sign-in for everyone (T068).** Move the Google Auth Platform app from Testing to
  **In production**, once the real domain and the privacy policy exist (see "Known for later
  features"). Until then only the test users can link.

## 010 B03 ledger and sync

Built and tested on 2026-10-25, on branch `010-b03-ledger-sync`
([tasks.md](../specs/010-b03-ledger-sync/tasks.md),
[quickstart](../specs/010-b03-ledger-sync/quickstart.md)). The server keeps every player's money in
an append-only ledger, applies the app's offline operations through `POST /v1/sync` once each,
answers `GET /v1/bootstrap` and `GET /v1/state`, grants the gifts and story rewards, and notes odd
play as flags that staff review. Staff in `economy_ops` can adjust a balance. The app's side comes
in M06.

### Before merge

- [ ] **1. Approve the constitution VIII deviation (plan, Complexity Tracking).** The server-only
  numbers (the overdraft limit, the traffic-jam ad cap, the comeback gaps, the two flag thresholds
  and the hard duration bound) are environment settings with no Remote Config key and no
  `LiveSetting` copy until B10 moves them there. Their defaults are in
  [mobile §14.3](architecture-mobile.md) and
  [contracts/environment.md](../specs/010-b03-ledger-sync/contracts/environment.md). Say "approved"
  (or what to change) and Claude records it in the plan.

### After merge

- [ ] **1. The rules index and the live checks (T099).** Once staging deploys from `master`, run
  [economy.md "Before B03's first deploy"](runbooks/economy.md#before-b03s-first-deploy) on staging
  (the `content_index --rebuild` step), then
  [quickstart Part B](../specs/010-b03-ledger-sync/quickstart.md), B1 to B5: B3 is `economy_check`,
  B4 the load script (raise `THROTTLE_ADDRESS_RATE` and `THROTTLE_ANONYMOUS_RATE` in the staging
  env file for the run, then set them back). Then B1 and B3 on production. Paste the results in the
  PR, then tick `010-b03-ledger-sync` in the
  [delivery plan's Progress list](delivery-plan.md#progress).
- [ ] **2. Staff and the name filter (T100).** Create the `economy_ops` members
  (`create_staff <name> --group economy_ops`,
  [staff-accounts.md](runbooks/staff-accounts.md)), and read the name filter's seed list in the
  admin (Accounts → Name filter): delete what blocks honest names, add what is missing. A term is
  matched in any common Arabic spelling, but Latin terms must be entered in Latin too.

### After the closed test starts

- [ ] **Tune the flag thresholds (T100).** Read the first `fast_three_star` and `trip_rate` flags in
  the admin. If honest players are flagged, change `SYNC_FAST_RUN_PERCENT` or
  `SYNC_TRIPS_PER_DAY_FLAG` in the env file as
  [economy.md "Tuning the flag thresholds"](runbooks/economy.md#tuning-the-flag-thresholds) says.

## 011 M06 identity and sync

Built and tested on 2026-10-27, on branch `011-m06-identity-sync`
([tasks.md](../specs/011-m06-identity-sync/tasks.md),
[quickstart](../specs/011-m06-identity-sync/quickstart.md)). The app now has an account without a
sign-up: it creates one in the background with an install id that survives a re-install, keeps its
tokens in secure storage, and sends the offline operations to the server once each. A re-install on
the same phone gets its progress back. Home shows the offline banner and the maintenance card, and
every screen but the trip shows the update card. Internal builds' Home has a «sync» card with
«sync now». M14 builds the Google linking screens on its link request.

### Before merge

- [ ] **1. Approve two lines (T052, T075).** The toast after a sync takes back something you saw,
  «رصيدك اتظبط على آخر حساب», and the optional update card's second button, «بعدين», which the
  design doesn't draw. Say "approved" or give the wording, and Claude changes `app_ar.arb`.
- [ ] **2. The device checks (T091).** [Quickstart Part B](../specs/011-m06-identity-sync/quickstart.md#part-b-on-a-device)
  steps 1–14 on the Redmi Note 7, with Google backup on (Settings › Google › Backup), against the
  local stack. Step 7 is the re-install; step 14 reads `adb logcat` for tokens and the install id.
  Tell Claude what any step showed that the table doesn't expect.

### After merge

- [ ] **1. Staging (T091).** Quickstart steps 2, 7 and 14 again on a staging build.
- [ ] **2. The App Store id (T074), once the App Store listing exists.** Until then the iOS update
  card has no store button (it still blocks when forced). Give Claude the listing's numeric id for
  `iosAppStoreId` in `apps/mobile/lib/core/platform/store_launcher.dart`.
- [ ] **3. The iPhone re-install (T093, SC-006).** Run one Codemagic `ios-dev-unsigned` build of the
  branch (it now points the dev IPA at staging), sideload it as
  [ios-test-build.md](runbooks/ios-test-build.md) says, then quickstart step 15: note the player id
  on the «sync» card, delete the app, sideload it again, and check the same player comes back.
- [ ] **4. The Galaxy A06 (SC-001).** `tool/perf/cold_start.sh com.wassalogra.app.dev 10` with a
  median of 3,000 ms or less, and one first open of a returning player (a re-install with the
  network on), at most 3 s longer.

## 012 M07 onboarding

Built and tested on 2026-10-27, on branch `012-m07-onboarding`
([tasks.md](../specs/012-m07-onboarding/tasks.md),
[quickstart](../specs/012-m07-onboarding/quickstart.md)). A new player now gets the first session:
the opening scene, the Name card with a suggested name, five tutorial trips with بلية's coach, the
سلمى scene after trip 3, المعلم's fuel lesson and a full tank before trip 5, then Home. The name
saves at once and syncs later; a refused name is asked again on Home. Short screens (under 788 pt
with a 24 pt status bar, such as 360×640) get the trip screen's compact profile, where every minimum
size holds, which closes M02's exception. Internal builds' Home has an «Onboarding» card that
replays each screen and can coach every tutorial trip.

### Before the fuel lesson's design checks

- [x] **1. Draw `FuelLesson` and the five missing comic panels (T073).** Done on 2026-10-28: drawn
  with Claude Design, then exported, mapped and checked by Claude (T080). On the Claude Design canvas
  «وصّل الأجرة — Design», from [fuel-lesson.md](../specs/012-m07-onboarding/contracts/fuel-lesson.md)
  Part 1: the `FuelLesson` board, and the panels `opening_stand`, `opening_go` and the سلمى scene's
  three. Export with `docs/design/tools` (`export.py`, `boxes.py` + `boxes_post.py`,
  `build_assets.py`) and commit `docs/design/screens/FuelLesson.html`, `png/FuelLesson.png`,
  `boxes/FuelLesson.json`, the new illustrations and `manifest.json`, or hand the export to Claude.
  Claude then maps the panel slugs and adds the design checks (T080). Until then the panels show a
  plain fallback, and the fuel lesson follows the brief.

### Before merge

- [ ] **1. Approve the lines (T042, T058, T078, T087).** In `apps/mobile/lib/l10n/app_ar.arb`:
  - بلية's coach lines, `coach*` (research R18): «شايف؟ الأجرة وصلت الدرج», the change line with
    its coin and count, «دلوقتي دوس عليه.», the stop line with the station, the sleeper line;
  - المعلم's fuel lesson, `fuelLesson*`: «تفويلة من المعلم», «البنزين قرّب يخلص يا أسطى. كل مشوار
    بلتر، والمرة دي التفويلة عليّا!», the refill line, «يلا على المشوار», and the gauge's marks E and F
    (`fuelGaugeEmpty`, `fuelGaugeFull`, as the board draws them);
  - the name pool (`namePool`), the refused line «الاسم ده مينفعش. اختار اسم تاني.» and the
    default name «الأسطى».

  Say "approved" or give the wording, and Claude changes `app_ar.arb`.
- [ ] **2. Approve the compact look (T096).** The 360×640 trip goldens,
  `apps/mobile/test/goldens/trip/goldens/*_small_*.png` (and `*_mid_*.png`, 360×720). Three choices
  differ from the plan, because the plan's version covered the fares: reputation is a 6 pt line on
  the station strip's top edge, not its bottom; the compact strip has no «الموقف» label; a raised
  fare shows only the new fare in its red pill. On internal builds the debug button narrows the
  strip, so four long station names with a raised fare can reach over it (prod builds fit).
- [ ] **3. The trip title's new place.** In the compact profile the HUD has no title: it is in the
  pause card, over «واقفين على جنب». Confirm on the goldens (`paused_small_*.png`).
- [ ] **4. The device checks (T106).** [Quickstart Part B](../specs/012-m07-onboarding/quickstart.md#part-b-on-a-device)
  steps 1–15 on the Redmi Note 7, with the release draft imported on the local stack (its opening
  scene and `plays` added, as Part B's setup says). Tell Claude what any step showed that the
  table doesn't expect.

### After merge

- [ ] **1. The Galaxy A06 (SC-001).** From a fresh install, the first trip starts in under 20 s.
- [ ] **2. The frame rate on a coached trip.** `tool/perf/trip_fps.sh com.wassalogra.app.dev line_hay.02`
  on the A06, with the tutorial not yet done.
- [ ] **3. The moderated playtest (SC-007).** Five new players through the first session.
- [x] **4. The release draft.** Add chapter 1's opening scene and the scenes' `plays` to
  `content/drafts/core-r1` on the `content-core-r1` branch (research "Handed to later features"),
  before it is promoted. Done by Claude on 2026-10-28, in the `content-core-r1` worktree (uncommitted,
  like the rest of the draft):
  - the sample's three-panel opening;
  - `first_sight` after `line_hay.03`;
  - `moallem_verdict` after `line_hay.20`.

  Imported on the local stack as pack 11.

## 012.5 M22 animated scenes

Built and tested on 2026-10-28, on branch `012.5-m22-animated-scenes`
([tasks.md](../specs/012.5-m22-animated-scenes/tasks.md),
[quickstart](../specs/012.5-m22-animated-scenes/quickstart.md)). The first session's comic panels
now play as animations from a second Rive file, `wassal_scenes.riv`: the tuktuk drives, the
characters move, and each line's bubble appears while its speaker talks. «يلا» first shows the rest
of a panel's bubbles, then moves on. Without the file, for a panel whose artboard fails its check,
or under reduced motion, the panel is M07's drawing. The release draft's `ch1_*` panels draw the
same art. The usta has one look everywhere: the owner's new `wassal.riv`, and the design rebuilt
from the canvas.

### Before merge

- [ ] **1. The phone checks (T052).** [Quickstart Part B](../specs/012.5-m22-animated-scenes/quickstart.md#part-b-on-the-phones-owner)
  step 1 on the Redmi Note 7, with reduced motion off, then on. Then one timed first session on a
  fresh install (step 3's last bullet): the first trip within 20 s of opening the app. Claude asks
  before connecting to the phone. Your first run (2026-10-28) found that a finished panel needed two taps
  of «يلا»; that is fixed in the PR, so rebuild before checking again.
- [ ] **2. Rename the Rive source (quickstart Part B step 4).** In the Rive editor, rename «Untitled»
  to `wassal_scenes`. The app's copy doesn't change.
- [ ] **3. `opening_key`'s sky (T019).** The file's first frame of `opening_key` has the blue sky
  (`#BFE6F7`) and two clouds, as all six artboards do. Its drawing (the `Intro` board's art) has
  neither, unlike the other five drawings, so the still panel's top is the pale screen ground. The
  contract says the first frame is the drawing. Choose: redraw the `Intro` panel with the sky on the
  canvas (Claude then rebuilds `docs/design/` and syncs), or keep the file as it is.
- [ ] **4. The usta's quiff on the Name card (T044).** The avatar's head-and-shoulders crop (008.5)
  cuts about 4 pt off the tip of the new quiff (`test/goldens/design/goldens/Name_*.png`). Choose:
  keep it, or let Claude widen the crop, which moves every avatar a little and changes their goldens.
- [ ] **5. The design rebuild's leftovers (T041).** Rebuilding `docs/design/` from the canvas took
  only the usta's files. Say which of these to add, if any:
  - the canvas's new `SceneMotion` artboard («حركة المشاهد», on «النظام والمكوّنات»);
  - the brand boards and the Logo's unnamed icon (`brand/` is kept by hand today);
  - remeasured `boxes/`: this machine's Chromium measures text up to about 2 px differently, so
    every box moves a little without any change on the canvas. Claude kept the committed boxes.

### After merge

- [ ] **1. Every panel on the Galaxy A06 (SC-001).** Quickstart Part B step 1.
- [ ] **2. The frame rate and cold start on the A06 (SC-002, SC-003).**
  `tool/perf/scene_fps.sh com.wassalogra.app.dev` (paste the output in the PR or here), then
  `tool/perf/cold_start.sh com.wassalogra.app.dev 10`.
- [ ] **3. The first trip within 20 s on the A06 (SC-003, M07 SC-001).** On a fresh install, tap
  «يلا» as soon as it shows and accept the suggested name.
- [ ] **4. The release draft's line change.** The draft's `ch1_usta_dreams` line is now the usta's,
  in the `content-core-r1` worktree. It is committed with the draft, not in this PR.

## 013 M08 Home, pre-trip card and result

Built and tested on 2026-10-28, on branch `013-m08-home-result`
([tasks.md](../specs/013-m08-home-result/tasks.md),
[quickstart](../specs/013-m08-home-result/quickstart.md)). Home (الموقف) shows the next trip, the
line card, the savings goal, fuel and its countdown, and opens one arrival item at a time; the
pre-trip card shows the stops and their prices, the star goals, a «جديد» card for a new passenger
type or event, and the boosters; the result shows the stars, the breakdown, the mistakes, the pay,
the apartment bar and a passenger's line, and shares itself as a 1080×1080 picture. The playtest
Home is gone: its trip list is in Home's debug sheet on dev and staging.

### Before merge

- [ ] **1. The strings (T083).** Read the drafts in
  [research R18](../specs/013-m08-home-result/research.md#r18-strings-and-the-owners-approval),
  as they stand in `apps/mobile/lib/l10n/app_ar.arb`: the 19 «جديد» names and sentences, the goal
  titles, the mistake lines and the three summary families, the barker's call, the rule line for
  discounts other than 50%, and the share caption («قبضت … في مشوار … في وصّل الأجرة!»). Say what
  to change; Claude applies it and regenerates the goldens it touches.
- [ ] **2. The departures and the golden differences (T084).** Approve or refuse:
  - the three departures in the plan's Complexity Tracking: the booster buy asks for confirmation
    instead of the 3-second undo until M12 (R7), the fuel pill's screen-reader label gives minutes
    only (R11), and the goal title uses the vehicle's full name (R4);
  - the expected differences from the artboards (R20): the barker, riders and painted street, and
    the «جديد» card's event icons, which reuse existing glyphs;
  - the ones found while building, listed in the PR: Home's offline banner follows `HomeStates`
    (40 high) where `States` draws it alone; the goal tile's glyph follows the goal's kind (the
    microbus for a vehicle); the result's apartment tile is the ring until M09 brings the pieces'
    art; the share card's missed-star outline is built from two icons; with Western digits, Home's
    header and the goal card's second row wrap at 390 pt.
- [ ] **3. iOS (T086).** Run Codemagic's `ios-dev-unsigned` on the branch: it must build with no
  Podfile (`share_plus` comes as a Swift Package). Sideload it and check that «شارك» opens the
  share sheet ([quickstart §8](../specs/013-m08-home-result/quickstart.md#8-ios-owner)).
- [ ] **4. The side-by-side images (T086).** Run
  `fvm flutter test test/design test/goldens/design --dart-define=DESIGN_COMPARE=true` in
  `apps/mobile` and look at `build/design_compare/` for `C-Home`, `HomeStates`, `PreTrip`, `Result`
  and `ShareCard`, in both digit styles, beside `docs/design/png/`
  ([quickstart §4](../specs/013-m08-home-result/quickstart.md#4-the-design-checks-sc-005)).

### After merge

- [ ] **1. The device pass (T088).** [Quickstart §7](../specs/013-m08-home-result/quickstart.md#7-by-hand-on-the-owners-phone-dev-build)
  on the Redmi Note 7, or the Galaxy A06 when there is one: Home's figures, the countdown against a
  changed clock (SC-003), offline, the card's setting, a booster buy, the result, the arrival check,
  the share within a second (SC-010), and Home within a second after the result and a tab switch
  (SC-002). Claude asks before connecting to the phone.
- [ ] **2. The 10-player playtest (T089).** SC-008: do 8 of 10 know which star they missed and why,
  from the result alone? SC-009: do 8 of 10 who meet a new passenger type know what it does from the
  card? Tell Claude the counts.

## Known for later features

- **Solver previews (B05), when the admin gets more users or scripts.** Two things were left out on
  purpose, because today the admin has one or two staff, behind WireGuard, and previews exist only
  on staging:
  - a limit on active previews per user or overall (today it is one per trip). Many previews at
    once would delay staging's builds, which share the `content` queue;
  - pruning old `SolverRun` rows. Each preview adds one, with the staff name, and nothing removes
    them. Keep the newest `done` run of each `input_key`, which builds reuse.

- **Register the real domain before the first closed test.** That test is the step 7 option or
  step 12. B09's account-deletion page needs the domain too, and so does Google sign-in for
  players who aren't test users (B02 T068). The switch is configuration only: the
  hostnames in each VM's `/etc/wassal/edge.env` and its environment's `API_HOST` and `ADMIN_HOST`.
