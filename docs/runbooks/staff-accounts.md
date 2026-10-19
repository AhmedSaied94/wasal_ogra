# Staff accounts

Staff sign in to the admin with a username, a password and a TOTP code, and only over WireGuard.
There's no sign-up and no password-reset page. The operator runs everything here, over WireGuard,
on the host. Background: research R5 and data-model.md "Lifecycle".

The commands run inside the environment's admin container: `wassal-prod-admin-1` or
`wassal-staging-admin-1`. The examples use production.

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
3. **Network:** add a WireGuard peer with role `staff`, and install the admin CA root on their
   device (private-network.md).
4. They sign in at the admin URL. They should see the OTP field, and no admin page until the code
   is valid.

Permissions: a new staff user has none. Grant what they need under **Users** in the admin, or with
groups.

## Lost or replaced phone

```bash
$ADMIN staff_totp <username> --reset        # deletes the old device and issues a new key
```

If the phone also held their WireGuard config, remove that peer and add a new one
(`sudo wg-peer remove <device>`).

## Forgotten password

```bash
$ADMIN changepassword <username>
```

Staff change their own password at `/admin/password_change/`.

## Locked out

Five failed sign-ins for one username, or from one device address, within 15 minutes lock it for 15
minutes, even with the right password and code. Waiting is the normal fix. To unlock early:

```bash
$ADMIN axes_list_attempts                  # what's locked
$ADMIN axes_reset_username <username>
$ADMIN axes_reset_ip <10.66.0.x>
```

Look into unexplained lockouts before you reset them. The private network means the attempts came
from a peer device.

## Someone leaves

```bash
$ADMIN create_staff <username> --deactivate     # they can't sign in, and open sessions stop working
sudo wg-peer remove <each of their devices>
```

The account stays for the audit trail (admin history). Don't delete it.
