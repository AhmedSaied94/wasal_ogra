"""No import cycle between `ads` and `economy` (B07 plan, "Architecture boundaries")."""

from __future__ import annotations

import ast
from pathlib import Path

from django.conf import settings

APPS = Path(settings.BASE_DIR) / "apps"
# What `economy` may import from `ads`; neither of these imports `economy`.
SHARED = {"apps.ads.models", "apps.ads.services.status"}
PACKAGES = {"apps.ads", "apps.ads.services"}


def imported(path: Path) -> set[str]:
    """Every module `path` imports, `from package import module` counted as the module."""
    found: set[str] = set()
    for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
        if isinstance(node, ast.Import):
            found |= {alias.name for alias in node.names}
        elif isinstance(node, ast.ImportFrom) and node.module:
            if node.module in PACKAGES:
                found |= {f"{node.module}.{alias.name}" for alias in node.names}
            else:
                found.add(node.module)
    return found


def test_the_shared_ads_modules_never_import_economy() -> None:
    for module in SHARED:
        path = APPS.parent / (module.replace(".", "/") + ".py")
        assert not {m for m in imported(path) if m.startswith("apps.economy")}, module


def test_economy_imports_only_the_shared_ads_modules() -> None:
    for path in (APPS / "economy").rglob("*.py"):
        if "tests" in path.parts:
            continue
        ads = {m for m in imported(path) if m == "apps.ads" or m.startswith("apps.ads.")}
        assert ads <= SHARED, f"{path}: {sorted(ads - SHARED)}"
