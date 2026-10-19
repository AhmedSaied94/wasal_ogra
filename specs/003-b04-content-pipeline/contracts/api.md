# Contract: `GET /v1/content/manifest` (FR-029–FR-034)

This endpoint is on the API role only. It adds to B01's `contracts/api.md`, and keeps B01's error
envelope, request id, address throttle and `Cache-Control: no-store`.

## Request

| Part | Value |
| --- | --- |
| Method, path | `GET /v1/content/manifest` |
| Auth | None until B02 (FR-033). The view opts out of B01's default `IsAuthenticated` explicitly. |
| `X-Client-Version` | Optional. Read as `MAJOR.MINOR.PATCH`, with any `+BUILD` suffix ignored (`1.4.0+57` → `1.4.0`). A missing or malformed value counts as "not stated". |
| `X-Platform` | Ignored by this endpoint (B02 and B10 enforce it) |
| Body, query | None. Unknown query parameters are ignored. |

## Response `200`

The body validates against `manifest.schema.json` (contracts/content-schemas.md). A test checks
every response shape against it.

```json
{
  "version": 12,
  "packs": [
    {
      "pack_id": "core",
      "version": 12,
      "url": "https://api.<host>/packs/core-12.json.gz",
      "sha256": "9f2c…64 hex…",
      "size": 412233,
      "min_client_version": "1.0.0"
    }
  ]
}
```

| Case | `version` | `packs` |
| --- | --- | --- |
| No pack published in this environment (US4-7) | `0` | `[]` |
| No client version stated | the current pack's version | `[current]` |
| Stated version ≥ the current pack's `min_client_version` | the current pack's version | `[current]` |
| Stated version below it (US4-6, US4-11) | the newest published or retired pack whose `min_client_version` ≤ the stated version | `[that pack]` |
| Stated version below every pack's minimum | `0` | `[]`. The app keeps its bundled pack, and B10's force update takes over. |

- **`url`** is `CONTENT_PACKS_PUBLIC_URL + "core-<v>.json.gz"`, built per response and never
  stored (research R5).
- **Freshness.** Publishes, promotions and minimum-version changes show within 1 minute (FR-031).
  The response is cached server-side for 30 s per "offered version", and those three actions clear
  the cache on commit.

## Errors (B01 envelope)

| HTTP | `code` | When |
| --- | --- | --- |
| 405 | `method_not_allowed` | Any method other than `GET`, `HEAD` or `OPTIONS` |
| 406 | `not_acceptable` | An `Accept` header that excludes JSON |
| 429 | `rate_limited` | B01's per-address throttle |
| 503 | `dependency_unavailable` | The database is unreachable. If only the cache is unreachable, the endpoint answers from the database. |

No new error codes, so backend §6.2 is unchanged.

## OpenAPI

- **Contract.** A drf-spectacular serializer pair (`ContentManifest`, `ContentManifestPack`)
  generates the schema. The committed `contracts/openapi.yaml` gains the path, and B01's drift
  check and `schemathesis` cover it.
- **Matching the schema.** Field names, types and patterns match `manifest.schema.json` exactly.
  A test compares the two (FR-029).

## Performance

**Target**: p95 < 150 ms at 100 rps (SC-011). One indexed query, or none on a cache hit.
