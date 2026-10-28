# The tutorial fixture

Copies of the release draft's five tutorial trips, kept for M07's tests
(`specs/012-m07-onboarding/research.md` R20). The sample pack's own trips stay
as they are, so its parity fixtures and the backend's tests don't change.

- `trips/line_hay/line_hay.01.json`–`line_hay.05.json`, `lines/line_hay.json`
  and `speech/sleeper.{boards,missed_stop,woke}.json` (the pools trip 4's
  sleeper names that the sample lacks) come from
  `content/drafts/core-r1/pack/` in the `content-core-r1` worktree
  (`wasal_ogra-core-r1`), copied on 2026-10-27.
- `test/helpers/tutorial_content.dart` layers them over the bundled sample:
  the draft's `line_hay` and its trips 01–05 replace the sample's, and the
  speech pools are added. Everything else stays the sample's.
- They are copies, not links. When the draft's trips 01–05, its `line_hay`
  or those pools change, copy them here by hand and rerun the tests that use
  `tutorialContent()`.
