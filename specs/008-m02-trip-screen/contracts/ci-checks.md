# Contract: CI and Guards

What M02 adds to `.github/workflows/mobile.yml` and to the repo guards. Everything M03–M05 set up
keeps running unchanged.

## Workflow changes

| Job | Change | Why |
| --- | --- | --- |
| `app` | Before `flutter test`: `dart run rive_native:setup --verbose --clean --platform linux` in `apps/mobile` | Rive's Linux library for the character's contract test and goldens. `--clean` is required: a restored pub cache otherwise skips copying it into `build/` (research R2). |
| `app` | `python3 tool/sfx/generate.py && git diff --exit-code assets/audio/sfx` | The committed stand-in sounds are exactly what the script makes. `flame_audio` itself has no build step; tests use a fake `SfxPlayer`. |
| `build-android` | Nothing | `rive_native`'s Gradle task downloads the Android libraries before `preBuild`; `dart` comes from `flutter-action`. |
| `update-goldens` | The same setup step before `--update-goldens` | So the Rive goldens regenerate on the CI image. |

Network: the setup downloads a 33 MB zip (Linux) or 13 MB (Android), checked against its sha512.

## Guards

| Guard | Change |
| --- | --- |
| `domain_imports_test.dart` | Adds `lib/features/trip/domain` (allowed list in trip-records.md). |
| `economy_writes_test.dart` | The trip store and its provider file may import the database; only the trip store writes the trip tables. |
| `no_arabic_literals_test.dart`, `no_raw_style_values_test.dart`, `integer_money_test.dart` | Unchanged rules; they now cover `lib/features/trip/`. |
| `palette_test.dart` | The new tokens: `fare` (ink text ≥ 4.5:1, ΔL* ≥ 18 from `primary`), `bubbleWarn`, `bubbleFight`, `bubbleThanks` (their text ≥ 4.5:1), and the shirt colors. |
| `tunables_defaults_test.dart` | Unchanged: no new tunable. |
| New `test/repo/no_ads_in_trip_test.dart` | No file under `lib/features/trip/` imports an ad SDK or `core/ads/`. |
| New `test/repo/trip_text_in_canvas_test.dart` | No `TextPainter`, `TextComponent` or `TextBoxComponent` under `lib/features/trip/presentation/scene/` (constitution: text never in the canvas). |
| New `test/core/glossary/line_id_names_test.dart` | The glossary's `LineId` and `content_models`' `LineId` have the same value names (research R23). |

## Coverage

The app's gate stays at ≥ 80% lines (`tool/check_coverage.dart --min 80`), now including
`lib/features/trip/`.
