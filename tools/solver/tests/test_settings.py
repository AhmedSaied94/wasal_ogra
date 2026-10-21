"""The solver settings (data-model.md "SolverSettings", research R12) and the bundled params."""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
from typing import Any

import pytest
from wassal_content.canonical import canonical_bytes
from wassal_content.loader import load_json_bytes

from tests.paths import PACKAGE_ROOT
from wassal_solver.engine.params import TripParams
from wassal_solver.settings import SettingsError, SolverSettings, load_settings
from wassal_solver.tunables import bundled_params

PACKAGED = PACKAGE_ROOT / "src" / "wassal_solver" / "data" / "settings.json"
PACKAGED_TUNABLES = PACKAGE_ROOT / "src" / "wassal_solver" / "data" / "tunables.json"


def packaged() -> dict[str, Any]:
    document: dict[str, Any] = load_json_bytes(PACKAGED.read_bytes())
    return document


def written(tmp_path: Path, document: object) -> Path:
    path = tmp_path / "settings.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    return path


def test_the_packaged_settings_hold_the_initial_values() -> None:
    settings = load_settings()
    assert isinstance(settings, SolverSettings)
    assert settings.reaction_ms == 600
    assert settings.tap_ms == 198
    assert settings.effort_budget_steps == 1_500_000
    assert settings.safety_cap_seconds == 180
    assert settings.transposition_cap == 100_000
    assert settings.report_reaction_ms == (900, 1200)
    assert settings.score.slack_ref_ms == 12000
    assert settings.score.term("owed_at_once").per == 8
    assert settings.to_json() == packaged()


def test_the_settings_are_frozen() -> None:
    settings = load_settings()
    with pytest.raises(AttributeError):
        settings.reaction_ms = 1  # type: ignore[misc]


def test_a_file_reads_like_the_packaged_one(tmp_path: Path) -> None:
    assert load_settings(written(tmp_path, packaged())) == load_settings()


@pytest.mark.parametrize(
    ("edit", "message"),
    [
        (lambda d: d.update(extra=1), "unknown key extra"),
        (lambda d: d["score"].update(extra=1), "unknown key score.extra"),
        (lambda d: d["score"]["breaks"].update(extra=1), "unknown key score.breaks.extra"),
        (lambda d: d.pop("tap_ms"), "tap_ms is missing"),
        (lambda d: d["score"].pop("variety"), "score.variety is missing"),
        (lambda d: d["score"]["variety"].pop("cap"), "score.variety.cap is missing"),
        (lambda d: d.update(reaction_ms=True), "reaction_ms must be an integer"),
        (lambda d: d.update(reaction_ms="600"), "reaction_ms must be an integer"),
        (lambda d: d["score"]["breaks"].update(per=None), "score.breaks.per must be an integer"),
        (lambda d: d.update(report_reaction_ms=[900, "x"]), "report_reaction_ms[1] must be"),
        (lambda d: d.update(report_reaction_ms=900), "report_reaction_ms must be a list"),
        (lambda d: d.update(score=[]), "score must be an object"),
        (lambda d: d.update(reaction_ms=-1), "reaction_ms must not be negative"),
        (lambda d: d.update(tap_ms=-33), "tap_ms must not be negative"),
        (lambda d: d["score"]["tightness_ms"].update(unit=0), "score.tightness_ms.unit must be"),
        (lambda d: d.update(effort_budget_steps=0), "effort_budget_steps must be at least 1"),
        (lambda d: d.update(safety_cap_seconds=0), "safety_cap_seconds must be at least 1"),
    ],
)
def test_loading_refuses_a_bad_record(tmp_path: Path, edit: Any, message: str) -> None:
    document = copy.deepcopy(packaged())
    edit(document)
    with pytest.raises(SettingsError, match=message.replace("[", r"\[").replace("]", r"\]")):
        load_settings(written(tmp_path, document))


def test_loading_refuses_a_file_that_is_not_strict_json(tmp_path: Path) -> None:
    path = tmp_path / "settings.json"
    for text in ('{"reaction_ms": NaN}', '{"reaction_ms": 600.5}'):
        path.write_text(text, encoding="utf-8")
        with pytest.raises(SettingsError, match="not strict JSON"):
            load_settings(path)


def test_the_settings_version_is_16_hex_digits_of_the_canonical_sha256() -> None:
    settings = load_settings()
    expected = hashlib.sha256(canonical_bytes(packaged())).hexdigest()[:16]
    assert settings.settings_version == expected


@pytest.mark.parametrize(
    "edit",
    [
        lambda d: d.update(reaction_ms=601),
        lambda d: d.update(tap_ms=231),
        lambda d: d.update(effort_budget_steps=999_999),
        lambda d: d.update(safety_cap_seconds=181),
        lambda d: d.update(transposition_cap=1),
        lambda d: d.update(report_reaction_ms=[900]),
        lambda d: d["score"].update(slack_ref_ms=1),
        lambda d: d["score"]["variety"].update(free=2),
    ],
)
def test_the_settings_version_changes_with_any_field(tmp_path: Path, edit: Any) -> None:
    document = copy.deepcopy(packaged())
    edit(document)
    changed = load_settings(written(tmp_path, document))
    assert changed.settings_version != load_settings().settings_version


@pytest.mark.parametrize("line_id", ["line_hay", "line_gamaa"])
def test_bundled_params_are_the_packaged_tunables_for_the_line(line_id: str) -> None:
    tunables = load_json_bytes(PACKAGED_TUNABLES.read_bytes())
    assert bundled_params(line_id) == TripParams.from_tunables(tunables, line_id)
