"""Each host's edge proxies to its own environment's ports (FR-001a, FR-005, contracts/operations.md
"Edge").

Both hosts run the same `edge/Caddyfile`. Its sites import the snippets `api-{$WASSAL_ENV}` and
`admin-{$WASSAL_ENV}`, and each snippet holds one environment's loopback port, which must equal
`API_PORT` or `ADMIN_PORT` in that environment's sizing file, `docker/env/<env>.env`.
`edge/smoke.sh` checks that Caddy loads the file for both environments and refuses an empty one.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

DOCKER = Path(__file__).resolve().parents[2]
CADDYFILE = DOCKER / "edge" / "Caddyfile"
ENVIRONMENTS = ["prod", "staging"]
ROLES = {"api": "API_PORT", "admin": "ADMIN_PORT"}
# A snippet definition: its name, then its body up to the first closing brace at the line start.
SNIPPET = re.compile(r"^\(([\w-]+)\)\s*\{\n(.*?)^\}", re.MULTILINE | re.DOTALL)


def snippets() -> dict[str, str]:
    return {name: body for name, body in SNIPPET.findall(CADDYFILE.read_text())}


def sizing(env: str) -> dict[str, str]:
    lines = (DOCKER / "env" / f"{env}.env").read_text().splitlines()
    return dict(line.split("=", 1) for line in lines if line and not line.startswith("#"))


def sites() -> list[tuple[str, str]]:
    """The site blocks after the snippets, as text."""
    text = CADDYFILE.read_text()
    return re.findall(r"^(?!\()(\S[^\n]*)\{\n(.*?)^\}", text, re.MULTILINE | re.DOTALL)


@pytest.mark.parametrize("env", ENVIRONMENTS)
@pytest.mark.parametrize("role", ROLES)
def test_snippet_port_is_the_sizing_files_port(env: str, role: str) -> None:
    body = snippets()[f"{role}-{env}"]

    assert body.split() == ["import", role, sizing(env)[ROLES[role]]]


def test_the_environments_use_different_ports() -> None:
    ports = [sizing(env)[key] for env in ENVIRONMENTS for key in ROLES.values()]

    assert len(set(ports)) == len(ports)


def test_only_the_environment_snippets_name_ports() -> None:
    """A site that named a port itself would serve that port on both hosts."""
    named = {
        name for name, body in snippets().items() if re.search(r"import (api|admin) \d+", body)
    }
    text = CADDYFILE.read_text()

    assert named == {f"{role}-{env}" for role in ROLES for env in ENVIRONMENTS}
    assert len(re.findall(r"import (?:api|admin) \d+", text)) == len(named)


@pytest.mark.parametrize(
    ("address", "bind", "role"),
    [("{$API_HOST}", "{$PUBLIC_BIND_IP}", "api"), ("{$ADMIN_HOST}", "{$ADMIN_BIND_IP}", "admin")],
)
def test_each_site_imports_its_hosts_snippet(address: str, bind: str, role: str) -> None:
    by_address = {head.strip(): body for head, body in sites()}

    lines = [line.strip() for line in by_address[address].splitlines()]

    assert f"bind {bind}" in lines
    assert f"import {role}-{{$WASSAL_ENV}}" in lines


def test_the_edge_has_one_api_and_one_admin_site() -> None:
    addresses = {head.strip() for head, _ in sites()}

    assert addresses == {"{$API_HOST}", "{$ADMIN_HOST}", "http://127.0.0.1:2020"}


def test_the_edge_reads_host_env_then_edge_env() -> None:
    """host.env's WASSAL_ENV picks the snippets; edge.env holds the binds and hostnames."""
    compose = yaml.safe_load((DOCKER / "edge" / "compose.yml").read_text())

    assert compose["services"]["caddy"]["env_file"] == [
        "/etc/wassal/host.env",
        "/etc/wassal/edge.env",
    ]
