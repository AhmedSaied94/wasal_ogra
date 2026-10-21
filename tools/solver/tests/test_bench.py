"""The bench corpus (research R17): 50 trips derived from the sample, reproducible."""

from __future__ import annotations

import importlib.util
import json
import sys

from wassal_content.validate import document_findings

from tests.paths import PACKAGE_ROOT
from tests.support.solving import SAMPLE_IDS

BENCH = PACKAGE_ROOT / "src" / "wassal_solver" / "data" / "bench"
SCRIPT = PACKAGE_ROOT / "scripts" / "make_bench.py"


def test_the_corpus_is_50_valid_trips_on_both_lines_clear_of_the_samples() -> None:
    files = sorted(BENCH.glob("*.json"))
    assert len(files) == 50
    documents = [json.loads(path.read_text(encoding="utf-8")) for path in files]
    assert {d["line_id"] for d in documents} == {"line_hay", "line_gamaa"}
    ids = [d["trip_id"] for d in documents]
    assert [f"{trip_id}.json" for trip_id in ids] == [path.name for path in files]
    assert not set(ids) & set(SAMPLE_IDS)
    for document in documents:
        errors = [f for f in document_findings("trip", document) if f.severity == "error"]
        assert errors == [], document["trip_id"]


def test_the_script_rewrites_identical_bytes() -> None:
    spec = importlib.util.spec_from_file_location("make_bench", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["make_bench"] = module
    spec.loader.exec_module(module)
    made = module.make()
    assert sorted(made) == sorted(path.name for path in BENCH.glob("*.json"))
    for name, data in made.items():
        assert (BENCH / name).read_bytes() == data, name
