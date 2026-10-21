"""Pieces and the money tables (RULES.md §14, glossary §3.2), ported from `money_test.dart`."""

from __future__ import annotations

import pytest
from wassal_content.canonical import canonical_text

from wassal_solver.engine.money import (
    BREAK_DOWN_TABLE,
    CHANGE_BAG,
    DENOMINATIONS,
    EMPTY,
    Pieces,
    break_down,
    change_request_pieces,
    fewest_pieces,
    is_denomination,
    scale,
)


def p(counts: dict[int, int]) -> Pieces:
    return Pieces.of(counts)


class TestPieces:
    def test_adds_removes_and_totals(self) -> None:
        pieces = p({100: 2, 50: 1})
        assert pieces.total == 250
        assert pieces.length == 3
        assert pieces.plus_one(500).total == 750
        assert pieces.plus(p({100: 1})).count(100) == 3
        assert pieces.minus_one(100).count(100) == 1
        assert pieces.minus(p({100: 2})) == p({50: 1})
        assert pieces.minus(pieces).is_empty
        assert pieces.contains(p({100: 2}))
        assert not pieces.contains(p({100: 3}))

    def test_removing_a_missing_piece_is_an_error(self) -> None:
        with pytest.raises(ValueError, match="not all held"):
            p({100: 1}).minus_one(50)
        with pytest.raises(ValueError, match="not all held"):
            p({100: 1}).minus(p({100: 2}))

    def test_holds_only_denominations_each_at_least_once(self) -> None:
        with pytest.raises(ValueError, match="not a denomination"):
            p({300: 1})
        with pytest.raises(ValueError, match="below 1"):
            p({100: 0})
        with pytest.raises(ValueError, match="not a denomination"):
            Pieces.of_list([100, 25])
        with pytest.raises(ValueError, match="not a denomination"):
            p({True: 1})

    def test_is_in_ascending_order(self) -> None:
        pieces = p({1000: 1, 50: 2, 500: 1})
        assert list(pieces.to_json()) == ["50", "500", "1000"]
        assert pieces.to_list() == [50, 50, 500, 1000]
        assert Pieces.of_list([500, 50, 50]) == p({50: 2, 500: 1})
        with pytest.raises(AttributeError):
            pieces.total = 1  # type: ignore[misc]

    def test_has_a_canonical_json_form(self) -> None:
        assert p({100: 2}).to_json() == {"100": 2}
        assert canonical_text(p({50: 1, 100: 2}).to_json()) == '{"100":2,"50":1}'
        assert Pieces.from_json({"100": 2, "50": 1}) == p({50: 1, 100: 2})
        assert EMPTY.to_json() == {}
        assert EMPTY.is_empty
        assert EMPTY.total == 0

    @pytest.mark.parametrize(
        "bad", [{"300": 1}, {"100": 0}, {"100": "2"}, {"abc": 1}, {"100": True}, {"100": 2.0}]
    )
    def test_from_json_refuses_bad_keys_and_counts(self, bad: dict[str, object]) -> None:
        with pytest.raises(ValueError):  # noqa: PT011 - each case has its own message
            Pieces.from_json(bad)


def test_is_denomination() -> None:
    assert DENOMINATIONS == (50, 100, 500, 1000, 2000, 5000, 10000, 20000)
    assert all(is_denomination(d) for d in DENOMINATIONS)
    assert not is_denomination(300)
    assert not is_denomination(0)
    assert not is_denomination(True)


def test_scale_is_integer_percent() -> None:
    assert scale(1100, 150) == 1650
    assert scale(100, 33) == 33
    assert scale(33, 150) == 49
    for x, pct in [(0, 1), (1, 1), (999, 999), (1500, 1000), (77, 3)]:
        assert scale(x, pct) == x * pct // 100


class TestFewestPieces:
    def test_4150_is_2000x2_100_and_50(self) -> None:
        assert fewest_pieces(4150) == p({2000: 2, 100: 1, 50: 1})

    def test_50_is_one_coin_0_is_nothing(self) -> None:
        assert fewest_pieces(50) == p({50: 1})
        assert fewest_pieces(0) == EMPTY

    def test_the_largest_note_comes_first(self) -> None:
        assert fewest_pieces(37950) == p(
            {20000: 1, 10000: 1, 5000: 1, 2000: 1, 500: 1, 100: 4, 50: 1}
        )

    def test_refuses_amounts_that_are_not_multiples_of_50(self) -> None:
        with pytest.raises(ValueError, match="multiple of 50"):
            fewest_pieces(75)
        with pytest.raises(ValueError, match="multiple of 50"):
            fewest_pieces(-50)


class TestBreakDown:
    def test_every_row_totals_its_note(self) -> None:
        assert sorted(BREAK_DOWN_TABLE) == [1000, 2000, 5000, 10000, 20000]
        for note in BREAK_DOWN_TABLE:
            row = break_down(note)
            assert row is not None
            assert row.total == note

    def test_the_rows(self) -> None:
        assert break_down(1000) == p({500: 1, 100: 4, 50: 2})
        assert break_down(2000) == p({1000: 1, 500: 1, 100: 4, 50: 2})
        assert break_down(5000) == p({2000: 2, 500: 1, 100: 4, 50: 2})
        assert break_down(10000) == p({5000: 1, 2000: 2, 500: 1, 100: 4, 50: 2})
        assert break_down(20000) == p({10000: 1, 5000: 1, 2000: 2, 500: 1, 100: 4, 50: 2})

    def test_500_and_the_coins_have_no_row(self) -> None:
        assert break_down(500) is None
        assert break_down(100) is None
        assert break_down(50) is None


def test_the_change_bag_is_50x2_100x3_and_500x2() -> None:
    assert p({50: 2, 100: 3, 500: 2}) == CHANGE_BAG


class TestChangeRequestPieces:
    def test_1000_from_500x1_100x5(self) -> None:
        assert change_request_pieces(1000, p({500: 1, 100: 5})) == p({500: 1, 100: 5})

    def test_1000_from_500x1_100x4_has_no_selection(self) -> None:
        assert change_request_pieces(1000, p({500: 1, 100: 4})) is None

    def test_5000_from_2000x2_500x1_100x5(self) -> None:
        tray = p({2000: 2, 500: 1, 100: 5})
        assert change_request_pieces(5000, tray) == tray

    def test_1000_from_500x1_100x3_50x4(self) -> None:
        tray = p({500: 1, 100: 3, 50: 4})
        assert change_request_pieces(1000, tray) == tray

    def test_backtracking_finds_what_greedy_misses(self) -> None:
        # Greedy takes the 5000 and then can't make the last 1000 from 2000s.
        assert change_request_pieces(10000, p({5000: 1, 2000: 5})) == p({2000: 5})

    def test_the_note_itself_is_never_used(self) -> None:
        assert change_request_pieces(1000, p({1000: 3})) is None

    def test_the_most_of_each_denomination_is_tried_first(self) -> None:
        assert change_request_pieces(1000, p({500: 2, 100: 10, 50: 20})) == p({500: 2})

    def test_a_large_tray_with_no_selection_is_answered_quickly(self) -> None:
        tray = p({10000: 1, 5000: 3, 2000: 9, 500: 39, 100: 4, 50: 1})
        assert change_request_pieces(20000, p({500: 39, 100: 4, 50: 1})) is None
        found = change_request_pieces(20000, tray)
        assert found is not None
        assert found.total == 20000
