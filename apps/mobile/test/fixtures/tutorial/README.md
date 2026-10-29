# The tutorial fixture

Copies of the release draft's five tutorial trips, kept for M07's tests
(`specs/012-m07-onboarding/research.md` R20). The sample pack's own trips stay
as they are, so its parity fixtures and the backend's tests don't change.

- `trips/line_hay/line_hay.01.json`–`line_hay.05.json`, `lines/line_hay.json`
  and `speech/sleeper.{boards,missed_stop,woke}.json` (the pools trip 4's
  sleeper names that the sample lacks) come from
  `content/drafts/core-r1/pack/` in the `content-core-r1` worktree
  (`wasal_ogra-core-r1`), copied on 2026-10-27.
- `lines/line_hay.json`'s `display_fare_piasters` and `whats_new` were added
  here on 2026-10-29, ahead of the draft, when M09 made them required
  (`specs/014-m09-lines-vehicles/research.md` R9). They are the sample's
  values; copy the draft's when it has them.
- `test/helpers/tutorial_content.dart` layers them over the bundled sample:
  the draft's `line_hay` and its trips 01–05 replace the sample's, and the
  speech pools are added. Everything else stays the sample's.
- `first_sight.json` is the draft's سلمى scene (its `scene_id`, `plays` and
  `panels`), from `chapters/ch1_first_job.json` in the same worktree, copied
  on 2026-10-28 for M22's tests (`specs/012.5-m22-animated-scenes/research.md`
  R11). Its panels have the draft's `ch1_*` names, and `ch1_usta_dreams`
  gives both lines to the usta. `draftFirstSight()` reads it.
- They are copies, not links. When the draft's trips 01–05, its `line_hay`,
  those pools or its `first_sight` change, copy them here by hand and rerun
  the tests that use `tutorialContent()` or `draftFirstSight()`.
