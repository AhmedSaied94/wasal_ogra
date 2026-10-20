# trip_engine

The rules engine of وصّل الأجرة: everything that decides a trip's outcome (constitution I). Fares,
the tray and the hand, the passing chain, the passenger types, the authored events, the player's
aids, reputation, stars and earnings.

It is pure Dart and deterministic. The caller advances a 33 ms logic clock, a seeded `xorshift32`
picks speech variants, and all money is integer piasters. Replaying
`(definition, seed, params, command_log)` gives the same result, the same events and the same
command-log fingerprint, so B05's Python mirror can check every fixture in `fixtures/parity/`.

- **The rules:** [RULES.md](RULES.md), the reference B05 mirrors. A rule change edits it in the
  same PR as the code and the fixtures.
- **The design:** `specs/004-m01-trip-engine/` (spec, plan, data model and contracts).

## Run

In this folder, after `packages/content_models` has been built
(`fvm dart pub get && fvm dart run build_runner build -d` there):

```bash
fvm dart pub get
fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
fvm dart analyze --fatal-infos
fvm dart test --coverage=coverage
fvm dart run coverage:format_coverage --lcov --report-on=lib --in=coverage --out=coverage/lcov.info
fvm dart run ../../apps/mobile/tool/check_coverage.dart --min 90 --lcov coverage/lcov.info
```

## Fixtures

```bash
fvm dart run tool/fixtures.dart check                 # replay every fixture, exit 1 on a difference
fvm dart run tool/fixtures.dart update <file>...      # recompute expected_result, then review
fvm dart run tool/fixtures.dart show <file>           # print a fixture's event sequence
fvm dart run tool/stress_fixture.dart                 # regenerate stress__longest_trip.json
```

Every fixture needs an entry in `test/fixtures/expectations/`, which pins what it is about.

`fixtures/parity/README.md` explains the files.
