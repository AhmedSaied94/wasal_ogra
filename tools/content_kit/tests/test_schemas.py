"""Schema validation details the profile relies on (research R3)."""

from typing import Any

import pytest

from wassal_content.schemas import SchemaSet


def _errors(schema_set: SchemaSet, pattern: str, value: str) -> list[str]:
    validator: Any = schema_set.validator_for("trip")
    schema = {"type": "string", "pattern": pattern}
    return [error.message for error in validator.evolve(schema=schema).iter_errors(value)]


@pytest.mark.parametrize(
    ("pattern", "value", "matches"),
    [
        ("^[a-z]+$", "abc", True),
        # ECMA-262's `$` never matches before a trailing newline; Python's does without `\Z`.
        ("^[a-z]+$", "abc\n", False),
        # An escaped dollar at the end is a literal dollar, not an anchor.
        (r"^a\$", "a$", True),
        (r"^a\$", "a", False),
        (r"^a\\$", "a\\", True),
        ("^https?://", "https://x.invalid/a", True),
    ],
)
def test_patterns_follow_ecma_262(
    schema_set: SchemaSet, pattern: str, value: str, matches: bool
) -> None:
    assert (_errors(schema_set, pattern, value) == []) is matches
