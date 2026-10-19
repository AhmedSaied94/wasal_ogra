# Research: Backend Skeleton (B01)

Phase 0 output. Researched 2026-10-18 against PyPI, Docker Hub, GitHub releases and official vendor
docs. Every Technical Context unknown is resolved below. Backend §22.1, the open question this
feature owns, is closed in R1. Items marked **[verify in spike]** are confirmed by the spike
tasks T004, T005 and T047 (plan, "Spikes come first"). Revised 2026-10-19 for the owner's decision
to run each environment on its own VM (R1).

## R1 Hosts: Oracle Cloud Always Free (resolves backend §22.1)

**Changed 2026-10-19 (owner):** two VMs, one per environment. The one-VM design is below under
Alternatives rejected.

- **Decision:**
  - **Two `VM.Standard.A1.Flex` instances, 1 OCPU and 6 GB each**: one runs production, the other
    staging. Together they are the entire Always Free A1 allowance. The account is never upgraded
    (FR-042b), and there is no paid fallback.
  - Boot volumes: 100 GB for production, 47 GB for staging. That is 147 GB of the 200 GB Always Free
    block storage, and the 53 GB left fits the 47 GB rescue boot volume (R13).
  - OS: Canonical Ubuntu 24.04 aarch64 platform image, on both.
  - **Region: `me-jeddah-1`**, the home region of the owner's existing tenancy (owner, 2026-10-18).
    It can't be changed, and it is also the natural region for the Gulf launch in phase 2.
  - **Reserved public IPs:** the owner confirmed the tenancy allows two (2026-10-19). Each VM has
    its own, production `193.122.74.125` and staging `141.147.129.92`, so FR-042a holds as written.
  - Each VM is in its own VCN (private address: production `10.0.0.28`, staging `10.1.0.216`). It
    runs one environment's Compose project, with its own edge Caddy (R6), WireGuard server (R5) and
    host monitor (R11). Each VM is provisioned, patched, monitored and break-glassed on its own
    (R13).
- **Why two VMs (owner, 2026-10-19):** isolation that separate Compose projects on one host don't
  give.
  - CPU: a staging load or a runaway job can't take production's core.
  - Disk: staging's images, logs and data can't fill production's volume.
  - Host configuration: the firewall, WireGuard, sshd and Docker upgrades are per VM. A mistake
    while setting up or changing staging can't take production down. That happened while
    provisioning the first host: hand-made WireGuard and firewall rules had to be undone (R13).
  - Costs accepted: twice the edge, WireGuard, monitoring and patching; production capped at one
    core; and staging alone may fall under Oracle's idle-reclamation thresholds (below).
- **The allowance was halved in 2026.** Oracle's Always Free page (modified 2026-06-12) says: "the
  first 1,500 OCPU hours and 9,000 GB hours per month … equivalent to 2 OCPUs and 12 GB of memory".
  The 2025 page said 4 OCPUs and 24 GB, as do most blogs and backend §2's assumption. Sizing must use
  2/12 in total, which is 1/6 per VM.

### Memory budget

Each VM has 6 GB. The stack limits are the `mem_limit` values that `docker/env/<env>.env` passes to
`compose.yml` (FR-008). Limits are ceilings, not expected use.

| Service | production VM | staging VM |
| --- | --- | --- |
| `postgres` (`max_connections=50`; `shared_buffers` 256MB prod, 128MB staging) | 1024 MB | 512 MB |
| `valkey` (`noeviction`, AOF `everysec`; `maxmemory` 160mb prod, 80mb staging) | 256 MB | 128 MB |
| `api` (gunicorn `gthread`, 2 workers × 4 threads) | 768 MB | 384 MB (1 worker) |
| `admin` (1 worker × 4 threads) | 384 MB | 256 MB |
| `worker` (`--concurrency 2`) | 512 MB | 384 MB |
| `beat` | 192 MB | 192 MB |
| **Sum of stack limits** | **3,136 MB** | **1,856 MB** |
| Edge Caddy (`edge/compose.yml`) | 256 MB | 256 MB |
| OS, Docker and page cache (estimate) | 1 GB | 1 GB |
| Largest transient job | 1 GB, the backup | 2 GB, the restore drill |
| **Worst case** | **5,440 MB, 89% of 6 GB** | **5,184 MB, 84% of 6 GB** |

- **Production:**
  - The backup container has `mem_limit: 1g` (`compose.yml`). `migrate` has no limit of its own, but
    it never runs beside the backup, because deploy and backup take the same lock (R10). The drill
    no longer runs here (R9).
  - Outside the backup window the VM peaks at about 4.3 GB (72%).
  - **This is tight.** In the nightly backup window about 0.7 GB is left, and the 1 GB for the OS is
    an estimate. It holds because the limits are ceilings: while their sum stays under the VM's
    memory, a process that reaches its limit is stopped by its own cgroup, and the rest of the VM is
    untouched.
- **Staging:**
  - The drill's fetch container (`--memory 1g`) exits before the drill's database starts. The peak
    is that database plus the check runner, 1 GB each (`host/bin/restore-drill`).
  - The drill doesn't take the deploy lock, so a staging deploy during a drill adds `migrate` on
    top. The drill runs at 05:00 Cairo on the 1st, a quiet hour.
  - Outside the drill the VM peaks at about 3.1 GB (51%).
- **CPU:** 1 OCPU per VM, which on Ampere means 1 core. Production can't borrow staging's core, and
  staging can't take production's. One core is enough for B01. The p95 targets in backend §2 and the
  100 rps design point (§18) are load-tested before each phase launch (backend §16). The owner kept
  the §18 target unchanged for one core on 2026-10-19; the first load test decides whether it holds. The scale path
  in §15 (bigger VM, then a separate DB) now starts from 1 OCPU / 6 GB, which §15's update must say.

### Constraints that shape provisioning

| Fact (Oracle docs, checked 2026-10-18) | Consequence |
| --- | --- |
| Home region "is not changeable after your tenancy is provisioned". Always Free compute exists only in the home region. | The region is `me-jeddah-1`, the existing tenancy's home region. |
| "Out of host capacity" is "a temporary lack of Always Free shapes … might take several days". Oracle's advice is another availability domain, but Jeddah has only one. | The retry rule in the spec edge case: retry daily, with nothing else to rotate. US1 and US2 go ahead meanwhile. Both VMs exist (2026-10-19), so the rule now applies to a rebuild. |
| Idle reclamation: over 7 days, CPU p95 < 20% **and** network < 20% **and** memory < 20% (A1). Oracle doesn't define what "reclaim" does. Community evidence from 2023 says idle instances are *stopped* with about a week's notice, and data is kept. | Accepted risk (Clarifications), judged per instance. Coverage: the production uptime alert and each VM's host-monitor ping (R11), and `docs/runbooks/break-glass.md` "Instance stopped by Oracle" (start it, and retry if capacity is short). Production's normal memory footprint is expected above 20% of 6 GB (1.2 GB) but isn't guaranteed. Staging's is smaller, and when nobody uses it, it may fall under all three thresholds (accepted, owner 2026-10-19). Nothing artificial is added to dodge the rule. |
| "Accounts left idle for 30 days or more may be deemed abandoned and become eligible for suspension or termination." | The operator signs in to the OCI console at least monthly. It goes in the monthly routine with checking the drill result (`monitoring-setup.md`). |
| At trial end, non-Always-Free resources are deleted after 30 days. If A1 usage is over 2/12, *all* A1 instances are disabled and then deleted. | Create only Always Free resources from day one. Never size above 2/12 in total, even during the trial: 1/6 + 1/6. Growing one VM means shrinking the other. |
| "Your credit card will not be charged unless you upgrade your account." | SC-013 holds by construction for Oracle. |
| Ephemeral public IPs "remain assigned" when an instance is stopped and are deleted only on terminate. Reserved IPs persist until deleted. The Always Free page lists no reserved-IP allowance, but the owner confirmed the tenancy allows two (2026-10-19). | Provisioning reserves each VM's IP before creating the VM and attaches it, and the rebuild procedure reattaches the same IP (spec edge case). The sslip.io hostnames therefore survive a rebuild. |
| Always Free block storage is 200 GB, boot volumes included. | Boot volumes 100 GB + 47 GB = 147 GB. The 53 GB left fits one 47 GB rescue boot volume, so break-glass rescues one VM at a time (R13). |

- **Alternatives rejected:**
  - Upgrading to pay-as-you-go: forbidden by the USD 0 budget, even though it would stop
    reclamation.
  - One 2-OCPU / 12 GB VM running both environments as separate Compose projects behind one shared
    edge (the design until 2026-10-19). It needs half the edge, WireGuard, monitoring and patching,
    and production could burst onto 2 cores. But both environments share CPU, disk and host
    configuration, so staging load, a runaway job or a mistake in staging's setup can take
    production down ("Why two VMs" above).
  - Splitting environments across the AMD Micro VMs: 1 GB each is too small for PostgreSQL plus
    Django.

### Latency from Egypt

Oracle publishes no latency data, and the region is fixed anyway. Still, measure once and record it
in backend §2 as a baseline for the latency budgets. From two Egyptian ISPs (fixed and mobile), run
`curl -o /dev/null -s -w '%{time_connect}\n' https://<production api host>/healthz` 10 times each
(`provision-host.md`).

### Risks the owner should know

- **Production memory is tight** in the nightly backup window: 89% of 6 GB at worst (Memory budget).
  The free allowance can't grow, so more memory for production has to come from staging's 6 GB
  (resize both, 12 GB in total) or from the paid scale path in §15. Staging's own worst case leaves
  it under 1 GB to give, unless its sizes or the drill's shrink.
- **Staging may be stopped when idle** (constraints above). Its timers are `Persistent=true`, so a
  drill missed while it was stopped runs at the next boot.
- **The staging VM can read production's backups,** because the drill runs there (R9).
- **Twice the host work:** each VM is patched, provisioned, monitored and break-glassed on its own.
  Staff who use both admins run two WireGuard tunnels and install two CA roots (R5).
- **Serial console on A1 is not confirmed** (R13 covers the fallback). Test it on each VM.
- **Capacity:** Jeddah has one availability domain, so a rebuild may take days of retries.
- **Data location:** player data from B02 onward is stored in Saudi Arabia. Egypt's PDPL rules on
  cross-border transfer belong to the legal review in backend §22.9 (B09). Record the hosting
  location there.

## R2 Dependencies and versions (B01 only)

### Runtime and images

| Item | Version | Notes |
| --- | --- | --- |
| Python | 3.13.16 | `.python-version` = `3.13`, `requires-python = "==3.13.*"`. uv 0.13 downloads 3.15 by default, so the pin is required. |
| uv | 0.13.1 | Builder image `ghcr.io/astral-sh/uv:0.13.1-python3.13-trixie-slim` |
| Runtime image | `python:3.13.16-slim-trixie` | Must match the builder's Python path (uv's multistage guidance). Adds `postgresql-client-17` (17.11, trixie main) for `pg_dump`/`pg_restore`. |
| PostgreSQL | `postgres:17.11-trixie` | Multi-arch. The drill uses the same tag. |
| Valkey | `valkey/valkey:8.1.10-trixie` | The 8.1 line: mature, BSD, a drop-in for redis-py. Valkey `9.2` tags currently point at an RC, so they are avoided. |
| Caddy | `caddy:2.11.7` (Alpine 3.23) | Stock image, no plugins (rate limiting stays in Django, R4) |
| gitleaks | `v8.30.1` (`ghcr.io/gitleaks/gitleaks`) | R12 |

### Python packages (pinned in `pyproject.toml`, locked in `uv.lock`)

| Package | Version | Why this one |
| --- | --- | --- |
| Django | 5.2.18 | The LTS the constitution locks. 6.1.2 is the newest but is out of the locked range. |
| djangorestframework | 3.18.3 | Supports Django 5.2–6.1 |
| drf-spectacular | 0.30.0 | Django 5.2 classifier, `--validate --fail-on-warn` |
| celery | 5.6.3 | — |
| django-celery-beat | 2.9.0 | Requires `Django<6.1` (fine) |
| redis | **6.4.0** | `kombu[redis]` 5.6 requires `redis<6.5`, so the newest (8.1) can't be used |
| psycopg[binary] | 3.3.6 | — |
| django-environ | 0.14.0 | — |
| uuid-utils | 1.0.0 | `uuid_utils.compat.uuid7()` returns a stdlib `uuid.UUID` (Python 3.13 has no `uuid7`) |
| django-otp | 1.7.5 | TOTP plus `OTPAdminSite` (R5) |
| django-axes | 8.3.1 | Lockout (R5). Classifiers cover 4.2, 5.2 and 6.0. |
| sentry-sdk | 2.72.0 | — |
| python-json-logger | 4.2.0 | R7 |
| gunicorn | 26.2.0 | `gthread` workers |
| whitenoise | 6.12.0 | Serves the admin's static files from the image with `DEBUG` off (R3). Supports Django 5.2 and Python 3.13. |
| boto3 | 1.43.x | Ops role only (R9) |
| requests | 2.34.2 | The heartbeat ping (R11) |

### Dev and test

| Package | Version | Why this one |
| --- | --- | --- |
| ruff | 0.17.1 | — |
| mypy | **1.19.1** | django-stubs 5.2.9 supports mypy 1.13 – 1.19 |
| django-stubs | **5.2.9** | Full support for Django 5.2. 6.1.x only partly supports 5.2 (django-stubs README compatibility table). |
| djangorestframework-stubs | **3.16.9** | The newest that accepts django-stubs 5.2.x (3.17+ require django-stubs ≥ 6). Stub coverage lags DRF 3.18 slightly. That is acceptable, because B01 uses only long-standing DRF APIs. |
| celery-types | 0.26.0 | — |
| pytest / pytest-django / pytest-cov | 9.1.1 / 4.14.0 / 7.1.0 | — |
| factory-boy | 3.3.3 | — |
| hypothesis | 6.170.x | Used from B03. Installed now so the CI image is stable. |
| schemathesis | 4.31.x | R4 |
| moto[s3] | 5.2.4 | An in-process S3 fake (`mock_aws`) for backup and drill tests at the network boundary only (R9) |

- **Decision:** the pins above, all locked in `uv.lock`. CI uses `uv sync --locked`, so a stale lock
  fails.
- **Alternatives rejected:**
  - Django 6.x (outside the locked stack).
  - django-stubs 6.1 with mypy 2.4: only partial 5.2 support, so false passes are possible.
  - redis-py 8 (breaks kombu's pin).

## R3 Settings and configuration

- **Decision:**
  - Settings modules: `config/settings/{base,dev,test,staging,prod}.py`. `staging` imports `prod`
    and overrides nothing but naming.
  - All values go through one typed reader in `config/env.py` (django-environ underneath), which
    enforces the startup rules in contracts/environment.md (FR-003).
  - The role comes from the process: `ADMIN_ONLY=1` selects `config.urls_admin` (backend §4).
    Worker and beat use the same settings.
  - Proxy headers: `SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")` outside dev.
  - Cookies: `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `SESSION_COOKIE_HTTPONLY`, and
    `CSRF_TRUSTED_ORIGINS = ["https://" + ADMIN_HOST]`.
  - HSTS is set by the edge, not Django, so every hostname gets the same value (R6).
  - `DATA_UPLOAD_MAX_MEMORY_SIZE = 524288` (R6 backstop).
  - Static files: `collectstatic` runs at image build into `/app/staticfiles`, and WhiteNoise's
    middleware serves them with `CompressedManifestStaticFilesStorage`. The API role has no static
    files to serve, and the admin role serves only Django admin's own. Dev (with `DEBUG` on) and test
    use the plain storage. The image build runs `collectstatic` with `DEBUG` off, so the manifest that
    production needs is written, and the build fails if it is missing.
  - Timeouts: `DATABASE_URL` gets `connect_timeout=3`. The cache uses `socket_connect_timeout=2` and
    `socket_timeout=2`, so a dead dependency fails within 5 s (spec edge case).
- **Staff user model (FR-017):**
  - `accounts.User` on `AbstractBaseUser` + `PermissionsMixin` with a UUIDv7 key, and no
    email or name fields (minimal personal data), is `AUTH_USER_MODEL` from `accounts.0001`.
  - Backend §12 models players as a separate `Player`. simplejwt's blacklist tables have a
    *nullable* FK to `AUTH_USER_MODEL`, so B02 can either authenticate `Player` through a custom
    authentication class or extend `User`.
  - Either way, nothing B01 creates has to be rewritten.
- **UUIDv7 enforcement (FR-016):**
  - The abstract `common.models.UUIDv7Model` has `id = UUIDField(primary_key=True, default=uuid7,
    editable=False)`.
  - System check `common.E001` reports any concrete model in a module under `apps.` whose primary
    key isn't that field. Framework apps (`django.*`, `django_otp`, `axes`, `django_celery_beat`)
    are outside `apps.`, so they keep their own key types.
  - A pytest test calls `call_command("check")`, and a negative test registers a bad model and
    expects `E001`.
- **Alternatives rejected:**
  - `AbstractUser`: it brings email and name columns.
  - The default `auth.User`: swapping it later is the classic painful Django migration.
  - A separate `drill` settings module: the drill reuses `prod` with throwaway values (contracts/operations.md).

## R4 API conventions: errors, throttling, request ids, contract tests

- **Error envelope (FR-013):**
  - DRF `EXCEPTION_HANDLER = "apps.common.errors.exception_handler"` maps DRF exceptions to the
    codes in contracts/api.md.
  - `handler404` and `handler500` in `config/urls.py` return the same envelope.
  - The middleware `DependencyUnavailableMiddleware` turns `django.db.OperationalError` and
    `redis.ConnectionError`/`TimeoutError` into `503 dependency_unavailable`.
  - `RequestDataTooBig` becomes `413 payload_too_large`.
  - Messages are fixed strings per code.
  - Backend §6.2 gains `method_not_allowed`, `not_acceptable`, `payload_too_large`,
    `unsupported_media_type`, `server_error`, `not_ready` and `dependency_unavailable`.
- **Throttling (FR-015):**
  - `AddressRateThrottle` (a subclass of DRF `SimpleRateThrottle`) keys on the client address
    from `get_ident()`. It honours `NUM_PROXIES`: `1` behind Caddy, which appends to
    `X-Forwarded-For`.
  - It is the default on every view, at `120/min`, stored in the Valkey-backed Django cache. That
    cache is shared across processes, which is what FR-015 requires.
  - Health checks that didn't come through the edge are exempt. With `NUM_PROXIES` ≥ 1, a request to
    `/healthz` or `/readyz` with no `X-Forwarded-For` isn't counted (any other path is). If the cache
    is unreachable the limit fails open, so a Valkey outage can't take `/healthz` down with it. Only the host can send one, because the app ports bind to
    `127.0.0.1` and Caddy always adds the header. Without this, the container health checks and the
    deploy's verify step would share one address's budget, and a slow start could turn verification
    into `429`s and a needless rollback (spec edge case).
  - Stock Caddy has no rate limiter, so the plugin route is rejected (R6).
  - Carrier-grade NAT puts many Egyptian mobile users behind one address. This default only guards
    unauthenticated endpoints, and B02's per-player limits (backend §6.5) take over for
    authenticated traffic. Recorded for B02.
- **Request ids (FR-036):** `RequestIdMiddleware` accepts a well-formed `X-Request-ID` or generates a
  UUIDv7, stores it in a `contextvar` for the log formatter and Sentry scope, and echoes it.
- **Contract tests:**
  - schemathesis 4 loads the committed `contracts/openapi.yaml` and runs its pytest integration
    against pytest-django's `live_server`, with throttling disabled in the test settings.
  - OpenAPI is generated by `manage.py spectacular --validate --fail-on-warn`, and CI diffs it.
  - Endpoint metadata: `extend_schema` on the health views, with a shared `ErrorEnvelope` component
    and 429/503 responses.
- **Alternatives rejected:**
  - A third-party error-formatting package: the mapping is about 60 lines and must follow §6.2
    exactly.
  - Caddy `caddy-ratelimit`: unofficial, at v0.1.0, and it needs a custom Caddy build.

## R5 Admin security: private network, 2FA, lockout, CSP

- **Private network (Clarifications):**
  - Plain WireGuard (kernel module, `wireguard-tools` from Ubuntu main), one server per VM on UDP
    51820 of its own public IP: `wg0` = `10.66.0.1/24` on production, `10.67.0.1/24` on staging.
    It is silent to packets from unknown keys, which satisfies FR-023.
  - Each VM has its own peers, managed by its own `wg-peer` (contracts/operations.md). The role
    ranges keep the same offsets inside each /24: operator `.2`–`.9`, staff `.10`–`.99`, deploy
    `.200`–`.209`.
  - The subnets differ so an operator laptop can run both tunnels at once without clashing routes.
    A phone runs one at a time.
  - Each VM's edge has its own local CA for its admin site (R6), so staff who use both admins
    install two CA roots.
  - Roles are enforced with host iptables rules by source range (R13, data-model "Private-network
    peer").
  - The owner named WireGuard in the first clarification attempt, and the restarted session left
    the tool to the plan.
- **2FA:** django-otp's `OTPAdminSite` replaces the default admin site in `config/urls_admin.py`. It
  requires a verified device at login.
  - `staff_totp <user>` creates a confirmed `TOTPDevice` and prints its `otpauth://` URI and the
    base32 key once, so the code is set up with the operator present.
  - `--reset` replaces the device.
  - django-otp throttles wrong codes on its own.
- **Lockout (FR-022):** django-axes 8.3.1 with these settings:
  - `AXES_FAILURE_LIMIT = 5` and `AXES_COOLOFF_TIME = timedelta(minutes=15)`;
  - `AXES_LOCKOUT_PARAMETERS = ["username", "ip_address"]` (either one locks);
  - `AXES_RESET_ON_SUCCESS = True`;
  - the database handler;
  - `AXES_CLIENT_IP_CALLABLE = "apps.common.net.client_ip"`, the same logic as the throttle.
  The private-network address identifies the staff device.
- **CSP (FR-019):** set by the edge on the admin hostnames (contracts/operations.md). Django 5.2 has
  no built-in CSP (it arrives in 6.0).
  - **Spike result (2026-10-18, T047):**
    - Setup: headless Chromium behind the dev edge (`https://localhost:8444`), signed in with
      password and TOTP.
    - Pages: login, index (theme toggle), user list (select all), user change (`filter_horizontal`),
      user add, password change, periodic-task list, add and change (date widgets, the related-object
      popup and its response), the interval and crontab lists, the TOTP device list and change, the
      axes lists, and logout.
    - Result: one violation. It is django-celery-beat 2.9.0's inline script on the periodic-task add
      and change forms (`<script id="periodic-task-overrides">`). The script hides the crontab
      translation row and updates the crontab help text. When it is blocked, the form still works,
      but the row shows.
    - Fix: `script-src` now includes its hash, `'sha256-QE3U2xYF7B4J2ro1/9oxiKhaWCGW39gB7ocQ/xlD0bE='`,
      not `'unsafe-inline'`. The script text depends only on the release and on `LANGUAGE_CODE`,
      since there is no `LocaleMiddleware`.
    - After the fix the walk shows no violations, and the row is hidden. The only console error is
      `/favicon.ico` → 404.
  - **Guard:** `apps/accounts/tests/test_admin_csp.py` renders those pages and fails in either case:
    an inline script whose hash is missing from the CSP, or a hash that no page uses. It also fails
    on inline event handlers or `javascript:` URLs, and it checks that `Caddyfile` and
    `Caddyfile.dev` send the same CSP. So an upgrade that changes the script fails CI, not the page.
  - **Edge error responses:** Caddy drops the deferred header operations before it runs an error
    route, so the edge's own 413 and 502 responses lost HSTS and the other headers, and showed
    `Server: Caddy`. Both Caddyfiles now `import headers` inside `handle_errors` (measured on the
    dev edge).
- **Alternatives rejected:**
  - Tailscale: a third-party coordination service and a 3-user free plan, against plain WireGuard
    with no dependency.
  - IP allow-lists: Egyptian home connections have dynamic addresses.
  - django-csp: an extra dependency for a header the edge can set.

## R6 Edge: Caddy layout

- **Decision:** on each VM, one `caddy:2.11.7` container with `network_mode: host` serves that VM's
  environment only: its public API site and its admin site.
  - The API site binds to the VNIC's private IP; the admin site binds to the VM's WireGuard address
    (`10.66.0.1` on production, `10.67.0.1` on staging). Caddy says to bind every site on a port
    explicitly, and both are explicit.
  - `/etc/wassal/edge.env` holds `PUBLIC_BIND_IP`, `ADMIN_BIND_IP` (the VM's WireGuard address),
    `PUBLIC_TLS`, `API_HOST` and `ADMIN_HOST`. These replace the `PROD_…`/`STAGING_…` hostname
    pairs of the one-VM design.
  - `net.ipv4.ip_nonlocal_bind=1` lets it bind the WireGuard address before `wg0` is up at boot.
  - App containers publish only on `127.0.0.1`.
- **Why host networking:**
  - In a bridge network the container can't see which host interface a connection arrived on, so a
    `Host: admin…` request to the public address would reach the admin site.
  - Ports published by Docker are "diverted before" the host's INPUT chain (Docker docs), so host
    firewall rules wouldn't govern them.
  - With host networking, Caddy's sockets are filtered like any host process.
- **Body limit:**
  - `request_body max_size 512KB` returns 413 **only when the body is read**. (Caddy reads `KB` as 1000 bytes, so the Caddyfiles use `512KiB` = 524,288, the value in the envelope and Django's backstop. Measured 2026-10-18 on the dev edge: 524,288 bytes pass, 524,289 get 413.) Bodies stream, and an
    upstream that never reads them never triggers the limit (Caddy #6739).
  - So `reverse_proxy { request_buffers 1MB }` reads up to 1 MB before proxying, and the limit
    always fires.
  - `request_buffers unlimited` is avoided: in 2.11.7 it truncates over-limit bodies and forwards
    them (Caddy #8206, fixed on master, not yet released).
  - `handle_errors 413 { respond <envelope JSON> 413 }`. Caddy sets the JSON content type on its
    own.
  - Django's `DATA_UPLOAD_MAX_MEMORY_SIZE` is the backstop.
  - **Verified 2026-10-18** (task T004, run locally on Linux Docker with `--network host` and
    `caddy:2.11.7`): a 600 KB `POST` to an upstream that never reads the body gets `413` with the
    JSON envelope and `Content-Type: application/json`. A small `POST` passes.
- **Per-site bind (verified in the same run):** a request on `127.0.0.1:443` with the admin hostname,
  or on `127.0.0.2:443` with the API hostname, never reaches the other site. Caddy answers a hostname
  it has no site for on that address with an empty `200`, not a refused connection. The smoke test
  therefore asserts on the response content and the admin CSP header, not on the status. Plain HTTP
  on each bind gets a `308` to HTTPS, so the redirect listeners follow the site's bind too.
- **Restart hold (SC-004):** `lb_try_duration 30s`, `lb_try_interval 250ms`. Connection failures are
  retried for every method. Once connected, only GETs are retried, which is correct for
  non-idempotent writes.
- **TLS:**
  - Public sites use Let's Encrypt via HTTP-01/TLS-ALPN.
  - The admin site uses `tls internal`, so each VM's Caddy has its own local CA. The root is
    `/data/caddy/pki/authorities/local/root.crt` in that VM's volume, `skip_install_trust` is set,
    and leaf certificates last 12 h and renew on their own.
  - HTTP/3 is off (`protocols h1 h2`), so UDP 443 stays closed.
- **Logs:** a JSON access log at `/var/log/caddy/access.log` with `roll_size 50MiB` and
  `roll_keep_for 336h`. Client IPs (`remote_ip`/`client_ip`) are kept at most 14 days (backend
  §14.2). Sensitive headers are already redacted.
- **Alternatives rejected:**
  - Two Caddy containers publishing on different host IPs: twice the config, and still exposed to
    the published-port bypass.
  - nginx: Caddy is in the locked stack.

## R7 Logging and error tracking

- **Decision:**
  - python-json-logger formats stdout as one JSON object per line (contracts/api.md). Gunicorn's
    own access log is off, and `AccessLogMiddleware` writes the single request line. `route` is
    the resolved pattern, so no ids or query strings are logged.
  - Docker's `json-file` driver rotates at 10 MB × 5.
  - Sentry: `send_default_pii=False`, `include_local_variables=False`, `max_request_body_size="never"`.
    A `before_send` and `before_send_transaction` scrubber removes `request.headers`, `cookies`,
    `data`, `env` and `user.ip_address`, and `environment` and `release` are set from settings.
    `traces_sample_rate` comes from `SENTRY_TRACES_SAMPLE_RATE` (default 0.05, bounded at ≤ 0.1).
    The Django, Celery and logging integrations are on.
  - `manage.py sentry_test [--task]` raises a tagged test error for quickstart item 16.
- **Alternatives rejected:**
  - structlog: more than needed for one formatter.
  - Self-hosted Sentry: far beyond the free VM's purpose.

## R8 CI design

- **Decision:** `backend.yml` follows the pattern of `mobile.yml`: a `changes` job, no workflow-level
  `paths:`, and skipped jobs count as passing. It also adds an aggregate `backend` job as the single
  required check (contracts/ci-checks.md). Runner and action pins:
  - Runners: `ubuntu-24.04` and `ubuntu-24.04-arm`, named explicitly. `ubuntu-latest` moves to
    26.04 between 2026-10-19 and 2026-11-19.
  - `actions/checkout@v7` and `actions/upload-artifact@v7`, matching mobile.
  - `astral-sh/setup-uv@v10.3.0`. Since v8 it publishes no major tags, so `@v10` returns 404.
  - `docker/setup-buildx-action@v4`, `docker/build-push-action@v7`, `docker/login-action@v4`.
- **Native multi-arch:**
  - Each architecture builds on its own runner, with no QEMU: arm64 on `ubuntu-24.04-arm`, free for
    public repos (R12).
  - Each build pushes by digest, and `imagetools create` joins them into `sha-<commit>`.
- **Test services:** `postgres:17.11-trixie` and `valkey/valkey:8.1.10-trixie` as job services with
  health options.
- **Deploy jobs:** they run on `ubuntu-24.04` (amd64), where WireGuard on runners is proven.
  - Each environment deploys to its own VM over that VM's tunnel: staging runs
    `ssh deploy@10.67.0.1 staging <tag>`, production runs `ssh deploy@10.66.0.1 prod <tag>`. The
    `staging` and `production` GitHub environments each hold their own `WG_CONFIG`,
    `DEPLOY_SSH_KEY` and `DEPLOY_KNOWN_HOSTS`.
  - `wireguard-tools` is installed from apt, since it isn't preinstalled.
  - The client config has **no** `DNS=` line, which would need `resolvconf`, and its `AllowedIPs`
    is that VM's WireGuard address alone (`10.67.0.1/32` or `10.66.0.1/32`), so the runner's
    default route is untouched.
  - **[verify at first deploy]** `wg-quick up` and an SSH round trip from a hosted runner. T004 ran
    locally, without root, so it couldn't bring up `wg0`. The first staging deploy (T062) proves both.
- **Alternatives rejected:**
  - QEMU cross-builds: slow, about 10× for Python wheels.
  - `workflow_run` chaining for deploys: harder to follow, and the job-level `concurrency` already
    serializes deploys.

## R9 Backups to Backblaze B2 and the restore drill

Sources were checked on 2026-10-18: Backblaze docs, API docs, pricing, terms and blog, and the boto3
changelog. Help-center articles from 2022–2023 count as legacy.

- **Where each job runs (two VMs, 2026-10-19):**
  - The nightly backup runs on the production VM (`wassal-backup@prod.timer`). Staging isn't backed
    up.
  - The monthly drill runs on the **staging VM** (`wassal-restore-drill@prod.timer`). It fetches
    production's newest complete backup from B2 with the read-only drill key, using the staging
    VM's serving image. It restores and checks it with `sha-<release>`, the production release that
    took the backup (read from the backup's metadata). Staging's own image is wrong for the check:
    it usually carries migrations production hasn't applied yet (contracts/operations.md).
  - So `prod-backup.env` (the write key) is only on the production VM, and `prod-drill.env` (the
    read key) only on the staging VM. Neither VM keeps both, and the admin key is on neither. A real
    restore into production puts a temporary copy of the read key on the prod VM (restore.md).
  - A copy of production data is on the staging VM only while the drill runs. The throwaway
    database sits on an internal Docker network that staging's containers can't reach, and the drill
    removes its container, volume, network and directory on exit, pass or fail. No staging
    container, database, cache or volume ever sees the data (FR-040a).
  - Gains: production's VM never carries the drill's 2 GB (R1), and every drill proves a restore
    onto a different machine, as a rebuild would need.
  - Cost: the staging VM, which takes every merge to `master`, can read every production backup.
    From B02 on that is player data, so the staging VM's access rules (WireGuard-only SSH, its own
    operator peers) protect production data too. Accepted by the owner on 2026-10-19.
- **Free allowance:**
  - The first 10 GB of storage is free. Since 2026-05-01, Class A, B and C API calls are free for
    pay-as-you-go accounts. Egress is free up to 3× the average monthly storage.
  - Class D (Event Notifications) is still billed and can't be capped. **Event Notifications stay
    off**, and the buckets stay private.
  - Sign-up needs no card. Accounts that don't pay also have daily transaction caps
    (`transaction_cap_exceeded`). B01 makes a few calls a day.
  - Usage: at most 22 dumps are kept (14 daily, 8 weekly), a few MB each at first. That is orders of
    magnitude inside 10 GB until the database reaches hundreds of MB. Hidden and locked versions
    count as storage too.
- **Caps (SC-013):**
  - "If you do not set up data caps … unlimited charges can accrue." Caps are daily dollar limits,
    off by default. Alerts fire at 75% and 100% of a cap.
  - Decision: set **USD 0 caps** on storage and on Class A, B and C, plus downloads if the console
    offers it. Keep the alert emails on.
  - At a USD 0 cap, uploads past the free 10 GB fail (`cap_exceeded` on the native API; the S3 error
    isn't documented). The backup then pings `/fail`, so the problem shows up as an alert, not a bill.
  - No primary source says what happens to an account without a card at 10 GB. The caps make that
    moot.
  - Neither VM can list the bucket. Instead the backup job records the dump size on the production
    VM, and that VM's host monitor warns when the retained total (size × 22) passes 8 GB, 80% of the
    free storage.
- **Two buckets, Object Lock on at creation (FR-039a):**
  - Default retention is set per bucket, not per prefix. Daily and weekly backups therefore get one
    bucket each: `B2_DAILY_BUCKET` (14 days) and `B2_WEEKLY_BUCKET` (56 days). Bucket names are
    global in B2, so both are configuration.
  - Object Lock is enabled **when the bucket is created**. The docs disagree on whether enabling it
    later protects existing files, and it can never be turned off.
  - **Governance mode**, not compliance:
    - In compliance mode nobody can remove a lock, Backblaze Support included. The only way out is to
      close the account. A compromised production VM could then fill the free 10 GB with junk that
      inherits 56 days of retention, and at a USD 0 cap backups would stop for up to 8 weeks.
    - Governance mode stops every key that lacks `bypassGovernance`. Only the operator's admin key
      has that capability, and that key never goes on either VM. This also matches FR-039a: "only
      the operator's separate credentials can delete backups".
    - Governance can later be switched to compliance, but compliance can never be undone.
    - The web console only sets compliance as a default, so the setup goes through the API.
  - **What a write key can still do:**
    - B2 buckets are always versioned. `writeFiles` also covers `b2_hide_file`, and an upload to an
      existing name adds a newer version.
    - Neither removes a locked version: the original stays stored and listed by version until its
      lock expires. Within retention, a compromised host can hide or shadow backups but not destroy
      them.
    - So the drill checks content (checksum, restore, counts, invariants), not just the download.
      `restore.md` lists versions, in case the current versions were hidden or replaced.
  - B2's S3 PutObject documents no `If-None-Match`, so the design doesn't rely on conditional writes.
    Every key is unique, with a UTC timestamp to the second.
- **Lifecycle rules** (native API, one rule per bucket, prefix `""`):
  - daily bucket: `daysFromUploadingToHiding: 14, daysFromHidingToDeleting: 1`;
  - weekly bucket: `daysFromUploadingToHiding: 56, daysFromHidingToDeleting: 1`.
  - Rules run once a day, so the real lifetime is about 15–17 and 57–59 days. A locked version is not
    deleted ("the deletion does not occur"), and a retry after the lock ends isn't documented. The
    delete attempt therefore comes after the lock has ended: lock days ≤ hide days.
  - Rules are managed through the native API only. Backblaze says not to mix it with the S3
    lifecycle API.
- **Application keys** (created by `b2_create_key` with an explicit capability list):
  - Never use a console "Write Only" key for all buckets. That combination gets `bypassGovernance`,
    `writeBucketRetentions`, `writeFileRetentions` and `writeFileLegalHolds`.
  - **Backup key** (production VM, `prod-backup.env`): `bucketIds` = both buckets, `namePrefix` =
    `prod/`, capabilities `["writeFiles"]`. Add `listAllBucketNames` only if the spike shows boto3
    needs it. It reveals bucket names only. No `listFiles`, `readFiles`, `deleteFiles`, retention,
    bucket or key capabilities.
  - **Drill key** (staging VM, `prod-drill.env`): the same buckets and prefix, `["listBuckets",
    "listFiles", "readFiles"]`.
  - **Admin key** (operator only, kept in the password manager, never on either VM): creates the
    buckets and keys, and can delete with `bypassGovernance`.
  - B2 accounts have no IAM users or bucket policies outside Enterprise, so key capabilities are the
    only control.
- **Setup is scripted:** `backend/tools/b2_setup.py`, run once with `uv run` on the operator's machine
  with the admin key typed in (never stored). It:
  1. creates both buckets with `fileLockEnabled: true` and the lifecycle rule (`b2_create_bucket`);
  2. sets governance default retention, 14 or 56 days (`b2_update_bucket`);
  3. creates the backup and drill keys;
  4. authorizes with each new key and checks that `allowed.capabilities`, `bucketIds` and
     `namePrefix` are exactly as above;
  5. prints the env lines once.

  `--check` repeats steps 2 and 4 read-only against existing buckets and keys, for after any console
  change.
- **boto3:**
  - Endpoint `https://s3.<region>.backblazeb2.com`, copied from the bucket's Endpoint field. The
    region is fixed when the account is created, so it is configuration (`B2_S3_ENDPOINT`,
    `B2_REGION`). Only SigV4 and HTTPS are supported.
  - Backblaze documents nothing about boto3 ≥ 1.36's default CRC32 checksums either way. The client
    uses `Config(signature_version="s3v4", request_checksum_calculation="when_required",
    response_checksum_validation="when_required")`.
  - **[verify in spike]** (task T005), against a scratch bucket created with the native API by a
    throwaway script and deleted afterwards with the admin key. The recorded call sequence then
    drives `b2_setup.py`:
    - one upload and download under the USD 0 caps;
    - the backup key is refused deleting a version, shortening retention and listing;
    - a second upload to the same name keeps the first version;
    - whether `listAllBucketNames` is needed;
    - an upload with a wrong `ContentMD5` is refused (`BadDigest`). The backup sends one with every
      upload, and the tests can't prove B2 checks it, because moto doesn't;
    - the bucket's default encryption (SSE-B2, AES256), set at creation, is reported back by
      `b2_list_buckets`, which `b2_setup.py --check` relies on.
- **Terms:**
  - The ToS requires MFA on the account, so turn it on first.
  - No inactivity clause was found, and usage-based accounts stay active until closed.
  - Business use is allowed. The "commercial purposes" restriction covers the unlimited products,
    not B2.
  - There is no retention guarantee ("as is", liability capped at USD 100). That is acceptable for
    a second copy whose health the monthly drill proves.
- **Data location:** the B2 region was chosen when the owner's account was created. Its choices are
  US East, US West, EU Central and Canada East. From B02 on, the backups hold player data, so record
  the region next to the Jeddah VMs for the PDPL review (backend §22.9, B09).
- **Snapshot-consistent counts:**
  - The backup opens a `REPEATABLE READ` transaction, exports its snapshot, counts rows in it, and
    runs `pg_dump --snapshot=<id>` before committing. The recorded counts are therefore exactly what
    the dump contains.
  - The drill's "row counts within range" check can use tolerance 0, and any difference means
    corruption, not timing.
- **Testing:** service tests use a real PostgreSQL. B2's S3 API is replaced only at the boto3
  boundary, by moto's in-process S3 (`mock_aws`). `b2_setup.py` is tested against a stubbed HTTP
  session. The tests cover:
  - dump → upload → metadata last, with daily and weekly going to their own buckets;
  - an aborted upload never leaves metadata;
  - the drill picks the newest *complete* backup;
  - a tampered sha256 fails;
  - a count mismatch fails;
  - a missing or extra table fails;
  - an unknown applied migration fails;
  - a pending migration fails;
  - the invariant registry passes and fails;
  - `b2_setup.py` refuses a key whose reported capabilities differ from the expected list.
- **Alternatives rejected:**
  - OCI Object Storage: the owner chose a second provider (Clarifications).
  - Cloudflare R2: the owner's first choice, replaced by B2, where the owner already has an account.
  - One bucket with per-file retention for the weekly backups: needs `writeFileRetentions` on the
    host key, which also lets it extend the retention of any file.
  - Compliance mode: irreversible, see above.

## R10 Deploy mechanism

- **Decision:** push-based over WireGuard to a forced-command SSH key, which runs
  `sudo /opt/wassal/bin/deploy` (contracts/operations.md).
  - Each VM has its own `deploy` user, deploy key and deploy WireGuard peer. Its sudoers rule and
    forced command allow only that script with the VM's own environment: `--only staging` on the
    staging VM, `--only prod` on the production VM. `deploy` isn't in the `docker` group.
  - The staging key and peer exist only on the staging VM, so they can't reach production's VM at
    all.
  - **Order:** migrate first, restart second. Expand/contract migrations, which the constitution
    requires, keep the serving release working on the new schema. A failed migration therefore
    never restarts anything (US4-4).
  - **Proof that checks passed:** the `sha-<commit>` image exists only when that commit's `master`
    run passed every job. The production workflow checks that it exists and that the commit is an
    ancestor of `master` (FR-030).
  - **Serialization:** GitHub job concurrency, plus `flock` on the VM, so manual and CI deploys
    can't overlap (FR-032). The nightly backup takes the same lock on the production VM.
  - **Rollback:** a deploy of the previous tag. Migrations are never reversed (FR-033).
  - **Rehearsal:** an argument that only the staging key may send (`rehearse-migrate-fail` or
    `rehearse-verify-fail`). It drives the real failure and restore paths without a broken image
    (quickstart items 11–12).
- **Testing:** `backend/docker/host/tests/test_deploy_script.py` runs the script under pytest, with a
  stub `docker` and `curl` first on `PATH`. It asserts the exact command sequence for success,
  migrate failure, verify failure, restore failure, bad input, the staging-only rehearsal and the
  lock.
- **Alternatives rejected:**
  - A pull-based agent on the host that polls GHCR. It would mean no deploy logs in GitHub, slower
    feedback, and a second scheduler to monitor.
  - Opening SSH to GitHub's IP ranges: thousands of changing ranges, against the WireGuard-only rule.

## R11 Monitoring and alerting services

All of these are free, and their terms allow commercial use (checked 2026-10-18).

| Need (FR-038) | Service | Plan facts |
| --- | --- | --- |
| Heartbeat, backup, drill, host-monitor dead-man's switches | **Healthchecks.io** Hobbyist | 20 checks (B01 uses 6: a heartbeat per environment, the backup, the drill, and a host monitor per VM), email, `/start` and `/fail` pings, cron or period schedules with a time zone. Commercial use explicitly allowed. No card. Accounts with no login for a year are deleted after a 30-day notice, so this goes in the monthly routine. The service is run by one person, so multi-hour outages are possible. This is accepted for the MVP: a monitoring outage causes missed alerts, not app downtime. |
| External uptime of the production API's `/healthz` | **UptimeRobot** Free | 50 monitors (B01 uses 1, production, for SC-008; a staging VM that Oracle stops is noticed by its host monitor's missed ping), 5-min interval, email. Its terms allow "any use, including commercial" **since 2026-05-26**. Before that the free plan was non-commercial only, so a dated copy of the terms is kept in `monitoring-setup.md`. |
| Second uptime opinion (optional) | **Sentry Uptime** | 1 monitor on every plan, 5-min interval. An issue opens after 3 failures, so it is too slow to be the primary for SC-008. |
| Certificate expiry < 14 days | **The host monitor** on each VM (`openssl`, that VM's own API hostname; its admin hostname only for current validity, since Caddy's `tls internal` certificates last 12 hours) → Healthchecks.io | No free external service alerts on expiry, and Let's Encrypt stopped expiry emails on 2025-06-04. If a VM itself is down, its missed ping alerts. |
| Errors and traces | **Sentry** Developer | 1 user, 5k errors and 5M spans a month, 30-day retention, email alerts. Over-quota data is dropped, never billed. **Data region: US**, chosen at org creation and permanent: the owner kept the existing `saied-store-div` organization on 2026-10-19 instead of the EU (Frankfurt) region first planned. The terms forbid personal data without a DPA, and R7's scrubber sends none. |
| Deploy failures | GitHub Actions notification email | Default for the triggering user. The runbook checks the setting is on. |

- **Decision:** the stack above.
- **A host monitor on each VM** (`wassal-host-monitor.timer`, each with its own Healthchecks.io
  check). The checks in `host/bin/host-monitor` split like this:
  - Disk (`/` and the Docker data root): on both VMs. On staging that includes the drill's space.
  - Certificates: each VM checks its own API and admin hostnames (`API_HOST` and `ADMIN_HOST` in its
    `edge.env`), from the addresses its edge binds. The API certificate must have 14 days left; the
    admin one, from Caddy's internal CA, lasts 12 hours, so it is only checked for being valid now.
  - Queue backlog: on both VMs, each for the 4 queues of its own environment.
  - Backup storage: on the production VM only, where the backup writes `last-backup.json`.
- **Alternatives rejected:**
  - Better Stack: its free plan is "for personal projects".
  - Sentry Crons as the dead-man's switch: only 1 on the free plan, and check-ins are stored in the
    US.
  - Self-hosted Uptime Kuma: it would run on a VM it's meant to watch, or watch production from
    staging, the VM Oracle may stop when idle.

## R12 Repository and CI security

- **Decision:**
  - **gitleaks v8.30.1** runs as the official MIT image `ghcr.io/gitleaks/gitleaks:v8.30.1`
    (`gitleaks git` over the PR or push range, plus `gitleaks dir .`). It is not run through
    `gitleaks-action`, which is under a proprietary EULA since v2, and v2 broke when Node 20 was
    removed.
  - **GitHub secret scanning and push protection** are free for this public, personally owned
    repository. Push protection *for users* is on by default. Repository-level push protection is
    off by default, so the runbook switches it on (Settings → Advanced Security) as defence in
    depth.
  - **Runners and registry:** standard hosted runners, including `ubuntu-24.04-arm`, are free and
    unlimited on public repositories. GHCR storage and bandwidth are free for public images, with a
    month's notice before any change. The image holds no secrets (FR-024), so a public image is
    fine.
  - **No scheduled workflows:** GitHub disables them after 60 days without activity, which is why
    every periodic job is a host timer (Complexity Tracking).
- **Alternatives rejected:** `trufflehog`. gitleaks is the smaller, MIT-licensed choice with a
  maintained image.

## R13 Host provisioning

- **Decision:** `backend/docker/host/provision.sh` is idempotent and safe to re-run. It sets up one
  VM for one environment, and runs on each VM separately. On Ubuntu 24.04 aarch64 it does the
  following:
  - the first run takes `--env staging|prod` with `--public-ip`, and records the choice in
    `/etc/wassal/host.env` (`WASSAL_ENV`, `WG_ADDRESS`). Later runs read it, and a different `--env`
    on a later run is refused. The WireGuard address follows the environment: `10.66.0.1` for
    prod, `10.67.0.1` for staging;
  - apt updates, then `unattended-upgrades` for security updates;
  - Docker Engine + Compose from Docker's apt repository;
  - `wireguard-tools`, and `wg0` on the VM's WireGuard address;
  - the firewall (below);
  - sshd: a drop-in that sets `ListenAddress` to the VM's WireGuard address, keys only, no root
    login;
  - the `deploy` user with a sudoers rule for the VM's own environment only (R10), `/opt/wassal`,
    `/etc/wassal` (`0700`) and `/var/lib/wassal`;
  - sysctl `net.ipv4.ip_nonlocal_bind=1`, so Caddy and sshd can bind the WireGuard address before
    `wg0` is up;
  - the systemd units, and the VM's timers: `wassal-backup@prod.timer` and
    `wassal-host-monitor.timer` on production, `wassal-restore-drill@prod.timer` (R9) and
    `wassal-host-monitor.timer` on staging.
  - `--finalize` applies the WireGuard-only SSH rule after the operator's peer on that VM works.
- **Firewall: keep Oracle's iptables framework, don't replace it.**
  - Oracle platform images ship host rules that "allow only SSH". On Ubuntu they live in
    `/etc/iptables/rules.v4` through `netfilter-persistent` and end in a `REJECT`.
  - Oracle warns against UFW ("might cause an instance not to boot"), and its rules include
    `InstanceServices` entries (iSCSI `169.254.0.2:3260`, metadata) that must stay.
  - So `provision.sh` renders `rules.v4` from `host/iptables/rules.v4.tmpl`, and `rules.v6` from
    `rules.v6.tmpl` unless Oracle's `rules.v6` filters nothing (then it stays unchanged). The
    template keeps Oracle's `InstanceServices` chain unchanged and inserts the project's `INPUT`
    rules (contracts/operations.md) **before** the final `REJECT`. It then loads the files with a
    full `iptables-restore`/`ip6tables-restore` (not `netfilter-persistent reload`, see below),
    followed by `systemctl restart docker`. The restore drops Docker's own chains, and the restart
    puts them back.
  - The `wg0` rules take their source ranges from the VM's own /24, with the same offsets on both
    VMs: operator `.2`–`.9` (TCP 22 and 443), staff `.10`–`.99` (TCP 443), deploy `.200`–`.209`
    (TCP 22).
  - **Verified on the host (2026-10-19, T054),** on the staging VM. The first instance was set up by
    hand and then with the one-VM script; the owner rebuilt it from a fresh image the same day and
    provisioned it with `--env staging`. The records below are from the fresh instance.
    - Oracle's own `rules.v4` and `rules.v6`, saved before the first render, are the test fixtures
      `host/tests/fixtures/oracle-rules.v{4,6}`, unchanged. `INPUT` accepts `RELATED,ESTABLISHED`,
      ICMP, `lo` and TCP 22 on every interface, then `REJECT`s. `OUTPUT` sends `169.254.0.0/16` to
      `InstanceServices`, and `FORWARD` is a single `REJECT`.
    - `iptables -S` before the render (`/var/lib/wassal/iptables-before.txt`) was those rules plus
      Docker's chains, since the same run installs Docker first, and Docker had set `FORWARD` to
      `DROP`.
    - `iptables -S` after the render: one `INPUT` set (`RELATED,ESTABLISHED`, ICMP, `lo`, the
      project's rules on `enp0s6` and on `wg0` with staging's `10.67.0.x` ranges, then one
      `REJECT`), `FORWARD` unchanged apart from its policy, the four `wassal-imds` rules in
      `DOCKER-USER`, and `InstanceServices` unchanged. The policy is `ACCEPT` after a live restore
      (Docker sets `DROP` only when it turns forwarding on itself, at boot); both end in Oracle's
      `REJECT`, so nothing more is forwarded.
    - The image's `/etc/default/netfilter-persistent` sets `IPTABLES_RESTORE_NOFLUSH=yes` and
      `IP6TABLES_RESTORE_NOFLUSH=yes`, so `netfilter-persistent reload` appends to the built-in
      chains instead of replacing them. After the first render, the old `INPUT` rules and their
      `REJECT` sat ahead of the project's, so the new rules never matched. Boot is unaffected,
      because it loads into an empty ruleset. A full restore leaves what boot would load.
    - The image doesn't filter IPv6. Its `rules.v6` has `ACCEPT` policies and no rules, and the
      host has no global IPv6 address. So `provision.sh` leaves `rules.v6` unchanged, and stops if
      the host ever has a global IPv6 address while `rules.v6` still has no `REJECT`.
    - The public interface is `enp0s6`, not Oracle's documented `ens3`. `provision.sh` takes it
      from the default route, and `--render-firewall` accepts `--public-if`.
  - **[verify on host]** The production VM (T104): compare its saved Oracle rules with the fixtures
    and record its `iptables -S` before and after, as above.
- **Break-glass access** (spec edge case, the OCI facts in R1), for each VM on its own:
  - The serial console connects through Oracle's console service on port 443, independently of the
    VM's network. But it needs a **local password** (Oracle sets none), and support on A1 isn't
    confirmed.
  - `provision.sh` therefore asks the operator to set a password for the `ubuntu` sudo user on each
    VM, stored in the operator's password manager. The runbook's first step is to **test the serial
    console once** on each VM.
  - Fallback: stop the VM, detach its boot volume, attach it to a temporary Always Free
    `VM.Standard.E2.1.Micro` rescue instance (47 GB boot, which fits the 53 GB left, so one rescue
    at a time), fix `wg0` or sshd, then re-attach and start.
  - `docs/runbooks/break-glass.md` covers both paths, plus "instance stopped by Oracle" (R1).
- **Public IPs:** each VM's reserved public IP (R1) is created before the VM and attached to its
  VNIC. A rebuild reattaches the same IP, so the hostnames don't change.
- **Reboot behaviour (FR-008, SC-010):**
  - Containers use `restart: unless-stopped`, and Docker starts at boot, after `wg-quick@wg0`
    (drop-in `After=`).
  - `Persistent=true` timers catch up on missed runs.
  - No custom stack units are needed: Docker's restart policy is the supervisor.
- **Alternatives rejected:**
  - Ansible or Terraform: another toolchain for two VMs. The script, run once per VM, and the
    runbook are enough to meet the 4 h RTO.
  - cloud-init only: hard to re-run and test.

## R14 Temporary hostnames (sslip.io) and certificates

- **Decision:** each hostname is derived from its own VM's address: the API from the VM's reserved
  public IP, the admin from its WireGuard address.

  | | Production VM | Staging VM |
  | --- | --- | --- |
  | API | `api.193-122-74-125.sslip.io` | `staging-api.141-147-129-92.sslip.io` |
  | Admin | `admin.10-66-0-1.sslip.io` | `staging-admin.10-67-0-1.sslip.io` |

  - Every one of them is configuration (FR-042a): `API_HOST` and `ADMIN_HOST` in that VM's
    `edge.env` and its environment's settings.
- **Facts (checked live 2026-10-18):**
  - Dash and dot forms both resolve, and **private addresses resolve too**: `admin.10-66-0-1.sslip.io`
    → `10.66.0.1`, TTL 3600.
  - sslip.io and nip.io are one service.
  - Rechecked 2026-10-19: all four hostnames above resolve to their VM's address.
- **Rate limits:**
  - sslip.io is **not** on the Public Suffix List; its PR was withdrawn in 2024 under the PSL's rule
    against IP-wildcard domains. For Let's Encrypt, every sslip.io user worldwide therefore shares
    one "registered domain" limit. Let's Encrypt's default is 50 certificates a week, and sslip.io
    says it has an override to 250,000.
  - Initial issuance can still be rate-limited. Caddy retries with backoff. The fallback is the
    same names under `nip.io`, which is a separate bucket.
  - Renewals coordinated through ARI are exempt from all limits, and Caddy's CertMagic uses ARI.
  - The duplicate limit (5 a week for the same names) only matters if a VM's edge loses its `/data`
    volume. It is a named volume, kept across redeploys.
- **Home-router DNS-rebind protection** (Fritz!Box, dnsmasq `--stop-dns-rebind`) can drop
  private-address answers for the admin hostnames. Each VM's WireGuard client configs set
  `DNS = 1.1.1.1`, which bypasses the router. The fallback is a `hosts` entry
  (`private-network.md`).
- **Certificate lifetime:** Let's Encrypt moves to 64-day certificates on 2027-02-10. Caddy renews at
  a third of the lifetime remaining. The 14-day alert threshold still means "renewal has been
  failing for about a week".
- **The real domain** (`docs/delivery-plan.md` step 1) removes the shared-limit risk before the
  closed test.
- **Alternatives rejected:**
  - Let's Encrypt IP-address certificates: they last 6 days only, and mobile clients would pin an
    IP.
  - Self-signed public certificates: the mobile app could only trust them through a custom CA,
    which constitution security forbids in spirit.

## R15 Docs to update in this PR

| Doc | Change |
| --- | --- |
| backend §2 | Target platform: two Always Free A1 VMs, one per environment, **1 OCPU / 6 GB each** (together the 2026 allowance), no paid fallback, region `me-jeddah-1` with a reserved public IP each, and the Egypt latency baseline (R1). Scale/Scope: note that the 100k-DAU design point needs the §15 scale path. |
| backend §4 | The edge runs host-network Caddy, one per VM. Admin is over WireGuard, one network per VM. Hostnames are configuration (sslip.io until a domain). `ADMIN_ONLY` unchanged. |
| backend §6.2 | The 7 new error codes (R4) |
| backend §13 | Admin: + WireGuard-only, lockout. Secrets: + B2 application keys (write key on the production VM, read key on the staging VM). |
| backend §15 | Hosts, shapes and region (`me-jeddah-1`), one VM per environment. The scale path now starts from 1 OCPU / 6 GB. Object storage: backups → Backblaze B2 (two buckets, governance Object Lock, lifecycle, write-only key on the production VM, USD 0 caps) and its account region. Backups: on the production VM, + monthly automated drill on the staging VM. Observability: Healthchecks.io, UptimeRobot, a host monitor per VM (certificate expiry; backup storage on production), Sentry (US region). CI and CD as built. The monthly operating routine. |
| backend §22.1 | Resolved, with a link to R1 |
| `CLAUDE.md` | The backend commands table, replacing "There is no backend yet". Deployment target: two Always Free A1 VMs (1 OCPU / 6 GB each, one per environment), WireGuard per VM. |
| `docs/delivery-plan.md` | Hand-overs to B02 and B03 (below) |
| `docs/runbooks/`, `docs/owner-actions.md` | Every host step per VM: provisioning (`--env`), private network (two tunnels, two CA roots), break-glass, monitoring (a host monitor per VM, the uptime monitor on production), and which VM runs the backup and which the drill. |

## Handed to later features

- **B02:**
  - `accounts.User` is staff-only. Decide how `Player` authenticates with simplejwt (R3).
  - Per-player throttles replace the per-address default for authenticated traffic. Mind
    carrier-grade NAT (R4).
- **B03:** register the `economy.wallet_equals_ledger` invariant with the drill registry
  (data-model, "Invariant check"), and add the direct-`Wallet`-write scan to CI.
- **B04:** content packs and their CDN (backend §22.3) are separate from the B2 backup bucket. Don't
  reuse the backup keys.
- **Before the first closed test:** register the real domain and switch hostnames (FR-042a, the
  `docs/delivery-plan.md` step 1 note).
