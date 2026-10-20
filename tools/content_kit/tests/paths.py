"""Paths the tests share."""

from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = PACKAGE_ROOT.parents[1]
CONTENT = REPO_ROOT / "content"
SCHEMAS = CONTENT / "schemas"
EXAMPLES = CONTENT / "examples"
ENGINE = CONTENT / "engine"
PARITY = REPO_ROOT / "fixtures" / "parity"
FIXTURES = Path(__file__).resolve().parent / "fixtures"
