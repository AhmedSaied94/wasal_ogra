# backend/CLAUDE.md

The Django backend: what it has, its commands and its conventions. The project-wide rules are in the root `CLAUDE.md`.

## What's built

- **B01** (`specs/002-b01-backend-skeleton/`): settings that refuse bad configuration, health endpoints, the error envelope, throttling, the Celery heartbeat, Docker Compose for dev, staging and prod, and the staff-only admin.
- **B04** (`specs/003-b04-content-pipeline/`, `backend/apps/content/`): authoring in the admin, zip import and export, builds and validation, publishing on staging, promotion to production, the manifest endpoint and the pack files the edge serves. It runs `tools/solver` as the content pipeline's solver stage and the admin's trip preview.
- **B02** (`specs/009-b02-accounts-auth/`, `backend/apps/accounts/`): anonymous players by install id, sessions with rotating refresh tokens, Google linking and its conflicts, and the read-only player admin.
- **M10's content** (`specs/015-m10-apartment-story/`, `backend/apps/content/`): the story fields B04 carries for the apartment and the story, as migration `0011_m10_story_fields` and `0012_rider_permissions` (expand-only: the slot CHECK lets a not-yet-authored 0 pass), the `StoryRider` model (a chapter's riders in `story_trip_info`, V-C7) with its importer, snapshot and admin. A pack built before the required fields no longer reads, so staging builds and publishes a fresh one after the deploy (`docs/runbooks/content-publishing.md`).
- **B03** (`specs/010-b03-ledger-sync/`, `backend/apps/economy/` and `backend/apps/progress/`): the append-only ledger and its wallets, `GET /v1/bootstrap`, `GET /v1/state` and `POST /v1/sync` with its eleven operation types, fuel on the server's clock, the gifts and story rewards, display names and the name filter, flags of odd play, and the staff's balance adjustments.
- **B10** (`specs/016-b10-catalog-offers/`, `backend/apps/liveops/`): the live settings registry and its append-only history, the `426 client_outdated` and `503 maintenance` default permissions, the maintenance command and the job skip, the store catalog with typed grants and `grants_for`, `GET /v1/offers`, offers with validated rules and an hourly expiry, and the daily Remote Config drift check. The eighteen `ECONOMY_*`/`SYNC_*`/`CLIENT_*` balancing variables are retired; a host's value was imported once on migrate.
- **B07** (`specs/017-b07-ads-ssv/`, `backend/apps/ads/`): AdMob's server-side verification callback `GET /v1/ads/ssv` (public, signed, its own per-address limit), which records every validly signed callback as an `AdReward` with its outcome and grants the morning piggy through the ledger; the app's lookup `GET /v1/ads/rewards/{nonce}`; bootstrap's `ads.morning_piggy` block; the sync op `ad_reward_seen`; the read-only ad rewards admin; the daily cleanup of non-granting rows (90 days); and the Sentry alerts on refused signatures and unreachable keys. `economy` imports only `ads.models` and `ads.services.status` (a test checks).

## Commands

Python is pinned by `backend/.python-version` and managed with uv (never pip). Run everything from `backend/`. CI (`.github/workflows/backend.yml`) runs the same commands. `docker compose …` below is short for `docker compose -f docker/compose.yml -f docker/compose.dev.yml`.

| Purpose | Command (in `backend`) |
| --- | --- |
| First setup | `cp .env.example .env && uv sync` |
| Start the local stack (migrates first) | `docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait` |
| Stop it (keep data) / wipe it | `docker compose … down` / `docker compose … down -v` |
| Migrate | `uv run manage.py migrate` |
| Lint and format check | `uv run ruff check . && uv run ruff format --check .` |
| Type check | `uv run mypy .` |
| Tests + coverage gate (on 4 workers, as CI; at most 7) | `uv run pytest -n 4 --cov --cov-fail-under=80` |
| Missing-migration check | `uv run manage.py makemigrations --check --dry-run` |
| Regenerate the API contract | `uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn` |
| Create a staff user / issue TOTP | `uv run manage.py create_staff <name> [--group content_author\|player_support\|economy_ops\|live_ops]` / `uv run manage.py staff_totp <name>` |
| Maintenance on, off or its state (B10) | `uv run manage.py maintenance status` / `maintenance on --actor <staff> [--until <ISO>] [--note …]` / `maintenance off --actor <staff>` (`docs/runbooks/live-ops.md`) |
| Print a new token signing key entry (`kid:key`) | `uv run manage.py auth_signing_key` (rotation: `docs/runbooks/auth-keys.md`) |
| The auth property test at 10,000 examples (once per feature that touches auth) | `HYPOTHESIS_PROFILE=thorough uv run pytest apps/accounts/tests/test_properties.py` |
| The economy property test at 10,000 examples (once per feature that touches the economy) | `HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py` |
| Write the missing rules index rows of published packs (a deploy step after B03; worker container on a host) | `uv run manage.py content_index --rebuild` |
| Dev only: sign an AdMob callback with the dev key and send it to the API (B07; the first run writes `backend/.dev/`, then restart the API container once) | `uv run manage.py ads_dev_callback --user <player_id> [--placement …] [--nonce …] [--transaction-id …] [--age-days N] [--tamper]` |
| Check every wallet against its ledger (exit 1 on a mismatch) | `uv run manage.py economy_check` (a mismatch: `docs/runbooks/economy.md`) |
| Import / export content (a `content/source` layout or zip) | `uv run manage.py content_import <dir-or-zip> --actor <staff>` / `uv run manage.py content_export <dir> [--version N] --actor <staff>` |
| Build a pack, or only print its checksums | `uv run manage.py content_build --actor <staff>` / `uv run manage.py content_build --actor <staff> --dry-run [--version N]` |
| Rewrite missing pack files, hash the present ones | `uv run manage.py content_files sync --verify` |
| Deploy, roll back, restore | See `docs/runbooks/deploy-and-rollback.md` and `docs/runbooks/restore.md` |

- The API is on <http://localhost:8000> (the Android emulator reaches it as `10.0.2.2:8000`), the admin on <http://localhost:8001/admin/>.
- Tests need the stack's PostgreSQL and Valkey: they run against the real services, never mocks (constitution XIII). pytest reads only the `TEST_*` URLs from `backend/.env`.
- The dev stack's PostgreSQL is on port 5433 (beside a native PostgreSQL's 5432), Valkey on 6379. If either is taken on your machine, export `WASSAL_DEV_PG_PORT` or `WASSAL_DEV_VALKEY_PORT` before `docker compose up`, and use the same port in the URLs in `backend/.env`.
- The backend's image carries its own copies of `tools/content_kit` and `tools/solver`. After changing either (a schema included), run `uv sync --reinstall-package wassal-content --reinstall-package wassal-solver` here and rebuild the dev stack's image (`docker compose … build`, then `up -d --wait`). Until then its worker checks packs against the old schemas, and a build fails with "not an allowed property".

## Environment

- Every value comes from the environment (`specs/002-b01-backend-skeleton/contracts/environment.md`). Outside `dev` and `test`, a missing, empty or `change-me` secret stops the process at startup.
- B04 adds the `CONTENT_*` variables (`specs/003-b04-content-pipeline/contracts/environment.md`): `CONTENT_ROLE` (`source` on dev and staging, `target` on prod), `CONTENT_PACKS_DIR`, `CONTENT_PACKS_PUBLIC_URL`, `CONTENT_VERSION_FLOOR_URL` (staging: production's packs URL), `CONTENT_PROMOTION_SOURCE_URL` (prod: staging's packs URL), `CONTENT_SOLVER_STAGE` (`solver`, the real stage, by default on staging and prod; `stand_in` in dev and test only), `CONTENT_MANIFEST_CACHE_SECONDS` and `CONTENT_HTTP_TIMEOUT_SECONDS`. The settings check refuses a role or URL in the wrong environment.
- B02 adds the `AUTH_*`, `GOOGLE_*` and four `THROTTLE_*` variables (`specs/009-b02-accounts-auth/contracts/environment.md`). `AUTH_SIGNING_KEYS` is required everywhere, and `GOOGLE_OAUTH_CLIENT_IDS` outside dev and test.
- B03's `ECONOMY_*` and `SYNC_*` balancing variables are **retired by B10**: every one is a live setting in `apps/liveops/registry.py` now, and a host's value was imported once on migrate (`liveops.W001` warns while one is still set). `SYNC_GAME_TIMEZONE`, `SYNC_OP_RETENTION_DAYS`, `CONTENT_INDEX_KEEP`, `THROTTLE_*` and the secrets stay in the environment. B10 adds `LIVEOPS_REFRESH_SECONDS` (30, 5–55), `FIREBASE_PROJECT_ID` and `REMOTE_CONFIG_SERVICE_ACCOUNT` (both optional, but only together).
- B07 adds `ADS_VERIFIER_KEYS_URL` (Google's AdMob key list; `https` outside dev and test, and a `file://` URL only in dev and test, for `ads_dev_callback`'s key list), `ADS_KEYS_CACHE_SECONDS` (86 400, 60–604 800), `ADS_HTTP_TIMEOUT_SECONDS` (5, 1–30), `THROTTLE_SSV_RATE` (`600/min`) and `ADS_ALLOWED_AD_UNITS` (the AdMob ad unit ids that may grant; empty grants nothing outside dev and test, because Google's keys sign every publisher's callbacks) (`specs/017-b07-ads-ssv/contracts/environment.md`). The morning piggy's cap and amounts are live settings.
- The ads tests sign real callbacks: the `admob_keys` fixture (`apps/ads/tests/conftest.py`) serves a session P-256 key in AdMob's key-list shape from a local HTTP server, and `apps/ads/tests/signing.py` signs queries with it (`callback(user_id=…)` sends one).

## Rules

- **Every balance change goes through `apps.economy.services.ledger`** (`apply_entry`, `flush_entries`, `apply_now`), which writes the `LedgerEntry` and the `Wallet` together. Nothing else assigns `jenehat` or `bonat` (an AST scan test fails on it), and nothing edits or deletes a ledger row. Sync operations are handlers in `apps/economy/services/ops/`, registered with `sync.register`; they read and change the batch's in-memory state, never the ORM (a test checks).
- **Every new `/v1` endpoint needs a player token and the two headers (`X-Client-Version`, `X-Platform`), and is limited per player**, unless its view opts out explicitly (B02 FR-032–FR-035). Those are the REST framework defaults (`PlayerAuthentication`, `IsAuthenticated` + `ClientHeaders`, the player throttle). The public ones today are `/healthz`, `/readyz`, the manifest and `POST /v1/auth/anonymous` and `/refresh`. A failed auth check raises `apps.common.errors.ApiError`, never DRF's `AuthenticationFailed`.
- The content commands that act for a person need `--actor <staff>` and make the admin's permission checks. Only the worker mounts the packs directory, so on a host run `content_files` in the worker container. Publishing and promoting: `docs/runbooks/content-publishing.md`.
- **Every balancing number is a live setting** in `apps/liveops/registry.py`, read through `apps.liveops.settings.current()` (one snapshot per batch or request); a new number goes there and, if the phone applies it, into `apps/mobile/assets/config/tunables.json` (a parity test keeps them equal). Never add one to the environment.
- **A scheduled job that writes uses `liveops.tasks.skip_in_maintenance`**; the only exceptions are the jobs that write only their own check rows (`common.tasks.heartbeat`, `liveops.tasks.check_remote_config`), and a test fails if a new `PeriodicTask` is neither wrapped nor listed.
- **Settings, products and offers are written only through `apps/liveops/services/`**, which records the `LiveopsChange` in the same transaction. The admin calls those services; no form or view saves a `LiveSetting` directly.

## Conventions (backend §5, §17.1)

- Each app is `apps/<name>/{models,services/,api/,tasks,admin}`. Business logic goes in `apps/<app>/services/`. Views and serializers stay thin.
- Use the error envelope `{"error": {"code", "message", "details"}}` with the code table in §6.2.
- UUIDv7 primary keys. Migrations are expand/contract, so the previous release keeps working during a deploy.
- External calls (stores, FCM) run in Celery with timeouts and retries. The exception is purchase verification, which is synchronous with a 10 s timeout and recovers through RTDN.
- The committed `contracts/openapi.yaml` must match the code. CI diffs it.

## Deployment

Two Oracle Cloud Always Free A1 VMs (ARM64) in `me-jeddah-1`, one per environment: production and staging, each 1 OCPU / 6 GB with its own reserved IP, running Docker Compose behind its own host-network Caddy. `provision.sh --env` fixes each VM's environment. Each VM has its own WireGuard network (`10.66.0.1` prod, `10.67.0.1` staging); its admin is reachable only over it, and so is SSH. Backups run on production, and on staging for its authored content (B04), each into its own Backblaze B2 buckets; the monthly restore drill runs on staging. Build images for `linux/arm64`. Operating it is in `docs/runbooks/`.
