"""Source guards for the mirror, the solver and the score (research R2, constitution I and II).

Every module under `engine/`, `solver/` and `scoring/` is parsed, and integer-only, I/O-free code
is enforced: no float, no true division, no power, no randomness, no clock, no files. The one
exception is `time.monotonic` in `solver/search.py`, for the safety cap. Fixture files are read and
written in `wassal_solver.fixture_files`, outside the scan.
"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest

from tests.paths import PACKAGE_ROOT

PACKAGE = PACKAGE_ROOT / "src" / "wassal_solver"
SCANNED = ("engine", "solver", "scoring")
FORBIDDEN_MODULES = frozenset(
    {"random", "math", "time", "datetime", "os", "io", "pathlib", "socket", "json"}
)
FORBIDDEN_CALLS = frozenset({"float", "open", "hash", "id"})
# (module, file relative to the package) → the only name it may import.
ALLOWED = {("time", "solver/search.py"): "monotonic"}


def _sources() -> list[Path]:
    return sorted(path for area in SCANNED for path in (PACKAGE / area).rglob("*.py"))


def _relative(path: Path) -> str:
    return path.relative_to(PACKAGE).as_posix()


def violations(source: str, relative: str) -> list[str]:
    """Every forbidden construct in `source`, as `file:line: what`."""
    found: list[tuple[int, int, str]] = []

    def flag(node: ast.AST, what: str) -> None:
        found.append((getattr(node, "lineno", 0), getattr(node, "col_offset", 0), what))

    for node in ast.walk(ast.parse(source, filename=relative)):
        if isinstance(node, ast.Constant) and isinstance(node.value, float):
            flag(node, f"float literal {node.value!r}")
        elif isinstance(node, ast.BinOp | ast.AugAssign) and isinstance(node.op, ast.Div | ast.Pow):
            flag(node, f"operator {type(node.op).__name__}")
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            if node.func.id in FORBIDDEN_CALLS:
                flag(node, f"call to {node.func.id}()")
        elif isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name.split(".")[0] in FORBIDDEN_MODULES:
                    flag(node, f"import {alias.name}")
        elif isinstance(node, ast.ImportFrom) and node.module is not None and node.level == 0:
            root = node.module.split(".")[0]
            if root not in FORBIDDEN_MODULES:
                continue
            allowed = ALLOWED.get((root, relative))
            for alias in node.names:
                if alias.name != allowed:
                    flag(node, f"from {node.module} import {alias.name}")
    return [f"{relative}:{line}: {what}" for line, _, what in sorted(found)]


def test_the_scan_covers_every_area() -> None:
    sources = _sources()
    for area in SCANNED:
        assert any(_relative(path).startswith(f"{area}/") for path in sources), area


@pytest.mark.parametrize("path", _sources(), ids=_relative)
def test_integer_only_and_no_io(path: Path) -> None:
    assert violations(path.read_text(encoding="utf-8"), _relative(path)) == []


def test_the_scan_catches_each_construct() -> None:
    source = (
        "import json\n"
        "from time import monotonic\n"
        "x = 1.5\n"
        "y = 3 / 2\n"
        "y /= 2\n"
        "z = 2 ** 3\n"
        "w = float(3)\n"
        "v = open('f')\n"
        "u = hash(1) + id(2)\n"
        "t = 7 // 2\n"
    )
    found = violations(source, "engine/probe.py")
    assert [line.split(": ", 1)[1] for line in found] == [
        "import json",
        "from time import monotonic",
        "float literal 1.5",
        "operator Div",
        "operator Div",
        "operator Pow",
        "call to float()",
        "call to open()",
        "call to hash()",
        "call to id()",
    ]
    assert found[0].startswith("engine/probe.py:1: ")


def test_monotonic_is_allowed_only_in_the_search() -> None:
    assert violations("from time import monotonic\n", "solver/search.py") == []
    assert violations("from time import sleep\n", "solver/search.py") != []
    assert violations("from time import monotonic\n", "solver/result.py") != []
