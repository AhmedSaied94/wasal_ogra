"""`wassal-solver parity` and `sync` (contracts/cli.md): output and exit codes."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from tests.paths import APP_TUNABLES, FIXTURES, PACKAGE_ROOT
from wassal_solver.cli import main

FIXTURE = "core__exact_change.json"


def test_parity_on_the_fixtures_prints_ok_and_exits_0(capsys: pytest.CaptureFixture[str]) -> None:
    count = len(list(FIXTURES.glob("*.json")))
    assert main(["parity", str(FIXTURES)]) == 0
    assert capsys.readouterr().out == f"ok {count}\n"


def test_parity_defaults_to_the_repositorys_fixtures(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.chdir(PACKAGE_ROOT)
    assert main(["parity"]) == 0
    assert capsys.readouterr().out.startswith("ok ")


def test_parity_reports_a_mismatch_and_exits_1(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    document = json.loads((FIXTURES / FIXTURE).read_text(encoding="utf-8"))
    stars = document["expected_result"]["stars"]
    document["expected_result"]["stars"] = stars - 1
    edited = tmp_path / FIXTURE
    edited.write_text(json.dumps(document), encoding="utf-8")
    shutil.copy(FIXTURES / "core__left_unpaid.json", tmp_path)
    assert main(["parity", str(tmp_path)]) == 1
    assert capsys.readouterr().out == (
        f"{edited}\n"
        "  path:     $.stars\n"
        f"  expected: {stars - 1}\n"
        f"  actual:   {stars}\n"
        "failed 1 of 2\n"
    )


def test_parity_on_an_unreadable_fixture_exits_1(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / "broken.json").write_text('{"seed": 1.5}', encoding="utf-8")
    (tmp_path / "short.json").write_text('{"seed": 1}', encoding="utf-8")
    assert main(["parity", str(tmp_path / "broken.json"), str(tmp_path / "short.json")]) == 1
    out = capsys.readouterr().out
    assert "ContentLoadError" in out
    assert "FixtureError" in out
    assert out.endswith("failed 2 of 2\n")


def test_parity_on_a_missing_path_or_a_bad_option_exits_2(tmp_path: Path) -> None:
    assert main(["parity", str(tmp_path / "nowhere")]) == 2
    assert main(["parity", "--fast"]) == 2
    assert main([]) == 2
    assert main(["fly"]) == 2


def _repo(tmp_path: Path, copy: bytes | None) -> Path:
    (tmp_path / ".fvmrc").write_text("{}", encoding="utf-8")
    app = tmp_path / "apps" / "mobile" / "assets" / "config"
    app.mkdir(parents=True)
    shutil.copy(APP_TUNABLES, app / "tunables.json")
    data = tmp_path / "tools" / "solver" / "src" / "wassal_solver" / "data"
    data.mkdir(parents=True)
    if copy is not None:
        (data / "tunables.json").write_bytes(copy)
    return data / "tunables.json"


def test_sync_check_passes_when_the_copy_is_current(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _repo(tmp_path, APP_TUNABLES.read_bytes())
    monkeypatch.chdir(tmp_path / "tools" / "solver")
    assert main(["sync", "--check"]) == 0


def test_sync_check_fails_when_the_copy_differs_or_is_missing(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    copy = _repo(tmp_path, APP_TUNABLES.read_bytes().replace(b"1300", b"6000", 1))
    monkeypatch.chdir(tmp_path / "tools" / "solver")
    assert main(["sync", "--check"]) == 1
    copy.unlink()
    assert main(["sync", "--check"]) == 1


def test_sync_rewrites_the_copy_byte_for_byte(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    copy = _repo(tmp_path, b"{}")
    monkeypatch.chdir(tmp_path / "tools" / "solver")
    assert main(["sync"]) == 0
    assert copy.read_bytes() == APP_TUNABLES.read_bytes()
    assert main(["sync", "--check"]) == 0


def test_sync_outside_a_repository_exits_2(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.chdir(tmp_path)
    assert main(["sync"]) == 2


def test_the_packaged_copy_is_current() -> None:
    packaged = PACKAGE_ROOT / "src" / "wassal_solver" / "data" / "tunables.json"
    assert packaged.read_bytes() == APP_TUNABLES.read_bytes()


def test_the_command_is_installed() -> None:
    script = Path(sys.executable).with_name("wassal-solver")
    done = subprocess.run(
        [str(script), "parity", str(FIXTURES / FIXTURE)],
        cwd=PACKAGE_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert done.returncode == 0, done.stderr
    assert done.stdout == "ok 1\n"
