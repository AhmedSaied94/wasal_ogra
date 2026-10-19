"""`wg-peer add|remove|list` (FR-023a, data-model "Private-network peer")."""

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


@pytest.fixture
def host(tmp_path: Path) -> Host:
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


def public_key_of(private_key: str) -> str:
    """What the stub `wg pubkey` derives: nothing of the private key shows through."""
    return f"PUB-{hashlib.sha256(private_key.encode()).hexdigest()[:40]}="


def config_value(config: str, key: str) -> str | None:
    for line in config.splitlines():
        name, sep, value = line.partition(" = ")
        if sep and name.strip() == key:
            return value.strip()
    return None


def test_add_operator(host: Host) -> None:
    config = host.add("ahmed-laptop", "operator")
    private_key = config_value(config, "PrivateKey")
    assert private_key
    assert config_value(config, "Address") == "10.66.0.2/32"
    assert config_value(config, "DNS") == "1.1.1.1"
    assert config_value(config, "PublicKey") == SERVER_PUBLIC_KEY
    assert config_value(config, "Endpoint") == ENDPOINT
    assert config_value(config, "AllowedIPs") == "10.66.0.1/32"
    assert config_value(config, "PersistentKeepalive") == "25"

    public_key = public_key_of(private_key)
    assert host.calls() == [
        f"wg set wg0 peer {public_key} allowed-ips 10.66.0.2/32",
        "wg-quick save wg0",
    ]
    [row] = host.rows()
    assert row[:4] == ["ahmed-laptop", "operator", "10.66.0.2", public_key]
    assert row[4].endswith("Z")
    assert row[5] == ""


def test_private_key_is_kept_in_no_file(host: Host) -> None:
    private_key = config_value(host.add("ahmed-laptop", "operator"), "PrivateKey")
    assert private_key
    for path in host.etc.rglob("*"):
        if path.is_file():
            assert private_key not in path.read_text(), path


@pytest.mark.parametrize(
    ("role", "first", "second"),
    [
        ("operator", "10.66.0.2", "10.66.0.3"),
        ("staff", "10.66.0.10", "10.66.0.11"),
        ("deploy-staging", "10.66.0.200", "10.66.0.201"),
        ("deploy-prod", "10.66.0.200", "10.66.0.201"),
    ],
)
def test_addresses_come_from_the_role_range(host: Host, role: str, first: str, second: str) -> None:
    assert config_value(host.add("one", role), "Address") == f"{first}/32"
    assert config_value(host.add("two", role), "Address") == f"{second}/32"


def test_deploy_ranges_are_shared(host: Host) -> None:
    host.add("ci-staging", "deploy-staging")
    assert config_value(host.add("ci-prod", "deploy-prod"), "Address") == "10.66.0.201/32"


@pytest.mark.parametrize("role", ["deploy-staging", "deploy-prod"])
def test_deploy_configs_have_no_dns(host: Host, role: str) -> None:
    config = host.add("ci", role)
    assert config_value(config, "DNS") is None
    assert config_value(config, "AllowedIPs") == "10.66.0.1/32"


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


def test_list_shows_peers_and_handshakes(host: Host) -> None:
    host.add("ahmed-laptop", "operator")
    host.add("ci-staging", "deploy-staging")
    host.add("old-phone", "staff")
    host.run("remove", "old-phone")
    laptop_key = host.rows()[0][3]
    deploy_key = host.rows()[1][3]
    host.handshakes.write_text(f"{laptop_key}\t1792320000\n{deploy_key}\t0\n")

    result = host.run("list")
    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert lines[0].split() == ["NAME", "ROLE", "ADDRESS", "LATEST-HANDSHAKE"]
    assert lines[1].split() == ["ahmed-laptop", "operator", "10.66.0.2", "2026-10-18T10:40:00Z"]
    assert lines[2].split() == ["ci-staging", "deploy-staging", "10.66.0.200", "never"]
    assert len(lines) == 3  # removed peers aren't listed


def test_unknown_command_shows_usage(host: Host) -> None:
    result = host.run("frobnicate")
    assert result.returncode != 0
    assert "usage" in result.stderr.lower()
