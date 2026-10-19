"""The pack file: canonical JSON, gzip-compressed, identified by the SHA-256 of the gzip bytes.

The header is fixed (level 9, `mtime` 0, no file name, OS byte 255), so the same canonical JSON
always gives the same file (FR-011, research R4). Readers check the SHA-256 of the file before
decompressing it, and decompress with a cap so a crafted file can't exhaust memory.
"""

from __future__ import annotations

import gzip
import hashlib
import zlib

__all__ = ["PackFileError", "PackTooLarge", "build_pack_file", "decompress_capped", "sha256_hex"]

_GZIP_WBITS = 16 + zlib.MAX_WBITS
_CHUNK = 64 * 1024


class PackFileError(ValueError):
    """The bytes aren't one well-formed gzip member."""


class PackTooLarge(PackFileError):
    """The decompressed content is over the allowed size."""


def build_pack_file(canonical: bytes) -> bytes:
    """Compress canonical JSON into the pack file's exact bytes."""
    return gzip.compress(canonical, compresslevel=9, mtime=0)


def sha256_hex(data: bytes) -> str:
    """The lowercase hex SHA-256 of `data`."""
    return hashlib.sha256(data).hexdigest()


def decompress_capped(data: bytes, *, max_bytes: int) -> bytes:
    """Decompress one gzip member, refusing output over `max_bytes` and any trailing bytes."""
    inflater = zlib.decompressobj(_GZIP_WBITS)
    output = bytearray()
    pending = data
    try:
        while pending and not inflater.eof:
            room = max_bytes - len(output) + 1
            output += inflater.decompress(pending, min(room, _CHUNK))
            if len(output) > max_bytes:
                raise PackTooLarge(f"the pack decompresses to more than {max_bytes} bytes")
            pending = inflater.unconsumed_tail
        while not inflater.eof:
            chunk = inflater.decompress(b"", _CHUNK)
            if not chunk:
                break
            output += chunk
            if len(output) > max_bytes:
                raise PackTooLarge(f"the pack decompresses to more than {max_bytes} bytes")
    except zlib.error as error:
        raise PackFileError(f"not a valid gzip file: {error}") from None
    if not inflater.eof:
        raise PackFileError("the gzip file is truncated")
    if inflater.unused_data:
        raise PackFileError("the gzip file has trailing bytes")
    return bytes(output)
