# Provision a host

Staging and production each run on their own Oracle Cloud Always Free VM in `me-jeddah-1`. This
runbook sets up one of them. Run it once per VM, with that VM's values from the table below. You
end up with a VM that serves its environment's API over HTTPS, with its admin and SSH reachable
only over its own WireGuard network. Background: `specs/002-b01-backend-skeleton/research.md` R1,
R6, R13 and R14.

This is stage 2 of the first-time setup. [README.md](README.md#first-time-setup) gives the order
across all the runbooks.

**Time each VM's run**, from step 1 until its environment serves `/healthz`. The 4 h recovery
target applies to each VM (SC-009): the prod VM's time plus the restore drill's restore duration
must fit it, and so must the staging VM's time on its own. Write the times down for step 10.

## The two VMs

The commands below use `<env>`, `<ip>` and `<wg>` for the values of the VM you're working on.

| | prod VM | staging VM |
| --- | --- | --- |
| `<env>` (`provision.sh --env`) | `prod` | `staging` |
| Shape | `VM.Standard.A1.Flex`, 1 OCPU / 6 GB | `VM.Standard.A1.Flex`, 1 OCPU / 6 GB |
| Boot volume | 100 GB | 47 GB |
| `<ip>`, the reserved public IP | `193.122.74.125` | `141.147.129.92` |
| VCN private IP (`PUBLIC_BIND_IP`) | `10.0.0.28` | `10.1.0.216` |
| `<wg>`, the WireGuard address (`ADMIN_BIND_IP`) | `10.66.0.1` | `10.67.0.1` |
| API hostname (`API_HOST`) | `api.193-122-74-125.sslip.io` | `staging-api.141-147-129-92.sslip.io` |
| Admin hostname (`ADMIN_HOST`) | `admin.10-66-0-1.sslip.io` | `staging-admin.10-67-0-1.sslip.io` |
| Env files of its own | `prod.env`, `prod-db.env`, `prod-backup.env` | `staging.env`, `staging-db.env`, `prod-drill.env` |
| Timers | `wassal-backup@prod`, `wassal-host-monitor` | `wassal-restore-drill@prod` (drills production's backups), `wassal-host-monitor` |
| Deploy peer, GitHub Environment | `deploy-prod`, `production` | `deploy-staging`, `staging` |

- Each VM has its own VCN, security list, reserved IP, WireGuard server, edge, host monitor and
  deploy key. Nothing on one VM reaches the other.
- A rebuilt VM keeps its reserved IP, so its hostnames stay the same. Its VCN private IP can change:
  read it in step 4.

## Before you start

- The OCI tenancy, signed in, with home region `me-jeddah-1`. It allows two reserved public IPs
  (R1).
- An SSH key pair on your machine (`ssh-keygen -t ed25519` if you have none).
- The WireGuard app on the device you'll administer from.
- A password manager entry ready for this VM's `ubuntu` console password. Each VM has its own.
- This repository checked out, with `backend/docker/` at the commit you're deploying.

Create **only Always Free resources**, from day one. If A1 usage ever goes over 2 OCPU / 12 GB in
total, Oracle disables every A1 instance (R1). The two VMs use all of it, so growing one means
shrinking the other.

## 1. Reserve the IP and create the VM

1. **Networking → IP management → Reserved public IPs → Reserve public IP address.** Name it after
   the environment and note the address. The hostnames are built from it, so it must survive
   rebuilds.
2. **Networking → Virtual cloud networks → Start VCN Wizard → Create VCN with Internet
   Connectivity.** This VM gets its own VCN. Never put both VMs in one.
3. **Compute → Instances → Create instance:**
   - Image: **Canonical Ubuntu 24.04** (the aarch64 platform image).
   - Shape: **`VM.Standard.A1.Flex`, 1 OCPU, 6 GB**.
   - Networking: this VM's VCN and its public subnet, and **no** public IPv4 address. You attach
     the reserved one next.
   - SSH key: paste your public key.
   - Boot volume: **100 GB** for prod, **47 GB** for staging. Together that is 147 GB of the
     200 GB allowance, which leaves 53 GB for one rescue volume (break-glass.md).
   - Every resource on the page shows the "Always Free-eligible" label. If one doesn't, stop.
4. On **"Out of host capacity"**, retry once a day. Jeddah has a single availability domain, so
   there is nothing else to try. US1 and US2 work doesn't wait for this.
5. Once the instance runs, open **Attached VNICs → the VNIC → IPv4 addresses → Edit**, and pick
   **Reserved public IP** with this VM's address.
6. In the public subnet's **security list**, allow ingress from `0.0.0.0/0` on TCP 80, TCP 443 and
   UDP 51820. Allow TCP 22 from `<your public ip>/32` only; it is temporary (step 7). The wizard's
   default list allows TCP 22 from anywhere, so narrow that rule. The image allows key-only SSH,
   and the console password from step 2 doesn't change that.

## 2. Console password, then test the serial console

```bash
ssh ubuntu@<ip>
sudo passwd ubuntu          # store it in the password manager; it is only for the serial console
```

Test the break-glass path once on this VM, now that you can still fix it:

1. On the instance page, open **Console connection → Launch Cloud Shell connection**.
2. Sign in as `ubuntu` with that password, then close Cloud Shell.

If it doesn't work on A1, note that in research.md R13. break-glass.md's boot-volume rescue then
becomes the only way back in.

## 3. Run the provisioning script

From `backend/` on your machine:

```bash
scp -r docker ubuntu@<ip>:wassal-docker
ssh ubuntu@<ip>
sudo ./wassal-docker/host/provision.sh --env <env> --public-ip <ip>
```

If `~/wassal-docker` already exists on the VM, copy with rsync instead. `scp -r` into an existing
directory nests the copy one level down:

```bash
rsync -a --delete docker/ ubuntu@<ip>:wassal-docker/
```

- The first run needs both `--env` and `--public-ip`. It records the VM's environment in
  `/etc/wassal/host.env`, with its WireGuard address, and prints
  `<env> host, WireGuard <wg>, timers …`.
- Every later run reads `host.env`, so `--env` is optional. A different `--env` is refused (exit 1,
  "it can't become …"), before anything changes: switching a VM's environment means rebuilding it.
- Before changing anything, it also refuses a `wg0.conf` on another address, or an `edge.env` whose
  `ADMIN_BIND_IP` isn't `<wg>`. Both only happen on a VM set up with the one-host design: see
  "Removing leftovers from the one-host design" below.
- It installs the updates, Docker, WireGuard on `<wg>`, and Oracle-compatible iptables rules. It
  also sets up the `deploy` user (allowed to deploy `<env>` only), `/opt/wassal`, `/etc/wassal` and
  the systemd units. It turns on this VM's timers, and disables any other `wassal-*` timer
  (`disabling …: it doesn't run on the <env> host`).
- It ends with `edge skipped: …`, which is expected on the first run.

Check what it did:

```bash
sudo cat /etc/wassal/host.env                    # WASSAL_ENV=<env> and WG_ADDRESS=<wg>
ip -4 -o addr show wg0                           # <wg>/24
systemctl list-timers 'wassal-*'                 # this VM's two timers only (table above)
sudo iptables -S INPUT | grep -c -- '-j REJECT'  # 1: a single rule set
```

If it prints a `WARNING: … (provision-host.md)` line, something on the VM belongs to the other
environment. The script never deletes it: follow "Removing leftovers from the one-host design"
below. A fresh VM has none.

If a run stops partway, run it again. Rules it rendered but didn't load are still applied on the
next run (`/var/lib/wassal/firewall-pending`).

Keep `~/wassal-docker` on the VM. Break-glass re-runs the script from it.

For step 10, record the VM's firewall:

```bash
sudo diff -I '^#' ~/wassal-docker/host/tests/fixtures/oracle-rules.v4 /var/lib/wassal/oracle-rules.v4
sudo diff -I '^#' ~/wassal-docker/host/tests/fixtures/oracle-rules.v6 /var/lib/wassal/oracle-rules.v6
sudo cat /var/lib/wassal/iptables-before.txt   # `iptables -S` before the first render
sudo iptables -S                               # after
```

- The `/var/lib/wassal/oracle-rules.v*` files are Oracle's original rules, saved before the first
  render. The fixtures in the repository came from the staging VM (T054).
- If either `diff` prints anything, paste it into research.md R13 and ask Claude to check that the
  firewall render and its tests handle that VM's rules.
- Paste the before and after `iptables -S` into R13, under this VM.
- The script finds the public interface from the default route, so `enp0s6` and Oracle's
  documented `ens3` both work. Note the name in R13 if it isn't `enp0s6`.

## 4. Fill the environment files

Every file is owned by root with mode `0400`. Variables and rules:
`specs/002-b01-backend-skeleton/contracts/environment.md`. Create each one like this:

```bash
sudo install -m 0400 -o root -g root /dev/null /etc/wassal/<env>.env
sudoedit /etc/wassal/<env>.env
```

Generate secrets on the VM and paste them straight into the editor. Never put them in chat, email
or the repository. Close the terminal tab afterwards, since `clear` keeps the scrollback:

```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(64))'   # SECRET_KEY, database passwords
```

Each VM holds only its own environment's files. Fill these now:

| File | prod VM | staging VM | Notes |
| --- | --- | --- | --- |
| `edge.env` | yes | yes | `PUBLIC_BIND_IP`: the VNIC's **private** address, the `src` in `ip route get 1.1.1.1`. `ADMIN_BIND_IP=<wg>`; the script refuses any other value. `PUBLIC_TLS`: your email for Let's Encrypt. `API_HOST` and `ADMIN_HOST`: this VM's hostnames from the table. |
| `<env>.env` | `prod.env` | `staging.env` | The application variables. `API_HOST` and `ADMIN_HOST` match `edge.env`. `SENTRY_DSN` and this environment's `HC_PING_HEARTBEAT_URL` come from monitoring-setup.md. |
| `<env>-db.env` | `prod-db.env` | `staging-db.env` | `POSTGRES_PASSWORD` and `WASSAL_DB_PASSWORD`, different from each other and from the other VM's |
| B2 | `prod-backup.env` | `prod-drill.env` | The lines `b2_setup.py` printed, plus the ping URL (monitoring-setup.md "Backblaze B2") |

`host-monitor.env` waits until this VM's environment serves. Until then it would only report a
failure (monitoring-setup.md "Healthchecks.io").

Then re-run the script. This time it starts the edge:

```bash
sudo ./wassal-docker/host/provision.sh
```

It first checks that `ADMIN_BIND_IP` in `edge.env` is this VM's WireGuard address, and stops if it
isn't. Caddy gets the Let's Encrypt certificate for the API hostname on its own. The API answers
`502` until the first deploy (step 9). That's expected, but the `http://` → `https://` redirect
already works:

```bash
curl -sI http://<API hostname>/healthz    # 308
```

## 5. Your WireGuard peer

```bash
sudo wg-peer add <your-device> operator      # for example ahmed-laptop
```

It prints a client config **once**, and that config holds the device's private key. Copy it to the
device over a channel you trust, import it in the WireGuard app ("Import tunnel from file"), then
delete the copy. On a phone, show it as a QR code from your laptop (`qrencode -t ansiutf8 < <file>`)
rather than sending the file.

- Save the file as `wassal-<env>.conf`, so the app names the tunnel after the VM.
- On your second VM, the same device gets a second tunnel, with its own key and address. A laptop
  can keep both up at once. A phone runs one at a time (private-network.md).

Connect, then open a **second** SSH session, over WireGuard:

```bash
ssh ubuntu@<wg>
```

## 6. Finalize: SSH over WireGuard only

In the WireGuard session:

```bash
sudo ./wassal-docker/host/provision.sh --finalize
```

It refuses unless:

- the live `wg0` carries `<wg>/24`. Otherwise it says `wg0 doesn't have <wg>/24`: restart
  `wg-quick@wg0` and reconnect first;
- an operator peer inside this VM's network had a handshake in the last 10 minutes. A peer of the
  other VM doesn't count.

After that it moves sshd to `<wg>:22`, checks that nothing else listens on port 22, and re-renders
the firewall without public TCP 22. Your open sessions survive. Every later run keeps public SSH
closed.

## 7. Close TCP 22 in the security list

Remove the TCP 22 ingress rule from this VM's security list. Then, **off** WireGuard:

```bash
nc -vz -w 5 <ip> 22     # times out
```

## 8. Deploy peers and keys

Each VM has one deploy peer and one deploy key, for its own environment: `deploy-staging` on the
staging VM, `deploy-prod` on the prod VM. `wg-peer` refuses the other one ("role deploy-prod
belongs on the prod host"). The commands use `<env>`:

```bash
# On your machine:
ssh-keygen -t ed25519 -N '' -C deploy-<env> -f deploy-<env>

# On the VM, over its WireGuard:
sudo wg-peer add deploy-<env> deploy-<env>       # prints the WireGuard config once
sudo install -d -m 700 -o deploy -g deploy ~deploy/.ssh
echo 'restrict,command="sudo /opt/wassal/bin/deploy --only <env>" <contents of deploy-<env>.pub>' |
  sudo tee -a ~deploy/.ssh/authorized_keys >/dev/null
sudo chown deploy:deploy ~deploy/.ssh/authorized_keys && sudo chmod 600 ~deploy/.ssh/authorized_keys
ssh-keyscan -t ed25519 <wg>                      # the DEPLOY_KNOWN_HOSTS line
```

In **GitHub → Settings → Environments**, open this VM's environment (`staging` for the staging VM,
`production` for the prod VM) and add these secrets (contracts/environment.md "CI secrets"):

- `WG_CONFIG`: the printed WireGuard config. Its `Endpoint` is `<ip>:51820` and its `AllowedIPs`
  is `<wg>/32`;
- `DEPLOY_SSH_KEY`: the private key file `deploy-<env>`;
- `DEPLOY_KNOWN_HOSTS`: the `ssh-keyscan` line.

Each Environment's secrets reach its own VM only. Then delete both key files and the printed
config from your machine.

## 9. Outside services and first deploys

If you haven't set up Sentry, Healthchecks.io and B2 yet ([README.md](README.md#1-accounts-no-host-needed)
stage 1), do it now and fill in this VM's env files. Once both VMs are through step 7, follow
README.md stages 3 and 4:

- the GitHub setup, and step 8 on each VM;
- the merge to `master`, which deploys the staging VM. Its first deploy fails with exit 4 until you
  make the image public;
- the `v0.1.0` tag, which deploys the prod VM;
- the monitoring that needs each environment serving.

## 10. Record

Per VM:

- **Setup time (SC-009):** the time from step 1 to its environment serving `/healthz`. The prod
  VM's time plus the drill's restore duration must stay within 4 h, and the staging VM's time on
  its own.
- **Firewall (R13):** the `diff` against the fixtures, and `iptables -S` before and after (step 3).

For the prod VM only:

- **Latency baseline (R1):** from two Egyptian connections, one fixed and one mobile, run this 10
  times each:

  ```bash
  curl -o /dev/null -s -w '%{time_connect}\n' https://api.193-122-74-125.sslip.io/healthz
  ```

  Record the median and the worst value in `docs/architecture-backend.md` §2.

## Removing leftovers from the one-host design

Until 2026-10-19 one VM ran both environments. A VM set up then has files that now belong to the
other VM. `provision.sh` never deletes data: it refuses to start on the two that would break this
VM, and prints a `WARNING: … (provision-host.md)` line for each of the others. Check that nothing
there is still needed, remove it, and re-run the script until it prints no warning.

**Refused before anything changes.** Fix these, then run the script again:

| Message | Do |
| --- | --- |
| `/etc/wireguard/wg0.conf has Address '…', not this host's <wg>/24` | `sudo systemctl disable --now wg-quick@wg0`, then move `/etc/wireguard/wg0.conf` and `/etc/wassal/wg-server.env` aside (to `/root/`). Move `/etc/wassal/wg-peers.tsv` aside too, if it exists. The run creates a new server key on `<wg>`, so every peer of the old network needs a new config (step 5). Delete the moved files once the new tunnel works: they hold the old server key. |
| `/etc/wassal/edge.env has ADMIN_BIND_IP '…', not this host's WG_ADDRESS <wg>` | Move `edge.env` aside and write a new one (step 4). |

**Warnings.** `<other>` is the other environment:

| Warning names | Do |
| --- | --- |
| `/var/lib/wassal/<other>` | `sudo rm -r /var/lib/wassal/<other>`. It holds the other environment's deploy state, which its own VM rebuilds. |
| `/etc/wassal/<other>.env` or `<other>-db.env` | `sudo rm /etc/wassal/<file>`. The other VM has its own, with its own secrets. |
| `prod-backup.env` on the staging VM; `prod-drill.env` on the prod VM | `sudo rm /etc/wassal/<file>`, once its lines are in your password manager. The backup key belongs on the prod VM only, the drill key on the staging VM only. |
| `staging-backup.env` or `staging-drill.env` | `sudo rm /etc/wassal/<file>`. Staging isn't backed up. |
| Peers that don't belong to this host's network | `sudo wg-peer remove <name>` for each one listed: peers outside `<wg>`'s /24, or with the other deploy role. Add the device again on the VM it belongs to. |
| `edge.env` still has the one-host `PROD_`/`STAGING_` variables | Rewrite it with `API_HOST` and `ADMIN_HOST` (step 4), then re-run the script. |
| The other environment's Compose project `wassal-<other>` | See below. |

The other environment's containers and volumes hold that environment's data. If production ever
served from this VM, make sure its data is on the prod VM or in a backup first. Then remove them:

```bash
P=wassal-<other>
sudo docker rm -f $(sudo docker ps -aq --filter label=com.docker.compose.project=$P)
sudo docker volume rm $(sudo docker volume ls -q --filter label=com.docker.compose.project=$P)
sudo docker network rm $(sudo docker network ls -q --filter label=com.docker.compose.project=$P)
```

A command with nothing to remove says so and changes nothing.
