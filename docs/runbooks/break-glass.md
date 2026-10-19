# Break-glass: getting back into a VM

Use this runbook when you can't reach a VM over its WireGuard. Typical causes: `wg0` is broken, the
server key is lost, every operator device is gone, or an sshd or firewall change locked you out. It
also covers Oracle stopping an instance. Background: research R1 and R13.

Each VM is break-glassed on its own: the prod VM (`193.122.74.125`, WireGuard `10.66.0.1`) or the
staging VM (`141.147.129.92`, WireGuard `10.67.0.1`). The other VM is unaffected and needs nothing.
The commands below use `<env>`, `<ip>` and `<wg>` for the VM you're fixing.

The API keeps serving through most of these, since only the private side is affected. Check that
VM's `/healthz` before you change anything.

## Path 1: the serial console (try this first)

1. In the OCI console, open **Compute → Instances → the VM's instance → Console connection →
   Launch Cloud Shell connection**.
2. Press Enter, then sign in as `ubuntu` with **that VM's console password** from the password
   manager (provision-host.md step 2). Each VM has its own.

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
sudo ~/wassal-docker/host/provision.sh --public-ip <ip>
```

The script reads the VM's environment from `/etc/wassal/host.env`, so it needs no `--env`. It
generates a new server key on the same address, `<wg>`, and writes a new
`/etc/wassal/wg-server.env`. The new `wg0` has no peers, so every client config for this VM is now
useless. Re-issue each one:

```bash
sudo wg-peer list
sudo wg-peer remove <name> && sudo wg-peer add <name> <role>   # for every peer, the deploy peer included
```

Update the `WG_CONFIG` secret of this VM's GitHub Environment (`production` or `staging`) with the
new deploy config. Devices keep their tunnel to the other VM. Then delete `/root/wg0.conf.old-*`
once you're back in.

### `host.env` is missing or broken

`/etc/wassal/host.env` holds the VM's environment and WireGuard address. Without a valid one,
`provision.sh`, `wg-peer add`, `deploy`, the backup, the drill and the host monitor all refuse to
run. `sudo wg-peer list` and `sudo wg-peer remove <name>` still work, so you can always cut a lost
device off first.

Only root can change the file, and `provision.sh` writes it only once. Find out what changed it
before you trust the VM again. Then move it aside and let the script write it again, with this
VM's own values:

```bash
sudo mv /etc/wassal/host.env /root/host.env.broken-$(date +%F)
sudo ~/wassal-docker/host/provision.sh --env <env> --public-ip <ip>
```

The script refuses an `--env` that doesn't match the VM's `wg0.conf`, so a wrong one changes
nothing.

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

Then add a TCP 22 ingress rule for `<your public ip>/32` to this VM's security list. The `iptables`
rule isn't saved, so a reboot or a `provision.sh --finalize` run removes it. A plain `provision.sh`
run leaves the live rules alone when the rules file hasn't changed.

To undo, once WireGuard works again, run this over this VM's WireGuard:

```bash
sudo ~/wassal-docker/host/provision.sh --finalize   # reinstalls the sshd drop-in, re-renders the firewall
```

Then remove the security-list rule.

## Path 2: boot-volume rescue (when the console doesn't work)

You fix the A1 instance's disk from a temporary Always Free AMD instance. The two VMs' boot volumes
use 147 GB of the 200 GB allowance, so the 53 GB left fits one 47 GB rescue volume: rescue one VM
at a time.

1. **Stop** the A1 instance (Force stop if it hangs).
2. Under the instance's **Boot volume**, choose **Detach**.
3. Create the rescue instance:
   - shape `VM.Standard.E2.1.Micro`, Always Free;
   - image Ubuntu 24.04 (x86), with a **47 GB** boot volume, which fits the 53 GB left;
   - in the broken VM's VCN and public subnet, with your SSH key and an ephemeral public IP.

   Add a TCP 22 ingress rule for `<your public ip>/32` to that VCN's security list, so you can reach
   it. Step 8 needs the rule too.
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
8. SSH in over the VM's public IP (the TCP 22 rule from step 3 allows it), and repair WireGuard
   (Path 1 steps). Then run `sudo ~/wassal-docker/host/provision.sh --finalize` and remove the TCP
   22 rule again.

## Instance stopped by Oracle

Oracle may stop an Always Free instance that has looked idle for 7 days: CPU, network and memory
all under 20% (R1). The data on the boot volume is kept. The staging VM, with no player traffic, is
the likelier one.

- **Signs:** the VM's host-monitor check (`host-monitor-prod` or `host-monitor-staging`) goes
  down, for production the uptime alert fires too, and the console shows the instance as
  **Stopped**.
- **Fix:** choose **Start**. On "Out of host capacity", retry once a day; Jeddah has one
  availability domain.
- **After it starts:**
  - Check that the reserved IP is still attached to the VNIC.
  - Run `curl https://<that VM's API hostname>/healthz`.
  - Connect over its WireGuard and check `sudo docker ps`. The restart policies bring every
    container back.
  - On the staging VM, a drill missed while it was stopped runs at boot (`Persistent=true`). Check
    `restore-drill-prod`.
  - Look at the instance's utilization metrics for the week before the stop, and note what you
    find in research.md R1.
- Don't add artificial load to dodge the rule (R1 accepts this risk).
