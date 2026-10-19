# Contract: API Conventions and Health Endpoints

Spec FR-010 – FR-015, FR-018, FR-036. The machine-readable contract is the generated, committed
`contracts/openapi.yaml` at the repository root. This document explains it. If they ever disagree,
the generated file is right and this document gets fixed.

## Conventions on the API hostname

| Rule | Value |
| --- | --- |
| Base path | `/v1` for API endpoints (none in B01, but the router is mounted). Health endpoints at the root. |
| Format | JSON, UTF-8, `snake_case` keys, ISO-8601 UTC timestamps (`2026-10-18T09:15:00Z`) |
| Request id | The `X-Request-ID` request header is accepted if it matches `^[A-Za-z0-9-]{8,64}$`. Otherwise the server generates a UUIDv7. Every response echoes it in `X-Request-ID`. |
| Caching | `Cache-Control: no-store` on every API response in B01 |
| Rate limit | Per client address, default `120/min` (`THROTTLE_ADDRESS_RATE`), counted in the shared cache across all API processes. The client address is taken behind exactly one proxy (`NUM_PROXIES=1` outside `dev`). With `NUM_PROXIES` ≥ 1, a request to `/healthz` or `/readyz` with no `X-Forwarded-For` isn't counted: only the host can send one, because the app ports bind to `127.0.0.1` and the edge always adds the header. That covers the container health checks and the deploy's verify step. Every other path is counted, header or not. If the cache is unreachable, the limit fails open (logged), so a cache outage never takes down `/healthz`. A malformed rate stops the process at startup. |
| Body size | Above 512 KiB (524,288 bytes) is rejected by the edge with `413 payload_too_large`, before Django |

Required client headers (`X-Client-Version`, `X-Platform`) and `426 client_outdated` are not enforced
in B01 (spec "Out of scope", B02/B10).

## Error envelope

Every non-2xx response from the API hostname has this body, whether it comes from Django, DRF or the
edge:

```json
{ "error": { "code": "rate_limited", "message": "Too many requests", "details": { "retry_after_s": 17 } } }
```

| Field | Rule |
| --- | --- |
| `code` | A code from backend §6.2 (the table below lists the ones B01 uses or adds). Clients branch on this. |
| `message` | Short, generic English for developers. Never a stack trace, internal name, SQL, hostname or personal data (FR-013). Clients show their own localized text. |
| `details` | Object, possibly empty. Only the documented keys appear. Field errors of nested serializers use dotted names (`inner.a`, `items.1.a`), each with a list of plain strings. |

### Codes used in B01 (additions to backend §6.2 in **bold**)

| HTTP | `code` | Raised by | `details` |
| --- | --- | --- | --- |
| 400 | `validation_error` | DRF `ValidationError`, `ParseError` | `{fields?: {name: [message]}}` |
| 404 | `not_found` | Unknown path (the API urlconf's last, catch-all route, so dev's `DEBUG` doesn't swap in Django's HTML page), `Http404` (`handler404`), DRF `NotFound` | `{}` |
| 405 | **`method_not_allowed`** | DRF `MethodNotAllowed` | `{allowed: ["GET"]}` |
| 406 | **`not_acceptable`** | DRF `NotAcceptable` | `{}` |
| 413 | **`payload_too_large`** | The edge's `request_body` limit. The backstop is `BodySizeLimitMiddleware`, which compares `Content-Length` with `DATA_UPLOAD_MAX_MEMORY_SIZE` (DRF reads the body stream itself, which skips Django's own check), plus `RequestDataTooBig` in the DRF handler | `{limit_bytes: 524288}` |
| 415 | **`unsupported_media_type`** | DRF `UnsupportedMediaType` | `{}` |
| 429 | `rate_limited` | DRF throttle | `{retry_after_s: int}`, plus a `Retry-After` header |
| 500 | **`server_error`** | Any unhandled exception (`handler500` and the DRF handler fallback) | `{}` (the request id is in the header) |
| 503 | **`not_ready`** | `/readyz` when a check fails | `{checks: {database, cache, migrations}}` |
| 503 | **`dependency_unavailable`** | Database or cache unreachable during a request (fails within 5 s, spec edge case) | `{}` |

- Mapping rule: an explicit table entry wins. Any other DRF `APIException` uses its `default_code`,
  which must then be added to §6.2 before it ships. Django's `Http404` and `PermissionDenied` are
  treated as DRF's `NotFound` and `PermissionDenied`, and a 401 keeps its `WWW-Authenticate` header.
- The catch-all 404 route is CSRF-exempt, so a `POST` to an unknown path gets the envelope, not
  Django's HTML CSRF page.
- The admin hostname keeps Django's HTML error pages for staff. The envelope applies to the API
  hostname only.

## Health endpoints

Both endpoints are unauthenticated, rate-limited like everything else, `no-store`, and present in
`contracts/openapi.yaml` (FR-012). The API and admin containers both serve them (the admin's are
reachable only on the private network and by the container runtime).

### `GET /healthz` — liveness (FR-010)

Checks nothing outside the process.

`200`:

```json
{ "status": "ok", "release": "3f9c2e1d…40-hex" }
```

No other fields: no versions, hostnames or uptime.

### `GET /readyz` — readiness (FR-011)

| Check | Pass when | Bound |
| --- | --- | --- |
| `database` | `SELECT 1` succeeds | Connect timeout 3 s |
| `cache` | A read from the cache succeeds (works for the drill's `locmem` cache too) | Socket connect/read timeout 2 s |
| `migrations` | No unapplied migration exists for the code (`MigrationExecutor` plan is empty). Cached per process after the first pass. | Runs only if `database` passed, otherwise it reports `fail`. Both database checks run with `SET LOCAL statement_timeout = '1s'`, so a server that accepts the connection and then stalls is bounded too. |

`200`:

```json
{ "status": "ready", "checks": { "database": "pass", "cache": "pass", "migrations": "pass" } }
```

`503` (error envelope):

```json
{ "error": { "code": "not_ready", "message": "Service not ready",
             "details": { "checks": { "database": "fail", "cache": "pass", "migrations": "fail" } } } }
```

- The whole response returns within 5 s even when every dependency hangs.
- The failure reason (exception text) goes to the log with the request id, never into the response
  (FR-011).

## Access log line (FR-036)

One JSON line per API request, written by `common.middleware.AccessLogMiddleware`:

```json
{"ts":"2026-10-18T09:15:00.123Z","level":"INFO","logger":"wassal.access","request_id":"…",
 "method":"GET","route":"/readyz","status":200,"duration_ms":4.2,"release":"3f9c…","env":"prod"}
```

- `route` is the resolved URL pattern (for example `/v1/things/<uuid:id>`), not the raw path, so ids
  and query strings never land in logs.
- No IP addresses, headers, cookies, bodies or tokens are logged.
- Client IPs exist only in the edge's access log, which is kept 14 days (backend §14.2).

## Contract tests

- `schemathesis` runs against the **committed** `contracts/openapi.yaml`, calling the app through
  pytest-django's `live_server` (constitution XIII). It checks status codes, response schemas and
  `Content-Type` for every documented operation.
- CI regenerates the schema and fails on any diff (FR-018, [ci-checks.md](./ci-checks.md)).
