# Contract: The Usta's Look

One look for the usta in every piece of art: the panels', with the lighter skin and the forelock.
Spec FR-020, FR-023, SC-007; research R12. The owner decided it on 2026-10-28 (spec
Clarifications), and updated the canvas's characters sheet and `wassal.riv`.

## The look

| Part | Before | After |
| --- | --- | --- |
| Skin | `#C68B5E` (the default passenger's) | `#E0A97A` |
| Hair | dark quiff | dark quiff with a forelock (the canvas sheet's extra path `M4 -52 Q22 -66 34 -50 Q20 -54 10 -46 Z`) |
| Shirt, collar | `primary`, white | unchanged |

HANDOFF §5.2 (rebuilt on 2026-10-28) gives the same: «dark quiff with a forelock, skin `#E0A97A`».

## Where it changes

| Art | File | How | Check |
| --- | --- | --- | --- |
| Rive, `look` 18 | `apps/mobile/assets/rive/wassal.riv` | the owner's export, already in the working tree | 008.5's contract test passes. On 2026-10-28 every other look and every vehicle rendered identical to the pixel. |
| The design's sheet | `docs/design/illustrations/characters/usta.svg`, `screens/Characters.html`, `png/Characters.png`, `boxes/Characters.json` | rebuilt from the canvas (below) | the diff review |
| Other artboards that draw the usta from the sheet | whichever the rebuild changes (candidates: `DeleteStep1`, `Album`, `SceneViewer`) | rebuilt from the canvas | the diff review |
| The motion reference | `docs/design/lottie/characters/usta.json` | the tools' step 4 | the diff review |
| The app's static usta | `apps/mobile/assets/illustrations/characters/usta.svg` | `fvm dart run tool/design/sync_assets.dart` | `design_assets_test` |
| The six panels | unchanged | they already draw the new look | the scene goldens don't change |

## Rebuilding `docs/design/`

`docs/design/tools/README.md`, with the canvas «وصّل الأجرة — Design»:

1. Download the canvas's `project/canvas.json` and `project/*.dc.html` with the Artifact tool into a
   scratch `design/project/`.
2. Run the tools' steps 1–5 into a scratch `out/`, then copy over `docs/design/`. Leave out
   `HANDOFF.md`: it is already rebuilt, with its banner restored (docs/design/README.md "Updating the
   design").
3. Review the diff:
   - expected: the usta's drawing and the files that draw it, and their PNGs and boxes;
   - anything else the canvas brings is listed for the owner and kept only on their word;
   - check that `README.md`'s overrides still hold (updated on 2026-10-28 for the new HANDOFF §6).
4. `sync_assets.dart`, then `design_assets_test`.

## Goldens that change

Only those that draw the usta, and only by his look:

| Test | What draws him |
| --- | --- |
| `test/features/trip/rive_art_goldens_test.dart` | the six story characters' sheet (`idle`, `talk`), Rive `look` 18 |
| `test/goldens/design/name_goldens_test.dart` | the Name card's `CharacterAvatar('usta')` |
| `test/core/theme/components/characters_test.dart` | wherever it renders the usta's avatar to a golden |
| the components and characters gallery goldens | wherever they draw the usta |

The tasks list every golden found by `grep` for `usta` in `test/`, and the PR shows each one beside
its old version. Any other golden that changes is a defect.

## What doesn't change

- The `look` table (008.5's contract): 18 is still `usta`.
- The other 23 people and the four vehicles, in Rive and in SVG.
- The scene panels' drawings and goldens.
