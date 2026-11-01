# Contract: Offer Rules

`Offer.rules` is a JSON list; a player sees the offer only when every rule holds (research R12). An
empty list means everyone. Each rule is validated on save: an unknown `rule`, a missing or extra
field, or a value of the wrong type is refused with the rule's position and name.

| `rule` | Fields | Holds when |
| --- | --- | --- |
| `country_in` | `countries`: non-empty list of ISO 3166-1 alpha-2 codes | `Player.country` is in the list (a blank country never matches) |
| `days_since_install` | `min`, `max`: integers, `0 ≤ min ≤ max ≤ 3650` | the Cairo calendar days from `Player.created_at` to now are in `[min, max]` (day 0 = the install day) |
| `payer` | `is`: bool | the player has (`true`) or hasn't (`false`) a granted purchase. Until B06: nobody has |
| `owns_product` | `product_id`: a catalog product | the player holds its entitlement. Until B06: nobody does |
| `lacks_product` | `product_id`: a catalog product | the opposite of `owns_product` |
| `chapter_reached` | `chapter_id`: glossary §3.6; `status`: `open` \| `completed` | the player's `StoryState` for that chapter is at least that status |

Always applied, whatever the rules:

- `starts_at ≤ now` and (`ends_at` is null or `now < ends_at`);
- the offer's product is active and on the request's platform;
- an offer for a `non_consumable` product is hidden from a player who owns it.

Example, phase 2's starter pack (B12):

```json
[
  { "rule": "chapter_reached", "chapter_id": "ch1_first_job", "status": "completed" },
  { "rule": "days_since_install", "min": 0, "max": 6 },
  { "rule": "lacks_product", "product_id": "starter_pack" }
]
```

The B06 hooks (`payer`, `owns_product`, `lacks_product`) read through
`apps.liveops.services.facts.PlayerFacts`, whose purchase fields B06 fills; B10 ships them returning
"no purchases, no entitlements", tested on both outcomes with a stubbed fact.
