# Private network (WireGuard)

The admin and SSH are reachable only over WireGuard. Each VM runs its own WireGuard server on
`wg0`, on UDP port 51820 of its own public IP, with its own key and its own list of peers. A server
never answers packets from unknown keys, so to a port scan it looks closed. Background: research
R5, R13 and R14, and contracts/operations.md "Network exposure".

| | prod VM | staging VM |
| --- | --- | --- |
| Server address (`<wg>`) | `10.66.0.1`, network `10.66.0.0/24` | `10.67.0.1`, network `10.67.0.0/24` |
| Endpoint | `193.122.74.125:51820` | `141.147.129.92:51820` |
| Admin | `https://admin.10-66-0-1.sslip.io/admin/` | `https://staging-admin.10-67-0-1.sslip.io/admin/` |
| Deploy peer | `deploy-prod` | `deploy-staging` |

The roles use the same ranges inside each VM's network:

| Role | prod VM | staging VM | Can reach on that VM |
| --- | --- | --- | --- |
| `operator` | `10.66.0.2`–`9` | `10.67.0.2`–`9` | SSH and the admin (TCP 22, 443) |
| `staff` | `10.66.0.10`–`99` | `10.67.0.10`–`99` | The admin only (TCP 443) |
| deploy | `deploy-prod`, `10.66.0.200`–`209` | `deploy-staging`, `10.67.0.200`–`209` | SSH only, as the `deploy` user, with its forced command for that VM's environment |

Each VM's firewall enforces these ranges. A staff device that tries SSH gets no answer, by design.
The two networks never reach each other: a peer of one VM can't reach the other VM.

## Peers

Run these on the VM whose network the device should join, over that VM's WireGuard:

```bash
sudo wg-peer add <name> <role>    # name: 2-32 characters from a-z, 0-9 and "-", such as sara-phone
sudo wg-peer list                 # name, role, address and latest handshake
sudo wg-peer remove <name>        # access to this VM ends at once
```

`add` takes the VM's network and environment from `/etc/wassal/host.env`, and refuses to run if
that file is missing or broken. It accepts only this VM's deploy role: on the staging VM,
`deploy-prod` is refused with `role deploy-prod belongs on the prod host`, and the reverse on the
prod VM. `list` and `remove` work even when `host.env` is broken, so you can always cut a device
off.

`add` prints the client config **once**. The config holds the device's private key, which the VM
doesn't keep, so treat it like a password:

- **Desktop:** save it to a file named `wassal-<env>.conf` and use "Import tunnel(s) from file" in
  the WireGuard app. Then delete the file.
- **Phone:** show it as a QR code from your laptop (`qrencode -t ansiutf8 < <file>`) and scan it in
  the app. Never send it by chat or email.

A device that needs both environments gets a peer on **each** VM: two configs, two keys, two
tunnels. Use the same name on both, so `wg-peer list` reads the same on each VM.

- **Laptop:** keep both tunnels up at once if you like. The networks differ, and each config routes
  only its own server's address.
- **Phone:** the WireGuard app runs one tunnel at a time. Switch to the tunnel of the admin you
  want.

Every config routes only `<wg>/32` through the tunnel, so the device's other traffic is unaffected.
Operator and staff configs set `DNS = 1.1.1.1` (see "Admin hostname doesn't resolve"). While a
tunnel is up, that replaces the device's DNS server for **all** lookups, outside the tunnel.
Disconnect when you're done with the admin, or, on a work laptop that needs its own DNS, delete the
`DNS` line and use the `hosts` entry below instead.

Remove a peer when a device is lost, replaced or handed back, on every VM it was added to. If its
owner is leaving, also follow staff-accounts.md "Someone leaves".

## Admin addresses

| Environment | URL | Tunnel |
| --- | --- | --- |
| Production | `https://admin.10-66-0-1.sslip.io/admin/` | the prod VM's |
| Staging | `https://staging-admin.10-67-0-1.sslip.io/admin/` | the staging VM's |

Always type `https://`. Port 80 isn't open on the private network, so `http://` hangs instead of
redirecting.

Use the hostnames from each VM's `/etc/wassal/edge.env` if they've changed (a real domain replaces
sslip.io before the closed test).

## Install the admin CA root on each staff device

Each VM's admin certificate comes from that VM's own certificate authority (Caddy's `tls internal`),
so there are two roots, one per VM. A device trusts each root it needs once: the prod root for the
production admin, the staging root for the staging admin. On each VM:

```bash
sudo docker exec wassal-edge-caddy-1 cat /data/caddy/pki/authorities/local/root.crt > wassal-<env>-admin-root.crt
openssl x509 -in wassal-<env>-admin-root.crt -noout -fingerprint -sha256
```

Both roots carry the same name (Caddy Local Authority), so keep each fingerprint in your password
manager next to its environment. Copy the file to the device, and check that the fingerprint
matches there before you trust it.

| Device | Steps |
| --- | --- |
| macOS | Open the file. In Keychain Access, under System, set the certificate to "Always Trust". |
| Windows | `certmgr.msc` → Trusted Root Certification Authorities → Certificates → All Tasks → Import |
| Linux | `sudo cp wassal-<env>-admin-root.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`. Firefox keeps its own store: Settings → Privacy & Security → Certificates → Import. |
| Android | Settings → Security → Encryption & credentials → Install a certificate → CA certificate |
| iOS | Install the profile from the file, then turn it on under Settings → General → About → Certificate Trust Settings |

- Each root lives in its VM's `caddy_data` volume and lasts for years.
- Leaf certificates last 12 hours and renew on their own.
- If a VM's volume is lost, or the VM is rebuilt, its edge creates a new root. Every device that
  uses that admin needs the new root, and should remove the old one.
- A device that trusts a root trusts **any** certificate signed with its key, for any site, banks
  included. The roots have no name constraints. Each key sits unencrypted in its VM's `caddy_data`
  volume.
  - The backups never include that volume: they hold only the database dump.
  - A copy of either volume, or root on either VM, is therefore enough to impersonate any site to
    every device that trusts that VM's root.
  - Install a root only on the devices, or a dedicated browser profile, used for that admin. Staff
    who use one admin install one root. Remove the roots when someone leaves.
  - A real domain with publicly trusted admin certificates (DNS-01) removes this risk. That's for
    the domain step in `docs/delivery-plan.md`.

## Admin hostname doesn't resolve

Some home routers (Fritz!Box, dnsmasq with `--stop-dns-rebind`) drop DNS answers that point to a
private address, such as `admin.10-66-0-1.sslip.io → 10.66.0.1`. The WireGuard configs set
`DNS = 1.1.1.1`, which normally gets around that. If a name still doesn't resolve while its tunnel
is up, add `hosts` entries on that device:

```text
10.66.0.1  admin.10-66-0-1.sslip.io
10.67.0.1  staging-admin.10-67-0-1.sslip.io
```

They go in `/etc/hosts` on macOS and Linux, and in `C:\Windows\System32\drivers\etc\hosts` on
Windows. Phones can't edit `hosts`, so on a phone check that the right tunnel is connected and its
DNS setting is still there.

## Troubleshooting

- `sudo wg show wg0` on the VM shows each of its peers' latest handshake. If there is no handshake,
  the device isn't reaching that VM's UDP 51820. Check that VM's security list and the device's
  network (some guest Wi-Fi blocks UDP).
- Your network blocks UDP (some ISPs and guest Wi-Fi do): on a computer, turn on Cloudflare WARP
  (the free 1.1.1.1 app) before you connect, so the tunnel's packets travel inside WARP. Then:
  - Add `MTU = 1200` under `[Interface]` in each tunnel config. WARP's own limit is 1280 and
    WireGuard adds 80 bytes, so without it the handshake works but pages and file copies hang.
  - If name lookups break while both are connected, delete the config's `DNS` line. WARP already
    resolves through 1.1.1.1.
  - Until provision-host.md step 7 closes a VM's public SSH, turn WARP off to use it. The VM sees
    a Cloudflare address, which the TCP 22 rule from step 1 doesn't allow.
  - A phone runs one VPN at a time, so it can't do this. Use mobile data instead.
- Handshake, but no admin: check the role (staff can't SSH), that VM's CA root and the hostname.
  Each admin answers only on its own VM's tunnel.
- A VM's own WireGuard is broken, or every operator device is lost: see break-glass.md. The other
  VM is unaffected.
