"""The hajja (RULES.md §5.4), ported from `hajja_test.dart`: a hop she passes on lasts
`scale(trip_hop_ms, trip_hop_pct_hajja)`; a hop to her takes the usual time.

The events are checked as the state they leave (research R3).
"""

from __future__ import annotations

from wassal_content.models import LineId, VehicleId

from tests.engine.archetypes.watch import hops
from tests.support.builders import TripBuilder
from tests.support.scripts import ok, passenger, start_trip
from wassal_solver.engine.commands import PickFromTray, SendHand


def test_her_own_fare_hops_at_2600_ms_on_line_hay_and_her_coins_reach_the_tray() -> None:
    trip = start_trip(
        TripBuilder(vehicle=VehicleId.TUKTUK, line=LineId.LINE_HAY)
        .station("madrasa", 30)
        .passenger(
            "p1", seat="A_r", dest="madrasa", payment=[500, 100, 100], pays_at=1, archetype="hajja"
        )
        .build()
    )
    tray_before = trip.state.tray.total
    # 2600 ms is 79 steps from 1023.
    assert hops(trip, 3597) == [("p1>DRIVER", 2600)]
    assert trip.state.tray.total == tray_before, "nothing has arrived"
    trip.step()
    assert trip.t_ms == 3630
    assert trip.state.tray.total == tray_before + 700


def test_as_a_middle_holder_only_the_hop_out_of_her_seat_is_slow() -> None:
    trip = start_trip(
        TripBuilder()
        .station("gamaa", 40)
        .passenger("p1", seat="C_r", dest="gamaa", payment=[1000], pays_at=1)
        .passenger("p2", seat="B_r", dest="gamaa", payment=[500, 100, 100], archetype="hajja")
        .build()
    )
    assert hops(trip, 6000) == [("p1>p2", 1100), ("p2>DRIVER", 2200)]
    for piece in (100, 100, 100):
        ok(trip, PickFromTray(piece))
    ok(trip, SendHand("p1"))
    assert hops(trip, 12000) == [("DRIVER>p2", 1100), ("p2>p1", 2200)]
    assert passenger(trip, "p1").balance == 0, "exact change"
    assert trip.state.mistakes == []
