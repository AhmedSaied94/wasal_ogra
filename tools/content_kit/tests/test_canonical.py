"""The canonical form (research R4): the same content always gives the same bytes."""

import re
from typing import Any

import pytest
from hypothesis import given
from hypothesis import strategies as st

from tests.paths import REPO_ROOT
from wassal_content.canonical import canonical_bytes
from wassal_content.loader import load_json_bytes, load_json_file

VECTORS: list[dict[str, Any]] = load_json_file(
    REPO_ROOT / "content" / "examples" / "canonical-vectors.json"
)


@pytest.mark.parametrize("vector", VECTORS, ids=[v["name"] for v in VECTORS])
def test_shared_vectors(vector: dict[str, Any]) -> None:
    assert canonical_bytes(vector["input"]) == vector["canonical"].encode("utf-8")


@pytest.mark.parametrize(
    "value",
    [None, 1.5, {"a": None}, [1, 2.0], {"a": {"b": float("nan")}}],
)
def test_refuses_null_and_floats(value: Any) -> None:
    with pytest.raises(ValueError, match=r"null|float"):
        canonical_bytes(value)


def test_refuses_non_string_keys() -> None:
    with pytest.raises(ValueError, match="key"):
        canonical_bytes({1: "a"})


def test_refuses_other_types() -> None:
    with pytest.raises(ValueError, match="set"):
        canonical_bytes({"a": {1, 2}})


@pytest.mark.parametrize("value", [2**53, -(2**53), 2**70])
def test_refuses_integers_outside_the_safe_range(value: int) -> None:
    with pytest.raises(ValueError, match=r"\$\.a: .*range"):
        canonical_bytes({"a": value})


@pytest.mark.parametrize(
    ("value", "path"),
    [({"a": "x\ud800"}, "$.a"), ({"\udc00": 1}, "$")],
)
def test_refuses_lone_surrogates(value: Any, path: str) -> None:
    with pytest.raises(ValueError, match=re.escape(path) + ": a lone surrogate"):
        canonical_bytes(value)


def test_tuples_are_arrays() -> None:
    assert canonical_bytes({"a": (1, 2)}) == b'{"a":[1,2]}'


_leaves = st.one_of(
    st.integers(min_value=-(2**53 - 1), max_value=2**53 - 1),
    st.booleans(),
    st.text(max_size=12),
)
_trees = st.recursive(
    _leaves,
    lambda children: st.one_of(
        st.lists(children, max_size=5),
        st.dictionaries(st.text(max_size=8), children, max_size=5),
    ),
    max_leaves=30,
)


@given(_trees)
def test_canonical_form_is_a_fixed_point(value: Any) -> None:
    once = canonical_bytes(value)
    assert canonical_bytes(load_json_bytes(once)) == once
