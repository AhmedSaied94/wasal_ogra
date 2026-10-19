"""The host deploy script (FR-030 to FR-034, research R10).

The steps and exit codes are contracts/operations.md "Deploy interface".

`bin/deploy` runs under bash with stub `docker`, `curl`, `flock` and `sleep` first on `PATH`. The
stubs log every call and act like the real stack: `compose up` with `RELEASE_TAG=<tag>` makes
`/healthz` report that image's release, unless the case says the release never gets ready.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest

BASH = shutil.which("bash") or "/bin/bash"
DEPLOY = Path(__file__).resolve().parent.parent / "bin" / "deploy"
REPO = "ghcr.io/ahmedsaied94/wassal-backend"
OLD = "sha-" + "a" * 40
NEW = "sha-" + "b" * 40
OLDER = "sha-" + "c" * 40
PORTS = {"staging": (8200, 8201), "prod": (8100, 8101)}

STUB = """
import json, os, sys
from pathlib import Path

name = Path(sys.argv[0]).name
args = sys.argv[1:]
state = Path(os.environ["STUB_DIR"])
with open(state / "calls.jsonl", "a") as log:
    log.write(json.dumps({"cmd": name, "args": args, "tag": os.environ.get("RELEASE_TAG")}) + "\\n")

def listed(var, value):
    return value in os.environ.get(var, "").split(",")

if name == "flock":
    sys.exit(1 if os.environ.get("STUB_FLOCK_FAIL") else 0)
if name == "sleep":
    sys.exit(0)
if name == "curl":
    url = next(a for a in args if a.startswith("http://"))
    if url.endswith("/readyz"):
        sys.exit(22 if os.environ.get("STUB_READYZ_FAIL") else 0)
    serving = state / "serving"
    release = serving.read_text() if serving.exists() else "nothing"
    print(json.dumps({"status": "ok", "release": release}))
    sys.exit(0)

# docker
if args[0] == "pull":
    sys.exit(1 if os.environ.get("STUB_PULL_FAIL") else 0)
if args[:2] == ["image", "inspect"]:
    tag = args[-1].rsplit(":", 1)[1]
    print("PATH=/usr/local/bin:/usr/bin")
    if not os.environ.get("STUB_NO_RELEASE"):
        print(f"RELEASE=rel-{tag}")
    sys.exit(0)
if args[0] == "create":
    print("cid-" + args[-1].rsplit(":", 1)[1])
    sys.exit(0)
if args[0] == "cp":
    dest = Path(args[2])
    (dest / "env").mkdir(parents=True, exist_ok=True)
    (dest / "postgres" / "initdb").mkdir(parents=True, exist_ok=True)
    (dest / "compose.yml").write_text("services: {}\\n")
    (dest / "postgres" / "initdb" / "01-app-role.sh").write_text("# init\\n")
    env_state = dest.parent.parent
    for env, ports in (("staging", (8200, 8201)), ("prod", (8100, 8101))):
        initdb = os.environ.get("STUB_INITDB_DIR", str(env_state.parent / env / "initdb"))
        (dest / "env" / f"{env}.env").write_text(
            f"API_PORT={ports[0]}\\nADMIN_PORT={ports[1]}\\nPOSTGRES_INITDB_DIR={initdb}\\n"
            f"BACKUP_STATE_DIR={env_state.parent / env / 'backup'}\\n"
        )
    sys.exit(0)
if args[0] == "rm" or args[:2] == ["image", "rm"]:
    sys.exit(0)
if args[:2] == ["image", "ls"]:
    images = state / "images"
    if images.exists():
        print(images.read_text(), end="")
    sys.exit(0)
if args[0] == "compose":
    tag = os.environ["RELEASE_TAG"]
    if "config" in args:
        # What `docker compose config --format json` renders for the real stack, from the sizing
        # file, with STUB_STACK_PATCH ({"<service>": {...}, "volumes": {...}}) merged in.
        sizing = Path(args[args.index("--env-file") + 1])
        values = dict(line.split("=", 1) for line in sizing.read_text().splitlines() if "=" in line)
        app = f"ghcr.io/ahmedsaied94/wassal-backend:{tag}"
        def service(image, **extra):
            networks = {"default": None}
            return {"image": image, "networks": networks, "restart": "unless-stopped", **extra}
        loopback = [{"host_ip": "127.0.0.1", "target": 8000, "published": "1"}]
        services = {name: service(app, ports=loopback) for name in ("api", "admin")}
        services |= {name: service(app) for name in ("worker", "beat", "migrate")}
        backup_dir = values.get("BACKUP_STATE_DIR")
        services["backup"] = service(app, volumes=[
            {"type": "bind", "source": backup_dir, "target": "/var/lib/wassal/backup"},
        ])
        services["postgres"] = service("postgres:17.11-trixie", volumes=[
            {"type": "volume", "source": "pgdata", "target": "/var/lib/postgresql/data"},
            {"type": "bind", "source": values.get("POSTGRES_INITDB_DIR"),
             "target": "/docker-entrypoint-initdb.d", "read_only": True},
        ])
        services["valkey"] = service("valkey/valkey:8.1.10-trixie")
        config = {
            "name": "x",
            "services": services,
            "networks": {"default": {"name": "x_default", "ipam": {}}},
            "volumes": {"pgdata": {"name": "x_pgdata"}},
        }
        for key, patch in json.loads(os.environ.get("STUB_STACK_PATCH", "{}")).items():
            target = config if key in ("volumes", "networks") else config["services"]
            target.setdefault(key, {}).update(patch)
        print(json.dumps(config))
        sys.exit(0)
    if "run" in args:
        failing = os.environ.get("STUB_MIGRATE_FAIL") or any("SystemExit" in a for a in args)
        sys.exit(1 if failing else 0)
    if "up" in args:
        if listed("STUB_UP_FAIL_TAGS", tag):
            sys.exit(1)
        if not listed("STUB_UP_SILENT_TAGS", tag):
            (state / "serving").write_text(f"rel-{tag}")
        sys.exit(0)
sys.exit(f"stub {name}: unexpected {args}")
"""


@dataclass
class Host:
    root: Path
    stubs: Path
    state: Path
    locks: Path

    def env_state(self, env: str) -> Path:
        return self.state / env

    def serving(self, env: str, tag: str) -> None:
        """Pretend `tag` is the release serving `env`, deployed earlier by this script."""
        base = self.env_state(env)
        copy = base / "deploy" / tag
        (copy / "env").mkdir(parents=True)
        api, admin = PORTS[env]
        (copy / "env" / f"{env}.env").write_text(f"API_PORT={api}\nADMIN_PORT={admin}\n")
        (copy / "compose.yml").write_text("services: {}\n")
        (base / "release").write_text(tag + "\n")
        (self.stubs / "serving").write_text(f"rel-{tag}")

    def images(self, *tags: str) -> None:
        (self.stubs / "images").write_text("".join(f"{tag}\n" for tag in tags))

    def run(self, only: str, request: str | None, **stub_env: str) -> Result:
        env = {
            "PATH": f"{self.stubs}:{os.environ['PATH']}",
            "STUB_DIR": str(self.stubs),
            "WASSAL_STATE_DIR": str(self.state),
            "WASSAL_LOCK_DIR": str(self.locks),
            "WASSAL_VERIFY_TIMEOUT": "6",
            "WASSAL_VERIFY_INTERVAL": "2",
            **stub_env,
        }
        if request is not None:
            env["SSH_ORIGINAL_COMMAND"] = request
        result = subprocess.run(  # noqa: S603 - fixed script and arguments
            [BASH, str(DEPLOY), "--only", only],
            env=env,
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
        log = self.stubs / "calls.jsonl"
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        log.unlink(missing_ok=True)
        return Result(result.returncode, result.stdout, result.stderr, calls)


@dataclass
class Result:
    code: int
    stdout: str
    stderr: str
    calls: list[dict[str, Any]]

    def docker(self) -> list[list[str]]:
        return [c["args"] for c in self.calls if c["cmd"] == "docker"]

    def steps(self) -> list[str]:
        """The docker calls as short step names, in order."""
        names = []
        for call in self.calls:
            args = call["args"]
            if call["cmd"] == "flock":
                names.append("lock")
            elif call["cmd"] != "docker":
                continue
            elif args[0] == "compose":
                step = "config" if "config" in args else "migrate" if "run" in args else "up"
                names.append(f"{step}:{call['tag']}")
            else:
                names.append(" ".join(args[:2]) if args[0] == "image" else args[0])
        return names

    def ups(self) -> list[str]:
        return [c["tag"] for c in self.calls if c["cmd"] == "docker" and "up" in c["args"]]


@pytest.fixture
def host(tmp_path: Path) -> Host:
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    for name in ("docker", "curl", "flock", "sleep"):
        target = stubs / name
        target.write_text(f"#!{sys.executable}\n{STUB}")
        target.chmod(0o755)
    (tmp_path / "locks").mkdir()
    return Host(tmp_path, stubs, tmp_path / "state", tmp_path / "locks")


def compose_prefix(host: Host, env: str, tag: str) -> list[str]:
    copy = host.env_state(env) / "deploy" / tag
    return [
        "compose",
        "-p",
        f"wassal-{env}",
        "-f",
        str(copy / "compose.yml"),
        "--env-file",
        str(copy / "env" / f"{env}.env"),
    ]


# -- success ---------------------------------------------------------------------------------------


def test_first_deploy_runs_every_step_in_order(host: Host) -> None:
    result = host.run("staging", f"staging {NEW}")

    assert result.code == 0, result.stderr
    assert result.steps() == [
        "lock",
        "pull",
        "image inspect",
        "create",
        "cp",
        "rm",
        f"config:{NEW}",
        f"migrate:{NEW}",
        f"up:{NEW}",
        "image ls",
    ]
    copy = host.env_state("staging") / "deploy" / NEW
    config, migrate, up = (args for args in result.docker() if args[0] == "compose")
    assert config == [
        *compose_prefix(host, "staging", NEW),
        "--profile",
        "ops",
        "config",
        "--format",
        "json",
    ]
    assert migrate == [
        *compose_prefix(host, "staging", NEW),
        "--profile",
        "ops",
        "run",
        "--rm",
        "migrate",
    ]
    assert up[: len(compose_prefix(host, "staging", NEW))] == compose_prefix(host, "staging", NEW)
    assert up[-4:] == ["api", "admin", "worker", "beat"]
    assert {"up", "-d", "--no-deps", "--wait"} <= set(up)
    assert ["pull", f"{REPO}:{NEW}"] == [a for a in result.docker()[0] if a != "--quiet"]
    # Copied beside the final directory, then renamed, so a half-done copy is never used.
    assert result.docker()[3] == ["cp", f"cid-{NEW}:/app/deploy/.", f"{copy}.new/"]
    assert not copy.with_name(f"{NEW}.new").exists()
    assert (copy / "compose.yml").is_file()
    initdb = host.env_state("staging") / "initdb"
    assert (initdb / "01-app-role.sh").is_file()
    assert not initdb.with_name("initdb.new").exists()
    assert (host.env_state("staging") / "release").read_text() == f"{NEW}\n"
    assert not (host.env_state("staging") / "release.previous").exists()
    summary = json.loads(result.stdout)
    assert summary["env"] == "staging"
    assert summary["tag"] == NEW
    assert summary["release"] == f"rel-{NEW}"
    assert summary["previous"] == ""


def test_verify_checks_readiness_and_release_on_both_ports(host: Host) -> None:
    result = host.run("staging", f"staging {NEW}")

    urls = [
        next(a for a in c["args"] if a.startswith("http"))
        for c in result.calls
        if c["cmd"] == "curl"
    ]
    assert urls == [
        "http://127.0.0.1:8200/readyz",
        "http://127.0.0.1:8200/healthz",
        "http://127.0.0.1:8201/readyz",
        "http://127.0.0.1:8201/healthz",
    ]
    assert all("--max-time" in c["args"] for c in result.calls if c["cmd"] == "curl")


def test_a_later_deploy_records_the_previous_release_and_prunes(host: Host) -> None:
    host.serving("staging", OLD)
    (host.env_state("staging") / "deploy" / OLDER).mkdir()
    host.images(OLDER, OLD, NEW, "v1.2.3", "<none>")

    result = host.run("staging", f"staging {NEW}")

    assert result.code == 0, result.stderr
    base = host.env_state("staging")
    assert (base / "release").read_text() == f"{NEW}\n"
    assert (base / "release.previous").read_text() == f"{OLD}\n"
    assert sorted(p.name for p in (base / "deploy").iterdir()) == sorted([OLD, NEW])
    removed = [args for args in result.docker() if args[:2] == ["image", "rm"]]
    assert removed == [["image", "rm", f"{REPO}:{OLDER}"]]
    assert json.loads(result.stdout)["previous"] == OLD


def test_production_deploys_a_version_tag(host: Host) -> None:
    result = host.run("prod", "prod v1.2.3")

    assert result.code == 0, result.stderr
    assert result.steps()[-2] == "up:v1.2.3"
    up = next(args for args in result.docker() if "up" in args)
    assert up[:3] == ["compose", "-p", "wassal-prod"]
    assert (host.env_state("prod") / "release").read_text() == "v1.2.3\n"


def test_the_lock_is_per_environment(host: Host) -> None:
    host.run("staging", f"staging {NEW}")
    assert (host.locks / "wassal-deploy-staging.lock").exists()
    flock = next(c for c in host.run("prod", "prod v1.0.0").calls if c["cmd"] == "flock")
    assert flock["args"][:2] == ["-w", "900"]


def test_redeploying_the_serving_tag_only_reverifies(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {OLD}")

    assert result.code == 0, result.stderr
    assert result.steps() == ["lock", "image inspect"]
    assert any(c["cmd"] == "curl" for c in result.calls)
    assert (host.env_state("staging") / "release").read_text() == f"{OLD}\n"
    assert not (host.env_state("staging") / "release.previous").exists()


# -- bad input -------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("only", "request_"),
    [
        ("prod", f"staging {NEW}"),  # the wrong environment for this key
        ("staging", f"prod {NEW}"),
        ("prod", f"prod {NEW}"),  # a staging tag sent to prod
        ("staging", "staging v1.2.3"),  # a version tag sent to staging
        ("staging", f"staging {NEW};id"),  # shell metacharacters
        ("staging", f"staging $({NEW})"),
        ("prod", "prod v1.2.3&&id"),
        ("staging", f"staging {NEW} rehearse-migrate-fail extra"),  # extra tokens
        ("staging", f"staging {NEW} rehearse-everything"),
        ("staging", f"staging {NEW}\nid"),  # a second line
        ("staging", "staging"),
        ("staging", ""),
        ("staging", None),
        ("dev", f"dev {NEW}"),
    ],
)
def test_bad_input_exits_2_without_touching_docker(
    host: Host, only: str, request_: str | None
) -> None:
    result = host.run(only, request_)

    assert result.code == 2
    assert result.calls == []
    assert not host.state.exists()


@pytest.mark.parametrize("argv", [[], ["--only"], ["staging"], ["--only", "staging", "extra"]])
def test_bad_arguments_exit_2(host: Host, argv: list[str]) -> None:
    result = subprocess.run(  # noqa: S603 - fixed script and arguments
        [BASH, str(DEPLOY), *argv],
        env={
            "PATH": f"{host.stubs}:{os.environ['PATH']}",
            "STUB_DIR": str(host.stubs),
            "SSH_ORIGINAL_COMMAND": f"staging {NEW}",
        },
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 2
    assert not (host.stubs / "calls.jsonl").exists()


@pytest.mark.parametrize("rehearsal", ["rehearse-migrate-fail", "rehearse-verify-fail"])
def test_rehearsals_are_refused_for_production(host: Host, rehearsal: str) -> None:
    result = host.run("prod", f"prod v1.2.3 {rehearsal}")

    assert result.code == 2
    assert result.calls == []


def test_the_image_repository_cannot_be_changed(host: Host) -> None:
    result = host.run(
        "staging",
        f"staging {NEW}",
        IMAGE_REPO="evil.example/x",
        WASSAL_IMAGE="evil.example/x",
        REPO="evil.example/x",
    )

    assert result.code == 0, result.stderr
    assert not any("evil" in arg for args in result.docker() for arg in args)
    assert f"{REPO}:{NEW}" in result.docker()[0]
    assert f"readonly IMAGE_REPO={REPO}\n" in DEPLOY.read_text()


# -- failures --------------------------------------------------------------------------------------


def test_lock_timeout_exits_3(host: Host) -> None:
    result = host.run("staging", f"staging {NEW}", STUB_FLOCK_FAIL="1")

    assert result.code == 3
    assert result.docker() == []


def test_pull_failure_exits_4(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {NEW}", STUB_PULL_FAIL="1")

    assert result.code == 4
    assert result.steps() == ["lock", "pull"]
    assert (host.env_state("staging") / "release").read_text() == f"{OLD}\n"


def test_an_image_without_a_release_exits_4(host: Host) -> None:
    result = host.run("staging", f"staging {NEW}", STUB_NO_RELEASE="1")

    assert result.code == 4
    assert not any(args[0] == "compose" for args in result.docker())


def test_migrate_failure_exits_5_and_restarts_nothing(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {NEW}", STUB_MIGRATE_FAIL="1")

    assert result.code == 5
    assert result.ups() == []
    assert (host.env_state("staging") / "release").read_text() == f"{OLD}\n"
    assert result.stdout == ""


def test_verify_failure_restores_the_previous_release_and_exits_6(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {NEW}", STUB_UP_SILENT_TAGS=NEW)

    assert result.code == 6
    assert result.ups() == [NEW, OLD]
    restore = [args for args in result.docker() if "up" in args][1]
    assert restore[: len(compose_prefix(host, "staging", OLD))] == compose_prefix(
        host, "staging", OLD
    )
    assert (host.env_state("staging") / "release").read_text() == f"{OLD}\n"
    assert (host.stubs / "serving").read_text() == f"rel-{OLD}"
    sleeps = [c for c in result.calls if c["cmd"] == "sleep"]
    assert [c["args"] for c in sleeps] == [["2"]] * 2  # 3 attempts, 2 s apart


def test_a_failed_restart_also_restores(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {NEW}", STUB_UP_FAIL_TAGS=NEW)

    assert result.code == 6
    assert result.ups() == [NEW, OLD]


def test_a_failed_restore_exits_7(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {NEW}", STUB_UP_SILENT_TAGS=NEW, STUB_UP_FAIL_TAGS=OLD)

    assert result.code == 7
    assert result.ups() == [NEW, OLD]


def test_a_failed_first_deploy_exits_6_and_leaves_it_running(host: Host) -> None:
    result = host.run("staging", f"staging {NEW}", STUB_READYZ_FAIL="1")

    assert result.code == 6
    assert result.ups() == [NEW]
    assert not (host.env_state("staging") / "release").exists()


# -- rehearsals ------------------------------------------------------------------------------------


def test_the_migrate_rehearsal_fails_the_real_migrate_step(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {NEW} rehearse-migrate-fail")

    assert result.code == 5
    migrate = next(args for args in result.docker() if "run" in args)
    service = migrate.index("migrate")
    assert migrate[service - 2 : service] == ["run", "--rm"]
    assert any("SystemExit" in arg for arg in migrate[service + 1 :])
    assert result.ups() == []


def test_the_verify_rehearsal_restores_the_previous_release(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {NEW} rehearse-verify-fail")

    assert result.code == 6
    assert result.ups() == [NEW, OLD]
    assert (host.env_state("staging") / "release").read_text() == f"{OLD}\n"


def test_a_rehearsal_on_the_serving_tag_still_runs_the_failure_path(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {OLD} rehearse-migrate-fail")

    assert result.code == 5
    assert "pull" in result.steps()


def test_a_sizing_file_with_another_initdb_path_exits_4(host: Host) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {NEW}", STUB_INITDB_DIR="/")

    # The stack check refuses the bind of / before initdb is synced or anything runs.
    assert result.code == 4
    assert "postgres: the bind mount of / isn't allowed" in result.stderr
    assert [step for step in result.steps() if step.startswith(("migrate", "up"))] == []
    assert not (host.env_state("staging") / "initdb").exists()
    assert (host.env_state("staging") / "release").read_text() == f"{OLD}\n"


@pytest.mark.parametrize(
    ("patch", "problem"),
    [
        ({"api": {"privileged": True}}, "api: privileged isn't allowed"),
        ({"worker": {"network_mode": "host"}}, "worker: network_mode isn't allowed"),
        (
            {"beat": {"volumes": [{"type": "bind", "source": "/", "target": "/host"}]}},
            "beat: the bind mount of / isn't allowed",
        ),
        ({"api": {"image": "ghcr.io/someone/else:1"}}, "api: the image isn't"),
        (
            # The point of the case: a port on every interface must be refused.
            {"admin": {"ports": [{"host_ip": "0.0.0.0", "target": 8000}]}},  # noqa: S104
            "admin: a port isn't bound to 127.0.0.1",
        ),
        ({"miner": {"image": "x:1"}}, "unknown service miner"),
        (
            {"volumes": {"pgdata": {"driver_opts": {"device": "/"}}}},
            "volume pgdata: only a plain named volume",
        ),
        ({"postgres": {"cap_add": ["SYS_ADMIN"]}}, "postgres: cap_add isn't allowed"),
    ],
)
def test_a_stack_that_asks_for_the_host_is_refused(
    host: Host, patch: dict[str, Any], problem: str
) -> None:
    host.serving("staging", OLD)

    result = host.run("staging", f"staging {NEW}", STUB_STACK_PATCH=json.dumps(patch))

    assert result.code == 4
    assert problem in result.stderr
    assert "asks for more than this host allows" in result.stderr
    assert [step for step in result.steps() if step.startswith(("migrate", "up"))] == []
    assert not (host.env_state("staging") / "initdb").exists()
    assert (host.env_state("staging") / "release").read_text() == f"{OLD}\n"


def test_another_environments_backup_directory_is_refused(host: Host) -> None:
    prod_dir = str(host.env_state("prod") / "backup")
    bind = {"type": "bind", "source": prod_dir, "target": "/var/lib/wassal/backup"}

    result = host.run(
        "staging", f"staging {NEW}", STUB_STACK_PATCH=json.dumps({"backup": {"volumes": [bind]}})
    )

    assert result.code == 4
    assert f"backup: the bind mount of {prod_dir} isn't allowed" in result.stderr
