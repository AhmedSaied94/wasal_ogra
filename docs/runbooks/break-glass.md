# Break-glass: getting back into the host

Use this runbook when you can't reach the host over WireGuard. Typical causes: `wg0` is broken, the
server key is lost, every operator device is gone, or an sshd or firewall change locked you out. It
also covers Oracle stopping the instance. Background: research R1 and R13.

The API keeps serving through most of these, since only the private side is affected. Check
`/healthz` before you change anything.

## Path 1: the serial console (try this first)

1. In the OCI console, open **Compute → Instances → the instance → Console connection → Launch
   Cloud Shell connection**.
2. Press Enter, then sign in as `ubuntu` with the **console password** from the password manager
   (provision-host.md step 2).

This works without the VM's network, but serial console support on A1 isn't confirmed. If you get
no login prompt, go to Path 2.

Once you're in, pick the fix that matches the cause.

### WireGuard is down

```bash
sudo systemctl status wg-quick@wg0
sudo journalctl -u wg-quick@wg0 -n 50
sudo wg show wg0
```

Fix the config error the journal shows, then run `sudo systemctl restart wg-quick@wg0`.

### Re-key `wg0` (server key lost or exposed)

```bash
sudo systemctl stop wg-quick@wg0
sudo mv /etc/wireguard/wg0.conf /root/wg0.conf.old-$(date +%F)
sudo ~/wassal-docker/host/provision.sh --public-ip <reserved ip>
```

The script generates a new server key and writes a new `/etc/wassal/wg-server.env`. The new `wg0`
has no peers, so every existing client config is now useless. Re-issue each one:

```bash
sudo wg-peer list
sudo wg-peer remove <name> && sudo wg-peer add <name> <role>   # for every peer, deploy peers included
```

Update the `WG_CONFIG` secret in both GitHub Environments with the new deploy configs. Then delete
`/root/wg0.conf.old-*` once you're back in.

### Reopen SSH temporarily

Do this only if you need SSH from the internet, for example because no device can run WireGuard
right now. Allow only your own address, and undo it as soon as you're done.

```bash
PUBLIC_IF="$(ip -o route show default | awk '{ print $5; exit }')"
sudo iptables -I INPUT 1 -i "$PUBLIC_IF" -p tcp -s <your public ip>/32 --dport 22 \
  -m comment --comment wassal-breakglass -j ACCEPT
sudo mv /etc/ssh/sshd_config.d/wassal.conf /root/wassal-sshd.conf.disabled
sudo systemctl daemon-reload && sudo systemctl restart ssh.socket
```

Then add a TCP 22 ingress rule for `<your public ip>/32` to the security list. The `iptables` rule
isn't saved, so a reboot or a `provision.sh --finalize` run removes it. A plain `provision.sh` run
leaves the live rules alone when the rules file hasn't changed.

To undo, once WireGuard works again, run this over WireGuard:

```bash
sudo ~/wassal-docker/host/provision.sh --finalize   # reinstalls the sshd drop-in, re-renders the firewall
```

Then remove the security-list rule.

## Path 2: boot-volume rescue (when the console doesn't work)

You fix the A1 instance's disk from a temporary Always Free AMD instance.

1. **Stop** the A1 instance (Force stop if it hangs).
2. Under the instance's **Boot volume**, choose **Detach**.
3. Create the rescue instance:
   - shape `VM.Standard.E2.1.Micro`, Always Free;
   - image Ubuntu 24.04 (x86), with a 47 GB boot volume, which fits the remaining 100 GB;
   - your SSH key, and an ephemeral public IP.
4. **Attach** the A1 boot volume to the rescue instance as a block volume (paravirtualized). Then
   connect to the rescue instance:

   ```bash
   ssh ubuntu@<rescue ip>
   lsblk                                     # the A1 disk is the second one, such as sdb
   sudo mkdir -p /mnt/rescue && sudo mount /dev/sdb1 /mnt/rescue
   ```

5. Fix the files. You can only edit files here, not run the A1 system's programs (it's aarch64):
   - **sshd lockout:** `sudo rm /mnt/rescue/etc/ssh/sshd_config.d/wassal.conf`.
   - **Firewall lockout:** `sudo cp /mnt/rescue/var/lib/wassal/oracle-rules.v4 /mnt/rescue/etc/iptables/rules.v4`.
     These are Oracle's original rules, which allow public SSH.
   - **Lost key:** append your public key to `/mnt/rescue/home/ubuntu/.ssh/authorized_keys`.
6. Unmount it (`sudo umount /mnt/rescue`), detach it from the rescue instance, and re-attach it to
   the A1 instance as its **boot volume**. Start the A1 instance.
7. **Terminate the rescue instance and delete its boot volume**, to stay inside the 200 GB
   allowance.
8. Add TCP 22 to the security list, SSH in over the public IP, and repair WireGuard (Path 1 steps).
   Then run `sudo ~/wassal-docker/host/provision.sh --finalize` and remove TCP 22 again.

## Instance stopped by Oracle

Oracle may stop an Always Free instance that has looked idle for 7 days: CPU, network and memory
all under 20% (R1). The data on the boot volume is kept.

- **Signs:** the uptime alert fires, and the console shows the instance as **Stopped**.
- **Fix:** choose **Start**. On "Out of host capacity", retry once a day; Jeddah has one
  availability domain.
- **After it starts:**
  - Check that the reserved IP is still attached to the VNIC.
  - Run `curl https://api.<ip-with-dashes>.sslip.io/healthz`.
  - Connect over WireGuard and check `sudo docker ps`. The restart policies bring every container
    back.
  - Look at the instance's utilization metrics for the week before the stop, and note what you
    find in research.md R1.
- Don't add artificial load to dodge the rule (R1 accepts this risk).
