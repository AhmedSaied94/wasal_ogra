# Contract: The API Client

How the app talks to the server's player endpoints. The server's side is B02's
`contracts/api.md` and `tokens.md`, and B03's `contracts/api.md`; this file says what the app sends
and reads. Research: R3, R4, R13.

## `ApiClient` (`lib/core/network/api_client.dart`)

```dart
abstract interface class ApiClient {
  /// One request. Never throws for an answer or a network failure.
  Future<ApiResult> send(ApiRequest request);
}

final class ApiRequest {
  const ApiRequest(this.method, this.path, {this.body, this.bearer, required this.receiveTimeout});
  final String method;          // GET | POST
  final String path;            // '/v1/…', joined to the flavor's base URL
  final Object? body;           // JSON-encodable; integers only for numbers
  final String? bearer;         // the access token, or null for the public auth calls
  final Duration receiveTimeout;
}

sealed class ApiResult {}
final class ApiOk extends ApiResult { int status; Map<String, Object?> json; int receivedAtElapsedMs; int sentAtElapsedMs; }
final class ApiFailure extends ApiResult { int status; String code; Map<String, Object?> details; Duration? retryAfter; }
final class ApiUnreachable extends ApiResult { UnreachableKind kind; }   // noConnection | timeout | dns
```

- **One implementation, `DioApiClient`**, on M04's `createHttpClient(flavor, info)`, so every
  request has the flavor's base URL, the URL check (`isAllowedUrl`), no redirects and the two
  headers (`X-Client-Version` with the build, `X-Platform`).
- The bearer is set per request as `Authorization: Bearer <access>`. The content manifest and the
  pack downloads don't go through `ApiClient`, and stay unauthenticated (B02 FR-035).
- `ApiFailure.code` is the envelope's `error.code`. A non-2xx body that isn't the envelope gives
  `server_error`. `Retry-After` (seconds) fills `retryAfter`.
- A `2xx` whose body isn't a JSON object is `ApiFailure(status, 'server_error')`.
- The elapsed times come from the uptime counter (M05's `UptimeSource`), for R15's time anchor.
- **No logging interceptor in any flavor.** Errors reported to Flutter's error handler carry the
  path, the status and the code, never headers or bodies.

### Timeouts

| Call | Connect | Receive |
| --- | --- | --- |
| auth (`anonymous`, `refresh`, `link`) | 10 s | 15 s |
| `GET /v1/bootstrap`, `GET /v1/state` | 10 s | 15 s |
| `POST /v1/sync` | 10 s | 30 s |

## `AuthorizedApi` (`lib/core/account/authorized_api.dart`)

Every player endpoint goes through it. It adds the bearer, renews and signs in again by R4, and
reports `account_deleted` and player changes to `AccountService`.

```dart
abstract interface class AuthorizedApi {
  /// Sends [request] with the session's access token. Renews before it when the access has
  /// under 60 s left, and handles the 401s of research R4. Answers `ApiFailure(403,
  /// 'account_deleted')` without a request when the account is deleted.
  Future<ApiResult> send(ApiRequest request);
}
```

### The token rules (B02 "Client obligations")

| Situation | What happens |
| --- | --- |
| No session | sign in with the install id first (`POST /v1/auth/anonymous`) |
| Access has < 60 s left (trusted time) | renew first |
| Renewal answer lost (unreachable or timeout) | retry with the **same** refresh token, at most twice, while under 60 s since the first attempt; then sign in again |
| Renewal `200` | store the pair (one write) before anything uses it |
| Call answers `401 token_expired` | renew, repeat the call once |
| Call answers `401 token_invalid` | renew once, repeat once; a second `token_invalid` signs in again |
| Renewal answers `401 token_expired` or `401 token_invalid` | sign in again |
| Any `403 account_deleted` | account `deleted` (account.md); no more player calls |
| A token answer names another player | account change (account.md) |
| Concurrent callers needing a renewal | one renewal; all wait for it |
| `429` on account creation | wait `details.retry_after_s`, play goes on |

## The endpoints and what the app reads

Fields the app doesn't list are ignored. Integers must be JSON integers, or the answer is
malformed (`server_error`).

| Call | Sends | Reads |
| --- | --- | --- |
| `POST /v1/auth/anonymous` | `{install_id, platform, locale: "ar-EG"}`, no bearer | `TokenPair` + `created` |
| `POST /v1/auth/refresh` | `{refresh}`, no bearer | `TokenPair` |
| `POST /v1/auth/link` | `{provider: "google", id_token}` or with `resolve`, `existing_player_id` | `{player_id, providers}`, or a `TokenPair` after `switch_to_existing`; 409 `details.current`, `details.existing`; 422 `details.reason` |
| `GET /v1/bootstrap` | — | `server_time`, `player.{player_id, display_name, driver_level, providers}`, `wallet`, `entitlements`, `state_version`, `content.version`, `client.{min_version, latest_version, force_update}`, `daily`, `comeback.claimable` |
| `GET /v1/state` | — | `state_version`, `server_time`, `player.{display_name, driver_level}`, `wallet`, `inventory`, `ownership[].{kind, sku_id, variant}`, `trips[].{trip_id, best_stars, best_time_ms, plays}`, `open_trip`, `last_result`; `story`, `grants`, `stats` kept raw |
| `POST /v1/sync` | `{base_state_version, ops[]}` (sync.md "The wire") | `state_version`, `state_stale`, `results[].{client_txn_id, status, reason?, granted?}`, `wallet` |

`TokenPair` is `{player_id, access, refresh, access_expires_in, providers}`. `wallet` is
`{jenehat, bonat, fuel, fuel_max, fuel_updated_at, fuel_unlimited_until}`, with times as ISO-8601
UTC (with or without milliseconds), read to integer milliseconds.

### Whole-request failures, by endpoint

| Code | bootstrap / state | sync | auth |
| --- | --- | --- | --- |
| `401 token_*` | token rules | token rules | renewal rules |
| `403 account_deleted` | deleted | deleted | deleted |
| `426 client_outdated` | forced update | forced update, hold | forced update |
| `429 rate_limited` | back off | back off (≥ `Retry-After`) | back off; creation waits `retry_after_s` |
| `503 maintenance` | maintenance (B10) | maintenance, hold until resume | maintenance |
| `503 dependency_unavailable`, `5xx`, unreachable | back off | back off | back off |
| `400`, `413`, `415`, `406` | logged as a bug | research R13 | logged as a bug |
