"""Healthchecks.io pings (FR-038, research R11)."""

from unittest import mock

import pytest
import requests

from apps.common.services import monitoring

URL = "https://hc.invalid/ping/check"


def answer(status: int) -> requests.Response:
    response = requests.Response()
    response.status_code = status
    return response


def test_success_ping_is_a_get() -> None:
    with mock.patch("requests.get", return_value=answer(200)) as get:
        monitoring.ping(URL)
    get.assert_called_once_with(URL, timeout=10, allow_redirects=False)


@pytest.mark.parametrize("kind", ["fail", "start"])
def test_kind_is_appended(kind: monitoring.PingKind) -> None:
    with mock.patch("requests.get", return_value=answer(200)) as get:
        monitoring.ping(URL + "/", kind=kind, timeout=5)
    get.assert_called_once_with(f"{URL}/{kind}", timeout=5, allow_redirects=False)


def test_body_is_posted_as_utf8() -> None:
    with mock.patch("requests.post", return_value=answer(200)) as post:
        monitoring.ping(URL, kind="fail", body="backup failed: disk full ✗")
    post.assert_called_once_with(
        f"{URL}/fail",
        data="backup failed: disk full ✗".encode(),
        timeout=10,
        allow_redirects=False,
    )


def test_a_redirect_is_a_failed_ping_and_is_not_followed() -> None:
    with (
        mock.patch("requests.get", return_value=answer(302)),
        pytest.raises(requests.HTTPError, match="HTTP 302"),
    ):
        monitoring.ping(URL)


def test_empty_url_does_nothing() -> None:
    with mock.patch("requests.get") as get, mock.patch("requests.post") as post:
        monitoring.ping("", body="x")
    get.assert_not_called()
    post.assert_not_called()


def test_http_error_raises_without_the_url() -> None:
    response = mock.Mock(spec=requests.Response)
    response.status_code = 503
    response.raise_for_status.side_effect = requests.HTTPError(f"503 Server Error for url: {URL}")
    with (
        mock.patch("requests.get", return_value=response),
        pytest.raises(requests.RequestException) as excinfo,
    ):
        monitoring.ping(URL)
    assert "ping/check" not in str(excinfo.value)
    assert "503" in str(excinfo.value)
    assert excinfo.value.__cause__ is None


def test_connection_error_raises_without_the_url() -> None:
    error = requests.ConnectionError(f"Max retries exceeded with url: {URL}")
    with (
        mock.patch("requests.get", side_effect=error),
        pytest.raises(requests.RequestException) as excinfo,
    ):
        monitoring.ping(URL)
    assert "ping/check" not in str(excinfo.value)
    assert "ConnectionError" in str(excinfo.value)
