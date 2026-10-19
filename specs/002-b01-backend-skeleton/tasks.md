---

description: "Task list for B01 Backend Skeleton"
---

# Tasks: Backend Skeleton (B01)

**Input**: Design documents from `specs/002-b01-backend-skeleton/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**:

- Tests are **mandatory** (constitution XIII). Every story writes its tests first, and they must fail
  before the implementation tasks start.
- Tests run against real PostgreSQL and Valkey. B2 is faked only at the boto3 boundary (moto), and
  the host scripts run under pytest with stub binaries first on `PATH`.
- Required coverage: ≥ 80% lines for the backend (SC-012).

**Organization**:

- Tasks are grouped by user story. Paths are from the repository root.
- The backend lives in `backend/`. Run `uv` and `manage.py` commands from `backend/` unless a task
  says otherwise.
- "Operator" tasks need the owner's accounts (Oracle, Backblaze, GitHub settings), so an agent can't
  do them alone.
- "Live validation" tasks run on the real host after the PR merges, because images exist only for
  `master` commits (contracts/ci-checks.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1–US6 from spec.md)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Pin the toolchain and dependencies, scaffold `backend/`, and run the spike items that
don't need application code (plan "Spikes come first").

- [X] T001 Create `backend/.python-version` containing `3.13` and `backend/pyproject.toml` (research R2), then run `uv lock` in `backend/` and commit `backend/uv.lock`:
  - `[project]`: `name = "wassal-backend"`, `version = "0.1.0"`, `requires-python = "==3.13.*"`, and exact pins `Django==5.2.18`, `djangorestframework==3.18.3`, `drf-spectacular==0.30.0`, `celery==5.6.3`, `django-celery-beat==2.9.0`, `redis==6.4.0`, `psycopg[binary]==3.3.6`, `django-environ==0.14.0`, `uuid-utils==1.0.0`, `django-otp==1.7.5`, `django-axes==8.3.1`, `sentry-sdk==2.72.0`, `python-json-logger==4.2.0`, `gunicorn==26.2.0`, `whitenoise==6.12.0`, `requests==2.34.2`, and `boto3` pinned to the newest `1.43.N` at lock time;
  - `[dependency-groups] dev`: `ruff==0.17.1`, `mypy==1.19.1`, `django-stubs==5.2.9`, `djangorestframework-stubs==3.16.9`, `celery-types==0.26.0`, `types-requests` (newest), `pytest==9.1.1`, `pytest-django==4.14.0`, `pytest-cov==7.1.0`, `factory-boy==3.3.3`, `moto[s3]==5.2.4`, and `hypothesis` and `schemathesis` pinned to the newest `6.170.N` and `4.31.N`;
  - `[tool.uv] package = false`;
  - `[tool.ruff]`: `target-version = "py313"`, `line-length = 100`, lint `select = ["E", "W", "F", "I", "B", "UP", "S", "DJ", "BLE", "SIM", "PT", "RUF"]`, `per-file-ignores` `"**/tests/**" = ["S101"]` and `"**/migrations/**" = ["E501"]`;
  - `[tool.mypy]`: `strict = true`, `plugins = ["mypy_django_plugin.main", "mypy_drf_plugin.main"]`, `exclude = ["^\\.venv/"]`, and `[tool.django-stubs] django_settings_module = "config.settings.test"`. Add `[[tool.mypy.overrides]]` with `ignore_missing_imports = true` only for the packages that the first `uv run mypy .` reports as untyped;
  - `[tool.pytest.ini_options]`: `DJANGO_SETTINGS_MODULE = "config.settings.test"`, `testpaths = ["apps", "tests", "docker/host/tests"]`, `addopts = "--strict-markers"`;
  - `[tool.coverage.run]`: `source = ["apps", "config", "tools"]`, `omit = ["*/migrations/*", "*/tests/*", "config/wsgi.py", "config/gunicorn.conf.py"]`.
- [X] T002 [P] Create the package skeleton in `backend/`:
  - `manage.py`, with default settings `config.settings.dev`;
  - `config/__init__.py` and `config/settings/__init__.py`;
  - `apps/__init__.py`;
  - `apps/common/{__init__.py,apps.py}` (`name = "apps.common"`, `label = "common"`, so the check id is `common.E001` and task names start with `common.`) and `apps/common/tests/__init__.py`;
  - `apps/accounts/{__init__.py,apps.py}` (`name = "apps.accounts"`, `label = "accounts"`) and `apps/accounts/tests/__init__.py`;
  - `tests/__init__.py`, `tools/__init__.py` and `docker/host/tests/__init__.py`.

  Append `backend/staticfiles/` to the root `.gitignore`.
- [X] T003 [P] Create `backend/.env.example` (FR-002, contracts/environment.md):
  - every "Application variables" entry, set to dev values: `DJANGO_SETTINGS_MODULE=config.settings.dev`, `WASSAL_ENV=dev`, `API_HOST=localhost`, `ADMIN_HOST=localhost`, `NUM_PROXIES=0`, `RELEASE=dev`, empty `SENTRY_DSN` and `HC_PING_HEARTBEAT_URL`;
  - `DATABASE_URL=postgres://wassal:change-me-db@127.0.0.1:5432/wassal`, `CACHE_URL=redis://127.0.0.1:6379/0` and `CELERY_BROKER_URL=redis://127.0.0.1:6379/1`. These are for commands run on the host; the dev containers override them with service names (T029);
  - `POSTGRES_PASSWORD=change-me-postgres` and `WASSAL_DB_PASSWORD=change-me-db` for the database container;
  - `TEST_DATABASE_URL=postgres://postgres:change-me-postgres@127.0.0.1:5432/postgres`, `TEST_CACHE_URL=redis://127.0.0.1:6379/2` and `TEST_BROKER_URL=redis://127.0.0.1:6379/3` for pytest;
  - a `SECRET_KEY` of at least 50 characters. Every secret value starts with `change-me-`.

  A comment at the top says that changing a dev password also means exporting the same value before `docker compose up`.
- [X] T004 [P] Spike, CI-runner half (plan spike item 1, research R6 and R8). On a scratch branch `spike/b01-edge`, add a throwaway `.github/workflows/spike-b01.yml` (`workflow_dispatch`, `ubuntu-24.04`). It does the following:
  - Runs `caddy:2.11.7` with `--network host` and a scratch Caddyfile with two sites:
    - `api.127-0-0-1.sslip.io`: `bind 127.0.0.1`, `tls internal`, `request_body { max_size 512KB }`, `reverse_proxy 127.0.0.1:9000 { request_buffers 1MB }`, and `handle_errors 413` responding with the `payload_too_large` envelope;
    - `admin.127-0-0-2.sslip.io`: `bind 127.0.0.2`, `tls internal`, `respond "admin" 200`.
  - Starts an upstream on `127.0.0.1:9000` that answers 200 without reading the request body: a `python3` `http.server` whose `do_POST` never reads `rfile`.
  - Asserts with `curl -k --resolve`:
    - a 600 KB `POST` to the API site → 413 with the envelope;
    - `Host: admin…` on `127.0.0.1:443` → no admin response;
    - `127.0.0.2:443` → `admin`.
  - Runs `sudo apt-get install -y wireguard-tools`, then `sudo wg-quick up` with a generated client config that has no `DNS=` line and `AllowedIPs = 10.66.0.1/32`. The peer endpoint can be unreachable: the check is that `wg-quick up` succeeds and the default route is unchanged. Then runs `wg-quick down`.

  Record each outcome in research.md R6 and R8, replacing each **[verify in spike]** marker with the result (or the workaround, if the check failed). Then delete the branch. The SSH round trip in R8 is proven by the first staging deploy (T062).

  *Done 2026-10-18, run locally with the same Caddy image instead of on a CI runner: the edge half passed and is recorded in R6. The WireGuard half (`wg-quick up` with no `DNS=` line) was not run; R8 is marked "[verify at first deploy]" and T062 checks it.*
- [ ] T005 [P] Spike, Backblaze half (operator, needs the B2 admin key; plan spike item 2, research R9). Use a throwaway script in a scratch directory outside the repository:
  1. In the B2 console, turn on MFA and set USD 0 caps on storage and on Class A, B and C transactions.
  2. With the native API:
     - create bucket `wassal-spike-<random>` with `fileLockEnabled: true`, `defaultServerSideEncryption: {"mode": "SSE-B2", "algorithm": "AES256"}` and the lifecycle rule `{"fileNamePrefix": "", "daysFromUploadingToHiding": 1, "daysFromHidingToDeleting": 1}`, then check that `b2_list_buckets` reports the encryption back;
     - set governance default retention of 1 day with `b2_update_bucket`;
     - create a write key (`capabilities: ["writeFiles"]`, this bucket, `namePrefix: "prod/"`) and a read key (`["listBuckets", "listFiles", "readFiles"]`).
  3. With boto3 and `Config(signature_version="s3v4", request_checksum_calculation="when_required", response_checksum_validation="when_required")`:
     - upload `prod/a.bin` with the write key and a correct `ContentMD5`, and download it with the read key;
     - upload `prod/b.bin` with a wrong `ContentMD5`. It must be refused (`BadDigest`); moto doesn't check this, so only the spike proves the backup's integrity check;
     - with the write key, try `delete_object` with a `VersionId`, `put_object_retention` and `list_objects_v2`. Each must be refused;
     - upload `prod/a.bin` again, then confirm with the read key's `list_object_versions` that both versions exist;
     - try the write key with and without `listAllBucketNames`, to find out whether boto3 needs it.
  4. Record in research.md R9, replacing its **[verify in spike]** item:
     - the native API version and the exact call sequence used;
     - each result, and the S3 error code returned for a refused call;
     - the `listAllBucketNames` answer.

     `b2_setup.py` (T079) follows this record.
  5. After the 1-day lock ends, delete the scratch bucket's file versions (with `bypassGovernance`) and the bucket itself with the admin key, then delete both scratch keys.

**Checkpoint**: T004 gates the edge and deploy tasks (T048, T049, T058), and T005 gates the B2 tasks
(T073, T079). Everything else can start once T001–T003 are done.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Settings with fail-fast validation, the UUIDv7 building block, the project-owned staff
user in the very first migration, and the database and cache that every test runs against.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests first (must fail before T009)

- [X] T006 [P] Write `backend/tests/test_settings_guards.py` (FR-003, FR-004, contracts/environment.md "Startup rules").
  - **Harness:** each case loads a settings module in a subprocess (`python -c "import django; django.setup()"`) with `DJANGO_SETTINGS_MODULE` set, `WASSAL_READ_DOTENV=0`, and a crafted environment. The developer's `backend/.env` is never read. Each case asserts the exit code and stderr.
  - A missing `SECRET_KEY`, `DATABASE_URL`, `CACHE_URL` or `CELERY_BROKER_URL` exits non-zero with `<NAME> is required`, and the output never contains any value from the environment.
  - With `config.settings.prod` and with `config.settings.staging`, each of these refuses to start and names the variable:
    - a secret containing `change-me`;
    - a `SECRET_KEY` shorter than 50 characters;
    - `DJANGO_DEBUG=true`;
    - a `WASSAL_ENV` that doesn't match the module.
  - `config.settings.dev` starts with the values in `backend/.env.example`.
  - `connect_timeout=3` is appended to `DATABASE_URL` when absent, and kept when present.
  - `SENTRY_TRACES_SAMPLE_RATE` outside `0.0`–`0.1` is refused. The default is `0.05`.
  - `ADMIN_ONLY=1` gives `ROOT_URLCONF == "config.urls_admin"`. Otherwise it is `config.urls`.
  - `TIME_ZONE == "UTC"` and `USE_TZ` is true.
- [X] T007 [P] Write `backend/apps/common/tests/test_ids.py` (FR-016):
  - `uuid7()` returns a `uuid.UUID` with `version == 7`;
  - 1000 consecutive values are unique and sort in creation order;
  - `UUIDv7Model._meta.get_field("id")` is the primary key, with `default` `apps.common.ids.uuid7` and `editable=False`, and `UUIDv7Model` is abstract.
- [X] T008 [P] Write `backend/apps/accounts/tests/test_user.py` (FR-017, data-model "accounts.User"):
  - `settings.AUTH_USER_MODEL == "accounts.User"`, and the model has no `email`, `first_name` or `last_name` field;
  - `id` is a UUIDv7;
  - `username` matches `^[a-z0-9._-]{3,150}$`:
    - it is lowercased on save (`Ahmed.S` → `ahmed.s`) and is unique;
    - `full_clean()` rejects `ab`, a 151-character name and `ahmed saied`;
  - `password_validation.validate_password` rejects an 11-character password, a common password, a numeric-only password and one similar to the username;
  - `is_staff` and `is_superuser` default to false and `is_active` to true, and `date_joined` is set on create;
  - the `accounts` app has exactly one migration, `0001_initial`, and it creates the table with a `uuid` primary key.

### Implementation

- [X] T009 Implement `backend/config/env.py` (research R3, contracts/environment.md). It is one typed reader over django-environ, `Env(<settings name>)`, with `string`, `integer`, `number`, `boolean` and `secret` accessors, `secret_key()`, `database()`, `cache()` and `broker()` for the composite values, and a `check_environment()` that enforces the startup rules:
  - a missing or invalid required variable raises `ImproperlyConfigured("<NAME> is required")` (or `"<NAME> is invalid"`), never including the value;
  - outside `dev` and `test`, these fail the same way:
    - a secret containing `change-me`;
    - a `SECRET_KEY` shorter than 50 characters;
    - `DJANGO_DEBUG` true;
    - a `WASSAL_ENV` that doesn't match the settings module;
  - `DATABASE_URL` gains `connect_timeout=3` if it has none;
  - in `dev` only, `backend/.env` is read first, without overriding variables that are already set. `WASSAL_READ_DOTENV=0` turns this off.
- [X] T010 Implement the settings modules in `backend/config/settings/` (research R3). Every value goes through `config.env`.
  - `base.py`:
    - `INSTALLED_APPS`: Django's `admin`, `auth`, `contenttypes`, `sessions`, `messages` and `staticfiles`, then `rest_framework`, `drf_spectacular`, `django_celery_beat`, `apps.common` and `apps.accounts`;
    - `AUTH_USER_MODEL = "accounts.User"`, and the four password validators, with `MinimumLengthValidator` set to `min_length=12`;
    - `DATABASES` from `DATABASE_URL`;
    - `CACHES` from `CACHE_URL`: a `redis://` URL gives `django.core.cache.backends.redis.RedisCache` with `socket_connect_timeout=2` and `socket_timeout=2`, and `locmem://` (used only by the restore drill) gives `LocMemCache`. Any other scheme is invalid;
    - `TIME_ZONE = "UTC"`, `USE_TZ = True` and `DATA_UPLOAD_MAX_MEMORY_SIZE = 524288`;
    - static files: `STATIC_URL = "/static/"`, `STATIC_ROOT = BASE_DIR / "staticfiles"`, and `STORAGES["staticfiles"]` set to WhiteNoise's `CompressedManifestStaticFilesStorage`;
    - `DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"`, which only framework apps use;
    - `ROOT_URLCONF` chosen by `ADMIN_ONLY`. `ALLOWED_HOSTS` is `[API_HOST]` or `[ADMIN_HOST]` by role, plus `127.0.0.1` and `localhost` for the container health checks and the deploy's verify step;
    - `RELEASE`, `WASSAL_ENV`, `SENTRY_DSN`, `SENTRY_TRACES_SAMPLE_RATE`, `THROTTLE_ADDRESS_RATE`, `NUM_PROXIES` and `LOG_LEVEL`.
  - `dev.py`:
    - `DEBUG` from the environment (default true) and `NUM_PROXIES = 0`;
    - `ALLOWED_HOSTS += ["10.0.2.2"]`, for the emulator;
    - when `DEBUG` is true, the plain `StaticFilesStorage`, with `WHITENOISE_USE_FINDERS = True` and `WHITENOISE_AUTOREFRESH = True`. With `DEBUG` false (the image build, T027), base's manifest storage stays, so `collectstatic` writes the manifest that production needs.
  - `test.py`:
    - `WASSAL_ENV = "test"` and a fixed test `SECRET_KEY`;
    - `DATABASES` from `TEST_DATABASE_URL` (default `postgres://postgres:change-me-postgres@127.0.0.1:5432/postgres`);
    - the cache from `TEST_CACHE_URL` (default `redis://127.0.0.1:6379/2`);
    - `CELERY_BROKER_URL` from `TEST_BROKER_URL` (default `redis://127.0.0.1:6379/3`), so the tests use the real Valkey as the broker (constitution XIII), and the MD5 password hasher;
    - the plain `StaticFilesStorage`, so admin pages render in tests without `collectstatic`;
    - it loads with no environment variables set, which mypy's django plugin needs.
  - `prod.py`:
    - `DEBUG = False` and `SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")`;
    - cookies: `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` and `SESSION_COOKIE_HTTPONLY`;
    - `CSRF_TRUSTED_ORIGINS = ["https://" + ADMIN_HOST]`, and `NUM_PROXIES` defaulting to `1`;
    - `SILENCED_SYSTEM_CHECKS = ["security.W004", "security.W008"]`, because the edge sets HSTS and the HTTPS redirect (R6).
  - `staging.py`: `from .prod import *` and nothing else.
- [X] T011 [P] Implement `backend/apps/common/ids.py` and `backend/apps/common/models.py` (FR-016, research R3):
  - `uuid7()` returns `uuid_utils.compat.uuid7()`;
  - the abstract `UUIDv7Model` has `id = models.UUIDField(primary_key=True, default=uuid7, editable=False)`.

  Then make T007 pass.
- [X] T012 Implement `backend/apps/accounts/models.py` and `backend/apps/accounts/admin.py` (data-model "accounts.User"), then run `uv run manage.py makemigrations accounts` to create `backend/apps/accounts/migrations/0001_initial.py`.
  - `User(UUIDv7Model, AbstractBaseUser, PermissionsMixin)` has:
    - `username`: `max_length=150`, `unique=True`, `RegexValidator(r"^[a-z0-9._-]{3,150}$")`;
    - `is_staff`, `is_active`, and `date_joined` with `default=timezone.now`;
    - `USERNAME_FIELD = "username"` and `REQUIRED_FIELDS = []`;
    - a `save()` that lowercases `username`.
  - A `UserManager` provides `create_user(username, password)` and `create_superuser(username, password)`.
  - In `admin.py`, a `UserAdmin` has no email or name fields. Its list shows `username`, `is_staff`, `is_superuser`, `is_active` and `last_login`.

  Then make T008 pass.
- [X] T013 Create the database and cache services (FR-005, FR-037, research R1).
  - `backend/docker/postgres/initdb/01-app-role.sh`, running as the superuser:
    - creates role `wassal` with `LOGIN` and password `$WASSAL_DB_PASSWORD`, and no `SUPERUSER`, `CREATEROLE` or `CREATEDB`;
    - creates database `wassal`, owned by that role;
    - runs `CREATE EXTENSION pg_stat_statements` in `wassal`, then `GRANT pg_read_all_stats TO wassal`;
    - uses `psql -v ON_ERROR_STOP=1` with `:'var'` variables, never SQL built from strings.
  - `backend/docker/compose.yml`, with two services:
    - `postgres`:
      - image `postgres:17.11-trixie`, `env_file: ${DB_ENV_FILE:-../.env}`;
      - command `-c shared_preload_libraries=pg_stat_statements -c shared_buffers=${POSTGRES_SHARED_BUFFERS:-256MB} -c max_connections=50`;
      - volume `pgdata`, with the init script mounted read-only in `/docker-entrypoint-initdb.d/`;
      - health check `pg_isready -U postgres -h 127.0.0.1` (over TCP, so it stays unhealthy while the init
        script runs on the socket-only server), and `mem_limit: ${POSTGRES_MEM_LIMIT:-1024m}`;
    - `valkey`:
      - image `valkey/valkey:8.1.10-trixie`, command `valkey-server --appendonly yes --appendfsync everysec --maxmemory ${VALKEY_MAXMEMORY:-160mb} --maxmemory-policy noeviction`;
      - volume `valkeydata`;
      - health check `valkey-cli ping`, and `mem_limit: ${VALKEY_MEM_LIMIT:-256m}`.

    Both get `restart: unless-stopped` and a shared `x-logging` anchor (`json-file`, `max-size: 10m`, `max-file: "5"`), and neither publishes a port.
  - `backend/docker/compose.dev.yml`, with `name: wassal-dev`, publishing `127.0.0.1:${WASSAL_DEV_PG_PORT:-5432}:5432`
    and `127.0.0.1:${WASSAL_DEV_VALKEY_PORT:-6379}:6379` so pytest can run on the host. The test settings read
    the `TEST_*` keys (only those) from `backend/.env`, so a developer whose port is taken changes it there.
- [X] T014 Add `backend/conftest.py`:
  - an autouse fixture that clears the Django cache between tests;
  - a `no_throttle` fixture that sets `THROTTLE_ADDRESS_RATE = None`. The throttle (T021) reads that
    setting on every request, because DRF copies `DEFAULT_THROTTLE_CLASSES` when the view class is
    defined, so emptying it in a test has no effect.

  Then start `docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait postgres valkey` and make T006–T008 pass. `uv run pytest`, `uv run ruff check . && uv run ruff format --check .` and `uv run mypy .` must all be clean.

**Checkpoint**: settings refuse bad configuration, the staff user exists from migration `0001`, and
tests run against the real database and cache.

---

## Phase 3: User Story 1 - The whole backend runs locally with one command (Priority: P1) 🎯 MVP

**Goal**: One documented command starts the API, admin, worker, scheduler, database and cache. The
health checks pass, and the commands in `CLAUDE.md` run against the real database and cache.

**Independent Test**: On a clean machine that has only Docker, uv and the PostgreSQL client tools,
follow `CLAUDE.md` from a fresh checkout. `/readyz` reports ready, and `uv run pytest` passes
(quickstart "Setup" and local scenarios 1–8).

### Tests for User Story 1 (write first, must fail)

- [X] T015 [P] [US1] Write `backend/apps/common/tests/test_errors.py` (FR-013, contracts/api.md "Error envelope"). Use Django's test `Client` on the API urlconf, plus test-only DRF views in a test urlconf (`override_settings(ROOT_URLCONF=…)`). Assert:
  - `GET /nope` → 404 `{"error": {"code": "not_found", "message": …, "details": {}}}`, with `application/json`;
  - `DELETE /healthz` → 405 `method_not_allowed`, whose `details.allowed` lists the view's methods and includes `"GET"`;
  - `Accept: application/xml` on `/healthz` → 406 `not_acceptable`;
  - a `POST` with `Content-Type: text/plain` to a view that parses its body → 415 `unsupported_media_type`;
  - a body over 524288 bytes to that view → 413 `payload_too_large` with `details.limit_bytes == 524288`;
  - malformed JSON → 400 `validation_error`;
  - with `DEBUG=False`, a view raising `RuntimeError("secret internals")` → 500 `server_error` with `details == {}`. The body contains neither `RuntimeError`, nor `secret internals`, nor a traceback;
  - every `message` equals the fixed string for its code, and `ErrorCode` has exactly the 10 codes in contracts/api.md.
- [X] T016 [P] [US1] Write `backend/apps/common/tests/test_health.py` (FR-010 – FR-012, contracts/api.md "Health endpoints"):
  - `/healthz` → 200 `{"status": "ok", "release": settings.RELEASE}`. The body has exactly those two keys, the response has `Cache-Control: no-store`, and no authentication is needed;
  - `/readyz` with everything up → 200 `{"status": "ready", "checks": {"database": "pass", "cache": "pass", "migrations": "pass"}}`;
  - point the database check, the cache check, or both, at the unroutable address `10.255.255.1`. Each case returns 503 `not_ready` with the matching `fail` values, the whole request takes under 5 s, and the body has no hostname, port or exception text;
  - an unapplied migration (patch the migration plan) → `migrations: fail`. When `database` fails, `migrations` reports `fail` without running;
  - both the API and the admin urlconfs serve both endpoints.
- [X] T017 [P] [US1] Write `backend/apps/common/tests/test_throttles.py` (FR-015, research R4). Override `THROTTLE_ADDRESS_RATE` to `3/min`, then assert:
  - two separate `Client` instances with the same `REMOTE_ADDR` share the limit through the real cache: the 4th request in total gets 429;
  - a different address is not limited;
  - the 429 body is `rate_limited`, with an integer `details.retry_after_s` equal to the `Retry-After` header;
  - with `NUM_PROXIES=1`, the address comes from the last `X-Forwarded-For` entry;
  - with `NUM_PROXIES=1`, a request with no `X-Forwarded-For` (one that didn't come through the edge) is never counted or limited: 10 such requests all get 200, and they use up no address's budget. With `NUM_PROXIES=0` (dev), every request is counted.
- [X] T018 [P] [US1] Write `backend/apps/common/tests/test_heartbeat.py` (FR-006, FR-007, contracts/operations.md "Heartbeat"):
  - `heartbeat` is registered as `common.tasks.heartbeat`, with `bind=True`, `max_retries == 3`, `autoretry_for == (requests.RequestException,)` and `retry_backoff`;
  - with `HC_PING_HEARTBEAT_URL` set, `heartbeat.apply()` makes one request to it with `timeout=10`. With the URL empty, it makes none;
  - a `requests.ConnectionError` is retried;
  - a round trip through the real Valkey broker: with `celery.contrib.testing.worker.start_worker` running in-process, `heartbeat.delay()` is picked up by the worker and makes its ping (patched `requests`) within 10 s (FR-007, constitution XIII);
  - after migrations, exactly one enabled `PeriodicTask` named `heartbeat` exists: task `common.tasks.heartbeat`, every 5 minutes, queue `default`;
  - the task queues in settings are exactly `default`, `purchases`, `content` and `push`, and `CELERY_BEAT_SCHEDULER` is the database scheduler.
- [X] T019 [P] [US1] Write `backend/apps/common/tests/test_dependency_errors.py` (spec edge case "Database or cache unreachable"). A test view that raises `django.db.OperationalError` returns 503 `dependency_unavailable` with `details == {}`. So do views raising `redis.exceptions.ConnectionError` and `redis.exceptions.TimeoutError`. None of the responses includes the exception text.

### Implementation for User Story 1

- [X] T020 [US1] Implement `backend/apps/common/errors.py` (contracts/api.md):
  - `ErrorCode`, a `StrEnum` with the 10 codes, and `MESSAGES`, one fixed string per code;
  - `envelope(code, details=None, status=…)`, returning a `JsonResponse`;
  - `exception_handler(exc, context)` for DRF:
    - entries in the explicit table win;
    - `RequestDataTooBig` → 413 with `limit_bytes`;
    - a throttle → 429 with `retry_after_s` and the `Retry-After` header;
    - any other `APIException` uses its `default_code`;
    - anything else returns `None`, so Django's 500 path runs;
  - `handler404(request, exception)` and `handler500(request)`, both returning the envelope.
- [X] T021 [US1] Implement `backend/apps/common/net.py` and `backend/apps/common/throttles.py` (FR-015, research R4):
  - `client_ip(request)` returns DRF's `BaseThrottle().get_ident(request)`, so the throttle and the lockout agree on the address;
  - `AddressRateThrottle(SimpleRateThrottle)` has `scope = "address"` and is keyed on `client_ip`. Its `get_rate()` returns
    `settings.THROTTLE_ADDRESS_RATE` on every call (DRF would otherwise freeze the rate when the class is defined), and a
    `None` rate allows every request, which the `no_throttle` fixture uses. When `NUM_PROXIES` is 1 or more and the request has no `X-Forwarded-For`, `allow_request` returns true without counting. Only the host can send such a request, because the app ports bind to `127.0.0.1` and Caddy always adds the header (spec edge case "Health endpoints hammered", contracts/api.md).
- [X] T022 [US1] Implement three middlewares in `backend/apps/common/middleware.py`:
  - `DependencyUnavailableMiddleware`: `process_exception` turns `django.db.OperationalError`, `redis.exceptions.ConnectionError` and `redis.exceptions.TimeoutError` into the 503 `dependency_unavailable` envelope, and logs the exception;
  - `NoStoreMiddleware`: sets `Cache-Control: no-store` on every response of the API role;
  - `BodySizeLimitMiddleware` (API role): a `Content-Length` above `DATA_UPLOAD_MAX_MEMORY_SIZE` gets the 413 `payload_too_large` envelope. DRF parses the WSGI stream itself, which skips Django's own size check, so without this the backstop never fires.

  Then make T019 pass.
- [X] T023 [US1] Implement `backend/apps/common/services/health.py` and `backend/apps/common/api/views.py` (contracts/api.md "Health endpoints"):
  - `liveness()` returns `{"status": "ok", "release": settings.RELEASE}`.
  - `readiness()`:
    - runs a cache read in a worker thread while the database `SELECT 1` runs in the request thread, so the 3 s and 2 s bounds overlap and the whole check stays under 5 s;
    - runs `migrations` only after `database` passes. It passes when `MigrationExecutor(connection).migration_plan(targets)` is empty, and a pass is cached per process;
    - logs failure reasons, never puts them in the response.
  - `HealthzView` and `ReadyzView` are DRF `APIView`s with `authentication_classes = []` and `permission_classes = [AllowAny]`, GET only. Each has an `extend_schema` describing 200 and 429, plus 503 for readyz, using a shared `ErrorEnvelope` serializer component.
- [X] T024 [US1] Wire the API conventions into the settings and URLs.
  - In `backend/config/settings/base.py`, set `REST_FRAMEWORK`:
    - `DEFAULT_RENDERER_CLASSES` and `DEFAULT_PARSER_CLASSES`: JSON only;
    - `DEFAULT_AUTHENTICATION_CLASSES = []` and `DEFAULT_PERMISSION_CLASSES = ["rest_framework.permissions.IsAuthenticated"]`, so later endpoints must opt out explicitly;
    - `DEFAULT_THROTTLE_CLASSES = ["apps.common.throttles.AddressRateThrottle"]` and `DEFAULT_THROTTLE_RATES = {"address": THROTTLE_ADDRESS_RATE}`;
    - `NUM_PROXIES`, `EXCEPTION_HANDLER = "apps.common.errors.exception_handler"` and `DEFAULT_SCHEMA_CLASS = "drf_spectacular.openapi.AutoSchema"`.
  - Set `MIDDLEWARE` in this order: `SecurityMiddleware`, `whitenoise.middleware.WhiteNoiseMiddleware`, `SessionMiddleware`, `CommonMiddleware`, `CsrfViewMiddleware`, `AuthenticationMiddleware`, `MessageMiddleware`, `XFrameOptionsMiddleware`, `DependencyUnavailableMiddleware`, plus `NoStoreMiddleware` and `BodySizeLimitMiddleware` for the API role.
  - `backend/config/urls.py`: `healthz`, `readyz`, `path("v1/", include(SimpleRouter().urls))` (no routes yet and no API root view), and a last catch-all `re_path(r"^", errors.not_found)`, so unknown paths get the envelope even under dev's `DEBUG`, with `handler404` and `handler500` from `apps.common.errors`.
  - `backend/config/urls_admin.py`: `admin/` → `admin.site.urls`, plus `healthz` and `readyz`.

  Then make T015, T016 and T017 pass.
- [X] T025 [US1] Implement the background path (FR-006, FR-007, research R11).
  - `backend/config/celery.py`: app `wassal`, `config_from_object("django.conf:settings", namespace="CELERY")` and `autodiscover_tasks()`. Import it in `backend/config/__init__.py`.
  - In `base.py`:
    - `CELERY_BROKER_URL` and `CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True`;
    - `CELERY_TASK_DEFAULT_QUEUE = "default"`, and `CELERY_TASK_QUEUES` for `default`, `purchases`, `content` and `push`, each `Queue(name, Exchange(name), routing_key=name)`. A bare `Queue(name)` shares the default route, so every message would be copied into all four queues and run four times (a test checks the routes are distinct);
    - `CELERY_TASK_IGNORE_RESULT = True`, `CELERY_TIMEZONE = "UTC"` and `CELERY_WORKER_HIJACK_ROOT_LOGGER = False`;
    - `CELERY_BEAT_SCHEDULER = "django_celery_beat.schedulers:DatabaseScheduler"`, and `HC_PING_HEARTBEAT_URL`.
  - `backend/apps/common/services/monitoring.py`: `ping(url, *, kind="success", body=None, timeout=10)`.
    - `kind` is `success`, `fail` or `start`, and `/fail` or `/start` is appended per Healthchecks.io.
    - It POSTs `body` when given, otherwise GETs.
    - It does nothing for an empty URL, and raises `requests.RequestException` on failure.
  - `backend/apps/common/tasks.py`: `@shared_task(name="common.tasks.heartbeat", bind=True, autoretry_for=(requests.RequestException,), retry_backoff=True, max_retries=3)`, calling `monitoring.ping(settings.HC_PING_HEARTBEAT_URL, timeout=10)`.
  - `backend/apps/common/migrations/0001_heartbeat_schedule.py`: a reversible `RunPython` that creates the 5-minute `IntervalSchedule` and the `heartbeat` `PeriodicTask` on queue `default`. It depends on `django_celery_beat`'s latest migration.

  Then make T018 pass.
- [X] T026 [P] [US1] Create `backend/config/wsgi.py` and `backend/config/gunicorn.conf.py`:
  - `bind = "0.0.0.0:8000"` and `worker_class = "gthread"`;
  - `workers` from `GUNICORN_WORKERS` (default 2) and `threads` from `GUNICORN_THREADS` (default 4);
  - `timeout = 30`, `graceful_timeout = 20`, `max_requests = 1000` and `max_requests_jitter = 100`;
  - `accesslog = None`, because the app writes the access line (research R7).
- [X] T027 [US1] Create `backend/docker/Dockerfile` and `backend/.dockerignore` (research R2, R3; FR-024, FR-029).
  - Builder stage `ghcr.io/astral-sh/uv:0.13.1-python3.13-trixie-slim`:
    - with `UV_COMPILE_BYTECODE=1`, `UV_LINK_MODE=copy`, `UV_PYTHON_DOWNLOADS=0` and `UV_PROJECT_ENVIRONMENT=/opt/venv`;
    - runs `uv sync --locked --no-dev --no-install-project` with a cache mount, then copies the source.
  - Runtime stage `python:3.13.16-slim-trixie`:
    - installs `postgresql-client-17` from trixie main and removes the apt lists;
    - adds a non-root user `app` (uid 10001), puts `/opt/venv` on `PATH`, and places the app in `/app`;
    - sets `ARG RELEASE=dev` → `ENV RELEASE=$RELEASE`.
  - Runs `collectstatic --noinput` at build time, passing throwaway, non-secret build values to that `RUN` only: `DJANGO_SETTINGS_MODULE=config.settings.dev`, `DJANGO_DEBUG=false` (so base's manifest storage applies, T010), `WASSAL_READ_DOTENV=0`, a `build-only` `SECRET_KEY` and dummy URLs. The next `RUN` fails the build unless `/app/staticfiles/staticfiles.json` exists.
  - Copies `docker/compose.yml`, `docker/env/` and `docker/postgres/` into `/app/deploy/` (contracts/operations.md, deploy step 3). `compose.yml` mounts `./postgres/initdb`, so without it a fresh server's database would start with no `wassal` role.
  - `.dockerignore` excludes `.env`, `.venv`, `**/__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `htmlcov` and `staticfiles`. The image holds no secret.
- [X] T028 [US1] Add the application services to `backend/docker/compose.yml`, and create the sizing files `backend/docker/env/prod.env` and `backend/docker/env/staging.env` (research R1 "Memory budget", data-model "Environment", FR-005, FR-008).
  - An `x-app` anchor:
    - `image: ghcr.io/ahmedsaied94/wassal-backend:${RELEASE_TAG:-dev}` and `env_file: ${APP_ENV_FILE:-../.env}`;
    - `restart: unless-stopped` and the logging anchor;
    - `depends_on` postgres and valkey with `service_healthy`.
  - `api`:
    - command `gunicorn -c config/gunicorn.conf.py config.wsgi`, `ports: ["127.0.0.1:${API_PORT:-8000}:8000"]`;
    - a health check that fetches `http://127.0.0.1:8000/healthz` with `python -c` and a 3 s timeout;
    - `mem_limit: ${API_MEM_LIMIT:-768m}` and `GUNICORN_WORKERS: ${API_WORKERS:-2}`.
  - `admin`: the same command with `ADMIN_ONLY: "1"`, `GUNICORN_WORKERS: "1"`, `ports: ["127.0.0.1:${ADMIN_PORT:-8001}:8000"]` and `mem_limit: ${ADMIN_MEM_LIMIT:-384m}`.
  - `worker`:
    - command `celery -A config worker -Q default,purchases,content,push --concurrency 2 --without-gossip --without-mingle`;
    - health check `celery -A config inspect ping -d celery@$$HOSTNAME --timeout 5`, and `mem_limit: ${WORKER_MEM_LIMIT:-512m}`.
  - `beat`: command `celery -A config beat --scheduler django_celery_beat.schedulers:DatabaseScheduler`, a health check that PID 1 is alive, and `mem_limit: ${BEAT_MEM_LIMIT:-192m}`.
  - `migrate` (profile `ops`, `restart: "no"`): `sh -c "python manage.py migrate --noinput && python manage.py check --deploy"`.
  - `prod.env`: `API_PORT=8100`, `ADMIN_PORT=8101`, `APP_ENV_FILE=/etc/wassal/prod.env`, `DB_ENV_FILE=/etc/wassal/prod-db.env`, and the prod column of the memory table.
  - `staging.env`: `API_PORT=8200`, `ADMIN_PORT=8201`, the staging files, `API_WORKERS=1`, `POSTGRES_SHARED_BUFFERS=128MB`, `VALKEY_MAXMEMORY=80mb`, and the staging column.

  `/etc/wassal/{staging,prod}.env` never set `RELEASE`, so the value baked into the image is reported.
- [X] T029 [US1] Complete `backend/docker/compose.dev.yml` (quickstart "Setup", data-model dev column).
  - On `api`, `admin`, `worker`, `beat` and `migrate`:
    - `build: {context: .., dockerfile: docker/Dockerfile}` and `image: wassal-backend:dev`;
    - the source bind-mounted at `/app` (the venv is in `/opt/venv`, so the mount doesn't hide it);
    - `environment` overriding `DATABASE_URL`, `CACHE_URL` and `CELERY_BROKER_URL` with the service names `postgres` and `valkey` and the dev passwords (`${WASSAL_DB_PASSWORD:-change-me-db}`).
  - `api` runs gunicorn with `--reload`.
  - `migrate` leaves the `ops` profile (`profiles: !reset []`) and runs `migrate --noinput`. The app services depend on it with `service_completed_successfully`, so `up -d --wait` migrates first and `/readyz` is 200 straight after (the `smoke` job relies on this), and `beat` never starts on an empty schema.
  - An `edge` service under profile `edge`: `caddy:2.11.7` with `backend/docker/edge/Caddyfile.dev`, publishing `127.0.0.1:8443:8443`.
  - Create `backend/docker/edge/Caddyfile.dev`: `https://localhost:8443` with `tls internal`, `reverse_proxy api:8000`, and the same security headers as production.
- [X] T030 [US1] Update `CLAUDE.md` (FR-044):
  - replace "There is no backend yet…" with a "Backend commands" table taken from contracts/ci-checks.md "Commands": install, start, stop or wipe, migrate, lint, type check, tests, the missing-migration check, regenerating the contract, and creating staff or issuing TOTP;
  - the deploy, rollback and restore rows point to `docs/runbooks/`;
  - add `backend/` to the "Project status" list.
- [X] T031 [US1] Validate US1 from a fresh clone: follow quickstart.md "Setup" and walk local scenarios 1–8 (including the emulator call to `http://10.0.2.2:8000/healthz`). Fix any failure, then confirm `uv run pytest` is green (US1 acceptance 1–5, SC-001).

  *Done 2026-10-18. Nothing is committed yet, so the "fresh clone" was a copy of the files git would commit (no `.venv`, `.env` or caches), set up from `.env.example`: 133 tests pass. Scenarios 1–3 and 5–8 pass against the dev stack. Scenario 4 had no emulator; the server side was checked with `Host: 10.0.2.2:8000` → 200. Fixes made on the way: unknown paths now get the envelope under dev's `DEBUG`; an empty required variable counts as missing; the four queues no longer share one route; the dev `migrate` service runs on `up`.*

**Checkpoint**: the whole stack runs locally, and health, errors, throttling and the heartbeat are proven
by tests against the real database and cache.

---

## Phase 4: User Story 2 - Every backend change is checked automatically (Priority: P2)

**Goal**: Every backend pull request runs lint, types, tests with coverage, the migration and contract
checks, the UUIDv7 check, a secret scan and the ARM64 image build. Any failure blocks the merge.

**Independent Test**: one PR that changes an endpoint without regenerating the contract, and one that
commits a credential, are both blocked. A clean PR passes (quickstart "Gates fail when they should").

### Tests for User Story 2 (write first, must fail)

- [X] T032 [P] [US2] Write `backend/apps/common/tests/test_checks.py` (FR-016, research R3):
  - `call_command("check")` reports no `common.E001` for the project;
  - inside `isolate_apps("apps.common")`, a model with an `AutoField`, or with a `UUIDField` whose default is `uuid4`, makes `run_checks()` return `common.E001` naming it;
  - models of `django.*`, `django_otp`, `axes` and `django_celery_beat` are ignored.
- [X] T033 [P] [US2] Write `backend/tests/test_contract.py` (constitution XIII, contracts/api.md "Contract tests"). Load the committed repository-root `contracts/openapi.yaml` with schemathesis 4's pytest integration, and run every operation against pytest-django's `live_server` with the `no_throttle` fixture. Check status codes, response schemas and `Content-Type`.
- [X] T034 [P] [US2] Write `backend/tests/test_openapi_drift.py` (FR-018). The schema generated with drf-spectacular's generator, using the same settings as `manage.py spectacular`, equals the committed `contracts/openapi.yaml`, and contains `/healthz`, `/readyz` and the `ErrorEnvelope` component. It is a local equivalent of the CI `contract` job's diff.

### Implementation for User Story 2

- [X] T035 [US2] Implement `backend/apps/common/checks.py`: a system check, registered in `CommonConfig.ready()` in `backend/apps/common/apps.py`. It reports `Error(id="common.E001")` for every concrete model whose module starts with `apps.` and whose primary key isn't the `UUIDv7Model` id: a `UUIDField` with `default=apps.common.ids.uuid7` and `editable=False`. Then make T032 pass.
- [X] T036 [US2] Set `SPECTACULAR_SETTINGS` in `backend/config/settings/base.py`: `TITLE = "wassal API"`, `VERSION = "1"`, `SERVE_INCLUDE_SCHEMA = False` and `COMPONENT_SPLIT_REQUEST = True`, with the schema built from the API urlconf only. Then generate `contracts/openapi.yaml` with `uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn` and commit it. Make T033 and T034 pass.
- [X] T037 [P] [US2] Create the secret scan (FR-027, research R12).
  - `.gitleaks.toml` at the repository root: `[extend] useDefault = true`, plus an allow-list for values starting with `change-me-`. It is scoped by value, not by file: in gitleaks 8.30.1 a `paths` entry allow-lists the whole file even with `condition = "AND"`, which was checked to hide a real-looking key planted in `.env.example`.
  - `.github/workflows/secrets.yml`, with one job `gitleaks`:
    - on `pull_request` and on `push` to `master`;
    - `ubuntu-24.04`, `actions/checkout@v7` with `fetch-depth: 0`, `permissions: contents: read`, `timeout-minutes: 15`;
    - runs `ghcr.io/gitleaks/gitleaks:v8.30.1` twice:
      - `git` over the PR or push range (`--log-opts` built from the event's base and head, falling back to the whole history on a branch's first push);
      - `dir .`.

      Both runs use `--config .gitleaks.toml --redact --exit-code 1`.
- [X] T038 [US2] Create `.github/workflows/backend.yml` (contracts/ci-checks.md, research R8), following `mobile.yml`'s pattern.
  - **Workflow level:**
    - triggers `pull_request`, `push` to `master`, and `workflow_dispatch` (the `rehearse` input comes in T058);
    - no workflow-level `paths:`;
    - `concurrency: backend-${{ github.ref }}` with `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`;
    - `permissions: contents: read`, `defaults.run.working-directory: backend`, `timeout-minutes: 15` on every job, and env `DJANGO_SETTINGS_MODULE: config.settings.test`.
  - **`changes`** (`ubuntu-24.04`): the same merge-base diff as `mobile.yml`, with the path rule `^(backend/|contracts/|\.github/workflows/backend[^/]*\.yml$)`. It outputs `backend`, forced to `true` for `workflow_dispatch`. Every later job runs only when `backend == 'true'`.
  - **`lint`, `types`, `test`, `contract`:** as in contracts/ci-checks.md, each with `astral-sh/setup-uv@v10.3.0` and `uv sync --locked`. `test` also:
    - has `postgres:17.11-trixie` (`POSTGRES_PASSWORD: postgres`) and `valkey/valkey:8.1.10-trixie` as services with health options;
    - installs `postgresql-client-17` from the PGDG apt repository;
    - sets `TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres`, `TEST_CACHE_URL=redis://localhost:6379/2` and `TEST_BROKER_URL=redis://localhost:6379/3`;
    - runs `uv run pytest --cov --cov-fail-under=80`.
  - **`image`:**
    - matrix `ubuntu-24.04` (amd64) and `ubuntu-24.04-arm` (arm64);
    - `docker/setup-buildx-action@v4` and `docker/build-push-action@v7` with context `backend`, file `backend/docker/Dockerfile` and `build-args: RELEASE=${{ github.sha }}`;
    - on `master` pushes only:
      - log in to GHCR with `docker/login-action@v4` and `GITHUB_TOKEN`;
      - push by digest (`outputs: type=image,name=ghcr.io/ahmedsaied94/wassal-backend,push-by-digest=true,name-canonical=true,push=true`);
      - upload the digest with `actions/upload-artifact@v7`;
    - job permission `packages: write`.
  - **`image-manifest`** (`master` only): download both digests, then `docker buildx imagetools create -t ghcr.io/ahmedsaied94/wassal-backend:sha-${{ github.sha }}` from them.
  - **`smoke`:**
    - copy `.env.example` to `.env`, then `docker compose -f docker/compose.yml -f docker/compose.dev.yml up -d --wait --build`. This fails if any service isn't healthy within 120 s;
    - `curl` `/healthz` and `/readyz` on `127.0.0.1:8000` and `127.0.0.1:8001`;
    - `docker compose … down -v` in an `always()` step.

    The edge assertions come in T049.
  - **`backend`:** `needs` all of the above and runs with `if: always()`. It fails when any needed job's result is `failure` or `cancelled`.
- [ ] T039 [US2] Prove every gate on a scratch branch and PR (quickstart "Gates fail when they should", US2 acceptance 1–7, SC-003), reverting each change after its run:
  - a model in `backend/apps/common/models.py` without `UUIDv7Model` → `test` fails on `common.E001`;
  - a field without a migration → `contract` fails;
  - a changed health response without regenerating `contracts/openapi.yaml` → `contract` fails;
  - deleting tests until coverage drops below 80% → `test` fails;
  - a committed `AKIA…`-style key → `gitleaks` fails;
  - a change to `apps/mobile/` only → `backend` reports success, with its jobs skipped.

  Every run must finish within 15 min. Put the run links in the PR description.
- [ ] T040 [US2] Operator: in the repository settings, make `backend` and `gitleaks` required status checks on `master` alongside the mobile checks, and switch on repository-level push protection (Settings → Advanced Security). See `specs/002-b01-backend-skeleton/contracts/ci-checks.md` and research R12.

*Review of US1 and US2 code (2026-10-18), fixed with tests:*

- the catch-all 404 is CSRF-exempt, so a `POST` to an unknown path gets the envelope, not an HTML 403;
- the throttle fails open when the cache is down, and its no-header exemption covers only `/healthz` and `/readyz`;
- nested serializer errors are flattened to dotted names; Django's `PermissionDenied` maps like DRF's, and 401s keep `WWW-Authenticate`;
- `monitoring.ping` re-raises without the ping URL, which is a secret, so it never reaches Celery's log or Sentry;
- `config.wsgi`, `config.celery` and the image default to `config.settings.prod`, so a missing `DJANGO_SETTINGS_MODULE` can't start a server on dev settings;
- `THROTTLE_ADDRESS_RATE` is validated at startup; `InterfaceError` is a dependency error; readiness queries carry a 1 s statement timeout;
- `.dockerignore` excludes `.env` files at any depth, and the dev containers don't re-read the bind-mounted `.env`;
- the Caddyfiles use `512KiB` (Caddy reads `512KB` as 512,000 bytes).

**Checkpoint**: the backend gates exist on `master`, and none can be skipped by a backend PR.

---

## Phase 5: User Story 3 - The API is live over HTTPS on the production host (Priority: P3)

**Goal**: The host serves the staging and production API over HTTPS with Let's Encrypt. The admin is
on its own hostname, reachable only over WireGuard, staff-only, with TOTP and lockout. Only 80/tcp,
443/tcp and 51820/udp are open to the internet.

**Independent Test**: From outside, both API hostnames answer `/healthz` over HTTPS, while the admin
and SSH can't be reached. From a WireGuard device, the admin asks for a password and a TOTP code
(quickstart production scenarios 1–9).

### Tests for User Story 3 (write first, must fail)

- [X] T041 [P] [US3] Write `backend/apps/accounts/tests/test_admin_auth.py` (FR-022, US3-6) against the admin urlconf:
  - a staff user with the right password and no OTP device can't sign in;
  - with a confirmed TOTP device, sign-in requires a valid current code, and `/admin/` pages open only after it;
  - a non-staff or inactive user is refused, even with a valid code;
  - lockout:
    - 5 failed sign-ins for one username within 15 minutes lock that username for 15 minutes, even with the right password and code;
    - 5 failures from one client address, across different usernames, lock that address the same way;
    - the lock lifts after 15 minutes, and a successful sign-in resets the counter;
  - the admin urlconf has no sign-up or password-reset URL.
- [X] T042 [P] [US3] Write `backend/apps/accounts/tests/test_staff_commands.py` (data-model "Lifecycle"). The password comes from a patched `getpass`.
  - `create_staff <name>` creates an active staff user with no device. It rejects an existing or invalid username, and a password that fails the validators. `--superuser` sets `is_superuser`, and `--deactivate` sets `is_active = false`.
  - `staff_totp <name>` creates one confirmed `TOTPDevice`, and prints an `otpauth://totp/` URI and the base32 key once. Running it again without `--reset` refuses. `--reset` deletes the old device and issues a new one.
- [X] T043 [P] [US3] Write `backend/docker/host/tests/test_wg_peer.py` (FR-023a, data-model "Private-network peer"). Run `backend/docker/host/bin/wg-peer` under pytest, with stub `wg` and `wg-quick` first on `PATH` and `WASSAL_ETC=<tmp>`.
  - `add` validates the name (`^[a-z0-9-]{2,32}$`, unique) and the role (`operator`, `staff`, `deploy-staging` or `deploy-prod`).
  - It assigns the lowest free address in the role's range (`10.66.0.2–9`, `10.66.0.10–99`, `10.66.0.200–209`), and fails when the range is full.
  - It appends a row to `wg-peers.tsv`, calls `wg set wg0 peer <pub> allowed-ips <addr>/32` and `wg-quick save wg0`, and prints a client config once:
    - operator and staff configs contain `DNS = 1.1.1.1`, and deploy configs have no `DNS` line;
    - every config has `AllowedIPs = 10.66.0.1/32`, `PersistentKeepalive = 25` and the server endpoint;
    - the client's private key is left in no file under `WASSAL_ETC`.
  - `remove` calls `wg set wg0 peer <pub> remove` and marks the row removed. The address can then be reused.
  - `list` prints the name, role, address and latest handshake.
- [X] T044 [P] [US3] Write `backend/docker/host/tests/test_firewall_template.py` (FR-023, research R13).
  - Render with `backend/docker/host/provision.sh --render-firewall <oracle-rules> [--finalize]`, against `backend/docker/host/tests/fixtures/oracle-rules.v4`. Until T054 replaces it with the real file, the fixture is Oracle's documented default `rules.v4` for Ubuntu 24.04 platform images.
  - Oracle's `InstanceServices` chain and its rules are unchanged, and the project rules come before the final `REJECT`.
  - the public interface (`ens3` by default; `--public-if` names another, since A1 shapes may use `enp0s6`) allows TCP 80, TCP 443 and UDP 51820, plus TCP 22 only without `--finalize`.
  - `wg0` allows exactly:
    - TCP 22 and 443 from `10.66.0.2-10.66.0.9`;
    - TCP 443 from `10.66.0.10-10.66.0.99`;
    - TCP 22 from `10.66.0.200-10.66.0.209`.

### Implementation for User Story 3

- [X] T045 [US3] Add the admin's second factor and lockout (research R5).
  - In `backend/config/settings/base.py`:
    - add `django_otp`, `django_otp.plugins.otp_totp` and `axes` to `INSTALLED_APPS`;
    - add `django_otp.middleware.OTPMiddleware` right after `AuthenticationMiddleware`, and `axes.middleware.AxesMiddleware` last;
    - set `AUTHENTICATION_BACKENDS = ["axes.backends.AxesStandaloneBackend", "django.contrib.auth.backends.ModelBackend"]`;
    - set the axes options: `AXES_FAILURE_LIMIT = 5`, `AXES_COOLOFF_TIME = timedelta(minutes=15)`, `AXES_LOCKOUT_PARAMETERS = ["username", "ip_address"]`, `AXES_RESET_ON_SUCCESS = True`, `AXES_HANDLER = "axes.handlers.database.AxesDatabaseHandler"` and `AXES_CLIENT_IP_CALLABLE = "apps.common.net.client_ip"`. Check each name against the django-axes 8.3.1 docs.
  - In `backend/config/urls_admin.py`, serve an `OTPAdminSite(name="admin")` at `admin/`, and register `accounts.User` and the `django_celery_beat` models on it.

  Apply the framework migrations, then make T041 pass.

  *As built:*
  - `apps/accounts/admin_config.StaffAdminConfig` replaces `django.contrib.admin` in `INSTALLED_APPS`. Its `default_site` is `StaffAdminSite(OTPAdminSite)`, so every library's `admin.register` lands on the OTP site without being registered again.
  - `StaffAuthenticationForm` uses the user's one confirmed device when the form names none. django-otp 1.7 otherwise requires a device choice.
  - `AXES_USERNAME_CALLABLE` lowercases the username, matching the lowercase usernames, so changing the letter case doesn't escape the per-username lockout.
- [X] T046 [US3] Implement `backend/apps/accounts/management/commands/create_staff.py` and `staff_totp.py` (data-model "Lifecycle", research R5):
  - `create_staff <username> [--superuser] [--deactivate]` reads the password twice with `getpass`, validates it with Django's validators, and never echoes it;
  - `staff_totp <username> [--reset]` creates a confirmed `TOTPDevice` named `default`, and prints its `config_url` and base32 key once.

  Then make T042 pass.
- [X] T047 [US3] Spike, admin-CSP half (plan spike item 3, research R5).
  - Add a second site to `backend/docker/edge/Caddyfile.dev`: `https://localhost:8444` with `tls internal`, `reverse_proxy admin:8000` and the admin CSP from contracts/operations.md. Publish `127.0.0.1:8444:8444` for the `edge` service in `backend/docker/compose.dev.yml`.
  - With `--profile edge`, sign in at `https://localhost:8444/admin/`. With the browser console open, visit the login, OTP, user list, user change and periodic-task pages.
  - Record the result in research.md R5. If a page reports a violation, add that script's hash to `script-src` rather than `'unsafe-inline'`, and use the same CSP in production (T048).

  *Result (2026-10-18):*
  - The check ran in headless Chromium across 20 page states. django-celery-beat's periodic-task form script was the only violation, so its hash is now in `script-src`.
  - `apps/accounts/tests/test_admin_csp.py` keeps the hash list exact.
  - Caddy drops headers before an error route, so both Caddyfiles set them again in `handle_errors` (R5).
- [X] T048 [US3] Create the production edge (contracts/operations.md "Edge", research R6, FR-019 – FR-021).
  - `backend/docker/edge/Caddyfile`:
    - global options: `servers { protocols h1 h2 }` and `skip_install_trust`;
    - snippet `(headers)`: HSTS `max-age=31536000; includeSubDomains`, `nosniff`, `DENY`, `strict-origin-when-cross-origin`, and `-Server`;
    - snippet `(api)`:
      - `request_body { max_size 512KiB }`. Caddy reads `512KB` as 512,000 bytes; `512KiB` is the 524,288 the envelope and Django's backstop use (measured 2026-10-18: 524,288 bytes pass, 524,289 get 413);
      - `reverse_proxy 127.0.0.1:{args[0]} { request_buffers 1MB lb_try_duration 30s lb_try_interval 250ms }`;
      - `handle_errors 413`, responding with the `payload_too_large` envelope and `limit_bytes: 524288`;
      - a JSON access log to `/var/log/caddy/access.log` with `roll_size 50MiB` and `roll_keep_for 336h`;
    - snippet `(admin)`: the admin CSP (T047's result) and `reverse_proxy 127.0.0.1:{args[0]}`;
    - sites:
      - `{$PROD_API_HOST}`: `bind {$PUBLIC_BIND_IP}`, `tls {$PUBLIC_TLS}`, `import api 8100`;
      - `{$STAGING_API_HOST}`: the same with `8200`;
      - `{$PROD_ADMIN_HOST}`: `bind {$ADMIN_BIND_IP}`, `tls internal`, `import admin 8101`;
      - `{$STAGING_ADMIN_HOST}`: the same with `8201`.

      Admin paths on the API sites reach Django, which answers the 404 envelope.

  *As built:*
  - A snippet `(errors)` holds `handle_errors 413` (the envelope) and a catch-all `handle_errors`, and both import `(headers)`.
  - `(headers)` also removes `Via`.
  - `provision.sh` reloads Caddy after `up`, so a changed Caddyfile takes effect.
  - After the security review:
    - the admin API moved to a socket inside the container;
    - the health check is a `127.0.0.1:2020` site, not `:2019/config/`;
    - there are server timeouts and an admin access log.

    See contracts/operations.md "Edge process".
  - `backend/docker/edge/compose.yml`:
    - project `wassal-edge`, image `caddy:2.11.7`, `network_mode: host`, `env_file: /etc/wassal/edge.env`;
    - named volumes `caddy_data:/data` and `caddy_config:/config`, and `/var/log/caddy` bind-mounted;
    - `restart: unless-stopped`, `mem_limit: 256m`, and the health check `wget -q -O /dev/null http://127.0.0.1:2019/config/`.
- [X] T049 [US3] Add the edge assertions to the `smoke` job in `.github/workflows/backend.yml` (contracts/ci-checks.md "Edge smoke assertions"):
  - run `caddy validate` on both Caddyfiles inside the `caddy:2.11.7` image;
  - run the compose stack with `API_PORT=8100` and `ADMIN_PORT=8101`, so the real upstream ports apply, and move T038's `curl` checks to those ports;
  - start the real `Caddyfile` with `--network host` and these values: `PUBLIC_BIND_IP=127.0.0.1`, `ADMIN_BIND_IP=127.0.0.2`, `PUBLIC_TLS=internal`, `PROD_API_HOST=api.127-0-0-1.sslip.io` and `PROD_ADMIN_HOST=admin.127-0-0-2.sslip.io`, plus `staging-` equivalents;
  - assert every row of the table with `curl -k --resolve`.

  *As built:* `backend/docker/edge/smoke.sh` holds the assertions, so they also run locally, and the job calls it. It also checks the security headers on the 413, `Via`/`Server` absent, the API hostname absent on the admin bind, the admin's 308, and the JSON access log. Verified locally against a stack on 8100/8101.
- [X] T050 [P] [US3] Create the host configuration files in `backend/docker/host/` (research R13, contracts/operations.md "Network exposure"):
  - `iptables/rules.v4.tmpl` and `iptables/rules.v6.tmpl`: placeholders where `provision.sh` inserts the project's `INPUT` rules before Oracle's final `REJECT`, keeping the `InstanceServices` chain. The v6 file mirrors the v4 public rules;
  - `sysctl.d/90-wassal.conf`: `net.ipv4.ip_nonlocal_bind = 1`;
  - `sshd_config.d/wassal.conf`: `ListenAddress 10.66.0.1`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no` and `AllowUsers ubuntu deploy`;
  - `wireguard/wg0.conf.example`: `Address = 10.66.0.1/24`, `ListenPort = 51820`, a `PrivateKey` placeholder, and no peers;
  - `systemd/docker.service.d/after-wg.conf`: `After=wg-quick@wg0.service` and `Wants=wg-quick@wg0.service`.
- [X] T051 [US3] Implement `backend/docker/host/bin/wg-peer` in bash with `set -euo pipefail` (contracts/operations.md "Private-network administration"). It provides `add <name> <role>`, `remove <name>` and `list`, keeps the registry in `$WASSAL_ETC/wg-peers.tsv` (default `/etc/wassal`), and reads the server's public key and endpoint from `$WASSAL_ETC/wg-server.env`. Then make T043 pass.
- [X] T052 [US3] Implement `backend/docker/host/provision.sh` (research R13). It is idempotent and runs as root on Ubuntu 24.04 `aarch64`, with `set -euo pipefail`. It refuses to run on any other OS or architecture, except in `--render-firewall` mode.
  - **Packages:** apt update and upgrade; `unattended-upgrades` on for security updates; Docker Engine and the Compose plugin from Docker's apt repository; `wireguard-tools`.
  - **Console password:** if `ubuntu` has no password, prompt once (`passwd ubuntu`). The serial console needs it (R13).
  - **Users and directories:**
    - create `deploy`, with no password and not in group `docker`;
    - install `/etc/sudoers.d/wassal-deploy` (`0440`, checked with `visudo -cf`), allowing exactly `deploy ALL=(root) NOPASSWD: /opt/wassal/bin/deploy --only staging, /opt/wassal/bin/deploy --only prod`, with `Defaults!/opt/wassal/bin/deploy env_keep += "SSH_ORIGINAL_COMMAND"`. The key's forced command is `sudo /opt/wassal/bin/deploy --only <env>` (contracts/environment.md). An `authorized_keys` line that is missing its forced command then gives an unprivileged shell, not the root-equivalent `docker` group;
    - create `/opt/wassal/{bin,edge}`, `/etc/wassal` (`0700`), `/var/lib/wassal/{staging,prod}` and `/var/lib/wassal/host-monitor`, all owned by root.
  - **Install:**
    - `bin/*` to `/opt/wassal/bin/` (`0755`) and `../edge/` to `/opt/wassal/edge/`;
    - the systemd units and timers, the docker drop-in and the sysctl file;
    - then `systemctl daemon-reload` and enable the timers.
  - **WireGuard:**
    - on the first run, generate the server key into `/etc/wireguard/wg0.conf` (from the example, `0600`);
    - write `/etc/wassal/wg-server.env` with `WG_SERVER_PUBLIC_KEY` and `WG_ENDPOINT=<public IP>:51820`, where the public IP comes from a required `--public-ip` argument on that first run;
    - enable `wg-quick@wg0`.
  - **Firewall:**
    - on the first run, save `iptables -S` to `/var/lib/wassal/iptables-before.txt`;
    - render `rules.v4` and `rules.v6` from the templates, then `netfilter-persistent reload` and `systemctl restart docker`;
    - `--render-firewall <oracle-rules> [--finalize]` only prints the rendered rules.
  - **Edge:** if `/etc/wassal/edge.env` exists, start it with `docker compose -p wassal-edge -f /opt/wassal/edge/compose.yml up -d`. Otherwise skip it, and print that the env files must be filled (quickstart step 4) and `provision.sh` re-run. On the first run the file doesn't exist yet, so provisioning finishes without the edge.
  - **`--finalize`**, run once the operator's peer works:
    - install the sshd drop-in, then `systemctl daemon-reload && systemctl restart ssh.socket`. On Ubuntu 24.04, ssh is socket-activated, and the socket generator turns `ListenAddress` into the socket's address;
    - check with `ss -tlnp` that sshd listens only on `10.66.0.1:22`;
    - re-render the firewall without public TCP 22.

  *As built:*
  - The firewall step finds the public interface from the default route, so it isn't always `ens3` (R13 **[verify on host]**).
  - `--finalize` refuses unless an operator peer had a handshake in the last 10 minutes, `sshd -t` passes, and `ss` shows only `10.66.0.1:22`. It then writes `/var/lib/wassal/ssh-finalized`, and every later run keeps public SSH closed.
  - It links `wg-peer` into `/usr/local/sbin`, which is on sudo's `secure_path`.
  - The firewall is applied (netfilter reload plus a Docker restart) only when the rendered rules changed, or with `--finalize`. A re-run to update the edge then doesn't restart production.
  - The live-peer check avoids a pipefail and SIGPIPE false negative when several operator peers are live.
  - `--finalize` installs an `ssh.socket` `FreeBind=yes` drop-in (security review).

  Then make T044 pass.
- [X] T053 [P] [US3] Write the host runbooks (FR-023a, FR-043, quickstart "Production: first-time setup"):
  - `docs/runbooks/provision-host.md`:
    - quickstart steps 1–7 in full: reserve the IP; create the VM in `me-jeddah-1` with Always Free resources only; the capacity retry rule; the serial-console test; `provision.sh --public-ip <ip>`; filling every `/etc/wassal/*.env` from contracts/environment.md; re-running `provision.sh`, which then starts the edge; the first peer; `--finalize`; removing TCP 22 from the security list;
    - the latency baseline (research R1);
    - timing the run for SC-009.
  - `docs/runbooks/private-network.md`:
    - `wg-peer add`, `remove` and `list`, and importing a config;
    - installing the admin CA root on staff devices. It is `/data/caddy/pki/authorities/local/root.crt` in the `caddy_data` volume;
    - the DNS-rebind fallback `hosts` entry (research R14).
  - `docs/runbooks/break-glass.md`: the serial-console path, the boot-volume rescue path, re-keying `wg0`, reopening SSH temporarily, and "Instance stopped by Oracle" (research R1, R13).
  - `docs/runbooks/staff-accounts.md`: `create_staff`, `staff_totp` (with `--reset` for a lost device) and `--deactivate`, run over WireGuard with `docker exec wassal-<env>-admin-1 python manage.py …`.
- [ ] T054 [US3] Operator, before merging: provision the host by following `docs/runbooks/provision-host.md` (quickstart steps 1–7).
  - Replace `backend/docker/host/tests/fixtures/oracle-rules.v4` with the real `/etc/iptables/rules.v4` saved before the first render, and re-run T044.
  - Record `iptables -S` from before and after in research.md R13 (**[verify on host]**).
  - Record the setup duration for SC-009.
- [ ] T055 [US3] Live validation, after the first deploys (T062): walk production scenarios 1–9 and 23 in `specs/002-b01-backend-skeleton/quickstart.md`:
  - HTTPS and HSTS from mobile data, and the 308 redirect;
  - the outside port scan, and the admin unreachable off WireGuard;
  - OTP and lockout over WireGuard;
  - removing a peer;
  - admin and API host separation, and the 413;
  - scenario 23: staging and production share no database, cache, volume, network or env file (US3-5).

  Fix any failure in a follow-up PR.

**Checkpoint**: the edge, firewall, WireGuard, admin 2FA and lockout are built and tested, and the
host is provisioned.

---

## Phase 6: User Story 4 - Releases deploy themselves, and a bad release doesn't take the API down (Priority: P4)

**Goal**: A merge to `master` deploys staging, and a `v*` tag on a green `master` commit deploys
production. Migrations run first. A failed migration or a release that never gets ready leaves the
previous release serving.

**Independent Test**: A merged change shows its release in staging's `/healthz`. The
`rehearse: migrate-fail` run keeps the previous release serving, and its failure email arrives
(quickstart production scenarios 10–15).

### Tests for User Story 4 (write first, must fail)

- [X] T056 [P] [US4] Write `backend/docker/host/tests/test_deploy_script.py` (FR-030 – FR-034, research R10, contracts/operations.md "Deploy interface").
  - **Harness:** run `backend/docker/host/bin/deploy` under pytest with stub `docker`, `curl` and `flock` first on `PATH`. Each stub logs its argv to a file and fails on demand through environment variables. Set `WASSAL_STATE_DIR=<tmp>`, `WASSAL_LOCK_DIR=<tmp>`, and `SSH_ORIGINAL_COMMAND` per case.
  - Assert the exact command sequence and exit code for each case:
    - **Success:**
      - the steps run in order: validate → lock → pull → copy `/app/deploy/` to `deploy/<tag>/` → migrate → restart → verify (`/readyz` 200, and the `/healthz` release, on both ports) → record;
      - `release.previous` gets the old tag and `release` the new one, a JSON summary goes to stdout, and only the two newest `deploy/<tag>/` copies remain.
    - **Bad input** → exit 2 with no `docker` call:
      - the wrong environment for `--only`;
      - a staging tag sent to prod;
      - a tag containing shell metacharacters;
      - extra tokens.
    - **Lock timeout** → exit 3. **Pull failure** → exit 4.
    - **Migrate failure** → exit 5, with no `up` call (US4-4).
    - **Verify failure** → restart with `release.previous`, then exit 6. If that restore also fails → exit 7 (US4-5). On the first deploy, with no previous release, a failed verify exits 6 and leaves the new release running.
    - **Rehearsal:** `rehearse-migrate-fail` and `rehearse-verify-fail` drive those two paths with `--only staging`, and are refused (exit 2) with `--only prod`.
    - **Same tag:** deploying the tag already serving only re-verifies.
    - **Fixed repository:** no input can change the image repository.

### Implementation for User Story 4

- [X] T057 [US4] Implement `backend/docker/host/bin/deploy` in bash with `set -euo pipefail`, following the steps table in contracts/operations.md "Deploy interface", including the release copy in step 3:
  - the state dir is `${WASSAL_STATE_DIR:-/var/lib/wassal}` and the lock dir is `${WASSAL_LOCK_DIR:-/run/lock}`;
  - the image repository is fixed to `ghcr.io/ahmedsaied94/wassal-backend`;
  - every `docker compose` call uses `-p wassal-<env> -f <deploy dir>/compose.yml --env-file <deploy dir>/env/<env>.env`;
  - the verify step polls every 2 s until its 120 s limit.

  Then make T056 pass.

  *As built:*
  - Step 9 prunes the stack copies and images of every tag but the serving and previous ones, so the disk doesn't fill with one image per staging merge.
  - `up` has `--wait-timeout 180`.
  - A rehearsal on the serving tag still runs the failure path.
  - `WASSAL_VERIFY_TIMEOUT` and `WASSAL_VERIFY_INTERVAL` exist for the tests. sudo resets the environment, so a deploy key can't set them.
  - The init-script mount is fixed through `POSTGRES_INITDB_DIR` (contracts/operations.md).
  - Validated against real containers on 2026-10-18 with two local `sha-` images and a `docker` shim that skips only the registry pull. The runs covered the first deploy, an upgrade, both rehearsals, a rollback and a same-tag re-verify. PostgreSQL and Valkey were never restarted.
- [X] T058 [US4] Add deployment to `.github/workflows/backend.yml` (contracts/ci-checks.md).
  - Add the `workflow_dispatch` input `rehearse`: `none` (default), `migrate-fail` or `verify-fail`. When it isn't `none` on `master`, only `deploy-staging` runs, and it sends `sha-${{ github.sha }} rehearse-<value>`.
  - The `deploy-staging` job:
    - `needs: [backend, image-manifest]`, and runs for `master` pushes, or for a dispatch with `rehearse`;
    - `environment: staging`, and `concurrency: {group: deploy-staging, cancel-in-progress: false}`;
    - installs `wireguard-tools`, writes `WG_CONFIG` to `/etc/wireguard/wg0.conf` (`0600`), and runs `sudo wg-quick up wg0`;
    - writes `DEPLOY_SSH_KEY` and `DEPLOY_KNOWN_HOSTS`, then runs `ssh -i <key> -o UserKnownHostsFile=<file> deploy@10.66.0.1 staging sha-${{ github.sha }}`;
    - runs `wg-quick down` in an `always()` step.

  *As built:*
  - A rehearsal sends the newest `master` commit that has an image, found with `imagetools inspect` over the last 50 commits. `master`'s HEAD has no image when its last change didn't touch the backend.
  - The `changes` job outputs `backend=false` for a rehearsal, so the other jobs skip.
  - Plain pushes deploy only when `image-manifest` succeeded.
- [X] T059 [US4] Create `.github/workflows/backend-release.yml` (contracts/ci-checks.md "backend-release.yml"). It runs on `push` of tags matching `v[0-9]+.[0-9]+.[0-9]+`, with `timeout-minutes: 15` on every job.
  - `verify`:
    - `actions/checkout@v7` with `fetch-depth: 0`;
    - `git merge-base --is-ancestor $GITHUB_SHA origin/master`;
    - `docker buildx imagetools inspect ghcr.io/ahmedsaied94/wassal-backend:sha-$GITHUB_SHA`;
    - if either fails, the workflow fails without deploying.
  - `tag`: `imagetools create -t …:${{ github.ref_name }} …:sha-$GITHUB_SHA`, with `packages: write`.
  - `deploy-prod`: `environment: production`, `concurrency: {group: deploy-prod, cancel-in-progress: false}`, and the same WireGuard and SSH steps as staging, sending `prod ${{ github.ref_name }}`.
- [X] T060 [P] [US4] Write `docs/runbooks/deploy-and-rollback.md` (FR-033):
  - how staging and production deploy, and how to read a failed deploy (exit codes 2–7 in contracts/operations.md);
  - rollback: re-run the previous tag's release workflow, or, over WireGuard as `ubuntu`, run `sudo env SSH_ORIGINAL_COMMAND='prod vX.Y.Z' /opt/wassal/bin/deploy --only prod`;
  - the rehearsal inputs;
  - setting up the deploy keys:
    - `ssh-keygen -t ed25519`;
    - the `restrict,command="sudo /opt/wassal/bin/deploy --only <env>"` line in `~deploy/.ssh/authorized_keys`;
    - `wg-peer add deploy-<env> deploy-<env>`;
    - the GitHub Environment secrets from contracts/environment.md "CI secrets";
  - checking that GitHub's failure emails are on;
  - updating the edge by re-running `provision.sh`.
- [ ] T061 [US4] Operator, before merging (`docs/runbooks/deploy-and-rollback.md`):
  - create the GitHub Environments `staging` and `production`. Production's deployment rule allows tags matching `v*` only;
  - add `WG_CONFIG`, `DEPLOY_SSH_KEY` and `DEPLOY_KNOWN_HOSTS` to each (quickstart step 7);
  - add the two deploy peers and keys on the host.
- [ ] T062 [US4] Live validation, after merge, following `specs/002-b01-backend-skeleton/quickstart.md`:
  - the merge deploys staging (quickstart scenario 10). That also proves research R8's SSH round trip;
  - tag `v0.1.0` deploys production (quickstart step 9);
  - then walk scenarios 11–15: the two rehearsals, polling production's `/healthz` throughout to show that staging failures don't touch it (US3-5); a tag on a branch commit refused; rollback within 10 min; downtime ≤ 30 s per deploy;
  - two merges within a minute deploy one after the other (US4-6).

  Record the results in the PR or a follow-up issue.

**Checkpoint**: deploys and rollbacks are automated and rehearsed, and a bad release never takes the
API down.

---

## Phase 7: User Story 5 - The operator knows when something breaks (Priority: P5)

**Goal**: Errors reach Sentry with environment and release and no personal data. Each request leaves
one structured log line. The operator is emailed when the API is down, the heartbeat stops, a queue
backs up, the disk fills, or a certificate is near expiry.

**Independent Test**: A test error in the API and one in a task appear in Sentry with the right tags.
Stopping the production API sends an alert (quickstart production scenarios 16–18).

### Tests for User Story 5 (write first, must fail)

- [X] T063 [P] [US5] Write `backend/apps/common/tests/test_logging.py` (FR-036, contracts/api.md "Access log line"):
  - one request to `/readyz` produces exactly one `wassal.access` JSON line with `ts`, `level`, `logger`, `request_id`, `method`, `route` (`/readyz`), `status`, `duration_ms`, `release` and `env`;
  - a parameterized test route logs its pattern, not the raw path or the query string;
  - no line contains the client address, or any header, cookie or body;
  - an incoming `X-Request-ID` matching `^[A-Za-z0-9-]{8,64}$` is echoed and logged. An invalid one is replaced by a generated UUIDv7. Every response carries `X-Request-ID`.
- [X] T064 [P] [US5] Write `backend/apps/common/tests/test_sentry.py` (FR-024, FR-035, research R7):
  - the scrubber removes `request.headers`, `request.cookies`, `request.data`, `request.env`, `request.query_string` and `user.ip_address`, from both events and transactions;
  - with `SENTRY_DSN` empty, `init_sentry` doesn't call `sentry_sdk.init` (patched). Otherwise it passes `environment`, `release`, `send_default_pii=False`, `include_local_variables=False`, `max_request_body_size="never"` and the configured `traces_sample_rate`;
  - `sentry_test` raises a tagged error, and `sentry_test --task` queues the test task.
- [X] T065 [P] [US5] Write `backend/docker/host/tests/test_host_monitor.py` (FR-038, contracts/operations.md "Host monitor"). Run `backend/docker/host/bin/host-monitor` with stub `df`, `openssl`, `docker` and `curl` on `PATH`, and `WASSAL_STATE_DIR=<tmp>`:
  - all checks pass → one ping to `HC_PING_HOST_MONITOR_URL`;
  - disk at 80% → `/fail` naming `disk`;
  - a certificate with 13 days left → `/fail` naming the hostname;
  - a queue over 100 for 9 minutes passes, and for 10 minutes sends `/fail`. The state file `host-monitor/backlog.json` keeps the first-seen time, and resets when the queue drains;
  - several failures are listed together.

### Implementation for User Story 5

- [X] T066 [US5] Implement request ids and the access log (FR-036, research R4, R7):
  - in `backend/apps/common/middleware.py`:
    - `RequestIdMiddleware`, first in `MIDDLEWARE`, storing the id in a `request_id` contextvar;
    - `AccessLogMiddleware`, second, writing one `wassal.access` line per API-role request, with the resolved route pattern;
  - `backend/apps/common/logging.py`: the python-json-logger formatter, and a filter that adds `request_id`, `release` and `env`;
  - `LOGGING` in `backend/config/settings/base.py`, writing JSON to stdout at `LOG_LEVEL`.

  Then make T063 pass.

  *As built:*
  - The request id is cleared on `request_finished`, not when the middleware returns, because Django logs 4xx/5xx responses after the middleware chain.
  - The formatter rewrites `django.request` lines ("Not Found: <path>") to the route, and never serializes the attached request object, whose repr holds the raw path.
  - A path no pattern matches is logged as `<unmatched>`.
- [X] T067 [US5] Implement error tracking (FR-024, FR-035, research R7):
  - `backend/apps/common/sentry.py`:
    - `init_sentry()`, with the Django, Celery and logging integrations;
    - `scrub()`, used as both `before_send` and `before_send_transaction`;
    - the request id from the contextvar, set as a tag;
  - call `init_sentry()` from `base.py` when `SENTRY_DSN` is set;
  - `backend/apps/common/management/commands/sentry_test.py`, where `--task` sends `common.tasks.sentry_test` to the `default` queue. Add that task to `backend/apps/common/tasks.py`.

  Then make T064 pass.
- [X] T068 [US5] Implement `backend/docker/host/bin/host-monitor` in bash, and `backend/docker/host/systemd/wassal-host-monitor.{service,timer}` (`OnCalendar=*:0/5`, `Persistent=true`, `EnvironmentFile=/etc/wassal/host-monitor.env`). It checks:
  - disk use on `/` and on the Docker data root;
  - each served certificate, with `openssl s_client -connect <bind ip>:443 -servername <host>`. The hostnames and bind IPs come from `/etc/wassal/edge.env`;
  - the four prod queues, with `docker exec wassal-prod-valkey-1 valkey-cli -n 1 LLEN <queue>`.

  Then make T065 pass.

  *As built:*
  - It also runs the backup-storage check (T075, T082).
  - The service has `ConditionPathExists=/etc/wassal/host-monitor.env`, so it is skipped until that file is filled.
  - Certificates are checked with `openssl x509 -checkend`. Exit 1 means a check failed; 2 means the ping or the config failed.
- [X] T069 [P] [US5] Write `docs/runbooks/monitoring-setup.md` (research R11, data-model "Monitoring check"):
  - the Healthchecks.io account and its five checks (`heartbeat-prod`, `heartbeat-staging`, `backup-prod`, `restore-drill-prod`, `host-monitor`), each with its period and grace, and the env file each ping URL goes into;
  - the UptimeRobot monitor on prod `/healthz` (5 min), with a dated copy of its terms;
  - the optional Sentry uptime monitor;
  - the Sentry organization (US region, kept by the owner on 2026-10-19), with one project whose DSN goes into `/etc/wassal/{staging,prod}.env`;
  - GitHub failure emails on;
  - the monthly operating routine from quickstart.md.
- [ ] T070 [US5] Live validation, after the first production deploy:
  - walk scenarios 16–18 in `specs/002-b01-backend-skeleton/quickstart.md`: two Sentry issues tagged with environment and release, with no IP, cookies or headers; the uptime alert within 10 min; the heartbeat alert within 20 min;
  - force a host-monitor failure, for example with a one-off `DISK_ALERT_PERCENT=1` run, and confirm the email arrives (US5-1 – US5-4, SC-007, SC-008).

**Checkpoint**: every alert in FR-038 except backups and the drill exists and is tested.

---

## Phase 8: User Story 6 - Production data is backed up every night and can be restored (Priority: P6)

**Goal**: A nightly, snapshot-consistent backup goes to Backblaze B2, which the host can add to but
not delete from. A monthly drill restores the newest backup into a throwaway database, runs four
checks and leaves nothing behind.

**Independent Test**: After a run, a new backup pair is in B2. The host's key can't delete or list
it. An on-demand drill passes all four checks, records its durations and leaves no container, volume,
network or directory (quickstart production scenarios 19–21).

### Tests for User Story 6 (write first, must fail)

- [X] T071 [P] [US6] Write `backend/apps/common/tests/test_backups.py` (FR-039, FR-039a, data-model "Backup", contracts/operations.md "Backup job"). Use the real test database. B2 is replaced by moto's `mock_aws` only at the boto3 boundary, with both buckets created in the mock.
  - A run writes `prod/YYYY/MM/DD/prod-<YYYYMMDDTHHMMSSZ>.dump` and then `.json` to the daily bucket, the JSON last. On `BACKUP_WEEKLY_WEEKDAY`, the same pair also goes to the weekly bucket. On other days it doesn't.
  - The metadata has `schema_version: 1`, plus:
    - `environment` (`prod`), `created_at`, `release`, `postgres_version` and `duration_s`;
    - `retention_class`, matching the bucket;
    - `dump` as `{key, size_bytes, sha256, format: "custom"}`, where `sha256` and `size_bytes` match the uploaded dump;
    - `tables` as `{"<schema>.<table>": int}`, with exact counts read in the dump's snapshot. To prove it, insert rows from a second connection after the snapshot is exported and before `pg_dump` runs (through a hook or a patch), and assert they appear in neither the counts nor the dump.
  - The dump passes `pg_restore --list`.
  - A failure during the dump upload leaves no metadata object and pings `/fail`. Success pings `HC_PING_BACKUP_URL` with the size and duration.
  - After a success, `last-backup.json` (a tmp path in tests) holds the metadata.
  - The count queries build identifiers with `psycopg.sql.Identifier`.
  - The boto3 client is built with `signature_version="s3v4"`, `request_checksum_calculation="when_required"` and `response_checksum_validation="when_required"`, and with the endpoint and region from configuration.
  - *As built:* the moto setup lives in `backend/apps/common/tests/b2.py`, shared with T072. A test proves the count queries quote a table named `odd "table"; drop`.
- [X] T072 [P] [US6] Write `backend/apps/common/tests/test_restore_drill.py` (FR-040, data-model "Restore drill result" and "Invariant check").
  - `fetch` picks the newest *complete* backup: a newer dump without metadata is skipped. It downloads the dump and the metadata, and fails on a `sha256` mismatch.
  - `check` restores a real dump, made by the backup service, into a fresh database that the test creates and drops. It reports `restore`, `migrations` and `row_counts` as `pass`, `invariants` as `{}`, and `outcome: pass`, with `restore_duration_s` and `total_duration_s`.
  - Each failure mode reports its check as `fail`, `outcome: fail`, and a short `failure` with no secrets or connection strings:
    - a count off by one, with tolerance 0;
    - a missing table, and an extra table;
    - an applied migration the code doesn't know, and a pending migration;
    - `pg_restore` exiting non-zero.
  - An invariant registered to fail appears in `invariants` as `fail`.
  - The result line has exactly `started_at`, `finished_at`, `backup_key`, `backup_created_at`, `release`, `checks`, `restore_duration_s`, `total_duration_s`, `outcome` and `failure`.
  - *As built:* the command tests also cover `fetch` needing the drill key, a failed fetch as a short error, a bad tolerance, and a failed check still printing its line.
- [X] T073 [P] [US6] Write `backend/tests/test_b2_setup.py` (research R9), with a stubbed `requests.Session` that follows the call sequence recorded by T005.
  - The script creates both buckets with `fileLockEnabled: true` and their lifecycle rules: daily hides after 14 days, weekly after 56, and both delete 1 day after hiding.
  - It sets governance default retention to 14 and 56 days.
  - It creates two keys:
    - the backup key: `["writeFiles"]` (plus `listAllBucketNames` only if T005 found it necessary), both bucket ids, and `namePrefix: "prod/"`;
    - the drill key: `["listBuckets", "listFiles", "readFiles"]`, on the same buckets and prefix.
  - It authorizes with each new key. If a key's reported `allowed.capabilities`, `bucketIds` or `namePrefix` differ from that list, the script exits non-zero.
  - `--check` makes no create or update call.
  - The admin key is read with `getpass` and never printed.
  - *As built:* provisional. The fake session follows the native API v4 as documented (`b2_authorize_account`, `b2_create_bucket`, `b2_update_bucket`, `b2_create_key`, `b2_list_buckets`, `b2_list_keys`; `allowed.buckets` for multi-bucket keys). The first live run called v3, which has no `allowed` object and no multi-bucket keys, and stopped at `KeyError: allowed`. T005 must confirm the sequence and the `listAllBucketNames` answer, then adjust both files.
- [X] T074 [P] [US6] Write `backend/docker/host/tests/test_restore_drill_script.py` (FR-040, FR-040a, contracts/operations.md "Restore drill"), with stub `docker`, `df` and `curl`:
  - the steps run in order:
    1. the disk check;
    2. fetch, on the default bridge with `prod-drill.env`;
    3. the internal network, the volume, and the database with `--memory 1g`;
    4. check, on `wassal-drill` only, with no storage key and the drill directory mounted read-only;
    5. append the result line, then ping;
  - low disk pings `/fail` and starts nothing;
  - a failure at any step still removes `wassal-drill-db`, the volume, the network and `/var/lib/wassal/drill/`, then pings `/fail`;
  - a check that prints no result pings `/fail`.
  - *As built:* `WASSAL_DRILL_READY_ATTEMPTS` keeps the never-ready case short. The stub records each `--env-file`'s contents, so the tests prove the check container gets no storage key.
- [X] T075 [P] [US6] Extend `backend/docker/host/tests/test_host_monitor.py` with the backup-storage check. When `size_bytes` × 22 ≥ `BACKUP_STORAGE_ALERT_BYTES`, the monitor sends `/fail` naming `backup-storage`. A missing `last-backup.json` passes, because there is no backup yet.
  - *As built:* the state file moved to `/var/lib/wassal/prod/backup/last-backup.json` (see T080).

### Implementation for User Story 6

- [X] T076 [US6] Implement `backend/apps/common/services/invariants.py`, a registry with:
  - `register(name)`, a decorator for a callable that takes a database connection and returns `(passed: bool, detail: str)`;
  - `registered()`;
  - `run_all(connection)`.

  B01 registers none. B03 registers `economy.wallet_equals_ledger` (data-model "Invariant check").
- [X] T077 [US6] Implement `backend/apps/common/services/backups.py` and `backend/apps/common/management/commands/backup_db.py` (contracts/operations.md "Backup job" steps 1–7, research R9).
  - Only this command reads `B2_S3_ENDPOINT`, `B2_REGION`, `B2_DAILY_BUCKET`, `B2_WEEKLY_BUCKET`, `B2_BACKUP_KEY_ID`, `B2_BACKUP_APP_KEY`, `BACKUP_PREFIX`, `BACKUP_WEEKLY_WEEKDAY` and `HC_PING_BACKUP_URL`, through `config.env`. The API and worker settings never require them.
  - `pg_dump` gets the password through `PGPASSWORD` in its environment, never in argv.
  - *As built:* `backend/apps/common/management/commands/_b2.py` holds the B2 variable rules shared with `restore_drill fetch`. A success ping that fails is logged only; Healthchecks then alerts after its grace.

  Then make T071 pass.
- [X] T078 [US6] Implement `backend/apps/common/services/restore_drill.py` and `backend/apps/common/management/commands/restore_drill.py` (contracts/operations.md "Restore drill" steps 2 and 4), with two subcommands:
  - `fetch <dir>` needs the drill-key variables;
  - `check <dir>` needs only `DATABASE_URL` and `DRILL_ROWCOUNT_TOLERANCE`, and prints the result line as JSON on stdout.
  - *As built:* `pg_restore` also gets `--no-privileges`, since the drill database has no `wassal` role. The migrations check reads `django_migrations` over the drill's psycopg connection and compares it with `MigrationLoader(None)`'s graph, because Django's recorder only works through a registered alias. `check` exits 1 after printing a `fail` line.

  Then make T072 pass.
- [X] T079 [US6] Implement `backend/tools/b2_setup.py` (research R9), run on the operator's machine from `backend/` as `uv run tools/b2_setup.py --daily-bucket <name> --weekly-bucket <name> [--check]`. It follows T005's recorded call sequence and prints the `prod-backup.env` and `prod-drill.env` lines once. Then make T073 pass.
  - *As built:* provisional until T005 (see T073). It also prints the B2 caps reminder; `--check` verifies keys from `b2_list_keys`, since their secrets aren't kept.
- [X] T080 [US6] Wire the nightly backup.
  - Add the `backup` service to `backend/docker/compose.yml`:
    - profile `ops`, `restart: "no"`, command `python manage.py backup_db`, `mem_limit: 1g`;
    - `env_file`: `${APP_ENV_FILE:-../.env}`, plus `${BACKUP_ENV_FILE:-/etc/wassal/prod-backup.env}` with `required: false`;
    - `/var/lib/wassal/prod` mounted at the same path.
  - Create `backend/docker/host/bin/backup <env>`. It reads the serving tag from `/var/lib/wassal/<env>/release` and runs `docker compose -p wassal-<env> -f /var/lib/wassal/<env>/deploy/<tag>/compose.yml --env-file …/env/<env>.env --profile ops run --rm backup`.
  - Create `backend/docker/host/systemd/wassal-backup@.service` (calls `/opt/wassal/bin/backup %i`, `MemoryMax=1G`) and `wassal-backup@.timer` (`OnCalendar=*-*-* 03:00:00 Africa/Cairo`, `Persistent=true`).
  - *As built:* the container mounts `/var/lib/wassal/prod/backup/` (owned by uid 10001, mode 0750) at `/var/lib/wassal/backup`, not the whole `/var/lib/wassal/prod`, which holds stack definitions that root runs. `bin/backup` takes the deploy lock and runs `run --rm --no-deps -T`. `provision.sh` enables template timers as `<name>@prod.timer`. Tests: `backend/docker/host/tests/test_backup_script.py`.
- [X] T081 [US6] Implement `backend/docker/host/bin/restore-drill` in bash, and `backend/docker/host/systemd/wassal-restore-drill@.{service,timer}` (`OnCalendar=*-*-01 05:00:00 Africa/Cairo`, `Persistent=true`, `EnvironmentFile=/etc/wassal/prod-drill.env` for `HC_PING_DRILL_URL`). Follow contracts/operations.md "Restore drill" steps 1–6, using the serving release's image and the PostgreSQL tag from the serving `compose.yml`. The check container gets exactly the throwaway values listed in step 4. Then make T074 pass.
  - *As built:* the fetch container gets the throwaway values too (with an unreachable `DATABASE_URL`), because prod settings won't start without them. Run for real once against local containers, with only the B2 download stubbed: pass in 12 s, nothing left behind.
- [X] T082 [US6] Add the backup-storage check to `backend/docker/host/bin/host-monitor`, reading `/var/lib/wassal/prod/last-backup.json`. Then make T075 pass.
  - *As built:* reads `/var/lib/wassal/prod/backup/last-backup.json` (see T080).
- [X] T083 [P] [US6] Write `docs/runbooks/restore.md` (FR-040, FR-043), and add a "Backblaze B2" section to `docs/runbooks/monitoring-setup.md`.
  - `restore.md`:
    - a real restore into production:
      1. stop the app services;
      2. list versions with the drill key, in case the current versions were hidden or replaced;
      3. download, and verify the `sha256`;
      4. `pg_restore --clean --if-exists --no-owner` into a fresh database;
      5. migrate, restart, and verify;
    - the full rebuild on a new host within the 4 h RTO: provision, restore, then deploy the serving tag;
    - how to read `drill-results.jsonl`.
  - The "Backblaze B2" section covers quickstart step 8: MFA, USD 0 caps, Event Notifications off, the offline admin key, `b2_setup.py`, the endpoint, and the account region for backend §15.
  - *As built:* the restore procedure was run once against a local PostgreSQL 17: `pg_stat_statements` is created by the superuser and left out of the `--role=wassal` restore through a `--use-list` TOC, then `migrate --check` passed. The full rebuild deploys the serving tag before restoring, because the database container comes from that release's stack.
- [ ] T084 [US6] Operator, before merging: set up B2 with `uv run tools/b2_setup.py` (quickstart step 8), fill `/etc/wassal/prod-backup.env` and `/etc/wassal/prod-drill.env`, and record the B2 account region in research.md R9 "Data location".
- [ ] T085 [US6] Live validation, after the first production deploy:
  - walk scenarios 19–21 in `specs/002-b01-backend-skeleton/quickstart.md`: a manual backup run; the backup key refused a version delete and a listing, and a re-upload under an existing name leaving the original version in place (FR-039a); an on-demand drill passing with durations and leaving nothing behind;
  - add the drill's restore duration to T054's setup time, and confirm the sum is within 4 h (SC-009);
  - about 17 days after the first backup, walk scenario 24: the first day's pair is gone from the daily bucket, and `uv run tools/b2_setup.py --daily-bucket <daily> --weekly-bucket <weekly> --check` passes (US6-1). B01 can merge and be ticked before this check; if it fails, fix the lifecycle rules in a follow-up.

**Checkpoint**: backups and the drill are tested, scheduled, and safe from a compromised host.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: The doc updates owed by this PR, the coverage gate, a review pass, and the cross-cutting
live checks.

- [X] T086 [P] Update `docs/architecture-backend.md`, following research R15:
  - §2: the target platform (one Always Free A1 VM, 2 OCPU / 12 GB, no paid fallback, `me-jeddah-1` with a reserved IP, the Egypt latency baseline) and the 100k-DAU note;
  - §4: host-network Caddy, the admin over WireGuard, and hostnames as configuration;
  - §6.2: the 7 new codes from contracts/api.md;
  - §13: the WireGuard-only admin and lockout, and the B2 application keys as secrets;
  - §15: the host and region; the scale path starting from 2/12; Backblaze B2 backups with the account region; the monthly drill; Healthchecks.io, UptimeRobot, the host monitor and Sentry (US region); CI and CD as built; the monthly routine;
  - §22.1: resolved, with a link to research R1.

  §3's glossary doesn't change: no shared identifier changes.
  - *As built:* every section above. The §4 diagram also shows Valkey and B2. The B2 account region stays a T084 placeholder.
- [X] T087 [P] Update `docs/delivery-plan.md` with the hand-overs in research "Handed to later features":
  - B02: the staff-only `accounts.User`, the player-auth choice, per-player throttles, and carrier-grade NAT;
  - B03: register `economy.wallet_equals_ledger`, and add the direct-`Wallet`-write scan;
  - B04: the backup buckets stay separate from content packs;
  - switching to the real domain before the closed test.
  - *As built:* the B04 hand-over is in step 2 and the B02 and B03 ones in step 6. The domain switch is a note under the step list, and covers B09's account-deletion page too.
- [X] T088 [P] Finish `CLAUDE.md` and `README.md`:
  - in `CLAUDE.md`, the deploy, rollback and restore entries point to `docs/runbooks/`, and the deployment-target bullet says Always Free A1 (2 OCPU / 12 GB) in `me-jeddah-1`, with the admin over WireGuard;
  - in `README.md`, the line "Build, lint and test commands arrive with `B01`" points to `CLAUDE.md` instead.
- [X] T089 Run `uv run pytest --cov --cov-fail-under=80` in `backend/`, and add tests until line coverage is ≥ 80% (SC-012). Don't exclude files to get there.
  - *As built:* 453 tests pass against real PostgreSQL 17 and Valkey 8.1, with 95.76% line coverage. The only omissions were set in T001, before any code: migrations, the tests, `config/wsgi.py` and `config/gunicorn.conf.py`. The host-script tests run the real bash scripts with stubbed `docker`, `curl` and `flock`.
- [X] T090 Review the branch with the python-reviewer and security-reviewer agents, and fix every CRITICAL and HIGH finding. The review covers:
  - secrets, and SQL composition;
  - shell quoting in `backend/docker/host/bin/*`;
  - the SSH and WireGuard restrictions;
  - Sentry scrubbing.
  - *As built:* two rounds, with no CRITICAL or HIGH findings. These MEDIUM findings were fixed:
    - `deploy` checks the release's rendered stack against an allowlist before anything starts, and refuses it with exit 4 (contracts/operations.md, Deploy);
    - a `DOCKER-USER` rule keeps containers off the instance metadata service, except DNS;
    - Sentry reduces request and outgoing URLs to their origin and drops the raw-path log params, so a Healthchecks ping URL can't leak;
    - Healthchecks pings don't follow redirects, and the shell scripts keep the ping URL off argv (`curl -K`);
    - every Actions step is pinned to a commit SHA; the image manifest needs every check job; a release needs a passing `gitleaks` check run.

    LOW findings left open, for later features or the operator:
    - the deploy lock sits in world-writable `/run/lock`;
    - the WireGuard peers have no PresharedKey;
    - the systemd units don't set `NoNewPrivileges`;
    - Celery tasks have no time limits;
    - the beat healthcheck is trivial;
    - Valkey's `mem_limit` and `maxmemory` aren't tied together;
    - there's no `handler400` or `handler403`;
    - a deadlock maps to 503 like any `OperationalError`, by design;
    - `b2_setup.py` hard-codes `namePrefix: "prod/"`;
    - the drill trusts the sha256 in the bucket's metadata, mitigated by its content checks;
    - one PutObject caps a dump at 5 GB, though the storage alert fires long before;
    - `mobile.yml`'s actions aren't SHA-pinned;
    - the gitleaks image is pinned by tag, not digest.
- [ ] T091 Live validation of the cross-cutting outcomes, after the first production deploy:
  - quickstart scenario 22: after a reboot, serving within 5 min (SC-010);
  - SC-002's 100 requests on both API hostnames;
  - the first pass of the monthly routine: every service shows USD 0 (SC-013).

  Tick B01 in the `docs/delivery-plan.md` Progress list once T055, T062, T070, T085 (apart from its 17-day expiry check) and this task pass.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T005):**
  - T001–T003 come first.
  - T004 (the CI spike) gates T048, T049 and T058.
  - T005 (the B2 spike, operator) gates T073 and T079.
  - Neither spike blocks Foundational, US1 or US2.
- **Foundational (T006–T014):** depends on T001–T003, and blocks every story.
- **US1 (T015–T031):** depends on Foundational.
- **US2 (T032–T040):**
  - T032 and T035 need only Foundational;
  - T033, T034 and T036 need US1's health endpoints (T023–T024);
  - T038 needs the Dockerfile and compose files (T027–T029);
  - T039 needs T037 and T038.
- **US3 (T041–T055):**
  - the code needs US1, because it uses the admin urlconf and the compose files;
  - T049 needs T038;
  - T054 (operator) needs T050–T053;
  - T055 runs after the first deploys (T062).
- **US4 (T056–T062):**
  - the code needs T052 (the `deploy` user and its sudoers rule, `/var/lib/wassal`) and T038 (images);
  - T061 needs T054;
  - T062 runs after merge.
- **US5 (T063–T070):**
  - the code needs US1;
  - the systemd unit in T068 is installed by T052;
  - T070 runs after the first production deploy.
- **US6 (T071–T085):**
  - the code needs US1;
  - T082 and T075 need T065 and T068;
  - T073 and T079 need T005;
  - T084 needs T079 and T054;
  - T085 runs after the first production deploy and T084.
- **Polish (T086–T091):** T086–T088 can run any time. T089 and T090 run last before merge. T091 runs
  after the first production deploy.

### Merge gate

The PR merges when every code and doc task is done, CI is green, the gates are proven (T039), and
the operator tasks T040, T054, T061 and T084 are complete. Without the provisioned host, the WireGuard
peers and the GitHub Environments, the merge's own `deploy-staging` run would fail.

After the merge, the live validations (T055, T062, T070, T085, T091) run on the real host. Failures
are fixed in follow-up PRs, and B01 counts as done only when they pass (spec edge case "No free
capacity").

### Within each story

- Tests first, and they must fail before the implementation starts.
- Services before views, and views before URLs.
- Host scripts follow their contract tables exactly. Every test drives the real script with stub
  binaries.

### Shared files (never edit in parallel)

These files are each touched by several tasks:

- `backend/pyproject.toml` and `backend/config/settings/base.py`;
- `backend/docker/compose.yml`, `backend/docker/compose.dev.yml` and `backend/docker/edge/Caddyfile.dev`;
- `.github/workflows/backend.yml`;
- `backend/apps/common/middleware.py` and `backend/apps/common/tasks.py`;
- `backend/docker/host/bin/host-monitor` and `backend/docker/host/tests/test_host_monitor.py`;
- `docs/runbooks/monitoring-setup.md` and `CLAUDE.md`.

---

## Parallel Examples

```text
# Setup, after T001:
T002 skeleton · T003 .env.example · T004 CI spike · T005 B2 spike (operator)

# Foundational, all tests together, then two independent building blocks:
T006 settings guards · T007 ids · T008 user model;  then T011 ids/models alongside T009 env.py

# US1, all tests together:
T015 errors · T016 health · T017 throttles · T018 heartbeat · T019 dependency errors

# Across stories, once US1 is done:
US2 (T032–T037) · US3 tests (T041–T044) · US5 tests (T063–T065) · US6 tests (T071–T074)

# Docs that touch no code:
T053 host runbooks · T060 deploy runbook · T069 monitoring runbook · T086–T088 doc updates
```

---

## Implementation Strategy

### MVP first (US1)

1. Setup (T001–T003; start the T004 and T005 spikes), then Foundational.
2. US1: the whole stack runs locally from one command, and the health, error, throttle and heartbeat
   tests pass against the real database and cache.
3. **Stop and validate:** quickstart "Setup" and local scenarios 1–8 (T031).

### Incremental delivery

1. US1, then US2 (CI gates).
2. US3 (edge, admin security, host provisioning), then US4 (deploys).
3. US5 (monitoring) and US6 (backups and drill). Their code can be written in parallel with US3 and
   US4, because it needs only US1.
4. Polish, then merge.
5. The live validations walk quickstart.md's production scenarios in order.

---

## Notes

- **No secrets anywhere in the repository.** Every placeholder starts with `change-me-`, and
  `.gitleaks.toml` allows only those. Real values live only in `/etc/wassal/*.env` and in GitHub
  Environment secrets.
- **SQL:** count and identifier queries use `psycopg.sql.Identifier`, and the init script uses psql
  variables. No string-formatted SQL.
- **Celery tasks** use `bind=True` with retries and a timeout on every outbound call.
- **Generated files:** `contracts/openapi.yaml` is generated and committed. Regenerate it whenever a
  view, serializer or `extend_schema` changes.
- **Owner actions** after the first CI run: make `backend` and `gitleaks` required checks (T040).

---

## Phase 10: Convergence

Two VMs, one per environment (2026-10-19, constitution v1.1.0). Tests come first for every script
change (constitution XIII). Keep the operator's uncommitted runbook edits when rewriting runbooks.

- [X] T092 CRITICAL: give each host one environment in `backend/docker/host/provision.sh` per Constitution locked stack (v1.1.0) and FR-001a (contradicts)
  - Tests first in a new `backend/docker/host/tests/test_provision_identity.py`. Make the identity logic testable without root, e.g. with path overrides like `wg-peer`'s `WASSAL_ETC`.
  - The first run requires `--env staging|prod` with `--public-ip`. It writes `/etc/wassal/host.env` (`0600`: `WASSAL_ENV`, `WG_ADDRESS`, where prod is `10.66.0.1` and staging is `10.67.0.1`). Later runs read it. A different `--env`, or a malformed `host.env`, is refused before anything changes (contracts/operations.md "Host identity").
  - The sudoers rule allows only `deploy --only <WASSAL_ENV>`. Create only that environment's state directory.
  - Enable only this host's timers: prod gets `wassal-backup@prod` and `wassal-host-monitor`; staging gets `wassal-restore-drill@prod` and `wassal-host-monitor`. Disable every other `wassal-*` timer. Install all unit files on both hosts.
  - Warn about leftovers from the one-host design (another environment's state, env files, timers or peers), but never delete them.
- [X] T093 Derive the private-network address from `WG_ADDRESS` in the firewall, WireGuard and sshd per FR-023, FR-023a and contracts/operations.md "Network exposure" (contradicts)
  - Tests first in `test_firewall_template.py`, for both `10.66.0.x` and `10.67.0.x`.
  - `iptables/rules.v4.tmpl`: replace `10.66.0` with `@WG_NET@`. `render_firewall` fills it in, and `--render-firewall` gains `--wg-address` (default `10.66.0.1`).
  - `wireguard/wg0.conf.example`: make the address a placeholder that `wireguard()` fills from `WG_ADDRESS`.
  - `--finalize` renders `sshd_config.d/wassal.conf` with `ListenAddress <WG_ADDRESS>` and checks that sshd listens only there.
  - Update the `10.66.0.1` comments in `sysctl.d/90-wassal.conf`, `systemd/docker.service.d/after-wg.conf` and `systemd/ssh.socket.d/wassal.conf`.
- [X] T094 Make `backend/docker/host/bin/wg-peer` per-host per FR-023a and data-model.md "Private-network peer" (contradicts)
  - Tests first in `test_wg_peer.py`: drop the test where both deploy roles share one range, and add staging-subnet cases.
  - Addresses and `AllowedIPs` come from the host's `WG_ADDRESS`, with the same offsets in its /24.
  - Accept only this host's deploy role (`deploy-<WASSAL_ENV>`).
- [X] T095 Run one environment per edge in `backend/docker/edge/` per FR-001a, contracts/operations.md "Edge" and contracts/ci-checks.md (contradicts)
  - Tests first in a new `backend/docker/host/tests/test_edge_ports.py`: the snippet ports must equal `API_PORT` and `ADMIN_PORT` in `docker/env/<env>.env`.
  - `Caddyfile`: two sites, `{$API_HOST}` and `{$ADMIN_HOST}`, importing the snippets `api-{$WASSAL_ENV}` and `admin-{$WASSAL_ENV}` (prod 8100/8101, staging 8200/8201). An empty or unknown `WASSAL_ENV` must fail to load.
  - `compose.yml`: `env_file` reads `/etc/wassal/host.env`, then `/etc/wassal/edge.env`.
  - `provision.sh edge()` refuses to start when `ADMIN_BIND_IP` ≠ `WG_ADDRESS`.
  - `smoke.sh` sets `WASSAL_ENV=prod`, `API_HOST` and `ADMIN_HOST`. `caddy validate` must pass for prod and staging and fail for an empty value.
- [X] T096 Move the restore drill to the staging host in `backend/docker/host/bin/restore-drill` per FR-040, FR-040a and contracts/operations.md "Restore drill" (contradicts)
  - Tests first in `test_restore_drill_script.py`.
  - Refuse unless `host.env` says `WASSAL_ENV=staging`.
  - Fetch with the staging host's serving image (`/var/lib/wassal/staging/release`).
  - Then read `release` from `/drill/backup.json` and validate it as 40 hex characters. `docker pull` `sha-<release>`.
  - Take the postgres image from that image's own `/app/deploy/compose.yml` (`docker create` and `docker cp`, with the temporary container removed afterwards).
  - Run the check with that image. Record the backup's release as the result's `release`.
- [X] T097 Make `backend/docker/host/bin/host-monitor` per-host per FR-038 and contracts/operations.md "Host monitor" (partial)
  - Tests first in `test_host_monitor.py`.
  - Read `WASSAL_ENV` from `host.env`. Exit 2 if it's missing or unknown.
  - Certificates: `API_HOST` must have more than `CERT_ALERT_DAYS` left. `ADMIN_HOST` is only checked for being valid now (`-checkend 0`), which fixes the 14-day check that can't pass on Caddy's 12-hour internal certificates.
  - Queues come from `wassal-$WASSAL_ENV-valkey-1`. Backup storage is checked on prod only.
  - Update the comment in `systemd/wassal-host-monitor.service`.
- [X] T098 Make `backend/docker/host/bin/deploy` refuse the other environment per FR-034 and contracts/operations.md "Deploy interface" step 1 (partial)
  - Tests first in `test_deploy_script.py`.
  - Read `WASSAL_ENV` from `$WASSAL_ETC/host.env`. A missing `host.env` is an error. Exit 2 when `--only` differs, even when the operator runs it with sudo.
- [X] T099 Make `backend/docker/host/bin/backup` run only on the prod host per FR-039 and contracts/operations.md "Backup job" (partial)
  - Tests first in `test_backup_script.py`. Refuse unless `host.env` says `WASSAL_ENV=prod`.
- [X] T100 Point the staging deploy at the staging host in `.github/workflows/backend.yml` (`deploy@10.67.0.1`) per contracts/ci-checks.md `deploy-staging` and FR-034 (contradicts)
  - `backend-release.yml` keeps `deploy@10.66.0.1`; update its comments to say "the prod host".
- [X] T101 Rewrite the runbooks for two VMs per FR-043, SC-009, research R13 and quickstart.md (partial)
  - `provision-host.md`: one pass per VM, covering the security list, console password, `provision.sh --env <env> --public-ip <ip>`, that VM's `edge.env`, its peer and `--finalize`.
  - `private-network.md`: two WireGuard servers (`10.66` and `10.67`), two tunnels, two CA roots, one deploy peer per host.
  - `deploy-and-rollback.md`: deploy key, peer and known-hosts per host; each GitHub Environment points at its own host; rollback runs on the prod host.
  - `monitoring-setup.md`: 6 Healthchecks.io checks, including `host-monitor-staging`; 1 UptimeRobot monitor; `prod-backup.env` on prod and `prod-drill.env` on staging.
  - `restore.md`: the drill runs on staging; a rebuild is per host.
  - `break-glass.md`: per VM; the rescue volume fits the 53 GB left.
  - `staff-accounts.md`: an admin URL per environment and two CA roots.
  - `README.md`: the first-time setup order for both VMs.
- [X] T102 Update `docs/owner-actions.md` for two VMs per the repo's owner-actions rule and FR-043 (partial)
  - Before/after-merge items per VM, the staging re-provision (T103), the prod provision (T104), the secrets (T105) and checks (T106), the second CA root, and the "Open now" table.
- [ ] T103 Operator: re-provision the staging VM as `staging` per FR-001a and T054 (missing)
  - Copy the updated `backend/docker` to `~/wassal-docker`.
  - Stop `wg-quick@wg0`. Move the `10.66` `/etc/wireguard/wg0.conf` and `/etc/wassal/wg-server.env` aside; there are no peers yet.
  - Run `sudo ./wassal-docker/host/provision.sh --env staging --public-ip 141.147.129.92`.
  - Confirm `host.env`, `wg0` on `10.67.0.1/24`, only staging's timers (`wassal-backup@prod.timer` is now disabled), and a single rule set in `iptables -S INPUT`. Act on any leftover warnings.
  - Record the `iptables -S` "after" in research R13 (closing its **[verify on host]**), then continue `provision-host.md` §4–7 for staging.
- [ ] T104 Operator: provision the prod VM (`193.122.74.125`, private `10.0.0.28`) as `prod` per FR-001a, FR-042 and T054 (missing)
  - Follow `provision-host.md`: security list, console password and serial-console test, `provision.sh --env prod --public-ip 193.122.74.125`, env files, operator peer, `--finalize`.
  - Compare its `/var/lib/wassal/oracle-rules.v4` and `.v6` with the test fixtures (taken from the staging VM), and record any difference in R13.
  - Time the setup for SC-009.
- [ ] T105 Operator: regenerate each GitHub Environment's `WG_CONFIG`, `DEPLOY_SSH_KEY` and `DEPLOY_KNOWN_HOSTS` from its own host per FR-034 and contracts/environment.md "CI secrets" (missing)
  - Staging: `wg-peer add deploy-staging deploy-staging` on the staging VM, with the host key pinned at `10.67.0.1`.
  - Production: the same on the prod VM, at `10.66.0.1`.
- [ ] T106 Operator: create the `host-monitor-staging` check in Healthchecks.io (6 checks in all), fill each host's `host-monitor.env`, and keep UptimeRobot on production only, per FR-038 and research R11 (missing)
- [X] T107 Document that `sha-` images must stay in GHCR for at least 56 days in `docs/runbooks/deploy-and-rollback.md`, per contracts/ci-checks.md's registry rule and FR-040 (missing)
  - The drill pulls the backup's release by that tag. If a registry cleanup is ever added, it must keep them.
- [ ] T108 Run the live validations (T055, T062, T070, T085, T091) on the host named in the "Host" column of quickstart.md's scenario table, per quickstart.md (partial)
