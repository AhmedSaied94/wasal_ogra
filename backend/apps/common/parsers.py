"""The request body parser of every endpoint (B03 security review, M1).

DRF's `JSONParser` turns a `ValueError` into a 400, but JSON nested deeper than Python's recursion
limit raises `RecursionError`, which became a 500. A few hundred kilobytes of `[` is enough, so
that is a 400 too.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import IO, Any

from rest_framework import parsers
from rest_framework.exceptions import ParseError


class JSONParser(parsers.JSONParser):
    def parse(
        self,
        stream: IO[Any],
        media_type: str | None = None,
        parser_context: Mapping[str, Any] | None = None,
    ) -> Any:
        try:
            return super().parse(stream, media_type, parser_context)
        except RecursionError:
            raise ParseError("JSON parse error - nested too deeply") from None
