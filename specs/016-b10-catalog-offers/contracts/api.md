# Contract: API Changes (B10)

The committed `contracts/openapi.yaml` is regenerated with these. Backend §6.2, §6.4 and §6.5 are
updated first (B01's rule for new codes).

## New error codes (backend §6.2)

| HTTP | `code` | `details` | When |
| --- | --- | --- | --- |
| 426 | `client_outdated` | `{"min_version": "1.3.0"}` | the parsed `X-Client-Version` is below `min_client_version_<X-Platform>`, on any endpoint with the default permissions except bootstrap |
| 503 | `maintenance` | `{"until": "2026-11-03T15:30:00Z"}` or `{}` | `maintenance_enabled`, on any `POST`, `PUT`, `PATCH` or `DELETE` with the default permissions; `until` only when set and in the future |

Order of checks on a default endpoint: authentication (401/403) → `ClientHeaders` (400) →
`CurrentClient` (426) → `NotInMaintenance` (503) → throttle (429) → the view. So an outdated app
gets 426 even during maintenance, which is the answer it can act on.

Not affected: `POST /v1/auth/anonymous`, `POST /v1/auth/refresh` (their own `ClientHeaders` only),
`GET /v1/content/manifest`, `/healthz`, `/readyz` (`AllowAny`). B06's and B07's store and ad
callbacks will declare their own permissions.

## `GET /v1/bootstrap` (backend §6.4)

The shape is unchanged. Now:

- `client.min_version` and `client.latest_version` are the request platform's live values;
  `force_update` is `X-Client-Version < min_version` (the build suffix ignored).
- It never answers 426 (`allow_outdated_client = True`).
- It writes `Player.platform` and `Player.client_version` when they differ from the headers.

## `GET /v1/offers` (new)

Auth: player token, the two headers, the player throttle, 426 (the defaults). A read, so it answers
during maintenance.

```json
{
  "server_time": "2026-11-01T09:00:00Z",
  "products": [
    { "product_id": "bonat_pack_s", "kind": "consumable", "bonat": 60, "bonus_bonat": 0, "entitlement": null, "best_value": false },
    { "product_id": "bonat_pack_m", "kind": "consumable", "bonat": 300, "bonus_bonat": 30, "entitlement": null, "best_value": false },
    { "product_id": "bonat_pack_l", "kind": "consumable", "bonat": 800, "bonus_bonat": 120, "entitlement": null, "best_value": true },
    { "product_id": "remove_ads", "kind": "non_consumable", "bonat": 0, "bonus_bonat": 0, "entitlement": "remove_ads", "best_value": false }
  ],
  "offers": [
    { "offer_id": "eg_launch_week", "kind": "sale", "product_id": "remove_ads", "ends_at": "2026-11-08T00:00:00Z" }
  ]
}
```

- `products`: active, offered on the request's platform, ordered by `display_order`. A player is
  granted `bonat + bonus_bonat` for a consumable (B06).
- `offers`: those the player is eligible for (contracts/offers.md), ordered by `priority` descending
  then `starts_at`; `ends_at` is null when open-ended. Empty at launch.
- Never a price or a currency. Prices come from the store (mobile §15.2).
- `Cache-Control: private, no-store`.
- Target: p95 ≤ 150 ms on staging (research R16).

## Service for other features

```text
apps.liveops.services.catalog.grants_for(product_id: str, platform: str) -> ProductGrants
    ProductGrants(bonat_total: int, entitlement: str | None)
    raises ProductUnavailable when the product is unknown, inactive or not on that platform
```

B06 calls it inside its grant transaction and stores the result on `Purchase` (research R11).
