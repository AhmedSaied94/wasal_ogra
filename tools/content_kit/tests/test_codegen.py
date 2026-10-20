"""The generator (research R1): deterministic output, drift detection, and refusals."""

import copy
import json
import shutil
from importlib import resources
from pathlib import Path
from typing import Any

import pytest

from tests.paths import ENGINE, FIXTURES, REPO_ROOT, SCHEMAS
from wassal_content.codegen import (
    CodegenError,
    Outputs,
    build_from_dir,
    check_outputs,
    outputs_for,
    write_outputs,
)
from wassal_content.codegen.dart import _string, emit_dart
from wassal_content.codegen.ir import build_model, dart_member, python_member
from wassal_content.codegen.python import emit_python
from wassal_content.loader import load_json_file
from wassal_content.schemas import default_schema_set, load_schema_set

FIXTURE_SCHEMAS = FIXTURES / "codegen" / "schemas"
EXPECTED = FIXTURES / "codegen" / "expected"


def test_python_output_matches_the_fixture() -> None:
    model, _ = build_from_dir(FIXTURE_SCHEMAS)
    assert emit_python(model) == (EXPECTED / "models.py").read_bytes()


def test_dart_output_matches_the_fixture() -> None:
    model, _ = build_from_dir(FIXTURE_SCHEMAS)
    files = emit_dart(model)
    expected = {path.name: path.read_bytes() for path in sorted((EXPECTED / "parts").iterdir())}
    assert files == expected


def test_generation_is_deterministic() -> None:
    first = outputs_for(REPO_ROOT)
    second = outputs_for(REPO_ROOT)
    assert first.files == second.files


def test_the_repository_is_up_to_date() -> None:
    assert check_outputs(outputs_for(REPO_ROOT)) == []


def test_the_packaged_schemas_equal_the_repositorys() -> None:
    assert default_schema_set().files == load_schema_set(SCHEMAS).files


def test_member_names() -> None:
    python_values: list[str | int] = ["line_hay", "A", "50", 50, "fuel_unlimited_1h"]
    assert [python_member(v) for v in python_values] == [
        "LINE_HAY",
        "A",
        "V50",
        "V50",
        "FUEL_UNLIMITED_1H",
    ]
    dart_values: list[str | int] = ["line_hay", "JENEHAT", "A", 50, "ch1_first_job", "index"]
    assert [dart_member(v) for v in dart_values] == [
        "lineHay",
        "jenehat",
        "a",
        "v50",
        "ch1FirstJob",
        "vIndex",
    ]


@pytest.fixture
def fake_repo(tmp_path: Path) -> Path:
    (tmp_path / ".fvmrc").write_text("{}\n")
    shutil.copytree(FIXTURE_SCHEMAS, tmp_path / "content" / "schemas")
    shutil.copytree(ENGINE, tmp_path / "content" / "engine")
    return tmp_path


def test_write_then_check_is_clean(fake_repo: Path) -> None:
    outputs = outputs_for(fake_repo)
    assert check_outputs(outputs) == sorted(outputs.files)
    assert write_outputs(outputs) == sorted(outputs.files)
    assert check_outputs(outputs) == []
    assert write_outputs(outputs) == []


def test_a_hand_edit_is_caught_and_undone(fake_repo: Path) -> None:
    outputs = outputs_for(fake_repo)
    write_outputs(outputs)
    edited = next(path for path in outputs.files if path.name == "thing.dart")
    edited.write_text(edited.read_text().replace("int? size", "int? sizeInCm"))
    assert check_outputs(outputs) == [edited]
    write_outputs(outputs)
    assert check_outputs(outputs) == []


def test_a_stale_file_is_caught_and_removed(fake_repo: Path) -> None:
    outputs = outputs_for(fake_repo)
    write_outputs(outputs)
    stale = next(iter(outputs.managed)) / "removed.schema.json"
    stale.write_text("{}\n")
    assert check_outputs(outputs) == [stale]
    write_outputs(outputs)
    assert not stale.exists()


def test_build_runner_parts_are_not_stale(fake_repo: Path) -> None:
    outputs = outputs_for(fake_repo)
    write_outputs(outputs)
    dart_dir = next(directory for directory in outputs.managed if directory.name == "generated")
    parts = [dart_dir / "thing.freezed.dart", dart_dir / "thing.g.dart"]
    for part in parts:
        part.write_text("// written by build_runner\n")
    assert check_outputs(outputs) == []
    assert write_outputs(outputs) == []
    assert all(part.exists() for part in parts)


def test_a_changed_schema_without_regenerating_is_caught(fake_repo: Path) -> None:
    write_outputs(outputs_for(fake_repo))
    path = fake_repo / "content" / "schemas" / "other.schema.json"
    schema = json.loads(path.read_text())
    schema["properties"]["extra"] = {"type": "integer"}
    path.write_text(json.dumps(schema))
    differing = {p.name for p in check_outputs(outputs_for(fake_repo))}
    assert {"_generated.py", "other.schema.json", "other.dart"} <= differing


def _capabilities(repo: Path) -> tuple[Path, Path]:
    """The capabilities file of `repo`, and its packaged copy."""
    package = repo / "tools" / "content_kit" / "src" / "wassal_content"
    return (
        repo / "content" / "engine" / "capabilities.json",
        package / "engine" / "capabilities.json",
    )


def test_the_packaged_capabilities_equal_the_repositorys() -> None:
    packaged = resources.files("wassal_content").joinpath("engine", "capabilities.json")
    assert packaged.read_bytes() == (ENGINE / "capabilities.json").read_bytes()


def test_the_capabilities_file_is_copied_byte_for_byte(fake_repo: Path) -> None:
    source, copied = _capabilities(fake_repo)
    # The file is hand-aligned: a copy that re-serialized it would lose the layout.
    source.write_bytes(source.read_bytes().replace(b'"bump":', b'"bump"   :', 1) + b"\n")
    assert write_outputs(outputs_for(fake_repo)).count(copied) == 1
    assert copied.read_bytes() == source.read_bytes()


def test_a_hand_edited_capabilities_copy_is_caught_and_undone(fake_repo: Path) -> None:
    outputs = outputs_for(fake_repo)
    write_outputs(outputs)
    _, copied = _capabilities(fake_repo)
    copied.write_bytes(copied.read_bytes().replace(b'"max": 60', b'"max": 90', 1))
    assert check_outputs(outputs) == [copied]
    write_outputs(outputs)
    assert check_outputs(outputs) == []


def test_a_changed_capabilities_file_without_regenerating_is_caught(fake_repo: Path) -> None:
    write_outputs(outputs_for(fake_repo))
    source, copied = _capabilities(fake_repo)
    source.write_bytes(source.read_bytes().replace(b'"hajja", ', b"", 1))
    assert check_outputs(outputs_for(fake_repo)) == [copied]


def test_a_stale_file_beside_the_capabilities_copy_is_removed(fake_repo: Path) -> None:
    outputs = outputs_for(fake_repo)
    write_outputs(outputs)
    _, copied = _capabilities(fake_repo)
    stale = copied.parent / "old.json"
    stale.write_text("{}\n")
    assert check_outputs(outputs) == [stale]
    write_outputs(outputs)
    assert not stale.exists()


def test_a_missing_capabilities_file_is_refused(fake_repo: Path) -> None:
    source, _ = _capabilities(fake_repo)
    source.unlink()
    with pytest.raises(CodegenError, match=r"capabilities\.json is missing"):
        outputs_for(fake_repo)


@pytest.mark.parametrize(
    ("text", "match"),
    [
        ('{"version": 1.5}', "only integers"),
        ('{"version": 1, "archetypes": [], "events": {}}', "speech_slots"),
    ],
    ids=["not strict JSON", "wrong shape"],
)
def test_a_malformed_capabilities_file_is_refused(fake_repo: Path, text: str, match: str) -> None:
    source, _ = _capabilities(fake_repo)
    source.write_text(text)
    with pytest.raises(CodegenError, match=match) as caught:
        outputs_for(fake_repo)
    assert "capabilities.json" in str(caught.value)


def test_outputs_type_is_plain_data() -> None:
    outputs = Outputs(files={}, managed={})
    assert check_outputs(outputs) == []


def _schemas() -> dict[str, Any]:
    return {
        path.name.removesuffix(".schema.json"): load_json_file(path)
        for path in FIXTURE_SCHEMAS.glob("*.schema.json")
    }


def _refused(mutate: Any, match: str) -> None:
    schemas = copy.deepcopy(_schemas())
    mutate(schemas)
    with pytest.raises(CodegenError, match=match):
        build_model(schemas, "9.3")


def test_a_schema_outside_the_profile_is_refused() -> None:
    _refused(lambda s: s["other"]["properties"].update(x={"type": "number"}), "profile")


def test_an_inline_enum_is_refused() -> None:
    inline = {"type": "string", "enum": ["a", "b"]}
    _refused(lambda s: s["other"]["properties"].update(x=inline), "named")


def test_duplicate_type_names_are_refused() -> None:
    _refused(lambda s: s["other"].__setitem__("title", "Thing"), "defined in both")


def test_a_dangling_ref_is_refused() -> None:
    _refused(
        lambda s: s["other"]["properties"].update(x={"$ref": "common.schema.json#/$defs/Nope"}),
        "points at nothing",
    )


def test_a_cycle_is_refused() -> None:
    def cycle(schemas: dict[str, Any]) -> None:
        schemas["other"]["properties"]["thing"] = {"$ref": "thing.schema.json"}

    _refused(cycle, "cycle")


def test_clashing_field_names_are_refused() -> None:
    def clash(schemas: dict[str, Any]) -> None:
        schemas["other"]["properties"]["a_b"] = {"type": "string"}
        schemas["other"]["properties"]["a-b"] = {"type": "string"}

    _refused(clash, "same field name")


def test_clashing_enum_members_are_refused() -> None:
    _refused(
        lambda s: s["common"]["$defs"]["Color"].__setitem__("enum", ["red", "RED"]),
        "same member name",
    )


def test_a_reserved_dart_field_name_is_refused() -> None:
    _refused(lambda s: s["other"]["properties"].update(hash_code={"type": "string"}), "reserved")


def test_a_missing_schema_set_file_is_refused(tmp_path: Path) -> None:
    shutil.copytree(FIXTURE_SCHEMAS, tmp_path / "schemas")
    (tmp_path / "schemas" / "schema-set.json").unlink()
    with pytest.raises(CodegenError, match=r"schema-set\.json"):
        build_from_dir(tmp_path / "schemas")


def test_python_docstrings_survive_quotes_backslashes_and_control_characters() -> None:
    schemas = copy.deepcopy(_schemas())
    text = 'Says """hi""" \\ to $you\r\nand ends with a quote"'
    schemas["other"]["description"] = text
    namespace: dict[str, Any] = {}
    exec(compile(emit_python(build_model(schemas, "9.3")), "_generated.py", "exec"), namespace)  # noqa: S102
    assert namespace["Other"].__doc__ == text


def test_dart_strings_are_escaped() -> None:
    assert _string("a'b$c\\d\ne\rf\x01") == "'a\\'b\\$c\\\\d\\ne\\rf\\u{1}'"
