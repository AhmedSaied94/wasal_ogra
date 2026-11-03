# Admin contract: B07

## Ad rewards (`ads.AdReward`)

- **Who:** `view_adreward`, granted by migration to `live_ops` and `economy_ops`. No group gets add,
  change or delete; the admin class returns False for all three, superusers included.
- **List:** created, player (link to the player page), placement, outcome, JENEHAT, BONAT, game
  day, shown. Filters: placement, outcome, game day (date hierarchy). Search: player id (exact),
  transaction id (exact).
- **Detail:** every field, read-only, with links to the grant's ledger entries
  (`ref_type = ad_reward`, `ref_id = id`).
- **Player page** (`economy/player_page.py`): a "Ad rewards" link filtered to the player, and today's
  piggy status (granted or not).

## Live settings (B10's pages, no new screen)

The three keys appear in B10's settings list with their ranges; the cross rule's message is
"The morning piggy must give something." Changes are recorded in `LiveopsChange` as for every
setting.
