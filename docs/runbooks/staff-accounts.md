# Staff accounts

Staff sign in to the admin with a username, a password and a TOTP code, and only over WireGuard.
There's no sign-up and no password-reset page. The operator runs everything here, over WireGuard,
on the environment's own VM. Background: research R5 and data-model.md "Lifecycle".

Each environment has its own admin, on its own VM, with its own accounts:

| Environment | Admin URL | VM, over its WireGuard | Admin container |
| --- | --- | --- | --- |
| Production | `https://admin.10-66-0-1.sslip.io/admin/` | `ssh ubuntu@10.66.0.1` | `wassal-prod-admin-1` |
| Staging | `https://staging-admin.10-67-0-1.sslip.io/admin/` | `ssh ubuntu@10.67.0.1` | `wassal-staging-admin-1` |

Someone who needs both admins gets an account, a second factor and a WireGuard peer in each, and
installs both CA roots. The examples use production:

```bash
ssh ubuntu@10.66.0.1
ADMIN="sudo docker exec -it wassal-prod-admin-1 python manage.py"
```

## Add a staff member

1. **Account:**

   ```bash
   $ADMIN create_staff <username>              # add --superuser only for the owner
   ```

   It asks for the password twice and never shows it. The password needs at least 12 characters,
   and it can't be common, entirely numeric, or close to the username. Usernames are
   case-insensitive.
2. **Second factor**, with the staff member present:

   ```bash
   $ADMIN staff_totp <username>
   ```

   It prints an `otpauth://` URI and the base32 key **once**. The staff member adds it to an
   authenticator app: type in the key, or scan a QR code you make on your laptop with
   `qrencode -t ansiutf8 '<URI>'`. Settings: TOTP, 6 digits, 30 seconds. Close the terminal
   tab afterwards (`clear` keeps the scrollback). Never send the key by chat or email.
3. **Network:** on the same VM, add a WireGuard peer with role `staff`, and install that VM's admin
   CA root on their device (private-network.md).
4. They sign in at that environment's admin URL. They should see the OTP field, and no admin page
   until the code is valid.

Permissions: a new staff user has none. Grant what they need under **Users** in the admin, or with
groups.

## Lost or replaced phone

In each environment where they have an account:

```bash
$ADMIN staff_totp <username> --reset        # deletes the old device and issues a new key
```

If the phone also held their WireGuard configs, remove that peer on each VM it was added to, and
add a new one (`sudo wg-peer remove <device>`).

## Forgotten password

```bash
$ADMIN changepassword <username>
```

Staff change their own password at `/admin/password_change/`. Each environment's password is
separate.

## Locked out

Five failed sign-ins for one username, or from one device address, within 15 minutes lock it for 15
minutes, even with the right password and code. Waiting is the normal fix. To unlock early, in the
environment where it happened:

```bash
$ADMIN axes_list_attempts                  # what's locked
$ADMIN axes_reset_username <username>
$ADMIN axes_reset_ip <10.66.0.x on prod, 10.67.0.x on staging>
```

Look into unexplained lockouts before you reset them. The private network means the attempts came
from a peer device.

## Someone leaves

In each environment where they have an account, and on each VM where they have a peer:

```bash
$ADMIN create_staff <username> --deactivate     # they can't sign in, and open sessions stop working
sudo wg-peer remove <each of their devices>
```

Have them remove the admin CA roots from their devices (private-network.md). The account stays for
the audit trail (admin history). Don't delete it.
