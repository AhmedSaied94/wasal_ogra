# Provision the production host

You end up with one Oracle Cloud Always Free VM in `me-jeddah-1`. It serves the staging and
production API over HTTPS, with the admin and SSH reachable only over WireGuard. Background:
`specs/002-b01-backend-skeleton/research.md` R1, R6, R13 and R14.

**Time the whole run**, from step 1 until production serves `/healthz`. Together with the restore
drill's duration, it must fit the 4 h recovery target (SC-009). Write both times down for step 10.

## Before you start

- The OCI tenancy, signed in, with home region `me-jeddah-1`.
- An SSH key pair on your machine (`ssh-keygen -t ed25519` if you have none).
- The WireGuard app on the device you'll administer from.
- A password manager entry ready for the `ubuntu` console password.
- This repository checked out, with `backend/docker/` at the commit you're deploying.

Create **only Always Free resources**, from day one. If A1 usage ever goes over 2 OCPU / 12 GB,
Oracle disables every A1 instance (R1).

## 1. Reserve the IP and create the VM

1. **Networking → IP management → Reserved public IPs → Reserve public IP address.** Note the
   address. The hostnames are built from it, so it must survive rebuilds.
2. **Compute → Instances → Create instance:**
   - Image: **Canonical Ubuntu 24.04** (the aarch64 platform image).
   - Shape: **`VM.Standard.A1.Flex`, 2 OCPU, 12 GB**.
   - Networking: the VCN's public subnet, and **no** public IPv4 address. You attach the reserved
     one next.
   - SSH key: paste your public key.
   - Boot volume: **100 GB**. That leaves 100 GB of the 200 GB allowance for a rescue volume
     (break-glass.md).
   - Every resource on the page shows the "Always Free-eligible" label. If one doesn't, stop.
3. On **"Out of host capacity"**, retry once a day. Jeddah has a single availability domain, so
   there is nothing else to try. US1 and US2 work doesn't wait for this.
4. Once the instance runs, open **Attached VNICs → the VNIC → IPv4 addresses → Edit**, and pick
   **Reserved public IP** with your address.
5. In the subnet's **security list**, allow ingress from `0.0.0.0/0` on TCP 80, TCP 443 and UDP
   51820. Allow TCP 22 from `<your public ip>/32` only; it is temporary (step 7). The image allows
   key-only SSH, and the console password from step 2 doesn't change that.

## 2. Console password, then test the serial console

```bash
ssh ubuntu@<ip>
sudo passwd ubuntu          # store it in the password manager; it is only for the serial console
```

Test the break-glass path once, now that you can still fix it:

1. On the instance page, open **Console connection → Launch Cloud Shell connection**.
2. Sign in as `ubuntu` with that password, then close Cloud Shell.

If it doesn't work on A1, note that in research.md R13. break-glass.md's boot-volume rescue then
becomes the only way back in.

## 3. Run the provisioning script

From `backend/` on your machine:

```bash
scp -r docker ubuntu@<ip>:wassal-docker
ssh ubuntu@<ip>
sudo ./wassal-docker/host/provision.sh --public-ip <ip>
```

It installs the updates, Docker, WireGuard and Oracle-compatible iptables rules. It also sets up the
`deploy` user, `/opt/wassal`, `/etc/wassal` and the systemd units. It ends with
`edge skipped: fill the /etc/wassal/*.env files`, which is expected on the first run.

Keep `~/wassal-docker` on the host. Break-glass re-runs the script from it.

For task T054, record the host's real firewall:

```bash
sudo cat /var/lib/wassal/oracle-rules.v4      # Oracle's original rules.v4, saved before the render
sudo cat /var/lib/wassal/iptables-before.txt  # `iptables -S` before
sudo iptables -S                              # after
```

Copy the first one over `backend/docker/host/tests/fixtures/oracle-rules.v4` in the repository and
run `uv run pytest docker/host/tests`. Paste the before and after `iptables -S` into research.md R13.
If the public interface isn't `ens3` (A1 shapes can use `enp0s6`), note that too. The script finds
the interface from the default route, so it works either way.

## 4. Fill the environment files

Every file is owned by root with mode `0400`. Variables and rules:
`specs/002-b01-backend-skeleton/contracts/environment.md`. Create each one like this:

```bash
sudo install -m 0400 -o root -g root /dev/null /etc/wassal/prod.env
sudoedit /etc/wassal/prod.env
```

Generate secrets on the host and paste them straight into the editor. Never put them in chat, email
or the repository. Close the terminal tab afterwards, since `clear` keeps the scrollback:

```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(64))'   # SECRET_KEY, database passwords
```

Fill these now:

| File | Notes |
| --- | --- |
| `edge.env` | `PUBLIC_BIND_IP` is the VNIC's **private** address (`ip -4 -o addr show scope global`). `ADMIN_BIND_IP=10.66.0.1`, and `PUBLIC_TLS` is your email for Let's Encrypt. Hostnames (R14): `PROD_API_HOST=api.<ip-with-dashes>.sslip.io`, `STAGING_API_HOST=staging-api.<ip-with-dashes>.sslip.io`, `PROD_ADMIN_HOST=admin.10-66-0-1.sslip.io`, `STAGING_ADMIN_HOST=staging-admin.10-66-0-1.sslip.io`. |
| `prod.env`, `staging.env` | The application variables. `API_HOST` and `ADMIN_HOST` match `edge.env`. |
| `prod-db.env`, `staging-db.env` | `POSTGRES_PASSWORD` and `WASSAL_DB_PASSWORD`, all different. |

`host-monitor.env`, `prod-backup.env` and `prod-drill.env` need the outside services. Fill them in
when `monitoring-setup.md` says to.

Then re-run the script. This time it starts the edge:

```bash
sudo ./wassal-docker/host/provision.sh
```

Caddy gets the Let's Encrypt certificates for the API hostnames on its own. The API answers `502`
until the first deploy (step 9). That's expected, but the `http://` → `https://` redirect already
works:

```bash
curl -sI http://api.<ip-with-dashes>.sslip.io/healthz    # 308
```

## 5. Your WireGuard peer

```bash
sudo wg-peer add <your-device> operator      # for example ahmed-laptop
```

It prints a client config **once**, and that config holds the device's private key. Copy it to the
device over a channel you trust, import it in the WireGuard app ("Import tunnel from file"), then
delete the copy. On a phone, show it as a QR code from your laptop (`qrencode -t ansiutf8 < <file>`)
rather than sending the file.

Connect, then open a **second** SSH session, over WireGuard:

```bash
ssh ubuntu@10.66.0.1
```

## 6. Finalize: SSH over WireGuard only

In the WireGuard session:

```bash
sudo ./wassal-docker/host/provision.sh --finalize
```

It refuses unless an operator peer had a handshake in the last 10 minutes. After that it moves sshd
to `10.66.0.1:22`, checks that nothing else listens on port 22, and re-renders the firewall without
public TCP 22. Your open sessions survive. Every later run keeps public SSH closed.

## 7. Close TCP 22 in the security list

Remove the TCP 22 ingress rule from the security list. Then, **off** WireGuard:

```bash
nc -vz -w 5 <ip> 22     # times out
```

## 8. Deploy peers and keys

Do this once for each of `staging` and `prod`. The commands use `staging`:

```bash
# On your machine:
ssh-keygen -t ed25519 -N '' -C deploy-staging -f deploy-staging

# On the host, over WireGuard:
sudo wg-peer add deploy-staging deploy-staging       # prints the WireGuard config once
sudo install -d -m 700 -o deploy -g deploy ~deploy/.ssh
echo 'restrict,command="sudo /opt/wassal/bin/deploy --only staging" <contents of deploy-staging.pub>' |
  sudo tee -a ~deploy/.ssh/authorized_keys >/dev/null
sudo chown deploy:deploy ~deploy/.ssh/authorized_keys && sudo chmod 600 ~deploy/.ssh/authorized_keys
ssh-keyscan -t ed25519 10.66.0.1                     # the DEPLOY_KNOWN_HOSTS line
```

In **GitHub → Settings → Environments → `staging`**, add these secrets (contracts/environment.md
"CI secrets"):

- `WG_CONFIG`: the printed WireGuard config;
- `DEPLOY_SSH_KEY`: the private key file `deploy-staging`;
- `DEPLOY_KNOWN_HOSTS`: the `ssh-keyscan` line.

Use environment `production` for the prod key. Then delete both key files and the printed config
from your machine.

## 9. Outside services and first deploys

Follow `monitoring-setup.md` (B2, Healthchecks.io, UptimeRobot and Sentry), then fill in the
remaining `/etc/wassal/*.env` files. Merge to `master`, which deploys staging, then tag `v0.1.0`,
which deploys production.

## 10. Record

- **Latency baseline (R1):** from two Egyptian connections, one fixed and one mobile, run this 10
  times each:

  ```bash
  curl -o /dev/null -s -w '%{time_connect}\n' https://api.<ip-with-dashes>.sslip.io/healthz
  ```

  Record the median and the worst value in `docs/architecture-backend.md` §2.
- **Setup time (SC-009):** the time from step 1 to production serving.
- **T054:** the rules fixture, and `iptables -S` before and after (step 3).
