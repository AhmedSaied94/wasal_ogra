# docs/design/tools

Scripts that rebuild this folder from the Claude Design canvas «وصّل الأجرة — Design». Run them when the canvas changes; never hand-edit the generated files.

Requirements: Python 3.11+, `pip install playwright pillow` (Chromium via `playwright install chromium`), Node 18+ for the browser fonts (`cd tools/fontpkg && npm i @fontsource/marhey@5.3.0 @fontsource/readex-pro@5.3.0`).

Input: the canvas files (`project/canvas.json` and `project/*.dc.html`). Claude can download them from the canvas with its Artifact tool; put them in `design/project/`.

| Step | Command | Writes |
| --- | --- | --- |
| 1. Artboards → HTML + PNG | `python3 export.py design/project out` | `screens/`, `png/`, `manifest.json` |
| 2. Measured boxes | `python3 boxes.py out && python3 boxes_post.py out tokens.json` | `boxes/` |
| 3. Icons + illustrations | `python3 build_assets.py design/project out icon_names.json` | `icons/`, `illustrations/` (new icons come out as `unnamed_<hash>.svg`: add a name to `icon_names.json` and rerun) |
| 4. People animations | `python3 gen_people.py out/illustrations out/lottie` | `lottie/passengers/`, `lottie/characters/` |
| 5. Vehicle + UI animations | `python3 gen_ui.py out out/lottie` | `lottie/vehicles/`, `lottie/ui/` |
| 6. Animation player | `python3 build_player.py out/lottie out/lottie/index.html ./lottie.min.js` (then wrap in a doctype as in this folder's `lottie/index.html`) | `lottie/index.html` |

`svg2lottie.py` is the shared SVG → Lottie converter (paths incl. arcs, circles, ellipses, rects, groups with transforms, fills, strokes, dashes). `gen_people.py` swaps each drawing's static face for the shared animated face set and adds the segment markers listed in HANDOFF §6.2; keep those names stable.

If an animator replaces a generated file with a hand-made one from Lottie Creator, keep the marker names and layer names from HANDOFF §6.2, and stop regenerating that file (delete it from step 4/5's output before copying).
