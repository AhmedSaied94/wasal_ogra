"""`wg-peer add|remove|list` (FR-023a, data-model "Private-network peer").

Each host has its own /24, from `WG_ADDRESS` in its `host.env`: `10.66.0.0/24` on the prod host,
`10.67.0.0/24` on the staging host (contracts/operations.md "Host identity").
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

BASH = shutil.which("bash") or "/bin/bash"
WG_PEER = Path(__file__).resolve().parent.parent / "bin" / "wg-peer"
SERVER_PUBLIC_KEY = "SERVERPUBLICKEYxxxxxxxxxxxxxxxxxxxxxxxxxxxx="
ENDPOINT = "203.0.113.10:51820"
HOST_ENV = {
    "prod": "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\n",
    "staging": "WASSAL_ENV=staging\nWG_ADDRESS=10.67.0.1\n",
}

STUB_WG = """#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  genkey) echo "PRIV$(date +%s%N)${RANDOM}=" ;;
  pubkey) read -r key; echo "PUB-$(printf '%s' "$key" | sha256sum | cut -c1-40)=" ;;
  set) echo "wg $*" >> "$WG_STUB_LOG" ;;
  show) cat "$WG_STUB_HANDSHAKES" ;;
  *) echo "unexpected: wg $*" >&2; exit 2 ;;
esac
"""
STUB_WG_QUICK = """#!/usr/bin/env bash
echo "wg-quick $*" >> "$WG_STUB_LOG"
"""


@dataclass
class Host:
    etc: Path
    log: Path
    handshakes: Path
    env: dict[str, str]

    def run(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(  # noqa: S603 - fixed script and arguments
            [BASH, str(WG_PEER), *args],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )

    def add(self, name: str, role: str) -> str:
        result = self.run("add", name, role)
        assert result.returncode == 0, result.stderr
        return result.stdout

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines() if self.log.exists() else []

    def rows(self) -> list[list[str]]:
        lines = (self.etc / "wg-peers.tsv").read_text().splitlines()
        return [line.split("\t") for line in lines[1:]]


def make_host(tmp_path: Path, wassal_env: str) -> Host:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name, body in (("wg", STUB_WG), ("wg-quick", STUB_WG_QUICK)):
        stub = bin_dir / name
        stub.write_text(body)
        stub.chmod(0o755)
    etc = tmp_path / "etc"
    etc.mkdir()
    (etc / "wg-server.env").write_text(
        f"WG_SERVER_PUBLIC_KEY={SERVER_PUBLIC_KEY}\nWG_ENDPOINT={ENDPOINT}\n"
    )
    (etc / "host.env").write_text(HOST_ENV[wassal_env])
    handshakes = tmp_path / "handshakes"
    handshakes.write_text("")
    log = tmp_path / "wg.log"
    env = {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "WASSAL_ETC": str(etc),
        "WG_STUB_LOG": str(log),
        "WG_STUB_HANDSHAKES": str(handshakes),
    }
    return Host(etc, log, handshakes, env)


@pytest.fixture
def host(tmp_path: Path) -> Host:
    """The prod host."""
    return make_host(tmp_path, "prod")


@pytest.fixture
def staging(tmp_path: Path) -> Host:
    """The staging host."""
    return make_host(tmp_path, "staging")


def public_key_of(private_key: str) -> str:
    """What the stub `wg pubkey` derives: nothing of the private key shows through."""
    return f"PUB-{hashlib.sha256(private_key.encode()).hexdigest()[:40]}="


def config_value(config: str, key: str) -> str | None:
    for line in config.splitlines():
        name, sep, value = line.partition(" = ")
        if sep and name.strip() == key:
            return value.strip()
    return None


@pytest.mark.parametrize(
    ("wassal_env", "address", "server"),
    [("prod", "10.66.0.2", "10.66.0.1"), ("staging", "10.67.0.2", "10.67.0.1")],
)
def test_add_operator(tmp_path: Path, wassal_env: str, address: str, server: str) -> None:
    host = make_host(tmp_path, wassal_env)
    config = host.add("ahmed-laptop", "operator")
    private_key = config_value(config, "PrivateKey")
    assert private_key
    assert config_value(config, "Address") == f"{address}/32"
    assert config_value(config, "DNS") == "1.1.1.1"
    assert config_value(config, "PublicKey") == SERVER_PUBLIC_KEY
    assert config_value(config, "Endpoint") == ENDPOINT
    assert config_value(config, "AllowedIPs") == f"{server}/32"
    assert config_value(config, "PersistentKeepalive") == "25"

    public_key = public_key_of(private_key)
    assert host.calls() == [
        f"wg set wg0 peer {public_key} allowed-ips {address}/32",
        "wg-quick save wg0",
    ]
    [row] = host.rows()
    assert row[:4] == ["ahmed-laptop", "operator", address, public_key]
    assert row[4].endswith("Z")
    assert row[5] == ""


def test_private_key_is_kept_in_no_file(host: Host) -> None:
    private_key = config_value(host.add("ahmed-laptop", "operator"), "PrivateKey")
    assert private_key
    for path in host.etc.rglob("*"):
        if path.is_file():
            assert private_key not in path.read_text(), path


@pytest.mark.parametrize(
    ("wassal_env", "role", "first", "second"),
    [
        ("prod", "operator", "10.66.0.2", "10.66.0.3"),
        ("prod", "staff", "10.66.0.10", "10.66.0.11"),
        ("prod", "deploy-prod", "10.66.0.200", "10.66.0.201"),
        ("staging", "operator", "10.67.0.2", "10.67.0.3"),
        ("staging", "staff", "10.67.0.10", "10.67.0.11"),
        ("staging", "deploy-staging", "10.67.0.200", "10.67.0.201"),
    ],
)
def test_addresses_come_from_the_role_range_in_the_hosts_subnet(
    tmp_path: Path, wassal_env: str, role: str, first: str, second: str
) -> None:
    host = make_host(tmp_path, wassal_env)
    assert config_value(host.add("one", role), "Address") == f"{first}/32"
    assert config_value(host.add("two", role), "Address") == f"{second}/32"


@pytest.mark.parametrize(
    ("wassal_env", "role"), [("prod", "deploy-staging"), ("staging", "deploy-prod")]
)
def test_the_other_hosts_deploy_role_is_refused(tmp_path: Path, wassal_env: str, role: str) -> None:
    host = make_host(tmp_path, wassal_env)

    result = host.run("add", "ci", role)

    assert result.returncode != 0
    assert f"this is the {wassal_env} host" in result.stderr
    assert f"deploy-{wassal_env}" in result.stderr
    assert host.calls() == []
    assert not (host.etc / "wg-peers.tsv").exists()


@pytest.mark.parametrize(
    ("wassal_env", "role", "server"),
    [("prod", "deploy-prod", "10.66.0.1"), ("staging", "deploy-staging", "10.67.0.1")],
)
def test_deploy_configs_have_no_dns(
    tmp_path: Path, wassal_env: str, role: str, server: str
) -> None:
    config = make_host(tmp_path, wassal_env).add("ci", role)
    assert config_value(config, "DNS") is None
    assert config_value(config, "AllowedIPs") == f"{server}/32"


def test_staff_configs_have_dns(host: Host) -> None:
    assert config_value(host.add("sara-phone", "staff"), "DNS") == "1.1.1.1"


@pytest.mark.parametrize("name", ["a", "x" * 33, "Ahmed", "bad_name", "has space", ""])
def test_invalid_names_are_refused(host: Host, name: str) -> None:
    result = host.run("add", name, "staff")
    assert result.returncode != 0
    assert "name" in result.stderr
    assert host.calls() == []


def test_duplicate_name_is_refused(host: Host) -> None:
    host.add("sara-phone", "staff")
    result = host.run("add", "sara-phone", "operator")
    assert result.returncode != 0
    assert "already" in result.stderr
    assert len(host.rows()) == 1


@pytest.mark.parametrize("role", ["admin", "deploy", "root", ""])
def test_invalid_roles_are_refused(host: Host, role: str) -> None:
    result = host.run("add", "someone", role)
    assert result.returncode != 0
    assert "role" in result.stderr
    assert host.calls() == []


def test_full_range_is_refused(host: Host) -> None:
    for number in range(8):  # 10.66.0.2 - 10.66.0.9
        host.add(f"op-{number}", "operator")
    result = host.run("add", "op-8", "operator")
    assert result.returncode != 0
    assert "full" in result.stderr


def test_remove_revokes_and_frees_the_address(host: Host) -> None:
    host.add("one", "operator")
    host.add("two", "operator")
    public_key = host.rows()[0][3]
    result = host.run("remove", "one")
    assert result.returncode == 0, result.stderr
    assert host.calls()[-2:] == [f"wg set wg0 peer {public_key} remove", "wg-quick save wg0"]
    assert host.rows()[0][5].endswith("Z")  # removed_at
    assert config_value(host.add("three", "operator"), "Address") == "10.66.0.2/32"
    assert config_value(host.add("one", "operator"), "Address") == "10.66.0.4/32"


def test_remove_unknown_peer_is_refused(host: Host) -> None:
    result = host.run("remove", "ghost")
    assert result.returncode != 0
    assert "no active peer" in result.stderr


def test_list_shows_peers_and_handshakes(staging: Host) -> None:
    staging.add("ahmed-laptop", "operator")
    staging.add("deploy-staging", "deploy-staging")
    staging.add("old-phone", "staff")
    staging.run("remove", "old-phone")
    laptop_key = staging.rows()[0][3]
    deploy_key = staging.rows()[1][3]
    staging.handshakes.write_text(f"{laptop_key}\t1792320000\n{deploy_key}\t0\n")

    result = staging.run("list")
    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert lines[0].split() == ["NAME", "ROLE", "ADDRESS", "LATEST-HANDSHAKE"]
    assert lines[1].split() == ["ahmed-laptop", "operator", "10.67.0.2", "2026-10-18T10:40:00Z"]
    assert lines[2].split() == ["deploy-staging", "deploy-staging", "10.67.0.200", "never"]
    assert len(lines) == 3  # removed peers aren't listed


def test_unknown_command_shows_usage(host: Host) -> None:
    result = host.run("frobnicate")
    assert result.returncode != 0
    assert "usage" in result.stderr.lower()


# -- host identity ---------------------------------------------------------------------------------


def test_add_needs_host_env(host: Host) -> None:
    (host.etc / "host.env").unlink()

    result = host.run("add", "ahmed-laptop", "operator")

    assert result.returncode != 0
    assert "host.env is missing" in result.stderr
    assert host.calls() == []
    assert not (host.etc / "wg-peers.tsv").exists()


@pytest.mark.parametrize(
    "contents",
    [
        "",
        "WASSAL_ENV=prod\n",  # no WG_ADDRESS
        "WG_ADDRESS=10.66.0.1\n",  # no WASSAL_ENV
        "WASSAL_ENV=dev\nWG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=prod\nWG_ADDRESS=10.67.0.1\n",  # staging's address on prod
        "WASSAL_ENV=staging\nWG_ADDRESS=10.66.0.1\n",  # and prod's on staging
        "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1/24\n",
        "WASSAL_ENV=prod\nWASSAL_ENV=staging\nWG_ADDRESS=10.66.0.1\n",
        'WASSAL_ENV="prod"\nWG_ADDRESS=10.66.0.1\n',
        "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\nPATH=/tmp\n",  # only the two lines belong
        "WASSAL_ENV=prod\r\nWG_ADDRESS=10.66.0.1\r\n",
    ],
)
def test_add_refuses_a_malformed_host_env(host: Host, contents: str) -> None:
    (host.etc / "host.env").write_text(contents)

    result = host.run("add", "ahmed-laptop", "operator")

    assert result.returncode != 0
    assert "host.env" in result.stderr
    assert host.calls() == []
    assert not (host.etc / "wg-peers.tsv").exists()


def test_host_env_is_read_as_data(host: Host, tmp_path: Path) -> None:
    marker = tmp_path / "sourced"
    (host.etc / "host.env").write_text(f"WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\ntouch {marker}\n")

    host.run("add", "ahmed-laptop", "operator")

    assert not marker.exists()


def test_revoking_access_does_not_depend_on_host_env(host: Host) -> None:
    host.add("old-phone", "staff")
    (host.etc / "host.env").unlink()

    assert host.run("list").returncode == 0
    result = host.run("remove", "old-phone")

    assert result.returncode == 0, result.stderr
    assert host.rows()[0][5].endswith("Z")
