# docs/design: the visual design

This folder is the design handoff for Style C, «كرتون ناعم» (soft cartoon). It replaced the
«ستيكر الميكروباص» style on 2026-10-23 (owner decision). [HANDOFF.md](HANDOFF.md) is the spec, and
the rest of the folder is its material:

| Path | What it is |
| --- | --- |
| `HANDOFF.md` | Tokens, components, the trip screen's geometry, characters, motion, navigation, accessibility, and one section per screen (§11) |
| `screens/<Artboard>.html` | The exported artboards: exact sizes, colours, radii, copy and icon art. Open one at 390 px wide. |
| `png/<Artboard>.png` | The same artboards at 2x, for comparing goldens |
| `boxes/<Artboard>.json` | Every visible box, measured: position, size, colour and token, font, radius, shadow. Layout tests check against these. |
| `tokens.json` | Every colour, type style, radius, lip, layout and motion value. The app's tokens are generated from it. |
| `icons/`, `illustrations/` | SVG icons and art: passengers, characters, passenger states, vehicles |
| `lottie/` | Motion reference only (see below). `lottie/index.html` plays every file and segment. |
| `brand/` | The app icon (direction أ) and its layers, the logo and its rules, the Play feature graphic ([brand/README.md](brand/README.md)) |
| `tools/` | Scripts that rebuild this folder from the design canvas ([tools/README.md](tools/README.md)) |

The living design is the canvas «وصّل الأجرة — Design»
(<https://claude.ai/artifact/9h9GpTSHVQXvsHUmgP8ixZ>). This folder is a snapshot of it.

## Who follows it

Feature 008.5 (M21, `specs/008.5-m21-design-refresh/`) moves everything built before it to this
design: the tokens, the components, the shell, the boot screen and the trip screen. Every feature
after it builds its screens from this folder. The delivery plan lists which artboards belong to which
feature ([Design sources](../delivery-plan.md#design-sources)).

## Project overrides

HANDOFF.md was written against the docs as they stood before M01. These rules win over it.

1. **Rive only, no Lottie.** The constitution locks Rive for characters (Platform constraints,
   "Locked stack"). HANDOFF §6 agrees, except for its Lottie fallback: §6.6's step 2 and its
   "Lottie fallback" paragraph don't apply. The `lottie`, `flame_lottie` and `dotlottie_loader`
   packages are not added.
   - The states keep their names and meaning: the passenger states of HANDOFF §5.4 and the segment
     list of §6.3, including which ones loop and which play once. 008.5's character contract
     (`specs/008.5-m21-design-refresh/contracts/rive-characters.md`) describes `wassal.riv` as
     delivered. Where it differs from HANDOFF §6.1–§6.5, the contract wins.
   - The files in `lottie/` show the timing and what moves in each state. `illustrations/` is the
     art, and the static fallback of HANDOFF §6.6 ("Last resort").
   - The performance gate of HANDOFF §6.6 applies to the Rive scene, without its Lottie step: rows
     that miss the gate fall back to the static art.
   - The Rive files live in the app, as `apps/mobile/assets/rive/wassal.riv` and
     `apps/mobile/assets/rive/wassal_scenes.riv`. This folder has no `rive/`; HANDOFF's `rive/`
     paths (§1's tree, §6, §6.8) mean those files. The comic panels' file belongs to 012.5
     (`specs/012.5-m22-animated-scenes/`). Its six panels are the opening's three and the سلمى
     scene's three, not "six opening" panels as §1's tree and §6.8 say.
   - Both files load with `riveFactory: Factory.flutter`, not §6.1's `Factory.rive`: it is the only
     factory that draws inside Flame and in Linux `flutter test` (M02 research R1).
2. **Identifiers come from the glossary.** The Shared Contract Glossary (architecture §3) names
   lines, vehicles, archetypes and every other id. The names in HANDOFF are art file names:
   - Vehicles: `microbus_old`, `microbus_new` and `microbus_travel` are `micro_old`, `micro_new` and
     `micro_safar`.
   - Passengers: the ids in HANDOFF §5.3 are looks (a trip's `skin`), not archetypes. For example,
     `hagga` is the look of archetype `hajja`, and `effendi_200` is the look of `big_note`. 008.5
     decides how skins map to the Rive files.
3. **Which source wins.** For anything you see (sizes, colours, radii, copy), the order is the
   artboard HTML, then HANDOFF.md, then the ux-spec, as HANDOFF §0 says. For behaviour, the order is
   the constitution, then the decisions of merged features (their `research.md`, recorded in the
   architecture docs), then HANDOFF.md, then the ux-spec. HANDOFF's notes cite older numbers that
   merged features have since changed, such as the 390×470 scene, the resume policy and the ad
   rules. Record every conflict you settle in the feature's `research.md` and its PR description.
4. **Open questions have owners.** HANDOFF §9.3's open product questions are assigned to features in
   the delivery plan. Don't settle one in a feature that doesn't own it.
5. **Sample data.** Every number and name in the artboards is sample data (HANDOFF §0). Prices, fares
   and rewards come from content packs and tunables, and store prices from the store.

## Checking a screen against the design

Every screen built from an artboard is checked three ways. The full contract, with its tables of
skips, pairings and expected differences, is
[specs/008.5-m21-design-refresh/contracts/design-checks.md](../../specs/008.5-m21-design-refresh/contracts/design-checks.md).

1. **A sample builder**, `apps/mobile/test/design/samples/<artboard>.dart`. It builds the screen in
   the artboard's sample state with fakes and the board's texts, at the artboard's size, RTL.
2. **A golden**, `apps/mobile/test/goldens/design/<artboard>_goldens_test.dart`. It renders the
   sample in both digit styles, to `test/goldens/design/goldens/<artboard>_<digits>.png`, which sit
   beside `png/<artboard>.png` for review. CI's `update_goldens` run covers them, and CI's images are
   the reference.
3. **A layout test**, `apps/mobile/test/design/<artboard>_layout_test.dart`. Every box in
   `boxes/<artboard>.json` whose role is `tap` must match one tappable in the sample, within ±2 pt,
   found by its label (or its text). Each skip and pairing gives its reason in the test, and every
   tappable the box file lacks must be listed as app-only. Moving or removing a box makes the test
   fail, naming the box (`test/design/drift_detection_test.dart` proves it).

To compare by eye, run, from `apps/mobile`:

```sh
fvm flutter test test/design test/goldens/design --dart-define=DESIGN_COMPARE=true
```

Each golden then also writes `apps/mobile/build/design_compare/<artboard>_<digits>.png`: the
design's PNG and the app's render side by side. Attach them to the PR, with the list of expected
differences (the contract's "What a golden may differ in", plus any the feature adds). Any other
visible difference is a bug, unless the owner accepts it in the PR.

A token change starts in `tokens.json`. Regenerate the app's tokens with
`fvm dart run tool/design/gen_tokens.dart` (from `apps/mobile`); `test/repo/design_tokens_test.dart`
fails until the generated file matches.

## Updating the design

When the canvas changes, rebuild this folder with `tools/` and review the diff in a PR. Keep this
README. If a new HANDOFF.md replaces this one, put back the banner at its top, and check the
overrides above still hold.
