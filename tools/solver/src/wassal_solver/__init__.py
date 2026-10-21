"""wassal-solver (B05): the Python mirror of the trip rules, the solver and the difficulty score.

The contracts are in `specs/005-b05-solver-parity/contracts/`.
"""

from wassal_solver.scoring.difficulty import Band, Score, in_band, score_trip
from wassal_solver.settings import SolverSettings, load_settings
from wassal_solver.solver import SolverResult, Verdict, solve
from wassal_solver.tunables import bundled_params

__all__ = [
    "Band",
    "Score",
    "SolverResult",
    "SolverSettings",
    "Verdict",
    "bundled_params",
    "in_band",
    "load_settings",
    "score_trip",
    "solve",
]
