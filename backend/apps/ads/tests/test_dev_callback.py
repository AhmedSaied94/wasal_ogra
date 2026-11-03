"""`ads_dev_callback` (B07 tasks.md T051): dev and test only, and what it sends is granted."""

from __future__ import annotations

import json
from collections.abc import Iterator
from io import StringIO
from pathlib import Path
from typing import Any

import pytest
import requests
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import Client
from pytest_django import Settings

from apps.accounts.models import Player
from apps.ads.management.commands import ads_dev_callback
from apps.ads.models import AdReward
from apps.ads.services import keys

pytestmark = pytest.mark.django_db


class _Answer:
    def __init__(self, response: Any) -> None:
        self.status_code = response.status_code
        self.text = response.content.decode()


@pytest.fixture
def dev_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, settings: Settings) -> Iterator[Path]:
    directory = tmp_path / ".dev"
    monkeypatch.setattr(ads_dev_callback, "dev_dir", lambda: directory)
    settings.ADS_VERIFIER_KEYS_URL = (directory / "admob_verifier_keys.json").as_uri()
    keys.reset()
    # The command calls the running API; here the test client is the API.
    client = Client()

    def get(url: str, timeout: int) -> _Answer:
        return _Answer(client.get(url.removeprefix("http://localhost:8000")))

    monkeypatch.setattr(requests, "get", get)
    yield directory
    keys.reset()


def send(*args: str) -> str:
    out = StringIO()
    call_command("ads_dev_callback", *args, stdout=out)
    return out.getvalue()


def test_it_refuses_outside_dev_and_test(settings: Settings) -> None:
    settings.WASSAL_ENV = "staging"
    with pytest.raises(CommandError, match="only in dev and test"):
        send()


def test_its_callback_is_granted_and_a_tampered_one_refused(dev_dir: Path, player: Player) -> None:
    output = send("--user", str(player.pk))
    assert "200 {}" in output
    assert AdReward.objects.get().outcome == "granted"
    assert json.loads((dev_dir / "admob_verifier_keys.json").read_text())["keys"]
    assert "403" in send("--user", str(player.pk), "--tamper")
    send("--user", str(player.pk), "--age-days", "8")
    assert AdReward.objects.filter(outcome="expired").count() == 1
