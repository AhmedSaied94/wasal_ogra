"""The host firewall keeps Oracle's rules and adds the project's (FR-023, research R13).

Each host's `wg0` rules use its own /24, from its WireGuard address: `10.66.0.1` on prod and
`10.67.0.1` on staging (contracts/operations.md "Network exposure").
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

BASH = shutil.which("bash") or "/bin/bash"
HOST_DIR = Path(__file__).resolve().parent.parent
PROVISION = HOST_DIR / "provision.sh"
ORACLE = HOST_DIR / "tests" / "fixtures" / "oracle-rules.v4"
ORACLE_V6 = HOST_DIR / "tests" / "fixtures" / "oracle-rules.v6"
FINAL_REJECT = "-A INPUT -j REJECT --reject-with icmp-host-prohibited"
WG_ADDRESSES = ["10.66.0.1", "10.67.0.1"]


def run_render(*extra: str, source: Path = ORACLE) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603 - fixed script and arguments
        [BASH, str(PROVISION), "--render-firewall", str(source), *extra],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def render(*extra: str, source: Path = ORACLE) -> list[str]:
    result = run_render(*extra, source=source)
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


def private_network(lines: list[str]) -> set[tuple[str, str]]:
    accepted = set()
    for rule in input_accepts(lines, "wg0"):
        source = rule.split("--src-range ")[1].split()[0]
        ports = rule.split("--dports ")[1].split()[0] if "--dports" in rule else None
        ports = ports or rule.split("--dport ")[1].split()[0]
        for port in ports.split(","):
            accepted.add((source, port))
    return accepted


@pytest.mark.parametrize("wg_address", WG_ADDRESSES)
@pytest.mark.parametrize("finalize", [False, True])
def test_private_network_by_role(finalize: bool, wg_address: str) -> None:
    flags = ["--finalize"] if finalize else []
    net = wg_address.rsplit(".", 1)[0]

    rendered = render(*flags, "--wg-address", wg_address)

    assert private_network(rendered) == {
        (f"{net}.2-{net}.9", "22"),
        (f"{net}.2-{net}.9", "443"),
        (f"{net}.10-{net}.99", "443"),
        (f"{net}.200-{net}.209", "22"),
    }


def test_private_network_defaults_to_the_prod_host() -> None:
    assert render() == render("--wg-address", "10.66.0.1")


@pytest.mark.parametrize("wg_address", ["10.67.0.2", "10.67.0", "10.67.0.1/24", "x.67.0.1", ""])
def test_wg_address_must_be_a_host_address(wg_address: str) -> None:
    result = run_render("--wg-address", wg_address)

    assert result.returncode != 0
    assert "--wg-address" in result.stderr
    assert not result.stdout


@pytest.mark.parametrize(
    "template",
    ["iptables/rules.v4.tmpl", "wireguard/wg0.conf.example", "sshd_config.d/wassal.conf"],
)
def test_templates_name_no_private_address(template: str) -> None:
    """provision.sh fills in the host's own address, so neither host gets the other's."""
    text = (HOST_DIR / template).read_text()

    assert "10.66." not in text
    assert "10.67." not in text


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


def test_unfiltered_ipv6_is_left_as_it_is() -> None:
    """Oracle's Ubuntu image doesn't filter IPv6, so there is no REJECT to insert before."""
    assert render("--ipv6", source=ORACLE_V6) == ORACLE_V6.read_text().splitlines()


def test_filtered_ipv6_gets_the_public_rules(tmp_path: Path) -> None:
    reject = "-A INPUT -j REJECT --reject-with icmp6-adm-prohibited"
    source = tmp_path / "rules.v6"
    source.write_text(f"*filter\n:INPUT ACCEPT [0:0]\n{reject}\nCOMMIT\n")

    rendered = render("--ipv6", source=source)

    assert [r for r in rules(rendered) if r.startswith("-A INPUT ")][-1] == reject
    assert public_ports(rendered) == {
        ("tcp", "80"),
        ("tcp", "443"),
        ("udp", "51820"),
        ("tcp", "22"),
    }
    assert not input_accepts(rendered, "wg0")


def test_unfiltered_ipv4_is_refused(tmp_path: Path) -> None:
    """Without Oracle's final REJECT there is no IPv4 firewall to add the project rules to."""
    source = tmp_path / "rules.v4"
    source.write_text(ORACLE_V6.read_text())

    result = run_render(source=source)

    assert result.returncode != 0
    assert "no final INPUT REJECT" in result.stderr


def test_rules_are_loaded_with_a_full_restore() -> None:
    """Oracle's image makes `netfilter-persistent reload` append, so the old rules keep deciding."""
    lines = PROVISION.read_text().splitlines()
    code = [line for line in lines if not line.lstrip().startswith("#")]
    assert not [line for line in code if "netfilter-persistent reload" in line]
    assert any("iptables-restore < /etc/iptables/rules.v4" in line for line in code)
    assert any("ip6tables-restore < /etc/iptables/rules.v6" in line for line in code)


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
