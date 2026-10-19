# Feature Specification: Backend Skeleton (B01)

**Feature Branch**: `002-b01-backend-skeleton`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "B01 Backend skeleton (short name: b01-backend-skeleton)". Scope, sources and
"done when" are taken from `docs/delivery-plan.md` step 1: project skeleton with settings per environment,
the container stack, the edge proxy, CI/CD, error tracking and health checks. Resolve backend §22.1 (OCI
free-tier capacity, or the paid fallback). Sources: docs/architecture-backend.md §2, §4, §5, §15. Done
when: the API answers `/healthz` behind the edge proxy on the ARM64 stack, CI is green, and the real
build, lint and test commands are added to `CLAUDE.md`.

## Clarifications

### Session 2026-10-18

- Q: Does B01 end with live staging and production environments on the real host, or only with a
  deployable stack verified on ARM64 in CI? → A: Live staging and production.
  - The owner sets up the host during B01, which settles backend §22.1 (free tier only; see the
    budget answer below). Since 2026-10-19 there are two hosts, one per environment (Session
    2026-10-19).
  - Deploys, HTTPS, backups and alerts are proven on the real hosts before B02 stores any player
    data.
- Q: Is a domain already owned for the API and admin hostnames? → A: No. Use a temporary hostname for
  now.
  - The hostnames come from a free wildcard DNS service that maps names to the host's IP address
    (sslip.io style), and they get real, publicly trusted HTTPS certificates.
  - The project switches to a real domain before the first closed test. Hostnames are configuration
    (FR-042a), so the switch changes configuration and DNS only, not code.
  - The plan's research picks the service and checks its certificate-issuance limits.
- Q: Who on the internet should be able to reach the admin tool and the server's remote login? → A:
  Nobody. Both are reachable only over a private network.
  - The admin (staging and production) and remote login are reachable only over a private network the
    operator runs (WireGuard or Tailscale style; the plan picks the tool). The internet sees only the
    API on HTTP and HTTPS. Since 2026-10-19 each host runs its own private network (FR-023a).
  - The admin still requires a staff account, a second factor and the sign-in lockout (FR-022).
  - The operator adds each staff device to the network and removes it when access ends. Content
    authors join the network too.
  - The provider's web console is the break-glass path, and the deploy path from CI must work without
    opening remote login to the internet (FR-034).
- Q: What is the most we may spend per month on hosting and operations for the MVP? → A: USD 0. Free
  tiers only.
  - The host is an Oracle Cloud Always Free ARM (A1) VM, as the constitution says. There is no paid
    fallback in the MVP, which resolves the "paid fallback" half of backend §22.1. Since 2026-10-19
    there are two A1 VMs, which together use the whole Always Free allowance (Session 2026-10-19).
  - If the region has no free A1 capacity, provisioning is retried until it succeeds (FR-042).
  - The risk that an idle free VM is reclaimed is accepted. It is covered by off-host backups, the
    outside uptime alert and the rebuild procedure (FR-043).
  - Every other tool (error tracking, uptime monitoring, the container registry, backup storage) must
    fit a free plan.
  - Confirmed by the owner during planning (2026-10-18): the Oracle tenancy already exists, with
    home region Jeddah (`me-jeddah-1`), and it allows a reserved public IP. On 2026-10-19 it also
    allowed a second one, so each host has its own.
- Q: Where are the nightly production backups stored? → A: With a second, independent provider, not
  in the Oracle account that runs the server.
  - The provider is S3-compatible and its free tier covers the backups.
  - The owner first named Cloudflare R2 (restore-drill answer). During planning (2026-10-18) the
    owner chose **Backblaze B2** instead, where they already have an account. The plan's research
    checks B2's terms.
  - Losing or closing the Oracle account doesn't lose the backups.
  - Analysis (2026-10-18): B2 keeps every version of a file. "Can't overwrite" therefore means that a
    re-upload under an existing name leaves the locked original in place (FR-039a, US6-8).
  - This replaces the `backups/` part of the "Object storage" row in backend §15. Content packs
    (`packs/`) stay B04's decision (backend §22.3).
- Q: Where does the restore drill restore the production backup to? → A: A temporary database
  container on the host. The drill is automated and runs monthly. Staging is never touched.
  - Monthly, at a quiet hour, the latest backup is restored from the backup storage (Backblaze B2,
    see above) into a temporary database
    container on the production host. It is not restored into production's database server.
  - Changed on 2026-10-19: the temporary container now runs on the staging host, not the production
    host. Staging's own database and data are still never touched (Session 2026-10-19).
  - The drill checks four things: the restore succeeds, the migrations match the code, row counts
    are within range, and every wallet equals its ledger sum.
  - It records how long the restore took, then deletes the container and its volume.
  - Any failure alerts the operator.

### Session 2026-10-19

- Q: Do staging and production keep sharing one VM, or get one VM each? → A: One VM each. The owner
  reversed the one-host design of 2026-10-18 (research R1 had rejected two VMs).
  - Both VMs are Always Free A1 with 1 OCPU and 6 GB, which together is the whole A1 allowance.
    Production's boot volume is 100 GB and staging's 47 GB. That leaves 53 GB of the 200 GB free
    block storage, enough for the 47 GB break-glass rescue boot volume.
  - Each host serves only its own environment, with its own reserved public IP, private network,
    edge, deploy access and host monitor (FR-001a). The operator's device can be on both private
    networks at once.
  - Nightly backups run on the production host only. The monthly restore drill runs on the staging
    host and fetches production's latest backup with the drill's read-only key. Production data is
    on the staging host only while the drill runs, and the drill leaves nothing behind (FR-040,
    FR-040a).
  - Why: separate Compose projects on one VM don't isolate CPU, disk or host configuration
    (firewall, private network, remote login, container-runtime upgrades). On separate VMs, a
    staging mistake can't take production down. That risk showed up in practice while the first host
    was being set up.
  - Costs accepted: twice the edge, private network, monitoring and patching; production is capped
    at one core; and the staging host, idle most of the time, may fall under Oracle's
    idle-reclamation thresholds. Its host monitor's alert and the break-glass procedure cover that
    (Edge Cases).
  - Each host is set up, patched, monitored and recovered on its own, and the 4-hour recovery target
    applies to each (SC-009). The budget stays USD 0 (SC-013).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the people who build and run the game, not players: the **developer**
who writes backend features, the **operator** who deploys and watches the servers (today the same
person, the project owner), and **staff** who will sign in to the admin tool from B04 onward. The mobile
app is the future consumer of everything set up here.

### User Story 1 - The whole backend runs locally with one command (Priority: P1)

A developer checks out the repository and starts the full backend on their own machine with one
documented command: the API, the admin, the background worker, the scheduler, the database and the
cache. The health checks pass, and the lint, type-check and test commands from `CLAUDE.md` run against
the real database and cache.

**Why this priority**: Every later backend feature (B02–B11) is built and tested on this stack. Nothing
else in this feature can be checked without it.

**Independent Test**: On a clean machine that has only the container runtime and the pinned toolchain,
follow `CLAUDE.md` from a fresh checkout. The readiness check reports ready, and the test suite passes.

**Acceptance Scenarios**:

1. **Given** a fresh checkout and only the committed example configuration, **When** the developer runs
   the documented start command, **Then** every service starts and `/readyz` reports ready, with no
   cloud account or production secret needed.
2. **Given** the local stack is running, **When** the database is stopped, **Then** `/readyz` reports
   not ready while `/healthz` still answers; **When** the database comes back, **Then** `/readyz`
   reports ready again without restarting any service.
3. **Given** the local stack is running, **When** the developer runs the test command, **Then** the
   tests run against the real database and cache, not substitutes.
4. **Given** an Android emulator on the same machine, **When** it calls the local API's `/healthz`,
   **Then** it gets an answer. The mobile `dev` variant targets the local backend (mobile §21).
5. **Given** a required setting is missing or invalid, **When** a service starts, **Then** it refuses
   to start and names the setting, without printing any secret value.

---

### User Story 2 - Every backend change is checked automatically (Priority: P2)

Every pull request that touches the backend is checked automatically: lint and format, static types,
tests against a real database and cache, the coverage threshold, migrations, the API contract, a secret
scan, and a production image build for ARM64. Any failure blocks the merge.

**Why this priority**: The constitution's backend CI gates must exist before the first feature code
lands on `master`. Without them, the contract, coverage and key-type rules can't be enforced.

**Independent Test**: Open one pull request that changes an endpoint without updating the committed
API contract, and another that commits a credential. Both are blocked. A clean pull request passes.

**Acceptance Scenarios**:

1. **Given** a pull request changes backend code, **When** it is opened or updated, **Then** the checks
   run and report pass or fail on the pull request.
2. **Given** the API changes but the committed contract (`contracts/openapi.yaml`) was not
   regenerated, **When** the checks run, **Then** they fail.
3. **Given** the data model changes without a matching migration, **When** the checks run, **Then**
   they fail.
4. **Given** line coverage of the backend drops below 80%, **When** the checks run, **Then** they fail.
5. **Given** a project data model uses a primary key that is not a UUIDv7, **When** the checks run,
   **Then** they fail.
6. **Given** a credential-like secret is committed anywhere in the repository, **When** the checks run,
   **Then** they fail.
7. **Given** a pull request touches only the mobile app, **When** it is opened, **Then** the backend
   check still reports a result (skipped counts as passing), so it can be a required check. The mobile
   check behaves the same way for backend-only pull requests.

---

### User Story 3 - The API is live over HTTPS on the staging and production hosts (Priority: P3)

The operator sets up two hosts, one for staging and one for production. Each serves its own
environment's API and admin hostnames over HTTPS. Plain HTTP is redirected. The admin lives on its
own hostname, is reachable only over its host's private network, and requires a staff account with a
second factor. Until the project has a real domain, the hostnames are temporary ones derived from
each host's IP addresses (Clarifications).

**Why this priority**: The constitution fixes the deployment target, and backend §22.1 (free-tier
capacity) can only be settled by actually getting the hosts. Doing it now finds hosting problems
before any player data exists.

**Independent Test**: From an outside network, request `/healthz` on the production and staging API
hostnames. Both answer over HTTPS with a valid certificate, while the admin and remote login of
either host can't be reached at all. From a device on a host's private network, that host's admin
asks for a staff sign-in and a second factor. The API hostname never shows admin pages.

**Acceptance Scenarios**:

1. **Given** the production stack is running, **When** anyone on the internet requests `/healthz` on
   the API hostname over HTTPS, **Then** it answers with a valid certificate and a strict-transport
   header.
2. **Given** a request over plain HTTP, **When** it reaches the edge, **Then** it is redirected to HTTPS
   and no API content is served over plain HTTP.
3. **Given** the API hostname, **When** someone requests an admin page on it, **Then** it is not found.
   **Given** the admin hostname, **When** someone requests an API path on it, **Then** it is not found.
4. **Given** a request body larger than 512 KB, **When** it reaches the edge, **Then** it is rejected
   before it reaches the application.
5. **Given** staging and production on separate hosts, **When** staging is deployed, migrated or
   broken, or the staging host's configuration is changed or broken, **Then** production's host,
   data, cache and settings are untouched and production keeps serving.
6. **Given** a staff member signs in to the admin, **When** they enter a correct password, **Then** they
   still can't reach any admin page until they enter a valid second-factor code.
7. **Given** a device that is not on a host's private network, **When** it tries to open that host's
   admin or remote login, **Then** it gets no connection. A device on staging's network only can't
   reach production's admin or remote login.
8. **Given** the operator removes a device from a host's private network, **When** that device tries
   that host's admin or remote login again, **Then** it gets no connection, even with a valid staff
   password and second factor.
9. **Given** the operator's device is on both hosts' private networks at once, **When** it opens the
   staging and the production admin, **Then** both work.

---

### User Story 4 - Releases deploy themselves, and a bad release doesn't take the API down (Priority: P4)

A merge to `master` deploys to staging once its checks pass. A version tag deploys to production. Each
deploy runs the database migrations once and restarts the services. If a migration fails or the new
release doesn't become ready, the deploy stops and the previous release keeps serving. Rolling back means
deploying the previous tag.

**Why this priority**: Without automated deploys, every later feature ships by hand, and a mistake can
take production down while players are mid-sync.

**Independent Test**: Merge a trivial change and watch staging report the new release in `/healthz`.
Then deploy a release whose migration fails on purpose, and confirm staging keeps serving the previous
release and the operator is alerted.

**Acceptance Scenarios**:

1. **Given** a change merged to `master` with passing checks, **When** the deploy finishes, **Then**
   staging's `/healthz` reports the new release identifier.
2. **Given** a version tag on a commit of `master` whose checks passed, **When** it is pushed, **Then**
   production is deployed and its migrations run exactly once.
3. **Given** a version tag on a commit whose checks failed or that isn't on `master`, **When** it is
   pushed, **Then** production is not deployed.
4. **Given** a release whose migration fails, **When** it is deployed, **Then** the deploy stops, the
   previous release keeps serving, and the operator is alerted.
5. **Given** a release that never becomes ready after its restart, **When** the deploy checks readiness,
   **Then** the deploy is marked failed, the previous release is restored, and the operator is alerted.
6. **Given** two merges land within a minute, **When** both trigger deploys, **Then** the deploys run
   one after the other, never in parallel, and the later release ends up serving.

---

### User Story 5 - The operator knows when something breaks (Priority: P5)

Errors from the API, the admin, the worker and the scheduler reach the error tracker with their
environment and release, and without personal data. An outside monitor checks production health. The
operator is alerted when the API is down, when background jobs stop running, when the job queue backs
up, when a backup fails, when either host's disk is filling up or either host stops reporting, or
when a certificate is about to expire.

**Why this priority**: The availability target (99.5% monthly, backend §15) can't be met or even
measured without monitoring. It matters less than the stack and the deploys themselves.

**Independent Test**: Trigger a test error in the API and in a background job, and see both in the
error tracker with the right tags. Stop the production API and receive an alert.

**Acceptance Scenarios**:

1. **Given** an unhandled error in an API request, **When** it happens, **Then** it appears in the error
   tracker with environment and release, and the client gets the error envelope with no internal
   details.
2. **Given** an unhandled error in a background job, **When** it happens, **Then** it appears in the
   error tracker with environment and release.
3. **Given** production `/healthz` fails for 5 minutes in a row, **When** the outside monitor sees it,
   **Then** the operator is alerted.
4. **Given** the scheduler or the worker has stopped, **When** the periodic heartbeat job doesn't run
   for 15 minutes, **Then** the operator is alerted.
5. **Given** any API request, **When** it completes, **Then** one structured log line records its
   request id, method, route, status and duration, and contains no tokens, passwords or personal data.

---

### User Story 6 - Production data is backed up every night and can be restored (Priority: P6)

Every night the production database is backed up to private storage at a second provider, independent
of the hosting account. Old backups expire on a fixed schedule. Once a month, an automated restore
drill on the staging host proves that the latest backup can be restored, without touching the
production host or staging's own database. The operator can also restore by hand by following a
written procedure.

**Why this priority**: The first player data arrives with B02. The backup pipeline must be proven
before then, but nothing in B01 itself stores player data yet.

**Independent Test**: After a night's run, a new backup is in private storage. Running the restore
drill on demand restores it into a temporary database, passes all four checks, records the duration
and leaves nothing behind.

**Acceptance Scenarios**:

1. **Given** a night has passed, **When** the operator checks the backup storage, **Then** a new
   production backup is there, and backups older than the retention schedule are gone.
2. **Given** a backup run fails, or no backup has completed in the last 26 hours, **When** the check
   runs, **Then** the operator is alerted.
3. **Given** the monthly drill time arrives, **When** the drill runs, **Then** it restores the latest
   backup into a temporary database container on the staging host, confirms the restore succeeded,
   the migrations match production's code, row counts are within range and every wallet equals its
   ledger sum. It records the restore duration, then deletes the container and its volume.
4. **Given** any drill check fails, or the drill can't start or finish, **When** it ends, **Then** the
   operator is alerted, and the temporary container and volume are still removed.
5. **Given** a drill is running, **When** production serves requests, **Then** the production host,
   its database, and staging's own database and data are untouched.
6. **Given** the backup storage, **When** anyone without a key the operator created tries to list or
   read it, **Then** access is refused. The staging host holds one such key, the drill's, which can
   list and read but can't add, delete or change anything. The production host's key can only add
   backups (scenario 8).
7. **Given** the hosting account is suspended or closed, **When** the operator follows the rebuild
   procedure on a new host, **Then** the latest backup is still available from the second provider.
8. **Given** the backup credentials stored on the production host, **When** they are used to delete a
   stored backup or shorten its retention, **Then** the storage refuses. **When** they upload under an
   existing backup's name, **Then** the original is still stored and restorable. The host can add new
   backups only, and expiry is handled by the storage's own retention rules.

---

### Edge Cases

- **Database or cache unreachable while running**: API requests fail fast (within 5 s) with an error
  envelope instead of hanging. The service recovers by itself when the dependency returns, with no
  restart.
- **A host reboots**: every service on it comes back by itself, and the database's data survives
  because it lives on persistent storage, not inside a container. The other host is unaffected.
- **A host's disk filling up**: logs are rotated with a size cap, and the operator is alerted at 80%
  disk use on either host, before a database or the restore drill can run out of space.
- **Certificate renewal fails**: the operator is alerted when any public certificate has less than 14
  days left.
- **Health endpoints hammered**: they fall under the default rate limit and answer `429 rate_limited`
  like any other endpoint. The container runtime's own checks and the deploy's verification call the
  services directly from the host, not through the edge, so they are never limited.
- **Unknown path or wrong method on the API host**: the answer is the error envelope (`not_found`, or a
  method-not-allowed code), never an HTML page or a stack trace.
- **Framework-provided tables** (staff permissions, sessions, scheduler tables) keep the framework's own
  key types. The UUIDv7 rule covers the project's apps only.
- **Staff member loses their second-factor device**: the operator resets it with a documented
  server-side command. There is no self-service reset on the admin.
- **A host's private network down, or the operator's own device key lost**: the operator gets in
  through the provider's web or serial console (the break-glass path), following a written
  procedure, and repairs or re-keys that host's network. Each host is break-glassed on its own. The
  public API keeps serving the whole time.
- **Migration that would break the running release**: migrations follow expand/contract (constitution),
  so the previous release keeps working against the new schema. Rollback never reverses a migration
  automatically.
- **Idle free-tier host reclaimed by the provider**: free-tier hosts can be stopped or reclaimed when
  idle, and the owner accepts this risk (Clarifications). The plan's research records the provider's
  current policy (backend §22.1). The staging host, which carries no player traffic, is the likelier
  one to be stopped. For production, the outside uptime check alerts the operator; for either host,
  so does its host monitor's missing report (FR-038). The break-glass procedure starts a stopped
  host, and the rebuild procedure (FR-043) brings service back within the recovery target, from
  backups for production.
- **Staging host down when the monthly drill is due**: the drill can't run, and the operator is
  alerted when no drill has run in 35 days (FR-038). Production is unaffected.
- **No free capacity in the region**: provisioning is retried, for example once a day, until a free
  VM is granted. Meanwhile the stories that don't need the hosts (US1 and US2) go ahead, and US3–US6
  wait. B01 isn't done until the host stories pass.
- **Trial credit ends**: new cloud accounts start with a time-limited trial credit. Anything created
  during the trial that isn't Always Free is stopped when the trial ends, so every resource must be
  Always Free–eligible from the start (FR-042b).
- **Staging broken for days**: production is unaffected, because it runs on its own host, and
  production deploys are not blocked by staging's state. Only the monthly drill waits for the
  staging host (see above).
- **A host's public IP address changes** (a rebuild, or a provider change): the temporary hostnames
  are derived from the IP, so they would change too. Each host keeps its own reserved public IP
  address, and the rebuild procedure (FR-043) reattaches it.
- **A host set up for one environment is pointed at the other**: setup refuses to switch an existing
  host's environment, and the host refuses deploys for the other environment (FR-001a).

## Requirements *(mandatory)*

### Functional Requirements

#### Environments and configuration

- **FR-001**: The backend MUST have three environments, `dev`, `staging` and `prod`, matching the
  mobile build variants (mobile §21). Each has its own settings, database, cache and hostnames.
  Staging and production MUST each run on their own host (Clarifications, Session 2026-10-19), and
  MUST NOT share a database, cache, stored files or secrets.
- **FR-001a**: Each host MUST serve exactly one environment, chosen once when the host is set up.
  Setup MUST refuse to switch an existing host to the other environment. Each host has its own edge,
  private network and device list, firewall, remote-login and container-runtime configuration,
  deploy access (FR-034) and host monitor (FR-038), so a change or failure on the staging host can't
  affect production. Nightly backups run only on the production host, and the restore drill only on
  the staging host (FR-039, FR-040).
- **FR-002**: All configuration MUST come from the environment. Secrets MUST come only from files
  mounted on the host or a secret manager, never from source code, committed configuration or committed
  `.env` files. The repository holds only an example configuration with placeholder values, and `dev`
  runs from it.
- **FR-003**: A service MUST refuse to start when a required setting is missing or invalid, naming the
  setting but not its value. In `staging` and `prod`, it MUST also refuse to start with debug mode on or
  with a placeholder secret.
- **FR-004**: Server time MUST be UTC, and every timestamp the API returns MUST be ISO-8601 UTC
  (backend §6.1).

#### Services

- **FR-005**: The stack MUST consist of the services in backend §4: the edge proxy, the API, the admin,
  the background worker, the scheduler, the database and the cache. The API, admin, worker and scheduler
  run from one shared build, each in its own role.
- **FR-006**: The worker MUST consume the queues `default`, `purchases`, `content` and `push`
  (backend §4). The scheduler's schedules MUST be stored as data, so live ops can change them without a
  release.
- **FR-007**: A periodic heartbeat job MUST run through the scheduler and the worker, so that the
  background path is proven to work even before any feature adds a job.
- **FR-008**: Every service MUST restart by itself after a crash or a host reboot, and MUST have a health
  check the container runtime uses.
- **FR-009**: The API, admin, worker and scheduler MUST keep no state of their own between requests;
  state lives only in the database, the cache and object storage, so the scale path in backend §15
  stays open.

#### Health checks

- **FR-010**: `GET /healthz` (liveness) MUST answer OK whenever the process can serve requests, without
  checking any dependency. It reports the release identifier and nothing else about the system.
- **FR-011**: `GET /readyz` (readiness) MUST answer OK only when the database and the cache are reachable
  and every migration is applied. Otherwise it MUST answer 503 with the error envelope, listing each
  check by name with pass or fail. It MUST NOT reveal hostnames, versions or error text.
- **FR-012**: Both health endpoints MUST need no authentication, MUST NOT be cached at the edge, and MUST
  appear in the API contract (they are listed in backend §6.3).

#### API conventions set up now

- **FR-013**: Every error response from the API hostname MUST use the error envelope
  `{"error": {"code", "message", "details"}}` (backend §6.2), including not found, method not allowed,
  rate limited, server error and dependency unavailable. Codes that §6.2 doesn't list yet (such as
  method not allowed and server error) are added to backend §6.2 in this feature. Server-error messages
  MUST be generic and MUST NOT include stack traces, internal names or personal data.
- **FR-014**: API endpoints MUST live under the base path `/v1` and use JSON, UTF-8 and `snake_case`
  (backend §6.1). The health endpoints sit at the root, as backend §6.3 lists them.
- **FR-015**: Every endpoint MUST be rate-limited by client address, with the limits held in shared
  storage so they apply across every API process (constitution, "Security & privacy"). Exceeding a
  limit returns `429 rate_limited` with a retry hint. Per-player limits (backend §6.5) come with B02.
- **FR-016**: The project MUST provide a shared UUIDv7 primary-key building block, and an automated
  check MUST fail when a model in a project app uses any other primary-key type.
- **FR-017**: The account model used for staff MUST be the project's own from the very first database
  migration, so later features (B02 players) can change account fields without rewriting existing
  tables.
- **FR-018**: The API contract MUST be generated from code and committed at `contracts/openapi.yaml`.
  At the end of this feature, it contains the health endpoints and the error envelope.

#### Edge and security

- **FR-019**: The edge MUST serve every public hostname over HTTPS with certificates that are issued and
  renewed automatically. Plain HTTP MUST redirect to HTTPS. Responses MUST carry a strict-transport
  header (at least one year, subdomains included), a no-sniff header, a deny-framing header and a
  strict referrer policy. Admin pages MUST also carry a content security policy.
- **FR-020**: The edge MUST reject request bodies larger than 512 KB before they reach the application
  (backend §4).
- **FR-021**: The API and the admin MUST run on separate hostnames (backend §4, §13). Each hostname
  serves only its own role. Each environment's admin MUST be reachable only over its host's private
  network, and MUST still be served over HTTPS there. Its certificate MAY come from a private
  authority (one per host) installed on staff devices, because a public authority can't check a
  private address.
- **FR-022**: The admin MUST allow only staff accounts and MUST require a second factor (an
  authenticator app code) at every sign-in. After 5 failed sign-ins for one account or from one client
  address within 15 minutes, further attempts MUST be refused for 15 minutes. Staff accounts are created
  only by a server-side command, never through a public sign-up.
- **FR-023**: On each host, only the edge (HTTP and HTTPS, serving that host's API) and the private
  network's own endpoint may be reachable from the internet. The private-network endpoint MUST NOT
  answer packets that aren't from a known device. The admin, remote login, the database, the cache
  and the application services MUST NOT be reachable from the internet.
- **FR-023a**: Each host MUST have its own private network and device list. The operator MUST be
  able to add a device to, and remove it from, each host's network with a written procedure, one key
  per device, and removing a device MUST cut its access to that host at once. One device MUST be
  able to join both networks at the same time. The break-glass path through the provider's console
  MUST be written down too.
- **FR-024**: No secret may be built into an image or written to a log. Before sending anything to the
  error tracker, the services MUST strip IP addresses, authorization headers, cookies and request
  bodies.

#### Automated checks

- **FR-025**: Every pull request and every push to `master` that touches the backend, the API contract
  or the backend workflow MUST run: lint and format checks, static type checks, tests against a real
  database and cache, line coverage of at least 80% (constitution XIII), a check that migrations match
  the models, a check that the committed contract matches the code, contract tests against the
  committed contract, the UUIDv7 check (FR-016), and a production image build for ARM64. Any failure
  blocks the merge.
- **FR-026**: The backend check MUST report a result on every pull request, even when nothing in the
  backend changed, so it can be a required check (the same rule the mobile workflow follows).
- **FR-027**: A secret scan MUST run over the whole repository on every pull request and fail when a
  credential-like secret is committed.
- **FR-028**: The language version and every dependency MUST be pinned in the repository, so developer
  machines and the checks resolve the same versions.
- **FR-029**: Release images MUST be published to a container registry, tagged with their commit, and
  built for ARM64 (the staging and production hosts) and for the developers' machines.

#### Deployment

- **FR-030**: A merge to `master` MUST deploy to staging once its checks pass. A version tag MUST deploy
  to production, but only when the tagged commit is on `master` and its checks passed.
- **FR-031**: A deploy MUST fetch the image for its commit, run migrations once in a separate step,
  restart the API, admin, worker and scheduler, and then confirm readiness and that `/healthz` reports
  the new release. If any step fails, the deploy MUST stop, the previous release MUST keep serving or be
  restored, and the operator MUST be alerted.
- **FR-032**: Deploys to the same environment MUST run one at a time.
- **FR-033**: Rolling back MUST mean deploying the previous version tag, and the procedure MUST be
  written down. A rollback never reverses migrations; expand/contract migrations keep the previous
  release working.
- **FR-034**: Deploy credentials MUST live only in the CI secret store. Each host has its own, and
  on that host it MUST allow deploying that host's environment and nothing else. The deploy path
  MUST NOT open remote login to the internet. Either CI joins the host's private network for the
  deploy, or the host fetches and applies releases itself. The plan chooses.

#### Observability

- **FR-035**: Errors from the API, the admin, the worker and the scheduler MUST reach the error tracker,
  tagged with environment and release. Performance traces MUST be sampled at a configurable rate, 10%
  or less by default (backend §15: "low sample rate").
- **FR-036**: Each API request MUST produce one structured log line with a request id, method, route,
  status and duration. The request id is taken from the incoming request or generated, and is returned
  in a response header so a support case can be traced. Logs are rotated with a size cap. Client IP
  addresses appear only in the edge's logs, which are kept for at most 14 days (backend §14.2).
- **FR-037**: The database MUST record per-query statistics, so slow queries can be found (backend §15).
- **FR-038**: For production, and for each host where a line says so, the operator MUST be alerted
  when:
  - `/healthz` fails for 5 minutes in a row (checked from outside the host);
  - a public certificate has less than 14 days left;
  - the heartbeat job (FR-007) hasn't run for 15 minutes;
  - a job queue holds more than its backlog threshold (configurable, 100 waiting jobs by default) for
    10 minutes;
  - a backup fails, or none has completed in 26 hours;
  - a restore drill fails any check, can't run, or hasn't run in 35 days;
  - disk use on either host reaches 80%;
  - either host's monitor stops reporting, which also covers a host the provider has stopped;
  - a deploy fails.

#### Backups and recovery

- **FR-039**: The production database MUST be backed up every night to private, S3-compatible object
  storage at a second provider, independent of the hosting account: Backblaze B2 (Clarifications).
  The backup runs on the production host. Backups are kept for 14 days (daily) and 8 weeks (weekly)
  (backend §15). Each backup MUST be checked as readable right after it is written, and MUST record
  each table's row count for the restore drill (FR-040).
- **FR-039a**: The credentials on the production host MUST be able to add backups, but MUST NOT be able
  to delete a stored backup or shorten its retention, so a compromised host can't destroy its own
  backups. Uploading under an existing name keeps the original, and hiding a backup deletes nothing.
  Expiry is done by the storage's own retention rules. Only the operator's separate credentials can
  delete a backup before it expires. The restore drill's credentials, on the staging host, MUST be
  able to list and read backups only.
- **FR-040**: A restore drill MUST run automatically once a month (backend §15), and its first run is
  part of this feature. It runs at a low-traffic hour (configurable, default early morning Cairo time),
  never at the same time as the nightly backup. Each run MUST:
  - restore the latest backup from the backup storage into a temporary database container on the
    staging host (Clarifications, Session 2026-10-19), never on the production host, into
    production's database server or into staging's database. It has its own memory limit and starts
    only when a configured minimum of disk is free, so it can't starve staging;
  - check that the restore succeeded, that the applied migrations match the code of the production
    release that took the backup (not staging's, which may be newer), that each table's row count is within
    the range expected from production at backup time (the plan sets how the range is recorded), and
    that every wallet equals the sum of its ledger entries (constitution, backend §7.2). There are
    no wallets until B03, which makes this check meaningful;
  - record the restore duration, so the recovery target (FR-041) can be tracked;
  - delete the temporary container and its volume, whether the checks passed or failed.
  The manual restore procedure MUST also be written down, for real recoveries.
- **FR-040a**: Production backups MUST NOT be copied to developer machines, to CI or into the
  staging environment (its database, cache or stored files). The one exception is the restore drill
  (FR-040): its temporary container on the staging host is not part of staging's stack, and it is
  deleted, with everything the drill fetched, when the drill ends.
- **FR-041**: The recovery targets are those of backend §15: at most 24 h of data loss (RPO) and at most
  4 h to restore service (RTO).

#### Hosting and documentation

- **FR-042**: This feature resolves backend §22.1, with a USD 0 budget and no paid fallback
  (Clarifications). The plan's research MUST:
  - choose the region and the VM shapes within Oracle's Always Free limits, one VM per environment
    (Clarifications, Session 2026-10-19). Check that each environment fits its VM (the staging VM
    also runs the drill), and that both VMs plus a rescue boot volume fit the allowance;
  - record the idle-reclamation policy, the accepted risk and how it is covered;
  - record the expected capacity against the targets in backend §2 and §18.
  The same change MUST record the decision in backend §2, §15 and §22.1.
- **FR-042b**: Every resource in the hosting account MUST be Always Free–eligible, and the account
  MUST NOT be upgraded to paid. That way nothing stops when the trial credit ends, and no charge is
  possible. Every other service the stack uses (error tracking, uptime monitoring, container
  registry, backup storage) MUST run on a free plan.
- **FR-042a**: Every public hostname MUST be configuration, set per environment, never written in code.
  Until the project has a real domain, the hostnames are temporary ones derived from each host's
  addresses (Clarifications): the API hostname from that host's reserved public IP address, with a
  publicly trusted certificate, and the admin hostname from its private-network address (FR-021).
  Moving to a real domain MUST need only configuration and DNS changes.
- **FR-043**: Setting up a new host MUST be written down as one procedure for both environments,
  scripted where practical, so a fresh host of either environment can be brought to a serving state
  within the RTO (FR-041), and a fresh production host also restored from the latest backup.
- **FR-044**: `CLAUDE.md` MUST list the real backend commands (start the local stack, migrate, test,
  lint, type check, regenerate the API contract, deploy, roll back, restore) and replace the "There is
  no backend yet" note.

### Key Entities *(include if feature involves data)*

- **Environment**: `dev`, `staging` or `prod`, with its own settings, database, cache, hostnames and
  secrets. `staging` and `prod` each run on their own host.
- **Host**: a VM that serves exactly one environment (`staging` or `prod`), with its own reserved
  public IP address, private network, edge, deploy access and host monitor. The production host also
  runs the nightly backup, and the staging host the restore drill.
- **Service**: one role in the stack (edge, API, admin, worker, scheduler, database, cache), with a
  health check and a restart policy.
- **Release**: a built image identified by its commit. A version tag marks a production release.
  `/healthz` reports the release that is serving.
- **Health check result**: the overall status and, for readiness, each named check with pass or fail.
- **Staff account**: a person allowed into the admin, with a second-factor device. Created only by a
  server-side command.
- **Private-network device**: a device (the operator's, a staff member's, or the deploy path's) with
  its own key on a host's private network. Added and removed by the operator, per host. A device can
  be on both hosts' networks.
- **Backup**: a nightly copy of the production database, with its time, size, retention class (daily or
  weekly), storage location, verification result, and the per-table row counts the drill compares
  against.
- **Restore drill result**: one monthly run, with its time, the backup it used, pass or fail for each
  of the four checks, and the restore duration.
- **Alert**: a notice to the operator, with its cause (one of FR-038) and the environment or host.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A contributor new to the repository gets a ready local stack and a passing test suite on
  the first attempt, using only `CLAUDE.md`, in under 30 minutes including downloads.
- **SC-002**: From an outside network, 100 consecutive requests to `/healthz` on the production and
  staging API hostnames all succeed over HTTPS with a valid certificate, each within 1 s.
- **SC-003**: Every backend pull request gets a pass or fail result within 15 minutes. A deliberately
  stale contract, failing test, coverage drop, missing migration, non-UUIDv7 key or committed secret
  blocks the merge every time.
- **SC-004**: A change merged to `master` is serving on staging, and a version tag is serving on
  production, within 15 minutes. The API is unavailable for at most 30 s during each deploy.
- **SC-005**: A release with a deliberately failing migration leaves the previous release serving, and
  the operator is alerted within 5 minutes.
- **SC-006**: Rolling back to the previous release takes at most 10 minutes.
- **SC-007**: A test error in the API and one in a background job each appear in the error tracker
  within 5 minutes, tagged with environment and release, with 0 IP addresses, tokens or cookies in the
  report.
- **SC-008**: With the production API stopped, the operator is alerted within 10 minutes. With the
  heartbeat stopped, within 20 minutes.
- **SC-009**: Every monthly restore drill passes all four checks, records its duration, and leaves no
  temporary container or volume behind. The 4-hour RTO applies to each host: the recorded restore
  duration plus the production host's setup time, and the staging host's setup time on its own,
  each measured once by following FR-043, stay within 4 hours. The drill runs on the staging host,
  which has the same shape as production.
- **SC-010**: After either host reboots, every service on it serves again within 5 minutes with no
  manual step.
- **SC-011**: A port scan of either host from outside finds only the HTTP and HTTPS ports open. The
  admin and remote login don't answer, and the private-network endpoint stays silent to unknown
  devices.
- **SC-012**: Line coverage of the backend is at least 80%.
- **SC-013**: After the account's trial credit has ended, every service on both hosts still runs,
  and every month the hosting account and every other service show USD 0 in charges.

## Assumptions

- **Tools**: the language, framework, database, cache, job runner, scheduler, edge proxy and container
  stack are fixed by the constitution's locked stack and `CLAUDE.md`. The error tracker is Sentry
  (backend §2, §15), used as a hosted service on its free plan. The plan names the remaining tools: the
  outside uptime monitor, the secret scanner, the container registry and the second provider for
  backups. Each must be free (FR-042b).
- **Hostnames**: the roles follow backend §4: `api` and `admin` for production, `staging-api` for
  staging, and `staging-admin` for staging's admin (this spec's choice, following the same pattern).
  In this feature they sit under the temporary IP-based domain (FR-042a). Each environment's API
  hostname points at its own host's public address, and its admin hostname at that host's
  private-network address (FR-021). Staging keeps the `staging-` prefix on its own host, so the
  names stay distinct. Once a real domain exists, they become `api.<domain>` and so on, as backend
  §4 describes.
- **Real domain**: registering it and switching to it happens before the first closed test (the
  step 7 option or step 12 in `docs/delivery-plan.md`). The account-deletion page that B09 publishes
  for the store listing needs it too (backend §14.1).
- **Deploy triggers**: backend §15 says production deploys on a tag. Deploying staging on every merge
  to `master` is this spec's choice, so each feature is tried on staging before it is tagged.
- **Alerts** go to the owner's email. There is no paging service in the MVP.
- **Staging is not backed up**, and production data never enters the staging environment (FR-040a).
  The restore drill borrows the staging host for its temporary container only. Staging can be
  rebuilt from scratch, so playtesters' progress on staging lasts until staging is rebuilt.
- **No player data exists until B02.** In this feature the production database holds only staff
  accounts and schedules. Backups still run from day one, so the pipeline is proven before real data
  arrives.
- **Latency goals** for bootstrap, sync and purchase verification (backend §2) belong to the features
  that build those endpoints. This feature sets up the traces that measure them.
- **Load testing** (backend §16, 100 rps on staging) runs before each phase launch, not in this feature.
- **Dependencies**: none. M03 is merged and shares no artifact with this feature. This feature creates
  `contracts/openapi.yaml`, which the mobile features consume from M06 onward.
- **Out of scope**:
  - player accounts, tokens and per-player rate limits (B02);
  - the required client headers `X-Client-Version` and `X-Platform`, and `426 client_outdated`
    (B02 and B10);
  - idempotency through `client_txn_id` (B02 and B03);
  - the maintenance-mode flag, which is a `LiveSetting` (B10);
  - the admin audit log for content publishes and wallet adjustments (B04 and B03);
  - object storage for content packs and the CDN (B04, backend §22.3);
  - continuous archiving and point-in-time recovery (phase 2);
  - a managed secret vault (later, backend §13);
  - pointing the mobile build variants at these environments (M06);
  - anything iOS-specific.
