"""Money: pieces of the glossary §3.2 denominations, and the fixed tables of RULES.md §14.

Mirrors `packages/trip_engine/lib/src/money.dart`. Every amount is integer piasters
(constitution II).
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass

DENOMINATIONS = (50, 100, 500, 1000, 2000, 5000, 10000, 20000)
"""The denominations, ascending."""

_INDEX = {denomination: i for i, denomination in enumerate(DENOMINATIONS)}
_ZERO = (0,) * len(DENOMINATIONS)
_PERCENT = 100


def is_denomination(piasters: object) -> bool:
    """Whether `piasters` is one of the denominations. A bool is not."""
    return type(piasters) is int and piasters in _INDEX


def scale(x: int, pct: int) -> int:
    """`x * pct // 100` (RULES.md §1.3)."""
    return x * pct // _PERCENT


@dataclass(frozen=True, slots=True)
class Pieces:
    """A multiset of denominations, as a count per denomination in ascending order."""

    counts: tuple[int, ...]
    """One count per entry of `DENOMINATIONS`, each at least 0."""
    total: int
    """The sum in piasters."""

    @staticmethod
    def of(counts: Mapping[int, int]) -> Pieces:
        """Pieces from denomination to count. Raises ValueError for anything that isn't a
        denomination, or a count below 1."""
        held = list(_ZERO)
        for denomination, count in counts.items():
            if not is_denomination(denomination):
                raise ValueError(f"{denomination!r} is not a denomination")
            if type(count) is not int or count < 1:
                raise ValueError(f"the count of {denomination} is {count!r}, below 1")
            held[_INDEX[denomination]] = count
        return _make(tuple(held))

    @staticmethod
    def of_list(pieces: Iterable[int]) -> Pieces:
        """Pieces from a list such as an authored payment."""
        held = list(_ZERO)
        for piece in pieces:
            if not is_denomination(piece):
                raise ValueError(f"{piece!r} is not a denomination")
            held[_INDEX[piece]] += 1
        return _make(tuple(held))

    @staticmethod
    def from_json(json: Mapping[str, object]) -> Pieces:
        """Pieces from their wire form, `{"100": 2}`. Raises ValueError."""
        counts: dict[int, int] = {}
        for key, value in json.items():
            denomination = int(key) if key.isascii() and key.isdigit() else None
            if denomination is None or not is_denomination(denomination):
                raise ValueError(f"not a denomination: {key}")
            if type(value) is not int or value < 1:
                raise ValueError(f"the count of {key} must be an integer ≥ 1")
            counts[denomination] = value
        return Pieces.of(counts)

    def count(self, denomination: int) -> int:
        index = _INDEX.get(denomination)
        return 0 if index is None else self.counts[index]

    @property
    def is_empty(self) -> bool:
        return self.total == 0

    @property
    def length(self) -> int:
        """The number of pieces."""
        return sum(self.counts)

    def contains(self, other: Pieces) -> bool:
        return all(mine >= theirs for mine, theirs in zip(self.counts, other.counts, strict=True))

    def plus(self, other: Pieces) -> Pieces:
        return Pieces(
            tuple(a + b for a, b in zip(self.counts, other.counts, strict=True)),
            self.total + other.total,
        )

    def plus_one(self, denomination: int) -> Pieces:
        index = _INDEX[denomination]
        counts = list(self.counts)
        counts[index] += 1
        return Pieces(tuple(counts), self.total + denomination)

    def minus(self, other: Pieces) -> Pieces:
        """These pieces without `other`. Raises ValueError if one is missing."""
        if not self.contains(other):
            raise ValueError(f"{other} is not all held in {self}")
        return Pieces(
            tuple(a - b for a, b in zip(self.counts, other.counts, strict=True)),
            self.total - other.total,
        )

    def minus_one(self, denomination: int) -> Pieces:
        index = _INDEX[denomination]
        if self.counts[index] < 1:
            raise ValueError(f"{denomination} is not all held in {self}")
        counts = list(self.counts)
        counts[index] -= 1
        return Pieces(tuple(counts), self.total - denomination)

    def to_list(self) -> list[int]:
        """Every piece, ascending."""
        return [
            d for d, count in zip(DENOMINATIONS, self.counts, strict=True) for _ in range(count)
        ]

    def to_json(self) -> dict[str, int]:
        """The wire form, in ascending order: `{"50": 1, "100": 2}`."""
        return {str(d): count for d, count in zip(DENOMINATIONS, self.counts, strict=True) if count}

    def __repr__(self) -> str:
        return f"Pieces({self.to_json()})"


def _make(counts: tuple[int, ...]) -> Pieces:
    return Pieces(counts, sum(d * n for d, n in zip(DENOMINATIONS, counts, strict=True)))


EMPTY = Pieces(_ZERO, 0)


def fewest_pieces(amount: int) -> Pieces:
    """The fewest pieces for `amount`, a multiple of 50 (§14.3): greedy from the largest
    denomination, with unlimited supply."""
    if amount < 0 or amount % DENOMINATIONS[0] != 0:
        raise ValueError(f"{amount} is not a multiple of 50 ≥ 0")
    rest = amount
    counts = list(_ZERO)
    for index in range(len(DENOMINATIONS) - 1, -1, -1):
        counts[index], rest = divmod(rest, DENOMINATIONS[index])
    return Pieces(tuple(counts), amount)


BREAK_DOWN_TABLE: Mapping[int, Mapping[int, int]] = {
    1000: {500: 1, 100: 4, 50: 2},
    2000: {1000: 1, 500: 1, 100: 4, 50: 2},
    5000: {2000: 2, 500: 1, 100: 4, 50: 2},
    10000: {5000: 1, 2000: 2, 500: 1, 100: 4, 50: 2},
    20000: {10000: 1, 5000: 1, 2000: 2, 500: 1, 100: 4, 50: 2},
}
"""What a note comes back as from «حد معاه فكة؟» (§14.1, M01 clarification 4)."""

_BREAK_DOWN = {note: Pieces.of(row) for note, row in BREAK_DOWN_TABLE.items()}


def break_down(note: int) -> Pieces | None:
    """The break-down of `note`, or None when it has no row."""
    return _BREAK_DOWN.get(note)


CHANGE_BAG = Pieces.of({50: 2, 100: 3, 500: 2})
"""The `change_bag` booster's contents (§14.2, glossary §3.3)."""


def change_request_pieces(note: int, tray: Pieces) -> Pieces | None:
    """The tray's pieces for a change request of `note` (§14.4).

    A depth-first search over the denominations below `note`, largest first, each count tried
    from the most available down. The first exact total wins. Branches that can't reach the total
    are cut, which never changes that answer.
    """
    options = [
        index for index in range(len(DENOMINATIONS) - 1, -1, -1) if DENOMINATIONS[index] < note
    ]
    # What the denominations from position i on can still make.
    reach = [0] * (len(options) + 1)
    for i in range(len(options) - 1, -1, -1):
        index = options[i]
        reach[i] = reach[i + 1] + DENOMINATIONS[index] * tray.counts[index]
    chosen = list(_ZERO)

    def search(i: int, rest: int) -> bool:
        if rest == 0:
            return True
        if i == len(options) or rest > reach[i]:
            return False
        index = options[i]
        denomination = DENOMINATIONS[index]
        most = min(tray.counts[index], rest // denomination)
        for count in range(most, -1, -1):
            chosen[index] = count
            if search(i + 1, rest - count * denomination):
                return True
        chosen[index] = 0
        return False

    return Pieces(tuple(chosen), note) if search(0, note) else None
