"""Plain-text forms of results, for the commands' output (contracts/cli.md)."""

from __future__ import annotations

from wassal_solver.scoring.difficulty import Band, in_band
from wassal_solver.solver import SolverResult, Verdict
from wassal_solver.solver.timeline import TimelineEntry

__all__ = ["seconds", "show_result"]

_MS = 1000


def seconds(t_ms: int) -> str:
    """`30030` → `30.030 s`, without floats."""
    return f"{t_ms // _MS}.{t_ms % _MS:03d} s"


def show_result(result: SolverResult, band: Band | None) -> list[str]:
    """The lines that describe one result: the verdict, then the score, the first loss and the
    timeline, or the refusals."""
    lines = [_headline(result)]
    if result.verdict is Verdict.REFUSED:
        lines.extend(f"  {refusal}" for refusal in result.refusals or ())
        return lines
    score = result.score
    if score is not None:
        parts = ", ".join(f"{name} {p.value} → {p.points}" for name, p in score.inputs)
        lines.append(f"  score {score.value}{_band(score.value, band)}: {parts}")
    loss = result.first_loss
    if loss is not None:
        where = ", ".join(x for x in (loss.passenger_id, loss.station_id) if x is not None)
        place = f" ({where})" if where else ""
        lines.append(f"  first {loss.kind} at {seconds(loss.t_ms)}{place}: {loss.detail}")
    lines.extend(f"  {_entry(entry)}" for entry in result.timeline)
    return lines


def _headline(result: SolverResult) -> str:
    head = f"{result.trip_id} (rev {result.rev}): {result.verdict.value}"
    if result.verdict is Verdict.REFUSED:
        return head
    return f"{head}, {result.end.value}, {result.stars} stars, {result.effort_steps} steps"


def _band(score: int, band: Band | None) -> str:
    if band is None:
        return ""
    verdict = "in band" if in_band(score, band) else "OUTSIDE the band"
    return f" ({verdict} {band.min} to {band.max})"


def _entry(entry: TimelineEntry) -> str:
    parts = [f"{seconds(entry.t_ms):>10}", f"{entry.decision:<22}"]
    if entry.passenger_id is not None:
        parts.append(entry.passenger_id)
    if entry.amount_piasters is not None:
        parts.append(str(entry.amount_piasters))
    if entry.pieces is not None:
        parts.append("+".join(str(piece) for piece in reversed(entry.pieces.to_list())))
    if entry.note is not None:
        parts.append(entry.note)
    return " ".join(parts).rstrip()
