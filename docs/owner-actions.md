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
| [006 M04 content loader](#006-m04-content-loader) | 1 | 1 now, 2 after production's first promotion | Built 2026-10-21 on `006-m04-content-loader`. Open as #7. |

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
  the edge, because a native PostgreSQL holds port 5432 on this machine. Keep exporting it, with the
  matching port in `backend/.env`'s URLs.
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

## Known for later features

- **Solver previews (B05), when the admin gets more users or scripts.** Two things were left out on
  purpose, because today the admin has one or two staff, behind WireGuard, and previews exist only
  on staging:
  - a limit on active previews per user or overall (today it is one per trip). Many previews at
    once would delay staging's builds, which share the `content` queue;
  - pruning old `SolverRun` rows. Each preview adds one, with the staff name, and nothing removes
    them. Keep the newest `done` run of each `input_key`, which builds reuse.

- **Register the real domain before the first closed test.** That test is the step 7 option or
  step 12. B09's account-deletion page needs the domain too. The switch is configuration only: the
  hostnames in each VM's `/etc/wassal/edge.env` and its environment's `API_HOST` and `ADMIN_HOST`.
