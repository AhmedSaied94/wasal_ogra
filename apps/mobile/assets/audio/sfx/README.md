# Trip sound effects (stand-ins)

The trip's sound effects: `coin`, `note_pass`, `call`, `horn`, `fight`, `thanks`, `wrong`, `bump` and
`alert` (specs/008-m02-trip-screen, research R18, contracts/trip-view.md "Stand-in effects").

- They are stand-ins, made by `tool/sfx/generate.py` from sines and noise. The project owns them, so
  they need no license.
- Each is a mono WAV, 22,050 Hz, 16-bit, at most 0.6 s.
- Never edit them by hand. Change the script and run `python3 tool/sfx/generate.py` from `apps/mobile`.
  CI runs it again and fails if the committed files differ from what it writes.
- The final sound set replaces them in the art pass, under the same names.
