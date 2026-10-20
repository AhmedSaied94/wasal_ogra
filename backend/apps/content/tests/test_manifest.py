"""`GET /v1/content/manifest` (tasks.md T078, contracts/api.md)."""

from __future__ import annotations

import json
import re
from typing import Any

import pytest
from django.core.cache import cache
from django.core.validators import RegexValidator
from django.db import OperationalError
from django.test import Client
from pytest_django import DjangoCaptureOnCommitCallbacks, Settings
from redis.exceptions import ConnectionError as RedisConnectionError
from wassal_content.schemas import default_schema_set

from apps.accounts.models import User
from apps.content.api.serializers import ContentManifestPackSerializer, ContentManifestSerializer
from apps.content.models import ContentPack
from apps.content.models.packs import Status
from apps.content.services import manifest
from apps.content.tests.factories import pack

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("no_throttle")]

URL = "/v1/content/manifest"
PUBLIC = "https://packs.test.invalid/packs/"


def get(client: Client, version: str | None = None) -> dict[str, Any]:
    headers = {} if version is None else {"HTTP_X_CLIENT_VERSION": version}
    response = client.get(URL, **headers)  # type: ignore[arg-type]
    assert response.status_code == 200, response.content
    payload: dict[str, Any] = json.loads(response.content)
    assert default_schema_set().validate_document("manifest", payload) == []
    return payload


def offered(client: Client, version: str | None = None) -> int:
    return int(get(client, version)["version"])


@pytest.fixture
def three(db: None) -> list[ContentPack]:
    """Packs 1-3, published, needing app 1.0.0, 1.2.0 and 1.4.0. Pack 3 is current."""
    return [
        pack(1, Status.PUBLISHED, min_client_version="1.0.0"),
        pack(2, Status.PUBLISHED, min_client_version="1.2.0"),
        pack(3, Status.PUBLISHED, min_client_version="1.4.0"),
    ]


# -- the response table ---------------------------------------------------------------------------


def test_nothing_published_offers_nothing(client: Client) -> None:
    pack(1, Status.VALIDATED)
    assert get(client) == {"version": 0, "packs": []}


def test_the_current_pack_in_full(client: Client, three: list[ContentPack]) -> None:
    current = three[-1]
    assert get(client) == {
        "version": 3,
        "packs": [
            {
                "pack_id": "core",
                "version": 3,
                "url": f"{PUBLIC}core-3.json.gz",
                "sha256": current.sha256,
                "size": current.size,
                "min_client_version": "1.4.0",
            }
        ],
    }


@pytest.mark.parametrize(
    ("stated", "expected"),
    [
        (None, 3),
        ("1.4.0", 3),
        ("2.0.0", 3),
        ("1.4.0+57", 3),
        ("abc", 3),
        ("1.4", 3),
        ("", 3),
        ("1.3.9", 2),
        ("1.2.0", 2),
        ("1.1.0", 1),
        ("1.10.0", 3),
        ("0.9.0", 0),
    ],
)
def test_older_apps_get_the_newest_pack_they_can_read(
    client: Client, three: list[ContentPack], stated: str | None, expected: int
) -> None:
    payload = get(client, stated)
    assert payload["version"] == expected
    assert [entry["version"] for entry in payload["packs"]] == ([expected] if expected else [])


def test_a_retired_pack_still_serves_old_apps(client: Client) -> None:
    pack(1, Status.RETIRED, min_client_version="1.0.0")
    pack(2, Status.PUBLISHED, min_client_version="1.5.0")

    assert offered(client, "1.1.0") == 1


def test_drafts_and_validated_packs_are_never_offered(client: Client) -> None:
    pack(1, Status.PUBLISHED, min_client_version="1.5.0")
    pack(2, Status.VALIDATED, min_client_version="1.0.0", current=False)

    assert offered(client, "1.1.0") == 0


def test_parse_client_version() -> None:
    assert manifest.parse_client_version("1.4.0+57") == (1, 4, 0)
    assert manifest.parse_client_version(" 2.0.1 ") == (2, 0, 1)
    for value in (None, "", "abc", "1.4", "1.4.0.1", "v1.4.0", "1." + "1" * 80 + ".0"):
        assert manifest.parse_client_version(value) is None


def test_urls_come_from_the_public_url(
    client: Client, three: list[ContentPack], settings: Settings
) -> None:
    settings.CONTENT_PACKS_PUBLIC_URL = "https://cdn.example.invalid/packs/"
    assert get(client)["packs"][0]["url"] == "https://cdn.example.invalid/packs/core-3.json.gz"


# -- the request ----------------------------------------------------------------------------------


def test_no_authentication_is_needed(client: Client, three: list[ContentPack]) -> None:
    response = client.get(URL)
    assert response.status_code == 200
    assert response["Cache-Control"] == "no-store"


def test_other_methods_get_405(client: Client) -> None:
    response = client.post(URL, data="{}", content_type="application/json")
    assert response.status_code == 405
    assert json.loads(response.content)["error"]["code"] == "method_not_allowed"


def test_the_database_down_is_503(client: Client, monkeypatch: pytest.MonkeyPatch) -> None:
    def down(*args: Any) -> Any:
        raise OperationalError("connection refused to db:5432")

    monkeypatch.setattr(manifest, "select_pack", down)

    response = client.get(URL)
    assert response.status_code == 503
    assert json.loads(response.content)["error"]["code"] == "dependency_unavailable"


# -- the cache (FR-031) ---------------------------------------------------------------------------


@pytest.fixture
def cached(settings: Settings) -> None:
    settings.CONTENT_MANIFEST_CACHE_SECONDS = 30


@pytest.mark.usefixtures("cached")
def test_answers_are_cached_per_app_version(client: Client, three: list[ContentPack]) -> None:
    assert offered(client) == 3
    assert offered(client, "1.3.0") == 2
    ContentPack.objects.filter(pk=three[1].pk).update(min_client_version="1.3.5")

    assert offered(client, "1.3.0") == 2  # cached
    assert offered(client, "1.3.1") == 1  # a new version, a new answer


@pytest.mark.usefixtures("cached")
def test_invalidate_retires_every_cached_answer(client: Client, three: list[ContentPack]) -> None:
    # Publish and promote call it on commit (test_publish, test_promote).
    assert offered(client) == 3
    assert offered(client, "1.3.0") == 2
    pack(4, Status.PUBLISHED)
    assert offered(client) == 3

    manifest.invalidate()

    # Pack 4 needs app 1.0.0, so both cached answers now name it.
    assert offered(client) == 4
    assert offered(client, "1.3.0") == 4


@pytest.mark.usefixtures("cached")
def test_a_minimum_change_clears_the_cache(
    client: Client,
    three: list[ContentPack],
    publisher: User,
    django_capture_on_commit_callbacks: DjangoCaptureOnCommitCallbacks,
) -> None:
    assert offered(client, "1.3.0") == 2

    with django_capture_on_commit_callbacks(execute=True):
        manifest.change_min_client_version(three[1], "1.3.5", publisher)

    assert offered(client, "1.3.0") == 1


@pytest.mark.usefixtures("cached")
def test_the_cache_down_still_answers(
    client: Client, three: list[ContentPack], monkeypatch: pytest.MonkeyPatch
) -> None:
    def down(*args: Any, **kwargs: Any) -> Any:
        raise RedisConnectionError("valkey:6379 refused")

    for name in ("get", "set", "add", "incr"):
        monkeypatch.setattr(cache, name, down)

    assert offered(client) == 3
    manifest.invalidate()  # logs, never raises


def test_without_a_cache_time_nothing_is_cached(client: Client, three: list[ContentPack]) -> None:
    assert offered(client) == 3
    ContentPack.objects.filter(pk=three[2].pk).update(min_client_version="9.0.0")
    assert offered(client, "1.4.0") == 2


# -- the schema (FR-029) --------------------------------------------------------------------------


def _schema() -> dict[str, Any]:
    return dict(default_schema_set().schemas["manifest"])


def test_the_serializers_match_the_schema() -> None:
    schema = _schema()
    pack_schema = schema["$defs"]["ManifestPack"]
    assert (
        set(ContentManifestSerializer().fields)
        == set(schema["properties"])
        == set(schema["required"])
    )
    fields = ContentManifestPackSerializer().fields
    assert set(fields) == set(pack_schema["properties"]) == set(pack_schema["required"])
    common = default_schema_set().schemas["common"]["$defs"]
    patterns = {
        "pack_id": pack_schema["properties"]["pack_id"]["pattern"],
        "url": pack_schema["properties"]["url"]["pattern"],
        "sha256": common["Sha256"]["pattern"],
        "min_client_version": common["ClientVersion"]["pattern"],
    }
    for name, pattern in patterns.items():
        regexes = [
            re.compile(v.regex).pattern
            for v in fields[name].validators
            if isinstance(v, RegexValidator)
        ]
        assert regexes == [pattern], name
    for name in ("version", "size"):
        assert fields[name].min_value == pack_schema["properties"][name]["minimum"]  # type: ignore[attr-defined]
    packs = ContentManifestSerializer().fields["packs"]
    assert packs.max_length == schema["properties"]["packs"]["maxItems"]  # type: ignore[attr-defined]
