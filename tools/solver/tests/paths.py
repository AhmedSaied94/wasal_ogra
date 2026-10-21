"""Paths the tests share."""

from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
REPO = PACKAGE_ROOT.parents[1]
FIXTURES = REPO / "fixtures" / "parity"
SAMPLE = REPO / "content" / "examples" / "sample"
SOURCE = REPO / "content" / "source"
APP_TUNABLES = REPO / "apps" / "mobile" / "assets" / "config" / "tunables.json"
DART_TESTS = REPO / "packages" / "trip_engine" / "test"
DATA = Path(__file__).resolve().parent / "data"
FAULTS = DATA / "faults"
