r"""`wassal-solver`: the solver's commands (contracts/cli.md).

| Command | What it does |
| --- | --- |
| `sync [--check]` | Copy the app's tunables into the package, or check the copy (research R5) |
| `parity [PATH...]` | Replay every parity fixture through the mirror and compare its result |
| `fixture TRIP.json... [--out DIR]` | Write a `solver__` parity fixture for each trip |
| `solve TRIP.json \| LAYOUT [--trip ID] [--json] [--reaction-ms N]` | Solve trips and report |
| `check-source LAYOUT [--bands error\|warning] [--json]` | Re-solve a layout and check it |
| `report LAYOUT \| PACK.json.gz [--csv FILE]` | The balancing report |
| `bench [--digest]` | Solve the packaged bench corpus and time it |

Exit codes: 0 clean, 1 a check failed, 2 a usage error. The repository root is the nearest
directory above the working directory that holds `.fvmrc`.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import sys
import time
from collections.abc import Sequence
from importlib import resources
from pathlib import Path

from wassal_content.canonical import canonical_bytes, canonical_text
from wassal_content.loader import ContentLoadError, load_json_bytes
from wassal_content.models import TripDefinition
from wassal_content.packfile import PackFileError, decompress_capped

from wassal_solver.engine.fixture import build_fixture, show_value
from wassal_solver.fixture_files import check_fixtures, write_fixture
from wassal_solver.inputs import (
    InputError,
    TripInput,
    read_layout_trips,
    read_trip_document,
    read_trip_file,
    read_trips,
)
from wassal_solver.report.balancing import render_table, report, write_csv
from wassal_solver.scoring.difficulty import in_band
from wassal_solver.settings import SolverSettings, load_settings
from wassal_solver.show import seconds, show_result
from wassal_solver.solver import SolverResult, Verdict, solve
from wassal_solver.tunables import APP_TUNABLES, PACKAGED_TUNABLES, bundled_params

__all__ = ["main"]

OK, FAILED, USAGE = 0, 1, 2
_FIXTURES = ("fixtures", "parity")
MAX_PACK_JSON_BYTES = 32 * 1024 * 1024
"""The most a pack file may decompress to, as the backend's promotion reads it."""


class UsageError(Exception):
    """A command was called wrongly."""


def find_repo_root(start: Path) -> Path:
    for directory in (start, *start.parents):
        if (directory / ".fvmrc").is_file():
            return directory
    raise UsageError(f"no repository root (a directory with .fvmrc) above {start}")


def _sync(args: argparse.Namespace) -> int:
    root = find_repo_root(Path.cwd())
    source = root.joinpath(*APP_TUNABLES)
    copy = root.joinpath(*PACKAGED_TUNABLES)
    wanted = source.read_bytes()
    if args.check:
        if copy.is_file() and copy.read_bytes() == wanted:
            print(f"sync: {copy.relative_to(root)} is up to date")
            return OK
        print(f"out of date: {copy.relative_to(root)}")
        print("run `uv run wassal-solver sync` in tools/solver and commit the result")
        return FAILED
    copy.write_bytes(wanted)
    print(f"wrote {copy.relative_to(root)}")
    return OK


def _fixture_paths(paths: Sequence[str]) -> list[Path]:
    if not paths:
        paths = [str(find_repo_root(Path.cwd()).joinpath(*_FIXTURES))]
    found: list[Path] = []
    for name in paths:
        path = Path(name)
        if path.is_dir():
            found += sorted(path.glob("*.json"))
        elif path.is_file():
            found.append(path)
        else:
            raise UsageError(f"no such file or directory: {name}")
    return found


def _parity(args: argparse.Namespace) -> int:
    paths = _fixture_paths(args.paths)
    mismatches = check_fixtures(paths)
    for mismatch in mismatches:
        print(mismatch.path)
        if mismatch.difference is not None:
            print(f"  path:     {mismatch.difference.path}")
            print(f"  expected: {show_value(mismatch.difference.expected)}")
            print(f"  actual:   {show_value(mismatch.difference.actual)}")
        else:
            print(f"  error:    {mismatch.error}")
    if mismatches:
        print(f"failed {len(mismatches)} of {len(paths)}")
        return FAILED
    print(f"ok {len(paths)}")
    return OK


def _fixture(args: argparse.Namespace) -> int:
    """Writes `solver__<trip>.json` for each trip (contracts/mirror.md §6): all of them, or none
    when a trip isn't solved or a file already exists."""
    out = Path(args.out) if args.out else find_repo_root(Path.cwd()).joinpath(*_FIXTURES)
    settings = load_settings()
    planned: list[tuple[Path, dict[str, object]]] = []
    problems: list[str] = []
    for name in args.trips:
        path = Path(name)
        definition = read_trip_file(path).definition
        params = bundled_params(definition.line_id)
        result = solve(definition, params, settings)
        target = out / f"solver__{definition.trip_id.replace('.', '_')}.json"
        if any(target == planned_target for planned_target, _ in planned):
            problems.append(f"{definition.trip_id} is given twice: not written")
        elif result.run is None:
            problems.append(
                f"{definition.trip_id}: {result.verdict.value}, {result.end.value}: not written"
            )
        elif target.exists():
            problems.append(f"{target} already exists: never overwritten")
        else:
            document = load_json_bytes(path.read_bytes())
            planned.append((target, build_fixture(document, params, result.run)))
    if problems:
        print("\n".join(problems))
        return FAILED
    for target, document in planned:
        write_fixture(target, document)
        print(f"wrote {target}")
    return OK


def _settings(args: argparse.Namespace) -> SolverSettings:
    settings = load_settings()
    reaction = getattr(args, "reaction_ms", None)
    if reaction is None:
        return settings
    if reaction < 0:
        raise UsageError("--reaction-ms must not be negative")
    return dataclasses.replace(settings, reaction_ms=reaction)


def _solve(args: argparse.Namespace) -> int:
    """Solves and reports. It never fails a check: every verdict exits 0."""
    trips = read_trips(Path(args.path), args.trip)
    settings = _settings(args)
    for trip in trips:
        definition = trip.definition
        result = solve(definition, bundled_params(definition.line_id), settings)
        if args.json:
            print(canonical_text(result.to_json()))
        else:
            print("\n".join(show_result(result, trip.band)))
    return OK


def _check_source(args: argparse.Namespace) -> int:
    """Re-solves every trip of a layout (FR-039, FR-040). Fails on any trip that isn't solved,
    and on an out-of-band score with `--bands error`."""
    root = Path(args.layout)
    if not root.is_dir():
        raise UsageError(f"{root} is not a layout directory")
    tree, trips = read_layout_trips(root)
    if tree.meta is None:
        print(f"no pack in {root}")
        return OK
    version = tree.meta.get("version")
    settings = load_settings()
    failed = 0
    for trip in trips:
        definition = trip.definition
        result = solve(definition, bundled_params(definition.line_id), settings)
        if args.json:
            print(canonical_text(result.to_json()))
        problem = _source_problem(result, trip, strict=args.bands == "error")
        if problem is None:
            if not args.json:
                print(_source_line(result, trip))
            continue
        failed += 1
        if not args.json:
            where = f"pack version {version}, trips/{definition.line_id}/{definition.trip_id}.json"
            print(f"FAILED {definition.trip_id} ({where}): {problem}")
    if failed:
        # With --json, stdout holds only results.
        print(f"failed {failed} of {len(trips)}", file=sys.stderr if args.json else sys.stdout)
        return FAILED
    if not args.json:
        print(f"ok {len(trips)}")
    return OK


def _source_problem(result: SolverResult, trip: TripInput, *, strict: bool) -> str | None:
    """Why `result` fails `check-source`, or None."""
    if result.verdict is Verdict.REFUSED:
        first = result.refusals[0] if result.refusals else None
        return f"refused: {first}"
    if not result.solved:
        loss = result.first_loss
        lost = "" if loss is None else f"; first {loss.kind} at {seconds(loss.t_ms)}"
        if loss is not None and (loss.passenger_id or loss.station_id):
            names = ", ".join(n for n in (loss.passenger_id, loss.station_id) if n)
            lost += f" ({names}): {loss.detail}"
        return f"{result.verdict.value}, {result.end.value}, best run {result.stars} stars{lost}"
    if strict and _outside(result, trip):
        return _band_warning(result, trip)
    return None


def _outside(result: SolverResult, trip: TripInput) -> bool:
    return (
        result.score is not None
        and trip.band is not None
        and not in_band(result.score.value, trip.band)
    )


def _band_warning(result: SolverResult, trip: TripInput) -> str:
    """The V-Z5 wording: the score, the band, and the inputs that give the most points."""
    score = result.score
    band = trip.band
    if score is None or band is None:
        return ""
    most = ", ".join(score.most())
    return (
        f"difficulty {score.value} is outside the line's band {band.min} to {band.max}; "
        f"most from {most}"
    )


def _source_line(result: SolverResult, trip: TripInput) -> str:
    line = f"{result.trip_id}: solved"
    if result.score is not None:
        line += f", score {result.score.value}"
    if _outside(result, trip):
        return f"warning: {result.trip_id}: {_band_warning(result, trip)}"
    if trip.band is not None:
        line += f" (in band {trip.band.min} to {trip.band.max})"
    return line


def _report(args: argparse.Namespace) -> int:
    """The balancing report of a layout or a pack file. It never fails a check."""
    path = Path(args.source)
    trips = _pack_trips(path) if path.is_file() else [t.definition for t in read_trips(path)]
    settings = load_settings()
    rows = report(trips, settings)
    print(render_table(rows, settings))
    if args.csv:
        with Path(args.csv).open("w", encoding="utf-8", newline="") as out:
            write_csv(rows, settings, out)
    return OK


def _pack_trips(path: Path) -> list[TripDefinition]:
    """The trips of a pack file, in pack order."""
    try:
        pack = load_json_bytes(decompress_capped(path.read_bytes(), max_bytes=MAX_PACK_JSON_BYTES))
    except (PackFileError, ContentLoadError) as error:
        raise UsageError(f"{path} is not a pack file: {error}") from None
    if not isinstance(pack, dict) or not isinstance(pack.get("trips"), list):
        raise UsageError(f"{path} is not a pack file: it has no trips")
    return [read_trip_document(trip, f"{path} trip {i}") for i, trip in enumerate(pack["trips"])]


def bench_trips() -> list[TripDefinition]:
    """The packaged bench corpus, in trip id order (research R17)."""
    corpus = resources.files("wassal_solver").joinpath("data", "bench")
    files = sorted((f for f in corpus.iterdir() if f.name.endswith(".json")), key=lambda f: f.name)
    return [read_trip_document(load_json_bytes(f.read_bytes()), f.name) for f in files]


def _bench(args: argparse.Namespace) -> int:
    """Solves the bench corpus: each trip's time and the total, and with `--digest` a SHA-256 over
    the canonical results in corpus order, which every machine must print alike (SC-005)."""
    settings = load_settings()
    digest = hashlib.sha256()
    trips = bench_trips()
    solved = 0
    started = time.perf_counter_ns()
    for definition in trips:
        begun = time.perf_counter_ns()
        result = solve(definition, bundled_params(definition.line_id), settings)
        spent = (time.perf_counter_ns() - begun) // 1_000_000
        solved += result.solved
        digest.update(canonical_bytes(result.to_json()) + b"\n")
        print(
            f"{definition.trip_id:<14} {result.verdict.value:<10} {result.end.value:<13} "
            f"{result.effort_steps} steps {spent:>6} ms"
        )
    total = (time.perf_counter_ns() - started) // 1_000_000
    print(f"total: {len(trips)} trips, {solved} solved, {total} ms")
    if args.digest:
        print(f"digest {digest.hexdigest()}")
    return OK


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="wassal-solver", description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    sync = commands.add_parser("sync", help="copy the app's tunables into the package")
    sync.add_argument("--check", action="store_true", help="only check that the copy is current")
    sync.set_defaults(run=_sync)
    parity = commands.add_parser("parity", help="replay the parity fixtures through the mirror")
    parity.add_argument("paths", nargs="*", metavar="PATH", help="fixture files or directories")
    parity.set_defaults(run=_parity)
    fixture = commands.add_parser("fixture", help="write solver parity fixtures")
    fixture.add_argument("trips", nargs="+", metavar="TRIP.json")
    fixture.add_argument("--out", metavar="DIR", help="default: the repository's fixtures/parity")
    fixture.set_defaults(run=_fixture)
    solve_ = commands.add_parser("solve", help="solve a trip, or every trip of a layout")
    solve_.add_argument("path", metavar="TRIP.json | LAYOUT")
    solve_.add_argument("--trip", metavar="ID", help="only this trip of the layout")
    solve_.add_argument("--json", action="store_true", help="print canonical results, one a line")
    solve_.add_argument("--reaction-ms", type=int, metavar="N", help="override the reaction time")
    solve_.set_defaults(run=_solve)
    check = commands.add_parser("check-source", help="re-solve every trip of a layout")
    check.add_argument("layout", metavar="LAYOUT")
    check.add_argument(
        "--bands",
        choices=("error", "warning"),
        default="warning",
        help="whether a score outside its line's band fails (default: warning)",
    )
    check.add_argument("--json", action="store_true", help="print canonical results, one a line")
    check.set_defaults(run=_check_source)
    report_ = commands.add_parser("report", help="the balancing report of a layout or a pack")
    report_.add_argument("source", metavar="LAYOUT | PACK.json.gz")
    report_.add_argument("--csv", metavar="FILE", help="also write the rows as CSV")
    report_.set_defaults(run=_report)
    bench = commands.add_parser("bench", help="solve and time the packaged bench corpus")
    bench.add_argument("--digest", action="store_true", help="also print a digest of the results")
    bench.set_defaults(run=_bench)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Run one command and return its exit code."""
    parser = _parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exit_:
        return USAGE if exit_.code else OK
    try:
        return int(args.run(args))
    except (UsageError, InputError) as error:
        print(f"error: {error}", file=sys.stderr)
        return USAGE
    except OSError as error:
        print(f"error: {error}", file=sys.stderr)
        return USAGE
