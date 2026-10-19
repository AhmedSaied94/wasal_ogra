"""The server models, generated from `content/schemas` into `_generated.py` (research R1).

Never edit `_generated.py`: change the schema and run `uv run wassal-content codegen`.
"""

from __future__ import annotations

from typing import Any

from wassal_content.models._generated import *  # noqa: F403
from wassal_content.models._generated import ROOT_MODELS, SCHEMA_SET_VERSION, ContentModel

__all__ = ["ROOT_MODELS", "SCHEMA_SET_VERSION", "ContentModel", "parse", "to_json_dict"]


def parse(part: str, document: Any) -> ContentModel:
    """Read a document of `part` with its root model. Unknown fields are ignored (FR-008)."""
    return ROOT_MODELS[part].model_validate(document)


def to_json_dict(model: ContentModel) -> dict[str, Any]:
    """The model as JSON data: original property names, and no absent optional fields."""
    return model.model_dump(mode="json", by_alias=True, exclude_none=True)
