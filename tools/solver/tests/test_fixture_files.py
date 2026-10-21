"""Writing fixture files (contracts/mirror.md §6): the export form, and never over a file."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from wassal_solver.fixture_files import write_fixture

DOCUMENT = {"seed": 1, "definition": {"name": "خط", "b": [1, 2]}, "command_log": []}


def test_a_fixture_is_written_sorted_indented_unescaped_with_a_newline(tmp_path: Path) -> None:
    path = tmp_path / "solver__x.json"
    write_fixture(path, DOCUMENT)
    text = path.read_text(encoding="utf-8")
    assert text == json.dumps(DOCUMENT, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
    assert "خط" in text
    assert text.index('"command_log"') < text.index('"definition"') < text.index('"seed"')


def test_an_existing_file_is_never_overwritten(tmp_path: Path) -> None:
    path = tmp_path / "solver__x.json"
    path.write_text("old\n", encoding="utf-8")
    with pytest.raises(FileExistsError):
        write_fixture(path, DOCUMENT)
    assert path.read_text(encoding="utf-8") == "old\n"
