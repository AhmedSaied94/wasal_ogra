# Auth signing keys

Players' tokens are signed with HS256 keys from `AUTH_SIGNING_KEYS`, in each environment's
`/etc/wassal/<env>.env`. The variable is a comma-separated ring of `kid:key` entries:

```text
AUTH_SIGNING_KEYS=k20261024:9mQ…,k20260301:Xc4…
```

- **The first entry signs.** Every entry verifies, and each token's `kid` header picks its key.
- **Startup refuses a bad ring:** 1 to 4 entries, each `kid` unique and `[a-z0-9-]`, each key
  base64url of at least 32 bytes, no `change-me` placeholder and no key equal to `SECRET_KEY`. A
  deploy with a bad ring fails at the migrate step and keeps the previous release.
- **Lifetimes:** access tokens last 15 minutes, refresh tokens 30 days. So a key no longer signs
  anything still valid 30 days and 15 minutes after it stopped being first.
- **Losing a key signs no one out for long.** Its tokens answer `401 token_invalid`, and the app
  signs in again with its install id, to the same player.

Background: `specs/009-b02-accounts-auth/research.md` R13 and `contracts/tokens.md`. Every command
below runs over the VM's WireGuard, as in [staff-accounts.md](staff-accounts.md). The examples use
production; for staging, use `10.67.0.1`, `staging` and `wassal-staging-…`.

```bash
ssh ubuntu@10.66.0.1
TAG="$(cat /var/lib/wassal/prod/release)"
STACK="/var/lib/wassal/prod/deploy/$TAG"
dc() { sudo RELEASE_TAG="$TAG" docker compose -p wassal-prod -f "$STACK/compose.yml" --env-file "$STACK/env/prod.env" "$@"; }
```

## Before B02's first deploy

Each environment needs these in `/etc/wassal/<env>.env` before the first release with B02 deploys
there, or that deploy fails (owner-actions T065, T066):

| Variable | Value |
| --- | --- |
| `AUTH_SIGNING_KEYS` | One entry, from "Generating a key" below. Different on staging and production. |
| `GOOGLE_OAUTH_CLIENT_IDS` | The Google web client id (comma-separated if there are several). Not a secret. |

The other B02 settings (`AUTH_REFRESH_RETRY_SECONDS`, `AUTH_MAX_SESSIONS_PER_PLAYER`, the
`THROTTLE_*` rates, …) have defaults; `backend/.env.example` lists them.

## Generating a key

On your machine, in `backend/`:

```bash
uv run manage.py auth_signing_key
```

It prints one entry, `k<YYYYMMDD>:<32 random bytes, base64url>`, and writes nothing. Once a release
with B02 serves, you can run it on the VM instead:
`sudo docker exec wassal-prod-admin-1 python manage.py auth_signing_key`.

Put the entry straight into your password manager, under the environment's name. Never paste it in
a chat, a ticket or a commit.

## Rotating

Once a year, or when someone who had a key leaves. Nobody is signed out.

1. **Before you edit,** keep a session to check with. Sign in with the install id you keep for these
   checks (one per environment, in your password manager, so every rotation reuses the same
   player), and keep its refresh token:

   ```bash
   API=https://api.193-122-74-125.sslip.io          # staging: https://staging-api.141-147-129-92.sslip.io
   PROBE=<the probe install id>
   HDRS=(-H 'Content-Type: application/json' -H 'X-Client-Version: 1.0.0' -H 'X-Platform: android')
   OLD=$(curl -fsS "${HDRS[@]}" -d "{\"install_id\":\"$PROBE\",\"platform\":\"android\",\"locale\":\"ar-EG\"}" \
     "$API/v1/auth/anonymous" | python3 -c 'import json,sys; print(json.load(sys.stdin)["refresh"])')
   ```

2. **Put the new entry first,** as `root`, and keep the old one after it:

   ```bash
   sudoedit /etc/wassal/prod.env      # AUTH_SIGNING_KEYS=<new entry>,<old entry>
   ```

3. **Recreate the services that read it:**

   ```bash
   dc up -d --force-recreate api admin worker beat
   ```

4. **Check:**
   - `curl -fsS "$API/readyz"` answers `200`;
   - renewing the old session works, and its new token names the new `kid`:

     ```bash
     curl -fsS "${HDRS[@]}" -d "{\"refresh\":\"$OLD\"}" "$API/v1/auth/refresh" | python3 -c '
     import base64, json, sys
     token = json.load(sys.stdin)["refresh"].split(".")[0]
     print(json.loads(base64.urlsafe_b64decode(token + "=" * (-len(token) % 4))))'
     ```

     It prints `{'alg': 'HS256', 'kid': '<new kid>', 'typ': 'JWT'}`.
5. **Set a reminder for 30 days and 15 minutes later.** Then remove the old entry, as in step 2, and
   recreate again as in step 3. Until then the ring keeps both: a session's retried renewal re-signs
   with the key its token named, while that key is still in the ring.

The ring holds at most 4 entries, so finish one rotation before starting the next.

## Emergency revocation

A key leaked: anyone holding it can mint tokens for any player. Don't wait 30 days.

1. **Edit the ring at once:** remove the leaked entry. If it was the only one, put a new entry in
   its place ("Generating a key") in the same edit, since the ring can't be empty.
2. **Recreate:** `dc up -d --force-recreate api admin worker beat`, then check `/readyz`.
3. **What players see:** every token the leaked key signed now answers `401 token_invalid`. The app
   signs in again with its install id and gets the same player, so a player notices at most a short
   wait.
4. **Afterwards:** look for sessions ended by reuse in the API logs (`event` `refresh_reuse` on the
   `wassal.security` logger), and record what happened in your incident notes.

## Measuring latency (quickstart B7)

Run this against **staging only**: it creates 300 players.

1. **Lift the account-creation limit for the run.** 300 creations from one address pass the
   60/hour limit. On the staging VM, add `THROTTLE_ANONYMOUS_RATE=1000/hour` to
   `/etc/wassal/staging.env`, then `dc up -d --force-recreate api`.
2. **From your machine,** 300 creations, each followed by a renewal:

   ```bash
   API=https://staging-api.141-147-129-92.sslip.io
   HDRS=(-H 'Content-Type: application/json' -H 'X-Client-Version: 1.0.0' -H 'X-Platform: android')
   for i in $(seq 300); do
     REFRESH=$(curl -fsS "${HDRS[@]}" \
       -d "{\"install_id\":\"$(uuidgen -r)\",\"platform\":\"android\",\"locale\":\"ar-EG\"}" \
       "$API/v1/auth/anonymous" | python3 -c 'import json,sys; print(json.load(sys.stdin)["refresh"])')
     curl -fsS -o /dev/null "${HDRS[@]}" -d "{\"refresh\":\"$REFRESH\"}" "$API/v1/auth/refresh"
   done
   ```

   For links, take a Google ID token from quickstart B2 (it lasts an hour), sign in once, and link
   the same player 30 times. The first call links, and the other 29 answer "already linked", each
   after a full verification:

   ```bash
   GOOGLE=<the ID token from B2>
   ACCESS=$(curl -fsS "${HDRS[@]}" \
     -d "{\"install_id\":\"$(uuidgen -r)\",\"platform\":\"android\",\"locale\":\"ar-EG\"}" \
     "$API/v1/auth/anonymous" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access"])')
   for i in $(seq 30); do
     curl -fsS -o /dev/null "${HDRS[@]}" -H "Authorization: Bearer $ACCESS" \
       -d "{\"provider\":\"google\",\"id_token\":\"$GOOGLE\"}" "$API/v1/auth/link"
   done
   ```

3. **On the staging VM,** read the server-side durations from the access log:

   ```bash
   sudo docker logs wassal-staging-api-1 --since 30m 2>&1 | python3 -c '
   import json, sys
   times = {}
   for line in sys.stdin:
       try:
           record = json.loads(line)
       except ValueError:
           continue
       route = record.get("route", "")
       if record.get("logger") == "wassal.access" and route.startswith("/v1/auth/"):
           times.setdefault(route, []).append(record["duration_ms"])
   for route, values in sorted(times.items()):
       values.sort()
       p95 = values[max(0, int(len(values) * 0.95) - 1)]
       print(f"{route}: n={len(values)} p95={p95} ms max={values[-1]} ms")'
   ```

   Pass: p95 ≤ 150 ms for `/v1/auth/anonymous` and `/v1/auth/refresh`, ≤ 1000 ms for
   `/v1/auth/link`. Record the numbers in owner-actions T067.
4. **Put the limit back:** remove the `THROTTLE_ANONYMOUS_RATE` line, then
   `dc up -d --force-recreate api`.
