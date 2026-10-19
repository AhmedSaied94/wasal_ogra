"""The shared example set (FR-009): valid examples pass, invalid ones fail at the named field."""

from pathlib import Path

import pytest

from tests.paths import EXAMPLES, FIXTURES
from wassal_content.loader import ContentLoadError, load_json_file
from wassal_content.schemas import PARTS, SchemaSet

VALID = sorted((EXAMPLES / "valid").glob("*/*.json"))
INVALID = sorted((EXAMPLES / "invalid").glob("*/*.json"))
EXPECTED: dict[str, str] = load_json_file(EXAMPLES / "invalid" / "expected.json")


def _id(path: Path) -> str:
    return f"{path.parent.name}/{path.name}"


def test_every_part_has_valid_and_invalid_examples() -> None:
    assert {path.parent.name for path in VALID} == set(PARTS)
    assert {path.parent.name for path in INVALID} == set(PARTS)
    counts = {part: sum(path.parent.name == part for path in INVALID) for part in PARTS}
    assert min(counts.values()) >= 3, counts


@pytest.mark.parametrize("path", VALID, ids=_id)
def test_valid_examples_pass(path: Path, schema_set: SchemaSet) -> None:
    assert schema_set.validate_document(path.parent.name, load_json_file(path)) == []


@pytest.mark.parametrize("path", INVALID, ids=_id)
def test_invalid_examples_fail_at_the_named_field(path: Path, schema_set: SchemaSet) -> None:
    findings = schema_set.validate_document(path.parent.name, load_json_file(path))
    assert findings, "an invalid example must fail"
    assert {finding.path for finding in findings} == {EXPECTED[_id(path)]}
    assert all(finding.code == "V-SC" and finding.stage == "schema" for finding in findings)


def test_expected_lists_exactly_the_invalid_files() -> None:
    assert set(EXPECTED) == {_id(path) for path in INVALID}


def test_findings_name_the_entity(schema_set: SchemaSet) -> None:
    [finding] = schema_set.validate_document(
        "trip", load_json_file(EXAMPLES / "invalid" / "trip" / "fare_475.json")
    )
    assert (finding.entity, finding.id) == ("trip", "line_gamaa.12")
    assert finding.to_dict()["path"] == "$.stations[0].fare_piasters"
    assert "file" not in finding.to_dict()


def test_a_float_is_refused_before_the_schema_runs() -> None:
    with pytest.raises(ContentLoadError) as caught:
        load_json_file(FIXTURES / "loader" / "fare_float.json")
    assert caught.value.line > 1
    assert "integers" in caught.value.message


def test_unknown_part_is_refused(schema_set: SchemaSet) -> None:
    with pytest.raises(KeyError, match="unknown part"):
        schema_set.validator_for("garage")
