"""The sample pack's golden checksums (FR-011, SC-004)."""

import json
import shutil
from pathlib import Path

import pytest

from tests.paths import EXAMPLES
from wassal_content.golden import compute_golden, golden_bytes
from wassal_content.loader import load_json_file
from wassal_content.schemas import SchemaSet


def test_the_sample_matches_its_golden_checksums(schema_set: SchemaSet) -> None:
    expected = load_json_file(EXAMPLES / "sample.golden.json")
    assert compute_golden(EXAMPLES / "sample", schema_set) == expected
    assert (
        golden_bytes(EXAMPLES / "sample", schema_set)
        == (EXAMPLES / "sample.golden.json").read_bytes()
    )


def test_any_content_change_changes_the_checksums(tmp_path: Path, schema_set: SchemaSet) -> None:
    shutil.copytree(EXAMPLES / "sample", tmp_path / "sample")
    path = tmp_path / "sample" / "rooms" / "salon.json"
    room = json.loads(path.read_text())
    room["completion_bonat"] += 1
    path.write_text(json.dumps(room))
    changed = compute_golden(tmp_path / "sample", schema_set)
    original = compute_golden(EXAMPLES / "sample", schema_set)
    assert changed["sha256"] != original["sha256"]
    assert changed["canonical_sha256"] != original["canonical_sha256"]


def test_key_order_and_whitespace_in_files_dont_matter(
    tmp_path: Path, schema_set: SchemaSet
) -> None:
    shutil.copytree(EXAMPLES / "sample", tmp_path / "sample")
    path = tmp_path / "sample" / "lines" / "line_hay.json"
    line = json.loads(path.read_text())
    path.write_text(json.dumps(dict(reversed(list(line.items()))), indent=7))
    assert compute_golden(tmp_path / "sample", schema_set) == compute_golden(
        EXAMPLES / "sample", schema_set
    )


def test_a_sample_with_findings_has_no_golden(tmp_path: Path, schema_set: SchemaSet) -> None:
    shutil.copytree(EXAMPLES / "sample", tmp_path / "sample")
    (tmp_path / "sample" / "rooms" / "salon.json").write_text("{}\n")
    with pytest.raises(ValueError, match="findings"):
        compute_golden(tmp_path / "sample", schema_set)
