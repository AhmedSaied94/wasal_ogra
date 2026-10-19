"""The host firewall keeps Oracle's rules and adds the project's (FR-023, research R13)."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

BASH = shutil.which("bash") or "/bin/bash"
HOST_DIR = Path(__file__).resolve().parent.parent
PROVISION = HOST_DIR / "provision.sh"
ORACLE = HOST_DIR / "tests" / "fixtures" / "oracle-rules.v4"
FINAL_REJECT = "-A INPUT -j REJECT --reject-with icmp-host-prohibited"


def render(*extra: str, source: Path = ORACLE) -> list[str]:
    result = subprocess.run(  # noqa: S603 - fixed script and arguments
        [BASH, str(PROVISION), "--render-firewall", str(source), *extra],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.splitlines()


def rules(lines: list[str]) -> list[str]:
    return [line for line in lines if line.startswith("-A ")]


def input_accepts(lines: list[str], interface: str) -> list[str]:
    return [r for r in rules(lines) if r.startswith(f"-A INPUT -i {interface} ") and "ACCEPT" in r]


def oracle_rules() -> list[str]:
    return rules(ORACLE.read_text().splitlines())


@pytest.mark.parametrize("finalize", [False, True])
def test_oracle_instance_services_are_unchanged(finalize: bool) -> None:
    rendered = render(*(["--finalize"] if finalize else []))
    for chain in ("OUTPUT", "InstanceServices", "FORWARD"):
        expected = [r for r in oracle_rules() if r.startswith(f"-A {chain} ")]
        assert [r for r in rules(rendered) if r.startswith(f"-A {chain} ")] == expected
    assert ":InstanceServices - [0:0]" in rendered
    assert rendered.count("COMMIT") == 1


def test_project_rules_come_before_the_final_reject() -> None:
    inputs = [r for r in rules(render()) if r.startswith("-A INPUT ")]
    assert inputs.count(FINAL_REJECT) == 1
    assert inputs[-1] == FINAL_REJECT
    assert any("-i ens3 " in r for r in inputs)
    assert any("-i wg0 " in r for r in inputs)


def test_oracle_ssh_rule_for_every_interface_is_gone() -> None:
    """It would let any WireGuard peer, staff included, reach SSH."""
    for line in rules(render()):
        if "--dport 22" in line and line.startswith("-A INPUT"):
            assert " -i " in line, line


def public_ports(lines: list[str]) -> set[tuple[str, str]]:
    ports = set()
    for rule in input_accepts(lines, "ens3"):
        proto = rule.split(" -p ")[1].split()[0]
        ports.add((proto, rule.split("--dport ")[1].split()[0]))
    return ports


def test_public_interface_before_finalize() -> None:
    assert public_ports(render()) == {
        ("tcp", "80"),
        ("tcp", "443"),
        ("udp", "51820"),
        ("tcp", "22"),
    }


def test_public_interface_after_finalize() -> None:
    assert public_ports(render("--finalize")) == {("tcp", "80"), ("tcp", "443"), ("udp", "51820")}


@pytest.mark.parametrize("finalize", [False, True])
def test_private_network_by_role(finalize: bool) -> None:
    accepted = set()
    for rule in input_accepts(render(*(["--finalize"] if finalize else [])), "wg0"):
        source = rule.split("--src-range ")[1].split()[0]
        ports = rule.split("--dports ")[1].split()[0] if "--dports" in rule else None
        ports = ports or rule.split("--dport ")[1].split()[0]
        for port in ports.split(","):
            accepted.add((source, port))
    assert accepted == {
        ("10.66.0.2-10.66.0.9", "22"),
        ("10.66.0.2-10.66.0.9", "443"),
        ("10.66.0.10-10.66.0.99", "443"),
        ("10.66.0.200-10.66.0.209", "22"),
    }


def test_public_interface_name_can_be_given() -> None:
    rendered = render("--public-if", "enp0s6")
    assert input_accepts(rendered, "enp0s6")
    assert not input_accepts(rendered, "ens3")


@pytest.mark.parametrize("finalize", [False, True])
def test_rendering_a_rendered_file_changes_nothing(tmp_path: Path, finalize: bool) -> None:
    flags = ["--finalize"] if finalize else []
    once = render(*flags)
    rendered = tmp_path / "rules.v4"
    rendered.write_text("\n".join(once) + "\n")
    assert render(*flags, source=rendered) == once


def test_finalize_can_be_reverted_by_re_rendering(tmp_path: Path) -> None:
    rendered = tmp_path / "rules.v4"
    rendered.write_text("\n".join(render("--finalize")) + "\n")
    assert public_ports(render(source=rendered)) == {
        ("tcp", "80"),
        ("tcp", "443"),
        ("udp", "51820"),
        ("tcp", "22"),
    }


def test_containers_cant_reach_the_metadata_service() -> None:
    lines = render()

    assert lines.count(":DOCKER-USER - [0:0]") == 1
    assert lines.index(":DOCKER-USER - [0:0]") == lines.index("*filter") + 1
    docker_user = [r for r in rules(lines) if r.startswith("-A DOCKER-USER ")]
    # DNS to Oracle's resolver first, then everything else in the link-local range is refused.
    assert [r.split(" -j ")[-1].split()[0] for r in docker_user] == [
        "RETURN",
        "RETURN",
        "REJECT",
        "REJECT",
    ]
    assert all("-d 169.254." in r for r in docker_user)
    assert "--dport 53" in docker_user[0]
    assert "--dport 53" in docker_user[1]
    assert "-d 169.254.0.0/16" in docker_user[-1]
