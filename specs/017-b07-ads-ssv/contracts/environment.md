# Environment: B07

Operational values only; every balancing number is a live setting (data-model.md), never an env
variable (backend/CLAUDE.md "Rules").

| Variable | Default | dev | staging | prod | Secret | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `ADS_VERIFIER_KEYS_URL` | `https://www.gstatic.com/admob/reward/verifier-keys.json` | `file:///app/.dev/admob_verifier_keys.json` (written by `ads_dev_callback`) | as default | as default | no | Must be `https` outside dev and test (the settings check refuses `http` and `file`). Tests point it at a local server. |
| `ADS_KEYS_CACHE_SECONDS` | `86400` | | | | no | 60–604 800 |
| `ADS_HTTP_TIMEOUT_SECONDS` | `5` | | | | no | 1–30 |
| `ADS_ALLOWED_AD_UNITS` | empty | empty (every unit) | the staging piggy unit's id | the production piggy unit's id | no | Added by the security review (H1): Google's verifier keys sign every publisher's callbacks, so only these ad unit ids (the digits after `/` in `ca-app-pub-…/…`, comma-separated) may grant. A callback for any other unit is answered 200, logged `foreign_ad_unit` and not recorded. Empty grants nothing outside dev and test. Set in `/etc/wassal/<env>.env`. |
| `THROTTLE_SSV_RATE` | `600/min` | | | | no | DRF rate string; the `no_throttle` fixture turns it off |

Constants in code (not tunables: they are protocol and safety bounds, not balancing):
`REFRESH_COOLDOWN_SECONDS = 60` (FR-003), `FAILED_FETCH_SECONDS = 15`, `EXPIRY_DAYS = 7`
(FR-006a), `RETENTION_DAYS = 90` (FR-006), `ALERT_SIGNATURE_THRESHOLD = 20` and
`ALERT_WINDOW_SECONDS = 3600` (FR-007), `UNSEEN_LIMIT = 5` (bootstrap).

`.env.example` and B01's `contracts/environment.md` table get the four rows.
