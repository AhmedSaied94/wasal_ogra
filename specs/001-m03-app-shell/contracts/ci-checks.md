# Contract: Mobile CI Checks

Spec FR-036, FR-039 – FR-042, SC-008, SC-010. The workflow is `.github/workflows/mobile.yml`.
Versions come from research.md R5.

## Triggers

| Event | Runs |
| --- | --- |
| `pull_request` (any) | The `changes` job always runs. The mobile jobs run only if the PR touches `apps/mobile/**`, `packages/**`, `.fvmrc` or `.github/workflows/mobile.yml`. |
| `push` to `master` | Same path rule |
| `workflow_dispatch` with input `update_goldens: true` | `update-goldens` only |

There is no workflow-level `paths:` filter. A required check whose workflow never starts stays
"pending" forever and blocks merges. Instead, the `changes` job computes the path rule with
`git diff --name-only` against the merge base, without third-party actions. Jobs it skips count as
passing.

`concurrency: mobile-${{ github.ref }}` with `cancel-in-progress: true`.

## Jobs

| Job | Needs | Steps | Fails when |
| --- | --- | --- | --- |
| `changes` | — | checkout (`fetch-depth: 0`) → diff → output `mobile=true/false` | never |
| `check` | `changes` | checkout → flutter-action (`flutter-version-file: .fvmrc`, `cache: true`, `pub-cache: true`) → `flutter pub get` → `dart run build_runner build -d` → format check → `flutter analyze --fatal-infos` → `flutter test --coverage` → `dart run tool/check_coverage.dart --min 80` → on failure, upload `test/**/failures/` | any format diff, any analyzer issue (infos included), any failing unit/widget/golden/palette/a11y/Arabic-literal/ARB test, coverage < 80% |
| `build-android` | `changes` | checkout → setup-java (`temurin`, 17) → flutter-action → `flutter build apk --flavor dev --debug` → upload the APK (7-day retention) | build error |
| `update-goldens` | — (dispatch only) | flutter-action → `flutter test --update-goldens test/goldens` → upload `test/goldens/**/*.png` | never gates; a maintainer commits the artifact |

- `check` and `build-android` run in parallel.
- Both have `timeout-minutes: 15` (SC-008).
- Every command runs in `apps/mobile` (`defaults.run.working-directory`).

## Commands (identical locally via FVM; listed in CLAUDE.md, FR-043)

| Purpose | Command (in `apps/mobile`) |
| --- | --- |
| Install deps and generate l10n | `fvm flutter pub get` |
| Code generation | `fvm dart run build_runner build -d` |
| Format check | `fvm dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` |
| Analyze | `fvm flutter analyze --fatal-infos` |
| All tests and goldens | `fvm flutter test --coverage` |
| Coverage gate | `fvm dart run tool/check_coverage.dart --min 80` |
| Update goldens (Linux only) | `fvm flutter test --update-goldens test/goldens` |
| Run the dev variant | `fvm flutter run --flavor dev` |
| Build the dev APK | `fvm flutter build apk --flavor dev --debug` |
| Cold-start measurement | `tool/perf/cold_start.sh` (see quickstart) |

## Checks implemented as tests (they run inside `flutter test`)

| Check | Test | Requirement |
| --- | --- | --- |
| Palette: ΔL\* ≥ 18, WCAG text-on-fill, «new» dot ≥ 3:1, hue separation | `test/core/theme/palette_test.dart` | FR-011 |
| No Arabic letters, digits or presentation forms (U+0600–06FF, U+0750–077F, U+08A0–08FF, U+FB50–FDFF, U+FE70–FEFF) in `lib/**/*.dart`, excluding `lib/l10n/generated/` | `test/repo/no_arabic_literals_test.dart` | FR-042 |
| No `double`/`num` in money code: parameters, fields, variables or return types whose name matches `(?i)(piaster\|amount\|price\|fare\|cash\|money\|jenehat\|bonat)` | `test/repo/integer_money_test.dart` | Constitution II |
| ARB numeric placeholders are `String` | `test/core/l10n/arb_placeholders_test.dart` | FR-028 |
| Tunables registry ⇔ `tunables.json` ⇔ documented table | `test/core/config/tunables_defaults_test.dart` | FR-031 – FR-033 |
| 44×44 tap targets, contrast, ≥ 12 pt text on every shell screen at 1.0× and 1.3× | `test/a11y/minimum_sizes_test.dart` | FR-040, FR-041, SC-004 |
| Goldens: every shell screen × {390×844, 360×640} × {Arabic-Indic, Western} × {1.0, 1.3}, plus each tab with the dot on and off | `test/goldens/shell_goldens_test.dart`, `navigation_goldens_test.dart` | FR-040 |
| Goldens: every MVP destination + `tripPause` at 390×844, 1.0×, both digit styles (46 images) | `test/goldens/all_destinations_goldens_test.dart` | FR-040, constitution X |

## Coverage rules

- **Excluded:** `**/*.g.dart`, `**/*.freezed.dart`, `lib/l10n/generated/**`, `lib/main.dart`. The Android and iOS host code
  is Kotlin/Swift and isn't measured.
- **Untested files count:** the gate script adds every file under `lib/` that is missing from
  `lcov.info` as 0% covered, so a file no test imports can't hide.

## Golden comparator

- **Fonts:** `test/flutter_test_config.dart` loads the bundled fonts (and Material Icons) through
  `FontLoader`, so goldens render real Arabic glyphs.
- **Tolerance:** it installs a comparator that tolerates up to 0.1% of pixels differing, to absorb
  sub-pixel noise between the Arch dev machine and `ubuntu-latest`.
- **Mismatch:** if the first CI run disagrees with local goldens beyond that, the reference images are
  regenerated with the `update-goldens` dispatch job, and CI becomes the source of truth.

## Repository settings (owner, one time)

Protect `master` and make `check` and `build-android` required checks. This is a manual step in
GitHub settings and is not done by code.
