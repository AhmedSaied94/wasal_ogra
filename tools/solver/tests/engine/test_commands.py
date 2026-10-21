"""Commands on the wire, `[t_ms, "Name", ...args]` (M01 replay-and-fixtures.md §1).

Ported from `command_codec_test.dart`. Like Dart's decoder, `decode` doesn't check that a
denomination is one of glossary §3.2: the engine rejects it with `bad_argument`, so it can never be
in an accepted log. `decode_untrusted` refuses it outright (research R6).
"""

from __future__ import annotations

import json
from typing import Any

import pytest
from wassal_content.models import BoosterId

from wassal_solver.engine.commands import (
    COMMAND_NAMES,
    Abandon,
    CollectDropped,
    Command,
    CommandFormatError,
    LoggedCommand,
    PickFromTray,
    RejectionCode,
    RequestBreak,
    ResolveChangeRequest,
    ResolveClaim,
    ResolveDispute,
    ReturnHand,
    Revive,
    SendHand,
    Tap,
    UndoLastSend,
    UseBooster,
    decode,
    decode_log,
    decode_untrusted,
)

CASES: list[tuple[Command, list[Any]]] = [
    (PickFromTray(100), [330, "PickFromTray", 100]),
    (ReturnHand(), [363, "ReturnHand"]),
    (SendHand("p2"), [396, "SendHand", "p2"]),
    (UndoLastSend(), [429, "UndoLastSend"]),
    (Tap("p1"), [462, "Tap", "p1"]),
    (ResolveClaim("p4", insist=True), [990, "ResolveClaim", "p4", True]),
    (ResolveDispute(2, "p1"), [1650, "ResolveDispute", 2, "p1"]),
    (ResolveChangeRequest("p3", agree=False), [1683, "ResolveChangeRequest", "p3", False]),
    (RequestBreak(5000), [1716, "RequestBreak", 5000]),
    (CollectDropped(7), [1749, "CollectDropped", 7]),
    (UseBooster(BoosterId.WAKE_ALL), [2013, "UseBooster", "wake_all"]),
    (Revive(), [2046, "Revive"]),
    (Abandon(), [2079, "Abandon"]),
]

MALFORMED: list[Any] = [
    "Tap",
    [],
    [33],
    [33, "Fly"],
    [33, "Tap"],
    [33, "Tap", "p1", "p2"],
    [33, "Tap", 1],
    [33, "PickFromTray", "100"],
    [33, "PickFromTray", 100.0],
    [33, "PickFromTray", True],
    [33, "ResolveClaim", "p1", "yes"],
    [33, "ResolveClaim", "p1", 1],
    [33, "ResolveDispute", "2", "p1"],
    [33, "ResolveDispute", False, "p1"],
    [33, "UseBooster", "rocket"],
    [33, "UseBooster", 3],
    [-33, "ReturnHand"],
    [34, "ReturnHand"],
    ["33", "ReturnHand"],
    [33.0, "ReturnHand"],
    [True, "ReturnHand"],
    [33, 7],
    (33, "ReturnHand"),
]


def test_there_are_13_commands() -> None:
    assert {wire[1] for _, wire in CASES} == set(COMMAND_NAMES)
    assert len(COMMAND_NAMES) == 13


@pytest.mark.parametrize(("command", "wire"), CASES, ids=lambda value: str(value)[:24])
def test_each_command_encodes_and_decodes(command: Command, wire: list[Any]) -> None:
    logged = LoggedCommand(wire[0], command)
    assert logged.to_json() == wire
    decoded = decode(json.loads(json.dumps(wire)))
    assert decoded == logged
    assert decoded.t_ms == wire[0]
    assert decoded.command.name == wire[1]
    assert decoded.to_json() == wire
    assert decode_untrusted(wire) == logged


def test_a_booster_outside_the_in_trip_four_still_decodes_for_the_engine_to_reject() -> None:
    decoded = decode([33, "UseBooster", "revive"])
    assert decoded.command == UseBooster(BoosterId.REVIVE)


@pytest.mark.parametrize("bad", MALFORMED, ids=repr)
def test_a_malformed_entry_is_refused(bad: Any) -> None:
    with pytest.raises(CommandFormatError):
        decode(bad)
    with pytest.raises(CommandFormatError):
        decode_untrusted(bad)


@pytest.mark.parametrize(
    "entry", [[33, "PickFromTray", 300], [33, "RequestBreak", 25], [33, "PickFromTray", 0]]
)
def test_a_denomination_outside_the_glossary(entry: list[Any]) -> None:
    assert decode(entry).to_json() == entry
    with pytest.raises(CommandFormatError, match="not a denomination"):
        decode_untrusted(entry)


def test_a_log_decodes_as_a_list_of_entries() -> None:
    log = decode_log(json.loads('[[33,"Tap","p2"],[1089,"PickFromTray",100]]'))
    assert [entry.to_json() for entry in log] == [[33, "Tap", "p2"], [1089, "PickFromTray", 100]]
    with pytest.raises(CommandFormatError, match="a command log is a list"):
        decode_log({"not": "a list"})


def test_commands_are_frozen_and_hashable() -> None:
    command = Tap("p1")
    with pytest.raises(AttributeError):
        command.passenger_id = "p2"  # type: ignore[misc]
    assert {Tap("p1"), Tap("p1"), ReturnHand()} == {Tap("p1"), ReturnHand()}


def test_rejection_codes_have_the_engine_api_wire_names() -> None:
    assert [code.value for code in RejectionCode] == [
        "wrong_status",
        "command_limit",
        "bad_argument",
        "tray_empty",
        "hand_empty",
        "not_aboard",
        "undo_unavailable",
        "no_effect",
        "no_choice",
        "cannot_make_change",
        "break_limit",
        "booster_limit",
        "not_revivable",
    ]
