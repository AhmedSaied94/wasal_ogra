# The release draft fixture

Copies of the release draft's catalog prices, salon, four items, three
family requests and chapters 1 to 4, kept for the ten owner boards of
2026-10-31 (specs/015-m10-apartment-story, T131 and T132). They are copied by
hand from `content/drafts/core-r1/pack/` in the `content-core-r1` worktree and
layered over `draftShaped()` by `releaseDraftPack()` in
`test/helpers/synthetic_packs.dart`. `prices.json` is `catalog.json`'s
`prices`. When the draft's catalog, `rooms/salon.json`, `items/`,
`family_requests/` or `chapters/ch1`–`ch4` change, copy them again and rerun
`test/design/` and `test/goldens/design/`.
