"""The fingerprints (data-model.md "Fingerprints", research R12)."""

from __future__ import annotations

import hashlib
import re
import shutil
from pathlib import Path

from wassal_content.canonical import canonical_bytes
from wassal_content.models import TripDefinition

from tests.paths import PACKAGE_ROOT
from tests.support.builders import TripBuilder, default_params, definition_of, params_with
from wassal_solver.fingerprint import input_key, params_fingerprint, solver_fingerprint

HEX16 = re.compile(r"[0-9a-f]{16}\Z")
HEX64 = re.compile(r"[0-9a-f]{64}\Z")


def package_copy(tmp_path: Path) -> Path:
    root = tmp_path / "wassal_solver"
    shutil.copytree(
        PACKAGE_ROOT / "src" / "wassal_solver", root, ignore=shutil.ignore_patterns("__pycache__")
    )
    return root


def test_the_solver_fingerprint_is_16_hex_digits_and_stable() -> None:
    first = solver_fingerprint()
    assert HEX16.match(first)
    assert solver_fingerprint() == first


def test_the_solver_fingerprint_covers_the_package(tmp_path: Path) -> None:
    root = package_copy(tmp_path)
    before = solver_fingerprint(root)
    assert before == solver_fingerprint()
    search = root / "solver" / "search.py"
    search.write_text(search.read_text(encoding="utf-8") + "\n# changed\n", encoding="utf-8")
    assert solver_fingerprint(root) != before


def test_the_solver_fingerprint_covers_the_data_files(tmp_path: Path) -> None:
    root = package_copy(tmp_path)
    before = solver_fingerprint(root)
    settings = root / "data" / "settings.json"
    settings.write_text(settings.read_text(encoding="utf-8") + " ", encoding="utf-8")
    assert solver_fingerprint(root) != before


def test_the_solver_fingerprint_ignores_other_files(tmp_path: Path) -> None:
    root = package_copy(tmp_path)
    before = solver_fingerprint(root)
    (root / "notes.txt").write_text("not code", encoding="utf-8")
    (root / "__pycache__").mkdir(exist_ok=True)
    (root / "__pycache__" / "x.pyc").write_bytes(b"\0")
    assert solver_fingerprint(root) == before


def test_the_solver_fingerprint_names_the_files(tmp_path: Path) -> None:
    root = package_copy(tmp_path)
    before = solver_fingerprint(root)
    (root / "solver" / "search.py").rename(root / "solver" / "search2.py")
    assert solver_fingerprint(root) != before


def test_the_params_fingerprint_is_16_hex_digits_of_the_canonical_params() -> None:
    params = default_params("line_hay")
    expected = hashlib.sha256(canonical_bytes(params.to_json())).hexdigest()[:16]
    assert params_fingerprint(params) == expected
    assert HEX16.match(params_fingerprint(params))
    assert params_fingerprint(params_with({"trip_hop_ms": 1000}, "line_hay")) != expected


def trip(fare: int = 700) -> TripBuilder:
    return (
        TripBuilder()
        .station("gamaa", 30, fare=fare)
        .passenger("p1", seat="A_r", dest="gamaa", payment=[1000])
    )


def with_rev(builder: TripBuilder, rev: int) -> TripDefinition:
    document = builder.document()
    document["rev"] = rev
    return definition_of(document)


def test_the_input_key_is_64_hex_digits_and_ignores_the_rev() -> None:
    params = default_params()
    first = input_key(with_rev(trip(), 1), params)
    assert HEX64.match(first)
    assert input_key(with_rev(trip(), 7), params) == first


def test_the_input_key_changes_with_the_definition_the_params_and_the_solver() -> None:
    params = default_params()
    definition = trip().build()
    key = input_key(definition, params)
    assert input_key(trip(fare=650).build(), params) != key
    assert input_key(definition, params_with({"trip_hop_ms": 1000})) != key
    assert input_key(definition, params, solver="0" * 16) != key
    assert input_key(definition, params, solver=solver_fingerprint()) == key
