# packages/trip_engine/CLAUDE.md

The pure-Dart rules engine from **M01** (`specs/004-m01-trip-engine/`): every trip rule, the 13 commands, replay and rebuild, and the fixture tool. Its living rules reference is `RULES.md`. The parity fixtures in `fixtures/parity/` (from M01 and B05), `{definition, seed, params, command_log, expected_result}`, are replayed by this engine and by the Python mirror in `tools/solver/` in CI. The project-wide rules are in the root `CLAUDE.md`.

## Commands

Run these in `packages/trip_engine`, after `packages/content_models` has been built (`tools/content_kit/CLAUDE.md`). CI runs them in the mobile `packages` job.

| Purpose | Command (in `packages/trip_engine`) |
| --- | --- |
| Install deps | `fvm dart pub get` |
| Format check | `fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` |
| Analyze | `fvm dart analyze --fatal-infos` |
| Tests (rules, fixtures, replay, fuzz, perf budget) | `fvm dart test --coverage=coverage` |
| Coverage gate (≥ 90%) | `fvm dart run coverage:format_coverage --lcov --report-on=lib --in=coverage --out=coverage/lcov.info && fvm dart run ../../apps/mobile/tool/check_coverage.dart --min 90 --lcov coverage/lcov.info` |
| Replay every fixture, exit 1 on a difference | `fvm dart run tool/fixtures.dart check` |
| Recompute a fixture's `expected_result` (then review the diff) | `fvm dart run tool/fixtures.dart update <file>...` |
| Print a fixture's event sequence | `fvm dart run tool/fixtures.dart show <file>` |
| Regenerate the longest-trip stress fixture | `fvm dart run tool/stress_fixture.dart` |

- A rule change edits `packages/trip_engine/RULES.md`, both engines (this package and `tools/solver/src/wassal_solver/engine/`) and the affected fixtures in the same PR (constitution III). `update` rewrites only `expected_result`; review every changed fixture before committing.
- Every fixture needs an entry in `test/fixtures/expectations/`, which pins what the fixture is about. The fixtures test fails on a fixture without one.
- The engine takes every balancing number as `TripParams`, built from `apps/mobile/assets/config/tunables.json` with `TripParams.fromTunables`. It has no defaults of its own.
