# Runbooks

Each runbook covers one area. The first-time setup crosses all of them, so this page gives the
order. Do the steps top to bottom. Each one links to the section that has the commands.

Staging and production each run on their own VM, and each VM is set up, monitored and repaired on
its own:

| | prod VM | staging VM |
| --- | --- | --- |
| Reserved public IP | `193.122.74.125` | `141.147.129.92` |
| WireGuard address | `10.66.0.1` | `10.67.0.1` |
| API | `api.193-122-74-125.sslip.io` | `staging-api.141-147-129-92.sslip.io` |
| Admin | `admin.10-66-0-1.sslip.io` | `staging-admin.10-67-0-1.sslip.io` |
| Also runs | the nightly backup | its own nightly backup (since B04), and the monthly restore drill of production's backups |

| Runbook | What it covers |
| --- | --- |
| [provision-host.md](provision-host.md) | Creating a VM and preparing it, up to its deploy key. Run once per VM. |
| [private-network.md](private-network.md) | Each VM's WireGuard peers, the admin addresses, the two admin CA roots |
| [monitoring-setup.md](monitoring-setup.md) | Healthchecks.io, UptimeRobot, Sentry, Backblaze B2, the monthly routine, and which env file goes on which VM |
| [deploy-and-rollback.md](deploy-and-rollback.md) | How releases reach each VM, rollbacks, the images to keep, the one-time GitHub setup |
| [staff-accounts.md](staff-accounts.md) | Admin accounts and their second factor, per environment |
| [restore.md](restore.md) | Restoring a backup into production or staging, rebuilding either VM, the drill's results |
| [content-publishing.md](content-publishing.md) | Authoring, building and publishing on staging, promoting to production, `content/source`, rollback, the minimum app version |
| [break-glass.md](break-glass.md) | Getting back into a VM when WireGuard or SSH doesn't work |

## First-time setup

Keep every secret (passwords, keys, ping URLs, the Sentry DSN) in your password manager as you
create it. You paste them into each VM's env files in stage 2.

### 1. Accounts (no host needed)

These need only your machine and a browser, so you can do them before the VMs exist.

1. **Sentry:** [monitoring-setup.md "Sentry"](monitoring-setup.md#sentry-errors), steps 1–5. Keep
   the DSN.
2. **Healthchecks.io:** [monitoring-setup.md "Healthchecks.io"](monitoring-setup.md#healthchecksio-dead-mans-switches),
   steps 1–3. Keep the seven ping URLs. A new check stays grey until its first ping, so it sends no
   alert yet.
3. **Backblaze B2:** [monitoring-setup.md "Backblaze B2"](monitoring-setup.md#backblaze-b2-backups),
   steps 1–6, then step 8 for staging's own backups. It prints the backup and drill keys once.
   Step 7 waits for stage 2.
4. **GitHub failure emails:** [monitoring-setup.md "GitHub"](monitoring-setup.md#github-deploy-failures).

### 2. The VMs, one at a time

Do every step below on the staging VM first, then on the prod VM. A mistake on the first pass then
costs staging, not production. Each VM gets its own values from
[provision-host.md "The two VMs"](provision-host.md#the-two-vms).

1. **VM, reserved IP, VCN and security list:** [provision-host.md §1](provision-host.md#1-reserve-the-ip-and-create-the-vm).
2. **Console password and serial console test:** [§2](provision-host.md#2-console-password-then-test-the-serial-console).
3. **Provisioning script:** [§3](provision-host.md#3-run-the-provisioning-script), with
   `--env staging` or `--env prod`. It records the VM's environment and creates `wg0` on its
   address: `10.67.0.1` on staging, `10.66.0.1` on prod. Don't set up WireGuard by hand before
   this: the firewall, sshd and the admin hostname all expect that address.
4. **Env files:** [§4](provision-host.md#4-fill-the-environment-files). Each VM gets only its own:
   - staging: `edge.env`, `staging.env`, `staging-db.env`, `staging-backup.env` and `prod-drill.env`;
   - prod: `edge.env`, `prod.env`, `prod-db.env` and `prod-backup.env`.

   Put the Sentry DSN and the environment's heartbeat ping URL from stage 1 in now, so you edit each
   file only once. The B2 files come from stage 1's output, with the drill or backup ping URL.
   Leave `host-monitor.env` for stage 4: it reports a failure until the VM's environment serves.
   Re-run the script, as §4 says. That also covers B2 step 7 on this VM.
5. **Your WireGuard peer:** [§5](provision-host.md#5-your-wireguard-peer). On the second VM, your
   device gets a second tunnel. If your network blocks UDP, see
   [private-network.md "Troubleshooting"](private-network.md#troubleshooting).
6. **SSH over WireGuard only:** [§6](provision-host.md#6-finalize-ssh-over-wireguard-only), then
   [§7](provision-host.md#7-close-tcp-22-in-the-security-list).

### 3. Deploy access

1. **GitHub Environments and branch protection:** [deploy-and-rollback.md "One-time setup"](deploy-and-rollback.md#one-time-setup),
   step 1. GitHub lists the `backend` and `gitleaks` checks for branch protection only once they've
   run on a pull request.
2. **Deploy peers and keys:** [provision-host.md §8](provision-host.md#8-deploy-peers-and-keys),
   once on each VM: `deploy-staging` on the staging VM into the `staging` Environment, and
   `deploy-prod` on the prod VM into `production`.

### 4. First deploys

1. **Merge to `master`.** The run builds the image and deploys the staging VM
   ([deploy-and-rollback.md](deploy-and-rollback.md#how-a-release-reaches-each-environment)).
2. **Make the image public.** The first merge creates the package as private, so that first
   staging deploy fails with exit 4. Follow [deploy-and-rollback.md "One-time setup"](deploy-and-rollback.md#one-time-setup)
   step 3, then re-run the failed `deploy-staging` job from the run's page.
3. **Tag `v0.1.0`** on `master`, which deploys the prod VM.
4. **Host monitors:** create `host-monitor.env` on each VM and test it
   ([monitoring-setup.md "Healthchecks.io"](monitoring-setup.md#healthchecksio-dead-mans-switches)).
5. **UptimeRobot:** [monitoring-setup.md "UptimeRobot"](monitoring-setup.md#uptimerobot-production-down),
   one monitor, for production. Before production serves, it would only report it down.
6. **Test Sentry, the backup and the drill:** the test commands at the end of the
   [Sentry](monitoring-setup.md#sentry-errors) and [B2](monitoring-setup.md#backblaze-b2-backups)
   sections. The backup runs on the prod VM, then the drill on the staging VM.
7. **Your admin accounts:** [staff-accounts.md "Add a staff member"](staff-accounts.md#add-a-staff-member)
   with `--superuser`, for yourself, once in each environment. You already have both peers, so step
   3 there is only each VM's admin CA root
   ([private-network.md](private-network.md#install-the-admin-ca-root-on-each-staff-device)).
8. **Record:** [provision-host.md §10](provision-host.md#10-record), for each VM.

Feature-specific checks (task IDs, scenarios to walk) are in [owner-actions.md](../owner-actions.md).

## After setup

| When | Go to |
| --- | --- |
| Releasing, or a deploy failed | [deploy-and-rollback.md](deploy-and-rollback.md) |
| A bad release is serving | [deploy-and-rollback.md "Roll back"](deploy-and-rollback.md#roll-back) |
| `backend/docker/edge/` or `backend/docker/host/` changed | [deploy-and-rollback.md "Updating the edge or the host scripts"](deploy-and-rollback.md#updating-the-edge-or-the-host-scripts), on each VM |
| A deploy key leaked or needs replacing | [deploy-and-rollback.md "Replacing a deploy key"](deploy-and-rollback.md#replacing-a-deploy-key) |
| Adding a registry cleanup, or deleting images | [deploy-and-rollback.md "Images in GHCR"](deploy-and-rollback.md#images-in-ghcr) |
| A device needs a private network, or one is lost | [private-network.md "Peers"](private-network.md#peers) |
| New staff, a lost phone, a forgotten password, a lockout, someone leaving | [staff-accounts.md](staff-accounts.md) |
| The first of the month | [monitoring-setup.md "Monthly routine"](monitoring-setup.md#monthly-routine) |
| The drill failed | [restore.md "Reading drill-results.jsonl"](restore.md#reading-drill-resultsjsonl) |
| Publishing or promoting content, rolling it back, or raising the minimum app version | [content-publishing.md](content-publishing.md) |
| Data is lost or wrong, and production must go back to a backup | [restore.md "Restore into production"](restore.md#restore-into-production) |
| Authored content on staging is lost or wrong | [restore.md "Restore staging"](restore.md#restore-staging) |
| A VM or its disk is gone | [restore.md "Full rebuild on a new host"](restore.md#full-rebuild-on-a-new-host-within-4-h) |
| WireGuard or SSH doesn't let you into a VM | [break-glass.md](break-glass.md) |
| Oracle stopped an instance | [break-glass.md "Instance stopped by Oracle"](break-glass.md#instance-stopped-by-oracle) |
