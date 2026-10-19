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
| [002 B01 backend skeleton](#002-b01-backend-skeleton) | 10 | 8 | Built and tested, not committed. Moving to one VM per environment (Phase 10). |

## Every month

This starts once production is live (B01). The restore drill runs by itself on the 1st at 05:00 Cairo
time, on the staging VM. The routine keeps the free accounts and their guarantees alive
([B01 quickstart](../specs/002-b01-backend-skeleton/quickstart.md#monthly-operating-routine-operator)):

- Check that this month's drill line passed: `/var/lib/wassal/drill-results.jsonl`, on the staging
  VM.
- Sign in to the OCI console, and check that both instances run. Oracle may suspend a tenancy left
  idle for 30 days.
- Sign in to Healthchecks.io. It deletes accounts with no login for a year.
- In the B2 console, check that the caps are still USD 0 and storage is well under 10 GB. If anything
  in the console changed, run `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check` from `backend/`.
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
       `wassal-host-monitor.timer`, and `systemctl is-enabled wassal-backup@prod.timer` says
       `disabled`;
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
    with `host-monitor-staging`'s URL and the thresholds, without `BACKUP_STORAGE_ALERT_BYTES`,
    and test it
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

## Known for later features

- **Register the real domain before the first closed test.** That test is the step 7 option or
  step 12. B09's account-deletion page needs the domain too. The switch is configuration only: the
  hostnames in each VM's `/etc/wassal/edge.env` and its environment's `API_HOST` and `ADMIN_HOST`.
