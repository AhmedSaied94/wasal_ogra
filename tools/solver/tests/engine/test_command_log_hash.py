"""The command-log fingerprint (M01 replay-and-fixtures.md §3), ported from
`fingerprint_test.dart`: lowercase hex SHA-256 of the log's canonical JSON, and the fingerprints
three fixtures pin, computed from their `command_log` alone.
"""

from __future__ import annotations

import pytest

from tests.paths import FIXTURES
from wassal_solver.engine import command_log_hash
from wassal_solver.engine.commands import LoggedCommand, PickFromTray, Tap, decode_log
from wassal_solver.fixture_files import load_fixture


def test_the_empty_log() -> None:
    assert (
        command_log_hash([]) == "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
    )


def test_a_two_command_log() -> None:
    log = [LoggedCommand(33, Tap("p2")), LoggedCommand(1089, PickFromTray(100))]
    assert command_log_hash(log) == (
        "2fc7facd65d1ed083cda40c815e6044ed3e58e41fdbaf0d7448bdc8129e45ed7"
    )


def test_any_change_to_the_log_changes_the_fingerprint() -> None:
    base = command_log_hash([LoggedCommand(33, Tap("p2"))])
    assert command_log_hash([LoggedCommand(66, Tap("p2"))]) != base
    assert command_log_hash([LoggedCommand(33, Tap("p3"))]) != base
    assert command_log_hash([LoggedCommand(33, Tap("p2"))]) == base


@pytest.mark.parametrize(
    "name",
    ["core__exact_change.json", "command__undo_last_send.json", "stress__longest_trip.json"],
)
def test_a_fixtures_fingerprint_comes_from_its_log_alone(name: str) -> None:
    document = load_fixture(FIXTURES / name)
    log = decode_log(document["command_log"])
    assert command_log_hash(log) == document["expected_result"]["command_log_hash"]
