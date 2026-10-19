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
| [002 B01 backend skeleton](#002-b01-backend-skeleton) | 8 | 7 | Built and tested, not committed |

## Every month

This starts once production is live (B01). The restore drill runs by itself on the 1st at 05:00 Cairo
time. The routine keeps the free accounts and their guarantees alive
([B01 quickstart](../specs/002-b01-backend-skeleton/quickstart.md#monthly-operating-routine-operator)):

- Check that the drill's line for this month in `/var/lib/wassal/drill-results.jsonl` passed.
- Sign in to the OCI console. Oracle may suspend a tenancy left idle for 30 days.
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

### Before merge, in this order

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
- [ ] **T054 Provision the host.** Follow [provision-host.md](runbooks/provision-host.md) §1–8.
  §10 lists what to record:
  - the real `/etc/iptables/rules.v4`, saved before the first render, replaces
    `backend/docker/host/tests/fixtures/oracle-rules.v4`. Then ask Claude to re-run the firewall
    tests (T044);
  - `iptables -S` from before and after, in research.md R13;
  - the latency baseline from Egypt, in `docs/architecture-backend.md` §2;
  - the time from §1 to a serving production (SC-009).
- [ ] **Outside services.** Follow [monitoring-setup.md](runbooks/monitoring-setup.md):
  - Healthchecks.io: 5 checks;
  - UptimeRobot: 1 monitor. Save a dated copy of its terms;
  - Sentry: done on 2026-10-19. Organization `saied-store-div` (US region, by your choice) and
    project `wassal-backend` exist, and test errors from the web and worker processes arrived. Put
    its DSN in `SENTRY_DSN` in `/etc/wassal/staging.env` and `/etc/wassal/prod.env`.

  Then fill in the remaining `/etc/wassal/*.env` files (provision-host.md §9).
- [ ] **T084 Backblaze B2.**
  - Turn on MFA, and set USD 0 caps on storage and on Class A, B and C transactions.
  - Keep the admin key in your password manager. It never goes on the host.
  - Run `uv run tools/b2_setup.py --daily-bucket <name> --weekly-bucket <name>` from `backend/`.
    Copy the lines it prints into `/etc/wassal/prod-backup.env` and `/etc/wassal/prod-drill.env`.
  - Record the account's region in research.md R9 "Data location".
- [ ] **T061 Deploy access** ([deploy-and-rollback.md](runbooks/deploy-and-rollback.md)):
  - create the GitHub Environments `staging` and `production`. Production deploys tags matching
    `v*` only. Required reviewers on production are recommended;
  - add `WG_CONFIG`, `DEPLOY_SSH_KEY` and `DEPLOY_KNOWN_HOSTS` to each environment;
  - add the two deploy peers and keys on the host (provision-host.md §8).
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

Then merge the PR. The merge deploys staging.

### After merge

- [ ] **T062 Deploys.**
  - The merge deploys staging (scenario 10).
  - Tag `v0.1.0` on `master`, which deploys production.
  - Walk scenarios 11–15:
    - the two staging rehearsals, while polling production's `/healthz`, to show it isn't touched;
    - a tag on a branch commit is refused;
    - a rollback takes ≤ 10 min;
    - a deploy causes ≤ 30 s of downtime.
  - Two merges within a minute deploy one after the other.

  Record the results in the PR or a follow-up issue.
- [ ] **T055 Production checks.** Walk scenarios 1–9 and 23:
  - HTTPS and HSTS from mobile data, and the 308 redirect;
  - an outside port scan; the admin unreachable off WireGuard;
  - OTP and lockout over WireGuard; removing a peer;
  - API and admin host separation, and the 413;
  - staging and production share nothing.
- [ ] **T070 Monitoring.** Walk scenarios 16–18:
  - Sentry issues are tagged with the environment and release, with no IP, cookies or headers;
  - the uptime alert arrives within 10 min;
  - the heartbeat alert arrives within 20 min.

  Then force a host-monitor failure with a one-off `DISK_ALERT_PERCENT=1` run, and confirm the
  email arrives.
- [ ] **T085 Backups.** Walk scenarios 19–21:
  - a manual backup;
  - the backup key is refused a version delete and a listing, and a re-upload keeps the original
    version;
  - an on-demand drill passes and leaves nothing behind.

  Add the drill's restore time to T054's setup time. The sum must be ≤ 4 h.
- [ ] **T091 Cross-cutting checks.**
  - After a reboot, production serves again within 5 min (scenario 22).
  - SC-002's 100 requests, on both API hostnames.
  - Your first monthly routine (above) shows USD 0 on every service.
- [ ] **Tick B01** in the [delivery plan's Progress list](delivery-plan.md#progress) once T062, T055,
  T070, T085 and T091 pass.
- [ ] **About 17 days after the first backup** (scenario 24):
  - the first day's pair is gone from the daily bucket;
  - `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check` passes.

  This doesn't hold up ticking B01. If it fails, the lifecycle rules get fixed in a follow-up.

### Local cleanup, any time

These are leftovers from Claude's test runs:

- `docker exec wassal-dev-postgres-1 rm /tmp/restore-e2e.dump /tmp/restore-e2e.list`
- `docker image rm wassal-backend:drill-e2e ghcr.io/ahmedsaied94/wassal-backend:v0.0.99`

## Known for later features

- **Register the real domain before the first closed test.** That test is the step 7 option or
  step 12. B09's account-deletion page needs the domain too. The switch is configuration only: the
  hostnames in `/etc/wassal/edge.env` and each environment's `API_HOST` and `ADMIN_HOST`.
