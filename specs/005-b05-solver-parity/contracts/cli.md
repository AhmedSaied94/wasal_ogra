# Contract: The `wassal-solver` Command

Run from `tools/solver` with `uv run wassal-solver …`. In the backend image, run it as
`wassal-solver …` inside the worker container. Every command exits `0` on success, `1` when a check
fails, and `2` on a usage error. Output is English, and readable as plain text.

| Command | Does | Exit 1 when |
| --- | --- | --- |
| `sync [--check]` | Copies `apps/mobile/assets/config/tunables.json` to `src/wassal_solver/data/tunables.json`. With `--check`, it only compares the two (research R5). | The copy differs, with `--check`. |
| `parity [PATH…]` | Replays every fixture: the given files or directories, `../../fixtures/parity` by default. Prints `ok <n>`, or one block per mismatch: the fixture, the JSON path, the expected value and the actual one. | Any mismatch, or an unreadable fixture. |
| `fixture TRIP.json… [--out DIR]` | Writes `solver__<trip>.json` for each trip (contracts/mirror.md §6). `DIR` defaults to `../../fixtures/parity`. | A trip isn't solved, or a file already exists. |
| `solve TRIP.json \| LAYOUT [--trip ID] [--json] [--reaction-ms N]` | Solves one trip, or every trip of a `content/source`-style layout. Prints the verdict, the end, the stars, the score (with its inputs and band) and the timeline. `--json` prints the canonical `SolverResult`s instead. `--reaction-ms` overrides the setting, for exploring. | Never. It reports. |
| `check-source LAYOUT [--bands error\|warning] [--json]` | Re-solves every trip in the layout with the bundled params (spec FR-039, FR-040). An empty layout (no `pack.json`) prints `no pack in <LAYOUT>`. | Any trip `not_solved` or `refused`, or any `end` ∈ `safety_cap`, `internal_error`. Also an out-of-band score with `--bands error`. With `warning`, it prints the score instead. |
| `report LAYOUT \| PACK.json.gz [--csv FILE]` | The balancing report (contracts/solver.md §6). It prints a table, and with `--csv`, also writes the CSV. | Never. |
| `bench [--digest]` | Solves the packaged bench corpus (50 trips, research R17), and prints each trip's time and the total. With `--digest`, it also prints `digest <sha256>` over the canonical results, in corpus order. | Never. |

**Notes.**

- `LAYOUT` is read with `wassal_content.source` (the `content/source` layout). A pack file is read
  with `wassal_content.packfile`, which verifies its gzip and parses it strictly.
- The band of a layout's trip comes from its line file.
- `solve` and `check-source` never write files. `fixture` writes only new files, and `sync` only its
  copy.
- Running a command doesn't need the backend, a database or the network.
