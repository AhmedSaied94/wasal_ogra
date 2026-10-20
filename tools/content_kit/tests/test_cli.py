"""The `wassal-content` commands and their exit codes (0 clean, 1 findings, 2 usage)."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from tests.paths import EXAMPLES, FIXTURES, REPO_ROOT
from wassal_content.cli import main


@pytest.fixture
def at_repo(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.chdir(REPO_ROOT / "tools" / "content_kit")


@pytest.mark.usefixtures("at_repo")
def test_codegen_check_passes_on_the_repository(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["codegen", "--check"]) == 0
    assert "up to date" in capsys.readouterr().out


def test_codegen_check_names_a_hand_edited_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / ".fvmrc").write_text("{}\n")
    shutil.copytree(FIXTURES / "codegen" / "schemas", tmp_path / "content" / "schemas")
    monkeypatch.chdir(tmp_path)
    assert main(["codegen"]) == 0
    edited = tmp_path / "packages" / "content_models" / "lib" / "src" / "generated" / "other.dart"
    edited.write_text(edited.read_text() + "// edited\n")
    capsys.readouterr()
    assert main(["codegen", "--check"]) == 1
    assert str(edited) in capsys.readouterr().out


@pytest.mark.usefixtures("at_repo")
def test_validate_a_valid_file(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["validate", str(EXAMPLES / "valid" / "trip" / "line_gamaa.12.json")]) == 0
    assert "valid trip" in capsys.readouterr().out


@pytest.mark.usefixtures("at_repo")
def test_validate_names_the_field(capsys: pytest.CaptureFixture[str]) -> None:
    path = EXAMPLES / "invalid" / "trip" / "fare_475.json"
    assert main(["validate", str(path)]) == 1
    assert "$.stations[0].fare_piasters [V-SC]" in capsys.readouterr().out


def test_validate_infers_the_part_from_layout_folders(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    trip = tmp_path / "trips" / "line_hay" / "line_hay.01.json"
    trip.parent.mkdir(parents=True)
    shutil.copy(EXAMPLES / "sample" / "trips" / "line_hay" / "line_hay.01.json", trip)
    assert main(["validate", str(trip)]) == 0
    line = tmp_path / "lines" / "line_hay.json"
    line.parent.mkdir()
    shutil.copy(EXAMPLES / "sample" / "lines" / "line_hay.json", line)
    assert main(["validate", str(line)]) == 0


def test_validate_needs_a_part_it_can_tell(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    path = tmp_path / "trip.json"
    shutil.copy(EXAMPLES / "valid" / "trip" / "line_gamaa.12.json", path)
    assert main(["validate", str(path)]) == 2
    assert "--part" in capsys.readouterr().err
    assert main(["validate", str(path), "--part", "trip"]) == 0
    assert main(["validate", str(path), "--part", "garage"]) == 2


def test_validate_reports_a_parse_error(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["validate", str(FIXTURES / "loader" / "fare_float.json"), "--part", "trip"]) == 1
    assert "only integers" in capsys.readouterr().out


def test_validate_source_on_the_sample(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["validate-source", str(EXAMPLES / "sample")]) == 0
    assert "0 error(s)" in capsys.readouterr().out


def test_validate_source_on_an_empty_layout(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / "README.md").write_text("x\n")
    assert main(["validate-source", str(tmp_path)]) == 0
    assert "nothing to validate" in capsys.readouterr().out


def test_validate_source_on_the_repository_source(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["validate-source", str(REPO_ROOT / "content" / "source")]) == 0


def test_validate_source_reports_findings(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    shutil.copytree(EXAMPLES / "sample", tmp_path / "sample")
    room = tmp_path / "sample" / "rooms" / "salon.json"
    data = json.loads(room.read_text())
    data["order"] = 0
    room.write_text(json.dumps(data))
    assert main(["validate-source", str(tmp_path / "sample")]) == 1
    assert "rooms/salon.json: $.order [V-SC] room salon" in capsys.readouterr().out


def test_validate_source_needs_a_directory(tmp_path: Path) -> None:
    assert main(["validate-source", str(tmp_path / "nowhere")]) == 2


@pytest.mark.usefixtures("at_repo")
def test_golden_matches(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["golden"]) == 0
    assert "match" in capsys.readouterr().out


def _git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t.invalid", *args],
        cwd=repo,
        check=True,
        capture_output=True,
    )


@pytest.fixture
def schema_repo(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    (tmp_path / ".fvmrc").write_text("{}\n")
    shutil.copytree(FIXTURES / "codegen" / "schemas", tmp_path / "content" / "schemas")
    _git(tmp_path, "init", "-q")
    _git(tmp_path, "add", ".")
    _git(tmp_path, "commit", "-qm", "base")
    monkeypatch.chdir(tmp_path)
    return tmp_path


def _break(repo: Path) -> None:
    path = repo / "content" / "schemas" / "other.schema.json"
    schema = json.loads(path.read_text())
    schema["properties"]["value"]["pattern"] = "^[a-z]+$"
    path.write_text(json.dumps(schema))


def test_schema_diff_is_free_before_content_source_exists(
    schema_repo: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    _break(schema_repo)
    assert main(["schema-diff", "--base", "HEAD"]) == 0
    assert "freely" in capsys.readouterr().out


def test_schema_diff_refuses_a_breaking_change_once_active(
    schema_repo: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    (schema_repo / "content" / "source").mkdir()
    (schema_repo / "content" / "source" / "pack.json").write_text("{}\n")
    assert main(["schema-diff", "--base", "HEAD"]) == 0
    assert "no breaking change" in capsys.readouterr().out
    _break(schema_repo)
    assert main(["schema-diff", "--base", "HEAD"]) == 1
    assert "breaking: other.schema.json#/properties/value/pattern" in capsys.readouterr().out
    set_file = schema_repo / "content" / "schemas" / "schema-set.json"
    set_file.write_text(json.dumps({"version": "10.0", "min_client_version_by_major": {}}))
    assert main(["schema-diff", "--base", "HEAD"]) == 0
    assert "major version went up" in capsys.readouterr().out


def test_schema_diff_needs_a_revision(schema_repo: Path) -> None:
    assert main(["schema-diff", "--base", "no-such-ref"]) == 2


def test_no_command_is_a_usage_error() -> None:
    assert main([]) == 2
    assert main(["frobnicate"]) == 2


def test_outside_a_repository_is_a_usage_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.chdir(tmp_path)
    assert main(["golden"]) == 2


def test_a_codegen_error_exits_1(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / ".fvmrc").write_text("{}\n")
    shutil.copytree(FIXTURES / "codegen" / "schemas", tmp_path / "content" / "schemas")
    path = tmp_path / "content" / "schemas" / "other.schema.json"
    schema = json.loads(path.read_text())
    schema["properties"]["value"]["type"] = "number"
    path.write_text(json.dumps(schema))
    monkeypatch.chdir(tmp_path)
    assert main(["codegen"]) == 1
    assert "profile" in capsys.readouterr().err


def test_validate_a_missing_file_is_a_usage_error(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(["validate", str(tmp_path / "nowhere.json"), "--part", "trip"]) == 2
    assert "nowhere.json" in capsys.readouterr().err


def test_codegen_names_a_schema_that_is_not_strict_json(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / ".fvmrc").write_text("{}\n")
    shutil.copytree(FIXTURES / "codegen" / "schemas", tmp_path / "content" / "schemas")
    (tmp_path / "content" / "schemas" / "other.schema.json").write_text('{"a": 1.5}')
    monkeypatch.chdir(tmp_path)
    assert main(["codegen"]) == 1
    assert "other.schema.json" in capsys.readouterr().err


def test_codegen_names_a_schema_set_without_a_version(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / ".fvmrc").write_text("{}\n")
    shutil.copytree(FIXTURES / "codegen" / "schemas", tmp_path / "content" / "schemas")
    (tmp_path / "content" / "schemas" / "schema-set.json").write_text("{}")
    monkeypatch.chdir(tmp_path)
    assert main(["codegen"]) == 1
    assert "schema-set.json" in capsys.readouterr().err


def test_schema_diff_reports_a_malformed_schema_set(
    schema_repo: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    (schema_repo / "content" / "schemas" / "schema-set.json").write_text("{}")
    assert main(["schema-diff", "--base", "HEAD"]) == 1
    assert "schema-set.json" in capsys.readouterr().err


def test_schema_diff_refuses_an_option_as_the_base(schema_repo: Path) -> None:
    assert main(["schema-diff", "--base", "--output=x"]) == 2


def test_validate_source_runs_the_rules_on_the_assembled_pack(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    shutil.copytree(EXAMPLES / "sample", tmp_path / "sample")
    room = tmp_path / "sample" / "rooms" / "salon.json"
    data = json.loads(room.read_text())
    data["chapter_id"] = "ch5_kitchen"
    room.write_text(json.dumps(data, ensure_ascii=False))
    assert main(["validate-source", str(tmp_path / "sample")]) == 1
    assert "$.chapter_id [V-R1] room salon" in capsys.readouterr().out
