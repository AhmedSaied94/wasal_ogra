"""Pack validation: stage results and the report format (contracts/admin.md)."""

import copy
from typing import Any

from tests.paths import EXAMPLES
from wassal_content.findings import Finding, Report
from wassal_content.loader import load_json_file
from wassal_content.schemas import SchemaSet
from wassal_content.validate import SIZE_WARNING_BYTES, validate_pack

PACK: dict[str, Any] = load_json_file(EXAMPLES / "valid" / "pack" / "core.json")


def test_a_valid_pack_passes(schema_set: SchemaSet) -> None:
    report = validate_pack(PACK, file_size=2582, schema_set=schema_set)
    assert report.stages == {
        "schema": "passed",
        "references": "passed",
        "content_rules": "passed",
        "size": "passed",
    }
    assert report.passed
    assert report.findings == []


def test_a_big_pack_is_a_warning_that_doesnt_block(schema_set: SchemaSet) -> None:
    report = validate_pack(PACK, file_size=SIZE_WARNING_BYTES + 1, schema_set=schema_set)
    assert report.stages["size"] == "warning"
    assert report.passed
    [finding] = report.findings
    assert (finding.code, finding.severity, finding.stage) == ("V-S1", "warning", "size")
    assert report.errors == []


def test_a_schema_error_fails_the_stage_and_names_the_entity(schema_set: SchemaSet) -> None:
    broken = copy.deepcopy(PACK)
    broken["trips"][2]["stations"][0]["fare_piasters"] = 475
    report = validate_pack(broken, file_size=None, schema_set=schema_set)
    assert report.stages == {
        "schema": "failed",
        "references": "not_available",
        "content_rules": "not_available",
    }
    assert not report.passed
    [finding] = report.errors
    assert (finding.entity, finding.id) == ("trip", "line_hay.01")
    assert finding.path == "$.stations[0].fare_piasters"


def test_the_report_as_json() -> None:
    report = Report()
    report.add_stage("schema", [])
    report.add_stage("solver", [Finding(path="$", code="V-Z1", message="x", stage="solver")])
    assert report.to_dict() == {
        "stages": {"schema": {"result": "passed"}, "solver": {"result": "failed"}},
        "findings": [
            {
                "path": "$",
                "code": "V-Z1",
                "message": "x",
                "stage": "solver",
                "severity": "error",
                "entity": "",
                "id": "",
            }
        ],
    }
