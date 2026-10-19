"""The pack file: gzip of the canonical JSON, byte-identical on every machine (research R4)."""

import gzip
import hashlib
import io
import zlib

import pytest

from wassal_content.packfile import (
    PackFileError,
    PackTooLarge,
    build_pack_file,
    decompress_capped,
    sha256_hex,
)

CANONICAL = b'{"pack_id":"core","version":1}'


def test_gzip_header_is_fixed() -> None:
    data = build_pack_file(CANONICAL)
    assert data[:3] == b"\x1f\x8b\x08"
    assert data[3] == 0, "no file name, comment or extra field"
    assert data[4:8] == b"\x00\x00\x00\x00", "mtime is 0"
    assert data[8] == 2, "level 9 sets XFL to 2"
    assert data[9] == 255, "OS byte is 255 (unknown)"


def test_same_input_same_bytes() -> None:
    assert build_pack_file(CANONICAL) == build_pack_file(bytes(CANONICAL))


def test_round_trips() -> None:
    assert gzip.decompress(build_pack_file(CANONICAL)) == CANONICAL


def test_sha256_is_over_the_given_bytes() -> None:
    data = build_pack_file(CANONICAL)
    assert sha256_hex(data) == hashlib.sha256(data).hexdigest()
    assert len(sha256_hex(data)) == 64


def test_decompress_within_the_cap() -> None:
    data = build_pack_file(CANONICAL)
    assert decompress_capped(data, max_bytes=len(CANONICAL)) == CANONICAL


def test_decompress_past_the_cap_is_refused() -> None:
    data = build_pack_file(CANONICAL)
    with pytest.raises(PackTooLarge):
        decompress_capped(data, max_bytes=len(CANONICAL) - 1)


def test_a_gzip_bomb_is_refused_without_inflating_it() -> None:
    bomb = gzip.compress(b"\0" * (64 * 1024 * 1024), compresslevel=9, mtime=0)
    assert len(bomb) < 100_000
    with pytest.raises(PackTooLarge):
        decompress_capped(bomb, max_bytes=1024 * 1024)


@pytest.mark.parametrize(
    "data",
    [
        b"not gzip at all",
        build_pack_file(CANONICAL)[:-6],  # truncated: no trailer
        build_pack_file(CANONICAL) + b"trailing",
    ],
)
def test_corrupt_files_are_refused(data: bytes) -> None:
    with pytest.raises(PackFileError):
        decompress_capped(data, max_bytes=1024)


def test_two_members_are_refused() -> None:
    buffer = io.BytesIO()
    buffer.write(build_pack_file(b"{}"))
    buffer.write(build_pack_file(b"{}"))
    with pytest.raises(PackFileError):
        decompress_capped(buffer.getvalue(), max_bytes=1024)


def test_raw_deflate_is_refused() -> None:
    with pytest.raises(PackFileError):
        decompress_capped(zlib.compress(CANONICAL), max_bytes=1024)
