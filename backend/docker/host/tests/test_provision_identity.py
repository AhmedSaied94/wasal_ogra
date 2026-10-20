"""`provision.sh` gives each host one environment, once (FR-001a, contracts/operations.md "Host
identity").

`provision.sh --identity --root <dir>` runs the host-identity step alone, with every path under
`<dir>`: it checks `--env` against `host.env`, `wg0.conf` and `edge.env`, names what the one-host
design left behind, and records `host.env` on the first run. `provision.sh --render-dirs <env>`
prints the state directories a run creates, with their owner and mode. The rest of a run needs root
and the real host.
"""

from __future__ import annotations

import re
import shutil
import stat
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

BASH = shutil.which("bash") or "/bin/bash"
HOST_DIR = Path(__file__).resolve().parent.parent
PROVISION = HOST_DIR / "provision.sh"
DOCKERFILE = HOST_DIR.parent / "Dockerfile"
PUBLIC_IP = "203.0.113.10"
WG_ADDRESS = {"prod": "10.66.0.1", "staging": "10.67.0.1"}
OTHER = {"prod": "staging", "staging": "prod"}
TIMERS = {
    "prod": "wassal-backup@prod.timer wassal-host-monitor.timer",
    # Its own backups since B04 (research R8), and the drill of production's.
    "staging": (
        "wassal-backup@staging.timer wassal-restore-drill@prod.timer wassal-host-monitor.timer"
    ),
}
# The image's app user and its group (docker/Dockerfile).
APP_USER = "10001:10001"
PEERS_HEADER = "name\trole\taddress\tpublic_key\tadded_at\tremoved_at\n"


def host_env(env: str) -> str:
    return f"WASSAL_ENV={env}\nWG_ADDRESS={WG_ADDRESS[env]}\n"


@dataclass
class Host:
    root: Path

    @property
    def etc(self) -> Path:
        return self.root / "etc" / "wassal"

    @property
    def state(self) -> Path:
        return self.root / "var" / "lib" / "wassal"

    @property
    def wg_conf(self) -> Path:
        return self.root / "etc" / "wireguard" / "wg0.conf"

    @property
    def host_env(self) -> Path:
        return self.etc / "host.env"

    def run(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(  # noqa: S603 - fixed script and arguments
            [BASH, str(PROVISION), "--identity", "--root", str(self.root), *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )

    def provision(self, env: str) -> subprocess.CompletedProcess[str]:
        result = self.run("--env", env, "--public-ip", PUBLIC_IP)
        assert result.returncode == 0, result.stderr
        return result

    def write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def snapshot(self) -> dict[str, tuple[int, bytes | None]]:
        """Every path under the root, with its mode and, for files, its content."""
        return {
            str(path.relative_to(self.root)): (
                path.stat().st_mode,
                path.read_bytes() if path.is_file() else None,
            )
            for path in sorted(self.root.rglob("*"))
        }


@pytest.fixture
def host(tmp_path: Path) -> Host:
    root = tmp_path / "root"
    root.mkdir()
    return Host(root)


def warnings(result: subprocess.CompletedProcess[str]) -> list[str]:
    return [line for line in result.stdout.splitlines() if "WARNING" in line]


def render_dirs(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603 - fixed script and arguments
        [BASH, str(PROVISION), "--render-dirs", *args],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def state_dirs(env: str) -> dict[str, tuple[str, str]]:
    """The state directories of the env's host: {path: (mode, owner)}."""
    result = render_dirs(env)
    assert result.returncode == 0, result.stderr
    return {
        path: (mode, owner)
        for mode, owner, path in (line.split(" ") for line in result.stdout.splitlines())
    }


def backup_condition(env: str) -> str:
    """The env file the backup unit's instance for env waits for."""
    service = (HOST_DIR / "systemd" / "wassal-backup@.service").read_text()
    [condition] = [line for line in service.splitlines() if line.startswith("ConditionPathExists=")]
    return condition.removeprefix("ConditionPathExists=").replace("%i", env)


# -- First run -------------------------------------------------------------------------------------


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_first_run_records_the_environment_and_its_address(host: Host, env: str) -> None:
    host.provision(env)

    # Exactly these bytes: the other host scripts parse it as strictly.
    assert host.host_env.read_bytes() == host_env(env).encode()
    assert stat.S_IMODE(host.host_env.stat().st_mode) == 0o600
    assert stat.S_IMODE(host.etc.stat().st_mode) == 0o700
    assert [path.name for path in host.etc.iterdir()] == ["host.env"]


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_the_run_names_the_hosts_timers(host: Host, env: str) -> None:
    result = host.provision(env)

    assert f"timers {TIMERS[env]}" in result.stdout
    assert f"{env} host, WireGuard {WG_ADDRESS[env]}" in result.stdout


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_each_host_backs_up_its_own_environment_only(host: Host, env: str) -> None:
    timers = host.provision(env).stdout.split(" timers ", 1)[1].split()

    assert [t for t in timers if t.startswith("wassal-backup@")] == [f"wassal-backup@{env}.timer"]


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_the_backup_waits_for_the_hosts_own_env_file(env: str) -> None:
    """The timer is on from the start, as production's is, and every run is skipped, not failed,
    until the operator adds that environment's backup env file (monitoring-setup.md)."""
    assert backup_condition(env) == f"/etc/wassal/{env}-backup.env"


@pytest.mark.parametrize(
    "args",
    [
        pytest.param(["--public-ip", PUBLIC_IP], id="no-env"),
        pytest.param(["--env", "prod"], id="no-public-ip"),
        pytest.param([], id="neither"),
    ],
)
def test_first_run_needs_env_and_public_ip(host: Host, args: list[str]) -> None:
    result = host.run(*args)

    assert result.returncode == 1
    assert "--env" in result.stderr
    assert "--public-ip" in result.stderr
    assert host.snapshot() == {}


@pytest.mark.parametrize("env", ["dev", "test", "PROD", "prod ", "production", ""])
def test_unknown_env_is_refused(host: Host, env: str) -> None:
    result = host.run("--env", env, "--public-ip", PUBLIC_IP)

    assert result.returncode != 0
    assert "--env" in result.stderr
    assert host.snapshot() == {}


# -- Later runs ------------------------------------------------------------------------------------


@pytest.mark.parametrize("env", ["prod", "staging"])
@pytest.mark.parametrize(
    "args",
    [
        pytest.param([], id="no-options"),
        pytest.param(["--env", "same"], id="same-env"),
        pytest.param(["--public-ip", "198.51.100.7"], id="public-ip"),
    ],
)
def test_later_runs_read_host_env(host: Host, env: str, args: list[str]) -> None:
    host.provision(env)
    before = host.snapshot()

    result = host.run(*[env if arg == "same" else arg for arg in args])

    assert result.returncode == 0, result.stderr
    assert f"{env} host, WireGuard {WG_ADDRESS[env]}" in result.stdout
    assert host.snapshot() == before


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_a_different_env_is_refused_before_anything_changes(host: Host, env: str) -> None:
    host.provision(env)
    before = host.snapshot()

    result = host.run("--env", OTHER[env], "--public-ip", PUBLIC_IP)

    assert result.returncode == 1
    assert env in result.stderr
    assert OTHER[env] in result.stderr
    assert host.snapshot() == before


@pytest.mark.parametrize(
    "content",
    [
        pytest.param("", id="empty"),
        pytest.param("WASSAL_ENV=dev\nWG_ADDRESS=10.66.0.1\n", id="unknown-env"),
        pytest.param("WASSAL_ENV=\nWG_ADDRESS=10.66.0.1\n", id="empty-env"),
        pytest.param("WASSAL_ENV=prod\nWG_ADDRESS=10.67.0.1\n", id="prod-with-staging-address"),
        pytest.param("WASSAL_ENV=staging\nWG_ADDRESS=10.66.0.1\n", id="staging-with-prod-address"),
        pytest.param("WASSAL_ENV=prod\n", id="no-address"),
        pytest.param("WG_ADDRESS=10.66.0.1\n", id="no-env"),
        pytest.param("WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\nWASSAL_ENV=prod\n", id="env-twice"),
        pytest.param(
            "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\nWG_ADDRESS=10.66.0.1\n", id="address-twice"
        ),
        pytest.param('WASSAL_ENV="prod"\nWG_ADDRESS=10.66.0.1\n', id="quoted"),
        pytest.param("WASSAL_ENV=prod \nWG_ADDRESS=10.66.0.1\n", id="trailing-space"),
        pytest.param("WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1/24\n", id="address-with-prefix"),
        pytest.param("WASSAL_ENV=prod\n\nWG_ADDRESS=10.66.0.1\n", id="blank-line"),
        pytest.param("WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\nPATH=/tmp\n", id="extra-line"),
        pytest.param("WASSAL_ENV=prod\r\nWG_ADDRESS=10.66.0.1\r\n", id="crlf"),
        pytest.param("WASSAL_ENV=$(touch pwned)\nWG_ADDRESS=10.66.0.1\n", id="not-sourced"),
    ],
)
@pytest.mark.parametrize("args", [[], ["--env", "prod"]], ids=["no-env", "with-env"])
def test_malformed_host_env_is_refused_before_anything_changes(
    host: Host, content: str, args: list[str]
) -> None:
    host.write(host.host_env, content)
    host.host_env.chmod(0o600)
    before = host.snapshot()

    result = host.run(*args, "--public-ip", PUBLIC_IP)

    assert result.returncode == 1
    assert "host.env" in result.stderr
    assert host.snapshot() == before
    assert not (host.root / "pwned").exists()


# -- What has to agree with host.env -------------------------------------------------------------


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_edge_env_must_bind_the_admin_to_the_hosts_address(host: Host, env: str) -> None:
    host.provision(env)
    host.write(host.etc / "edge.env", f"ADMIN_BIND_IP={WG_ADDRESS[OTHER[env]]}\n")
    before = host.snapshot()

    result = host.run()

    assert result.returncode == 1
    assert "ADMIN_BIND_IP" in result.stderr
    assert WG_ADDRESS[env] in result.stderr
    assert host.snapshot() == before


def test_edge_env_without_an_admin_bind_is_refused(host: Host) -> None:
    host.provision("prod")
    host.write(host.etc / "edge.env", "PUBLIC_BIND_IP=10.0.0.28\n")

    result = host.run()

    assert result.returncode == 1
    assert "ADMIN_BIND_IP" in result.stderr


def test_edge_env_is_checked_on_the_first_run_too(host: Host) -> None:
    host.write(host.etc / "edge.env", "ADMIN_BIND_IP=10.66.0.1\n")
    before = host.snapshot()

    result = host.run("--env", "staging", "--public-ip", PUBLIC_IP)

    assert result.returncode == 1
    assert "ADMIN_BIND_IP" in result.stderr
    assert host.snapshot() == before


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_edge_env_with_the_hosts_address_is_accepted(host: Host, env: str) -> None:
    host.provision(env)
    host.write(
        host.etc / "edge.env",
        f"PUBLIC_BIND_IP=10.0.0.28\nADMIN_BIND_IP={WG_ADDRESS[env]}\nPUBLIC_TLS=ops@example.com\n"
        "API_HOST=api.example.com\nADMIN_HOST=admin.example.com\n",
    )

    result = host.run()

    assert result.returncode == 0, result.stderr
    assert not warnings(result)


def test_wireguard_config_of_another_address_is_refused(host: Host) -> None:
    """The one-host design's wg0.conf (10.66.0.1) on the staging VM, which must move aside."""
    host.write(host.wg_conf, "[Interface]\nAddress = 10.66.0.1/24\nListenPort = 51820\n")
    before = host.snapshot()

    result = host.run("--env", "staging", "--public-ip", PUBLIC_IP)

    assert result.returncode == 1
    assert "wg0.conf" in result.stderr
    assert "10.67.0.1/24" in result.stderr
    assert host.snapshot() == before


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_wireguard_config_of_the_hosts_address_is_kept(host: Host, env: str) -> None:
    host.write(host.wg_conf, f"[Interface]\nAddress = {WG_ADDRESS[env]}/24\nListenPort = 51820\n")

    host.provision(env)

    assert host.host_env.read_text() == host_env(env)


# -- Leftovers of the one-host design ------------------------------------------------------------


def test_staging_host_names_leftovers_and_keeps_them(host: Host) -> None:
    (host.state / "prod").mkdir(parents=True)
    (host.state / "staging").mkdir(parents=True)
    for name in (
        "prod.env",
        "prod-db.env",
        "prod-backup.env",
        "staging.env",
        "staging-backup.env",
        "prod-drill.env",
    ):
        host.write(host.etc / name, "X=1\n")
    host.write(
        host.etc / "wg-peers.tsv",
        PEERS_HEADER
        + "laptop\toperator\t10.66.0.2\tPUB1=\t2026-10-18T10:00:00Z\t\n"
        + "phone\toperator\t10.67.0.2\tPUB2=\t2026-10-19T10:00:00Z\t\n"
        + "old-ci\tdeploy-prod\t10.67.0.200\tPUB3=\t2026-10-19T10:00:00Z\t\n"
        + "gone\tstaff\t10.66.0.10\tPUB4=\t2026-10-18T10:00:00Z\t2026-10-18T11:00:00Z\n",
    )
    host.write(
        host.etc / "edge.env",
        "PUBLIC_BIND_IP=10.1.0.216\nADMIN_BIND_IP=10.67.0.1\nPUBLIC_TLS=ops@example.com\n"
        "PROD_API_HOST=api.example.com\nSTAGING_API_HOST=staging-api.example.com\n",
    )
    before = host.snapshot()

    result = host.provision("staging")

    named = "\n".join(warnings(result))
    for name in ("prod.env", "prod-db.env", "prod-backup.env"):
        assert str(host.etc / name) in named
    assert str(host.state / "prod") in named
    assert "laptop" in named
    assert "old-ci" in named
    assert "PROD_" in named
    # Staging takes its own backups since B04 (research R8).
    for name in ("staging.env", "staging-backup.env", "prod-drill.env"):
        assert str(host.etc / name) not in named
    assert str(host.state / "staging") not in named
    assert "phone" not in named
    assert "gone" not in named
    after = host.snapshot()
    del after["etc/wassal/host.env"]
    assert after == before


def test_prod_host_names_leftovers(host: Host) -> None:
    (host.state / "staging").mkdir(parents=True)
    for name in (
        "staging.env",
        "staging-db.env",
        "staging-backup.env",
        "prod-drill.env",
        "prod.env",
        "prod-backup.env",
    ):
        host.write(host.etc / name, "X=1\n")
    host.write(
        host.etc / "wg-peers.tsv",
        PEERS_HEADER
        + "staging-runner\tdeploy-staging\t10.66.0.200\tPUB1=\t2026-10-19T10:00:00Z\t\n"
        + "prod-runner\tdeploy-prod\t10.66.0.201\tPUB2=\t2026-10-19T10:00:00Z\t\n",
    )

    result = host.provision("prod")

    named = "\n".join(warnings(result))
    for name in ("staging.env", "staging-db.env", "staging-backup.env", "prod-drill.env"):
        assert str(host.etc / name) in named
    assert str(host.state / "staging") in named
    assert "staging-runner" in named
    assert "prod-runner" not in named
    for name in ("prod.env", "prod-backup.env"):
        assert str(host.etc / name) not in named
    assert (host.etc / "staging.env").exists()
    assert (host.state / "staging").is_dir()


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_a_clean_host_has_no_warnings(host: Host, env: str) -> None:
    assert not warnings(host.provision(env))


# -- State directories -----------------------------------------------------------------------------


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_the_hosts_state_directories(env: str) -> None:
    assert state_dirs(env) == {
        "/var/lib/wassal": ("0755", "root:root"),
        # It holds the stack definitions that root runs, so it stays root's.
        f"/var/lib/wassal/{env}": ("0755", "root:root"),
        "/var/lib/wassal/host-monitor": ("0755", "root:root"),
        # The backup container's own directory, as bin/backup makes it (B04 research R8 on staging).
        f"/var/lib/wassal/{env}/backup": ("0750", APP_USER),
        # The worker publishes into it and the edge serves it read-only (B04).
        "/var/lib/wassal/packs": ("0755", APP_USER),
    }


def test_the_app_user_is_the_images() -> None:
    assert re.search(r"useradd [^\n]*--uid 10001 --user-group", DOCKERFILE.read_text())


@pytest.mark.parametrize("args", [[], ["dev"], ["prod", "staging"], ["../prod"]])
def test_render_dirs_needs_one_environment(args: list[str]) -> None:
    result = render_dirs(*args)

    assert result.returncode == 1
    assert "--render-dirs staging|prod" in result.stderr
    assert result.stdout == ""
