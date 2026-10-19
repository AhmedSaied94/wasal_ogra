"""The `content/source` layout: read, assemble and write (contracts/content-source.md)."""

import json
import os
import shutil
from pathlib import Path

import pytest

from tests.paths import EXAMPLES
from wassal_content.schemas import SchemaSet
from wassal_content.source import (
    SourceTree,
    assemble_pack,
    export_bytes,
    pack_to_files,
    read_files,
    read_layout,
    write_layout,
)

SAMPLE = EXAMPLES / "sample"


@pytest.fixture
def sample_copy(tmp_path: Path) -> Path:
    target = tmp_path / "sample"
    shutil.copytree(SAMPLE, target)
    return target


def _read(root: Path, schema_set: SchemaSet) -> tuple[SourceTree, list[tuple[str, str, str]]]:
    tree, findings = read_layout(root, schema_set)
    return tree, [(f.code, f.file or "", f.path) for f in findings]


def test_the_sample_reads_without_findings(schema_set: SchemaSet) -> None:
    tree, findings = _read(SAMPLE, schema_set)
    assert findings == []
    assert tree.meta == {"pack_id": "core", "schema_version": "1.0", "version": 0}


def test_assembled_arrays_are_sorted_by_identifier(schema_set: SchemaSet) -> None:
    tree, _ = read_layout(SAMPLE, schema_set)
    pack = assemble_pack(tree, version=1)
    assert pack["version"] == 1
    assert [trip["trip_id"] for trip in pack["trips"]] == [
        "line_gamaa.01",
        "line_gamaa.02",
        "line_hay.01",
        "line_hay.02",
        "line_hay.03",
    ]
    assert [day["day_index"] for day in pack["daily_rewards"]] == list(range(1, 8))
    prices = [(p["sku_kind"], p["sku_id"]) for p in pack["catalog"]["prices"]]
    assert prices == sorted(prices)
    assert schema_set.validate_document("pack", pack) == []


def test_a_file_named_unlike_its_identifier_is_refused(
    sample_copy: Path, schema_set: SchemaSet
) -> None:
    (sample_copy / "lines" / "line_hay.json").rename(sample_copy / "lines" / "line_souq.json")
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-LY", "lines/line_souq.json", "$.line_id")]


def test_a_trip_in_another_lines_folder_is_refused(
    sample_copy: Path, schema_set: SchemaSet
) -> None:
    source = sample_copy / "trips" / "line_hay" / "line_hay.01.json"
    target = sample_copy / "trips" / "line_gamaa" / "line_hay.01.json"
    source.rename(target)
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-LY", "trips/line_gamaa/line_hay.01.json", "$.line_id")]


@pytest.mark.parametrize(
    "relative",
    [
        "garage/x.json",
        "lines/notes.txt",
        ".hidden.json",
        "trips/line_hay.01.json",
        "lines/a/b.json",
    ],
)
def test_unknown_files_and_folders_are_refused(
    relative: str, sample_copy: Path, schema_set: SchemaSet
) -> None:
    path = sample_copy / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("{}\n")
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-LY", relative, "$")]


def test_a_symlink_is_refused(sample_copy: Path, schema_set: SchemaSet) -> None:
    os.symlink(sample_copy / "lines" / "line_hay.json", sample_copy / "lines" / "line_souq.json")
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-LY", "lines/line_souq.json", "$")]


def test_a_parse_error_names_the_file_line_and_column(
    sample_copy: Path, schema_set: SchemaSet
) -> None:
    (sample_copy / "rooms" / "salon.json").write_text('{"room_id": "salon", "order": 1.5}\n')
    tree, findings = read_layout(sample_copy, schema_set)
    [finding] = findings
    assert (finding.code, finding.file) == ("V-JS", "rooms/salon.json")
    assert "line 1, column 31" in finding.message
    assert tree.parts["rooms"] == []


def test_a_schema_error_names_the_file_and_path(sample_copy: Path, schema_set: SchemaSet) -> None:
    path = sample_copy / "trips" / "line_hay" / "line_hay.01.json"
    trip = json.loads(path.read_text())
    trip["stations"][1]["fare_piasters"] = 475
    path.write_text(json.dumps(trip))
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-SC", "trips/line_hay/line_hay.01.json", "$.stations[1].fare_piasters")]


def test_array_files_report_the_element(sample_copy: Path, schema_set: SchemaSet) -> None:
    path = sample_copy / "daily_rewards.json"
    days = json.loads(path.read_text())
    days[3]["day_index"] = 9
    path.write_text(json.dumps(days))
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-SC", "daily_rewards.json", "$[3].day_index")]


def test_an_array_file_must_be_an_array(sample_copy: Path, schema_set: SchemaSet) -> None:
    (sample_copy / "tasks.json").write_text("{}\n")
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-SC", "tasks.json", "$")]


@pytest.mark.parametrize(
    ("meta", "path"),
    [
        ({"pack_id": "extra", "schema_version": "1.0", "version": 0}, "$.pack_id"),
        ({"pack_id": "core", "schema_version": "1", "version": 0}, "$.schema_version"),
        ({"pack_id": "core", "schema_version": "1.0", "version": -1}, "$.version"),
        ({"pack_id": "core", "schema_version": "1.0", "version": True}, "$.version"),
        ({"pack_id": "core", "schema_version": "1.0"}, "$.version"),
        ({"pack_id": "core", "schema_version": "1.0", "version": 0, "x": 1}, "$.x"),
    ],
)
def test_pack_json_is_checked(
    meta: dict[str, object], path: str, sample_copy: Path, schema_set: SchemaSet
) -> None:
    (sample_copy / "pack.json").write_text(json.dumps(meta))
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-SC", "pack.json", path)]


def test_required_files_are_required(sample_copy: Path, schema_set: SchemaSet) -> None:
    (sample_copy / "catalog.json").unlink()
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-LY", "catalog.json", "$")]


def test_parts_without_pack_json_are_refused(sample_copy: Path, schema_set: SchemaSet) -> None:
    (sample_copy / "pack.json").unlink()
    _, findings = _read(sample_copy, schema_set)
    assert findings == [("V-LY", "pack.json", "$")]


def test_an_empty_layout_has_no_pack(tmp_path: Path, schema_set: SchemaSet) -> None:
    (tmp_path / "README.md").write_text("only promoted packs land here\n")
    tree, findings = read_layout(tmp_path, schema_set)
    assert findings == []
    assert tree.is_empty


def test_assembling_an_empty_layout_is_refused(tmp_path: Path, schema_set: SchemaSet) -> None:
    tree, _ = read_layout(tmp_path, schema_set)
    with pytest.raises(ValueError, match=r"pack\.json"):
        assemble_pack(tree, version=1)


def test_a_missing_root_is_refused(tmp_path: Path, schema_set: SchemaSet) -> None:
    with pytest.raises(FileNotFoundError):
        read_layout(tmp_path / "nowhere", schema_set)


def test_writing_reproduces_the_sample_byte_for_byte(tmp_path: Path, schema_set: SchemaSet) -> None:
    tree, _ = read_layout(SAMPLE, schema_set)
    write_layout(assemble_pack(tree, version=1), tmp_path, version=0)
    written = sorted(p.relative_to(tmp_path) for p in tmp_path.rglob("*") if p.is_file())
    expected = sorted(p.relative_to(SAMPLE) for p in SAMPLE.rglob("*") if p.is_file())
    assert written == expected
    for relative in written:
        assert (tmp_path / relative).read_bytes() == (SAMPLE / relative).read_bytes(), relative


def test_the_export_format(schema_set: SchemaSet) -> None:
    data = export_bytes({"b": [1], "a": {"ar-EG": "ق"}})
    assert data == '{\n  "a": {\n    "ar-EG": "ق"\n  },\n  "b": [\n    1\n  ]\n}\n'.encode()


def test_files_round_trip_through_read_files(schema_set: SchemaSet) -> None:
    tree, _ = read_layout(SAMPLE, schema_set)
    pack = assemble_pack(tree, version=7)
    again, findings = read_files(pack_to_files(pack, version=7), schema_set)
    assert findings == []
    assert assemble_pack(again, version=7) == pack
    assert again.meta is not None
    assert again.meta["version"] == 7


@pytest.mark.parametrize("bad", ["../escape", "a/b", "a\\b", ".hidden", ""])
def test_identifiers_that_are_not_one_path_component_are_refused(
    schema_set: SchemaSet, bad: str
) -> None:
    tree, _ = read_layout(SAMPLE, schema_set)
    pack = assemble_pack(tree, version=1)
    pack["rooms"] = [{**pack["rooms"][0], "room_id": bad}]
    with pytest.raises(ValueError, match="path component"):
        pack_to_files(pack, version=1)
    pack = assemble_pack(tree, version=1)
    pack["trips"] = [{**pack["trips"][0], "line_id": bad}]
    with pytest.raises(ValueError, match="path component"):
        pack_to_files(pack, version=1)


def test_writing_into_a_directory_that_holds_files_is_refused(
    tmp_path: Path, schema_set: SchemaSet
) -> None:
    (tmp_path / "rooms").mkdir()
    (tmp_path / "rooms" / "old.json").write_text("{}\n")
    tree, _ = read_layout(SAMPLE, schema_set)
    with pytest.raises(ValueError, match="not empty"):
        write_layout(assemble_pack(tree, version=1), tmp_path, version=0)
