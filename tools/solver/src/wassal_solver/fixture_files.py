"""Reading and writing parity fixture files (contracts/mirror.md §5 and §6). The engine does no
I/O (spec FR-002): this module reads the bytes and hands parsed documents to
`wassal_solver.engine.fixture`, and writes the documents it builds.
"""

from __future__ import annotations

import json
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from wassal_content.loader import ContentLoadError, load_json_bytes

from wassal_solver.engine.fixture import Difference, FixtureError, check_fixture
from wassal_solver.engine.replay import ReplayRefused


def load_fixture(path: Path) -> Any:
    """The fixture at `path`, read as strict JSON: no floats, no duplicate keys."""
    return load_json_bytes(path.read_bytes())


@dataclass(frozen=True, slots=True)
class Mismatch:
    """A fixture that doesn't hold: its first difference, or why it couldn't be checked."""

    path: Path
    difference: Difference | None
    error: str | None

    def __str__(self) -> str:
        detail = str(self.difference) if self.difference is not None else self.error
        return f"{self.path.name}: {detail}"


def check_fixtures(paths: Iterable[Path]) -> list[Mismatch]:
    """The fixtures among `paths` that don't hold, in the order given."""
    out: list[Mismatch] = []
    for path in paths:
        try:
            difference = check_fixture(load_fixture(path))
        except (OSError, ContentLoadError, FixtureError, ReplayRefused) as error:
            out.append(Mismatch(path, None, f"{type(error).__name__}: {error}"))
            continue
        if difference is not None:
            out.append(Mismatch(path, difference, None))
    return out


def write_fixture(path: Path, document: Mapping[str, Any]) -> None:
    """Writes a new fixture in the export form: keys sorted, a two-space indent, UTF-8 and a
    trailing newline. Raises FileExistsError rather than overwrite one."""
    text = json.dumps(document, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
    with path.open("x", encoding="utf-8") as out:
        out.write(text)
