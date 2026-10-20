"""The content admin (contracts/admin.md).

Every page is plain Django admin with no inline script, so B01's admin CSP is unchanged.
"""

from apps.content.admin import authoring, packs

__all__ = ["authoring", "packs"]
