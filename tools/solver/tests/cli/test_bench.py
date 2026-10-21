"""`wassal-solver bench` (contracts/cli.md): each trip's time, the total, and the digest."""

from __future__ import annotations

import re

import pytest

import wassal_solver.cli as cli_module
from tests.support.solving import sample_trips
from wassal_solver.cli import main


@pytest.fixture
def small_corpus(monkeypatch: pytest.MonkeyPatch) -> None:
    """The bench over the five sample trips, so the test stays quick."""
    monkeypatch.setattr(cli_module, "bench_trips", sample_trips)


def test_the_bench_prints_each_trip_and_the_total(
    small_corpus: None, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["bench"]) == 0
    lines = capsys.readouterr().out.splitlines()
    assert len(lines) == 6
    assert all(
        re.match(r"line_\w+\.\d\d +solved +found +\d+ steps +\d+ ms$", line) for line in lines[:5]
    )
    assert re.match(r"total: 5 trips, 5 solved, \d+ ms$", lines[5])


def test_the_digest_is_identical_across_runs(
    small_corpus: None, capsys: pytest.CaptureFixture[str]
) -> None:
    digests = []
    for _ in range(2):
        assert main(["bench", "--digest"]) == 0
        last = capsys.readouterr().out.splitlines()[-1]
        assert re.match(r"digest [0-9a-f]{64}$", last)
        digests.append(last)
    assert digests[0] == digests[1]


def test_the_packaged_corpus_has_50_trips() -> None:
    trips = cli_module.bench_trips()
    assert len(trips) == 50
    assert [t.trip_id for t in trips] == sorted(t.trip_id for t in trips)
