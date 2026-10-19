"""The strict loader refuses every number that isn't an integer, before any schema runs (R2)."""

from pathlib import Path

import pytest

from wassal_content.loader import ContentLoadError, load_json_bytes, load_json_file


@pytest.mark.parametrize(
    ("text", "line", "column"),
    [
        ('{"fare_piasters": 1.0}', 1, 19),
        ('{"a": 1e3}', 1, 7),
        ('{"a": [1, -0.5]}', 1, 11),
        ('{"a": 1E-2}', 1, 7),
        ('{\n  "a": {\n    "b": 2.50\n  }\n}', 3, 10),
    ],
)
def test_refuses_fractions_and_exponents_with_their_position(
    text: str, line: int, column: int
) -> None:
    with pytest.raises(ContentLoadError) as caught:
        load_json_bytes(text.encode())
    assert (caught.value.line, caught.value.column) == (line, column)
    assert "integer" in caught.value.message


@pytest.mark.parametrize("token", ["NaN", "Infinity", "-Infinity"])
def test_refuses_non_finite_constants(token: str) -> None:
    with pytest.raises(ContentLoadError) as caught:
        load_json_bytes(f'{{"a": {token}}}'.encode())
    assert (caught.value.line, caught.value.column) == (1, 7)


@pytest.mark.parametrize(
    ("text", "line", "column"),
    [
        ('{"a": 1, "a": 2}', 1, 10),
        ('{"x": [{"b": 1}, {"b": 1, "c": 2, "b": 3}]}', 1, 35),
        ('{\n  "a": 1,\n  "a": 1\n}', 3, 3),
    ],
)
def test_refuses_duplicate_keys_at_any_depth(text: str, line: int, column: int) -> None:
    with pytest.raises(ContentLoadError) as caught:
        load_json_bytes(text.encode())
    assert (caught.value.line, caught.value.column) == (line, column)
    assert "duplicate" in caught.value.message


def test_refuses_invalid_utf8() -> None:
    with pytest.raises(ContentLoadError) as caught:
        load_json_bytes(b'{"a": "\xff"}')
    assert "UTF-8" in caught.value.message
    assert (caught.value.line, caught.value.column) == (1, 8)


def test_refuses_a_byte_order_mark() -> None:
    with pytest.raises(ContentLoadError) as caught:
        load_json_bytes(b'\xef\xbb\xbf{"a": 1}')
    assert "BOM" in caught.value.message


@pytest.mark.parametrize(
    ("text", "line", "column"),
    [('{"a": }', 1, 7), ('{"a": 1,}', 1, 8), ("", 1, 1), ('{"a": 1} x', 1, 10)],
)
def test_reports_syntax_errors_with_their_position(text: str, line: int, column: int) -> None:
    with pytest.raises(ContentLoadError) as caught:
        load_json_bytes(text.encode())
    assert (caught.value.line, caught.value.column) == (line, column)


def test_accepts_integers_booleans_and_nesting() -> None:
    text = (
        '{"seed": 4294967295, "neg": -60, "ok": true, "no": false, '
        '"x": [[1], {"y": []}], "s": "\u0642"}'
    )
    assert load_json_bytes(text.encode()) == {
        "seed": 4294967295,
        "neg": -60,
        "ok": True,
        "no": False,
        "x": [[1], {"y": []}],
        "s": "\u0642",
    }


def test_string_escapes_are_decoded() -> None:
    assert load_json_bytes(rb'{"a": "x\"\\\n\u0642"}') == {"a": 'x"\\\n\u0642'}


def test_error_text_names_the_position() -> None:
    error = ContentLoadError("bad", line=3, column=4)
    assert str(error) == "line 3, column 4: bad"


def test_loads_a_file(tmp_path: Path) -> None:
    path = tmp_path / "a.json"
    path.write_bytes(b'{"a": 1}')
    assert load_json_file(path) == {"a": 1}


SAFE = 2**53 - 1


@pytest.mark.parametrize("value", [SAFE, -SAFE, 0])
def test_accepts_integers_within_the_safe_range(value: int) -> None:
    assert load_json_bytes(f'{{"a": {value}}}'.encode()) == {"a": value}


@pytest.mark.parametrize(
    "token",
    [str(SAFE + 1), str(-SAFE - 1), "9" * 5000, "-" + "9" * 5000],
    ids=["above", "below", "5000-digits", "minus-5000-digits"],
)
def test_refuses_integers_outside_the_safe_range(token: str) -> None:
    # Dart and Python must read every content integer the same way (I-JSON, RFC 7493).
    with pytest.raises(ContentLoadError) as caught:
        load_json_bytes(f'{{"a": [1, {token}]}}'.encode())
    assert (caught.value.line, caught.value.column) == (1, 11)
    assert "range" in caught.value.message


def test_accepts_nesting_up_to_the_limit() -> None:
    text = "[" * 32 + "]" * 32
    assert load_json_bytes(text.encode()) is not None


@pytest.mark.parametrize("depth", [33, 5000])
def test_refuses_deeper_nesting_with_its_position(depth: int) -> None:
    with pytest.raises(ContentLoadError) as caught:
        load_json_bytes(("[" * depth + "]" * depth).encode())
    assert (caught.value.line, caught.value.column) == (1, 33)
    assert "nested" in caught.value.message


def test_deep_nesting_with_a_float_is_still_a_load_error() -> None:
    with pytest.raises(ContentLoadError, match="nested"):
        load_json_bytes(("[" * 3000 + "1.5" + "]" * 3000).encode())


def test_nesting_counts_brackets_outside_strings_only() -> None:
    text = '{"a": "' + "[" * 100 + '"}'
    assert load_json_bytes(text.encode()) == {"a": "[" * 100}


@pytest.mark.parametrize(
    ("text", "column"),
    [(rb'{"a": "x\ud800"}', 7), (rb'{"a": ["\udc00"]}', 8), (rb'{"\ud83d": 1}', 2)],
)
def test_refuses_lone_surrogates(text: bytes, column: int) -> None:
    with pytest.raises(ContentLoadError) as caught:
        load_json_bytes(text)
    assert (caught.value.line, caught.value.column) == (1, column)
    assert "surrogate" in caught.value.message


def test_accepts_a_surrogate_pair() -> None:
    assert load_json_bytes(rb'{"a": "\ud83d\ude00"}') == {"a": "\U0001f600"}
