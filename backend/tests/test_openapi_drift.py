"""The committed contract matches the code (FR-018). The local twin of CI's `contract` diff.

Regenerate with:
    uv run manage.py spectacular --file ../contracts/openapi.yaml --validate --fail-on-warn
"""

from pathlib import Path

import yaml
from django.conf import settings
from drf_spectacular.renderers import OpenApiYamlRenderer
from drf_spectacular.settings import spectacular_settings
from drf_spectacular.validation import validate_schema

CONTRACT = Path(__file__).resolve().parents[2] / "contracts" / "openapi.yaml"


def generate() -> bytes:
    """What `manage.py spectacular` writes, built the same way."""
    generator = spectacular_settings.DEFAULT_GENERATOR_CLASS(urlconf=None, api_version=None)
    schema = generator.get_schema(request=None, public=True)
    validate_schema(schema)  # type: ignore[no-untyped-call]
    output: bytes = OpenApiYamlRenderer().render(schema, renderer_context={})  # type: ignore[no-untyped-call]
    return output


def test_schema_comes_from_the_api_urlconf() -> None:
    assert settings.ROOT_URLCONF == "config.urls"


def test_committed_contract_matches_the_code() -> None:
    assert CONTRACT.read_bytes() == generate(), "contracts/openapi.yaml is stale; regenerate it"


def test_contract_documents_health_and_the_envelope() -> None:
    contract = yaml.safe_load(CONTRACT.read_text())
    assert {"/healthz", "/readyz"} <= set(contract["paths"])
    assert "ErrorEnvelope" in contract["components"]["schemas"]
    readyz = contract["paths"]["/readyz"]["get"]["responses"]
    assert {"200", "429", "503"} <= set(readyz)
