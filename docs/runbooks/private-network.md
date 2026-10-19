# Private network (WireGuard)

The admin and SSH are reachable only over WireGuard. The server is `10.66.0.1` on `wg0`, on UDP
port 51820. It never answers packets from unknown keys, so to a port scan it looks closed. Background:
research R5, R13 and R14, and contracts/operations.md "Network exposure".

| Role | Addresses | Can reach |
| --- | --- | --- |
| `operator` | `10.66.0.2`–`9` | SSH and the admin (TCP 22, 443) |
| `staff` | `10.66.0.10`–`99` | The admin only (TCP 443) |
| `deploy-staging`, `deploy-prod` | `10.66.0.200`–`209` | SSH only, as the `deploy` user, with its forced command |

The host firewall enforces these ranges. A staff device that tries SSH gets no answer, by design.

## Peers

Run these on the host, over WireGuard:

```bash
sudo wg-peer add <name> <role>    # name: 2-32 characters from a-z, 0-9 and "-", such as sara-phone
sudo wg-peer list                 # name, role, address and latest handshake
sudo wg-peer remove <name>        # access ends at once
```

`add` prints the client config **once**. The config holds the device's private key, which the host
doesn't keep, so treat it like a password:

- **Desktop:** save it to a file and use "Import tunnel(s) from file" in the WireGuard app. Then
  delete the file.
- **Phone:** show it as a QR code from your laptop (`qrencode -t ansiutf8 < <file>`) and scan it in
  the app. Never send it by chat or email.

Every config routes only `10.66.0.1/32` through the tunnel, so the device's other traffic is
unaffected. Operator and staff configs set `DNS = 1.1.1.1` (see "Admin hostname doesn't resolve").
While the tunnel is up, that replaces the device's DNS server for **all** lookups, outside the
tunnel. Disconnect when you're done with the admin, or, on a work laptop that needs its own DNS,
delete the `DNS` line and use the `hosts` entry below instead.

Remove a peer when a device is lost, replaced or handed back. If its owner is leaving, also follow
staff-accounts.md "Someone leaves".

## Admin addresses

| Environment | URL |
| --- | --- |
| Production | `https://admin.10-66-0-1.sslip.io/admin/` |
| Staging | `https://staging-admin.10-66-0-1.sslip.io/admin/` |

Always type `https://`. Port 80 isn't open on the private network, so `http://` hangs instead of
redirecting.

Use the hostnames from `/etc/wassal/edge.env` if they've changed (a real domain replaces sslip.io
before the closed test).

## Install the admin CA root on each staff device

The admin certificates come from the edge's own certificate authority (Caddy's `tls internal`), so
every device must trust its root once. On the host:

```bash
sudo docker exec wassal-edge-caddy-1 cat /data/caddy/pki/authorities/local/root.crt > wassal-admin-root.crt
openssl x509 -in wassal-admin-root.crt -noout -fingerprint -sha256
```

Copy the file to the device, and check that the fingerprint matches there before you trust it.

| Device | Steps |
| --- | --- |
| macOS | Open the file. In Keychain Access, under System, set the certificate to "Always Trust". |
| Windows | `certmgr.msc` → Trusted Root Certification Authorities → Certificates → All Tasks → Import |
| Linux | `sudo cp wassal-admin-root.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`. Firefox keeps its own store: Settings → Privacy & Security → Certificates → Import. |
| Android | Settings → Security → Encryption & credentials → Install a certificate → CA certificate |
| iOS | Install the profile from the file, then turn it on under Settings → General → About → Certificate Trust Settings |

- The root lives in the `caddy_data` volume and lasts for years.
- Leaf certificates last 12 hours and renew on their own.
- If the volume is lost, the edge creates a new root, and every device needs it again.
- A device that trusts this root trusts **any** certificate signed with its key, for any site,
  banks included. The root has no name constraints. The key sits unencrypted in the `caddy_data`
  volume on the host.
  - The backups never include that volume: they hold only the database dump.
  - A copy of the volume, or root on the host, is therefore enough to impersonate any site to every
    enrolled device.
  - Install the root only on the devices, or a dedicated browser profile, used for the admin.
    Remove it when someone leaves.
  - A real domain with publicly trusted admin certificates (DNS-01) removes this risk. That's for
    the domain step in `docs/delivery-plan.md`.

## Admin hostname doesn't resolve

Some home routers (Fritz!Box, dnsmasq with `--stop-dns-rebind`) drop DNS answers that point to a
private address, such as `admin.10-66-0-1.sslip.io → 10.66.0.1`. The WireGuard configs set
`DNS = 1.1.1.1`, which normally gets around that. If the name still doesn't resolve while the
tunnel is up, add a `hosts` entry on that device:

```text
10.66.0.1  admin.10-66-0-1.sslip.io staging-admin.10-66-0-1.sslip.io
```

It goes in `/etc/hosts` on macOS and Linux, and in `C:\Windows\System32\drivers\etc\hosts` on
Windows. Phones can't edit `hosts`, so on a phone check that the tunnel is connected and its DNS
setting is still there.

## Troubleshooting

- `sudo wg show wg0` shows each peer's latest handshake. If there is no handshake, the device isn't
  reaching UDP 51820. Check the security list and the device's network (some guest Wi-Fi blocks
  UDP).
- Handshake, but no admin: check the role (staff can't SSH), the CA root and the hostname.
- The host's own WireGuard is broken, or every operator device is lost: see break-glass.md.
