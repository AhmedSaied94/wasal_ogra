"""The mirror: the Python copy of `packages/trip_engine/RULES.md` (contracts/mirror.md).

It reproduces state, results, the fingerprint, rejections and refusals, but not events, speech,
the PRNG, pause and resume, or rebuild (research R3). Everything is integer and pure: no files,
clock or randomness (spec FR-002).
"""

from wassal_solver.engine.capabilities import SUPPORTED
from wassal_solver.engine.commands import Rejection, RejectionCode, command_log_hash
from wassal_solver.engine.params import TripParams
from wassal_solver.engine.replay import ReplayReason, ReplayRefused, replay, replay_untrusted
from wassal_solver.engine.trip import Trip, start
from wassal_solver.engine.validation import Refusal, TripRefused

__all__ = [
    "SUPPORTED",
    "Refusal",
    "Rejection",
    "RejectionCode",
    "ReplayReason",
    "ReplayRefused",
    "Trip",
    "TripParams",
    "TripRefused",
    "command_log_hash",
    "replay",
    "replay_untrusted",
    "start",
]
