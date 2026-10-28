"""The shared example set (FR-009): valid examples pass, invalid ones fail at the named field.

An invalid example's `expected.json` entry is the schema path it fails at, or, for a document
the schema accepts but a rule beyond shape refuses (M07's `plays` and `narrator` rules), the
rule's `code` and `path`. Such a document is checked inside the sample pack, in place of the
sample's element with the same identifier.
"""

from pathlib import Path
from typing import Any

import pytest

from tests.paths import EXAMPLES, FIXTURES
from wassal_content.loader import ContentLoadError, load_json_file
from wassal_content.schemas import IDENTIFIER_FIELDS, PACK_ARRAYS, PARTS, SchemaSet
from wassal_content.source import assemble_pack, read_layout
from wassal_content.validate import validate_pack

VALID = sorted((EXAMPLES / "valid").glob("*/*.json"))
INVALID = sorted((EXAMPLES / "invalid").glob("*/*.json"))
EXPECTED: dict[str, str | dict[str, str]] = load_json_file(EXAMPLES / "invalid" / "expected.json")


def _id(path: Path) -> str:
    return f"{path.parent.name}/{path.name}"


SCHEMA_CASES = [path for path in INVALID if isinstance(EXPECTED.get(_id(path)), str)]
RULE_CASES = [path for path in INVALID if isinstance(EXPECTED.get(_id(path)), dict)]


def _in_sample(part: str, document: dict[str, Any], schema_set: SchemaSet) -> dict[str, Any]:
    """The sample pack with `document` in place of its element of the same identifier."""
    tree, findings = read_layout(EXAMPLES / "sample", schema_set)
    assert findings == []
    pack = assemble_pack(tree, version=1)
    [array] = [name for name, element_part in PACK_ARRAYS.items() if element_part == part]
    field = IDENTIFIER_FIELDS[part]
    others = [element for element in pack[array] if element[field] != document[field]]
    pack[array] = sorted([*others, document], key=lambda element: element[field])
    return pack


def test_every_part_has_valid_and_invalid_examples() -> None:
    assert {path.parent.name for path in VALID} == set(PARTS)
    assert {path.parent.name for path in INVALID} == set(PARTS)
    counts = {part: sum(path.parent.name == part for path in INVALID) for part in PARTS}
    assert min(counts.values()) >= 3, counts


@pytest.mark.parametrize("path", VALID, ids=_id)
def test_valid_examples_pass(path: Path, schema_set: SchemaSet) -> None:
    assert schema_set.validate_document(path.parent.name, load_json_file(path)) == []


@pytest.mark.parametrize("path", SCHEMA_CASES, ids=_id)
def test_invalid_examples_fail_at_the_named_field(path: Path, schema_set: SchemaSet) -> None:
    findings = schema_set.validate_document(path.parent.name, load_json_file(path))
    assert findings, "an invalid example must fail"
    assert {finding.path for finding in findings} == {EXPECTED[_id(path)]}
    assert all(finding.code == "V-SC" and finding.stage == "schema" for finding in findings)


@pytest.mark.parametrize("path", RULE_CASES, ids=_id)
def test_rule_examples_pass_the_schema_and_break_their_rule(
    path: Path, schema_set: SchemaSet
) -> None:
    part, document = path.parent.name, load_json_file(path)
    expected = EXPECTED[_id(path)]
    assert isinstance(expected, dict)
    assert schema_set.validate_document(part, document) == []

    pack = _in_sample(part, document, schema_set)
    report = validate_pack(pack, file_size=None, schema_set=schema_set)

    assert report.stages["schema"] == "passed", report.to_dict()
    errors = {(f.code, f.entity, f.id, f.path) for f in report.errors}
    identifier = str(document[IDENTIFIER_FIELDS[part]])
    assert (expected["code"], part, identifier, expected["path"]) in errors, sorted(errors)
    assert {f.code for f in report.errors} == {expected["code"]}


def test_the_rule_examples_cover_plays_and_narrator_rules() -> None:
    codes = {entry["code"] for entry in EXPECTED.values() if isinstance(entry, dict)}
    assert codes == {"V-C3", "V-C4", "V-C5"}


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
