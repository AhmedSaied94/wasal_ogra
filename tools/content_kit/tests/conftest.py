"""Shared fixtures: the repository's schema set, read straight from content/schemas."""

import pytest

from tests.paths import SCHEMAS
from wassal_content.schemas import SchemaSet, load_schema_set


@pytest.fixture(scope="session")
def schema_set() -> SchemaSet:
    return load_schema_set(SCHEMAS)
