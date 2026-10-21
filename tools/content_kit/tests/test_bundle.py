"""`wassal-content bundle`: the pack each app flavor carries (specs/006-m04-content-loader).

The modes and their failures are in `specs/006-m04-content-loader/contracts/bundling.md`.
"""

import email.message
import gzip
import http.client
import io
import json
import shutil
import urllib.request
import urllib.response
from pathlib import Path

import pytest

from tests.paths import EXAMPLES, REPO_ROOT, SCHEMAS
from wassal_content import bundle
from wassal_content.canonical import canonical_bytes
from wassal_content.cli import main
from wassal_content.loader import load_json_file
from wassal_content.packfile import build_pack_file, sha256_hex
from wassal_content.source import assemble_pack, read_layout


@pytest.fixture(autouse=True)
def at_repo(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.chdir(REPO_ROOT / "tools" / "content_kit")


@pytest.fixture
def dev_out(tmp_path: Path) -> Path:
    out = tmp_path / "dev"
    out.mkdir()
    (out / "README.md").write_text("# Bundled content pack: dev\n")
    assert main(["bundle", "dev", "--out", str(out)]) == 0
    return out


def test_dev_writes_the_sample_and_its_record(dev_out: Path) -> None:
    assert sorted(path.name for path in dev_out.iterdir()) == [
        "README.md",
        "bundled.json",
        "core-1.json.gz",
    ]
    packed = (dev_out / "core-1.json.gz").read_bytes()
    floor = load_json_file(SCHEMAS / "schema-set.json")["min_client_version_by_major"]["1"]
    record = {
        "file": "core-1.json.gz",
        "min_client_version": floor,
        "pack_id": "core",
        "sha256": sha256_hex(packed),
        "size": len(packed),
        "source": "sample",
        "version": 1,
    }
    assert (dev_out / "bundled.json").read_bytes() == canonical_bytes(record)
    pack = json.loads(gzip.decompress(packed))
    assert (pack["pack_id"], pack["version"]) == ("core", 1)


def test_dev_matches_the_samples_golden_checksums(dev_out: Path) -> None:
    golden = load_json_file(EXAMPLES / "sample.golden.json")
    packed = (dev_out / "core-1.json.gz").read_bytes()
    assert (sha256_hex(packed), len(packed)) == (golden["sha256"], golden["size"])


def test_dev_check_passes_on_fresh_output_and_leaves_the_readme(
    dev_out: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    readme = (dev_out / "README.md").read_bytes()
    capsys.readouterr()
    assert main(["bundle", "dev", "--check", "--out", str(dev_out)]) == 0
    assert "match" in capsys.readouterr().out
    assert (dev_out / "README.md").read_bytes() == readme


def test_dev_rewrites_stale_files_and_keeps_the_readme(dev_out: Path) -> None:
    (dev_out / "core-1.json.gz").write_bytes(b"stale")
    (dev_out / "core-7.json.gz").write_bytes(b"old")
    assert main(["bundle", "dev", "--out", str(dev_out)]) == 0
    assert main(["bundle", "dev", "--check", "--out", str(dev_out)]) == 0
    assert not (dev_out / "core-7.json.gz").exists()
    assert (dev_out / "README.md").is_file()


def _check_problems(out: Path, capsys: pytest.CaptureFixture[str]) -> list[str]:
    capsys.readouterr()
    assert main(["bundle", "dev", "--check", "--out", str(out)]) == 1
    return [line for line in capsys.readouterr().out.splitlines() if line.startswith(str(out))]


def test_dev_check_fails_on_one_changed_byte(
    dev_out: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    path = dev_out / "core-1.json.gz"
    data = bytearray(path.read_bytes())
    data[-9] ^= 0x01
    path.write_bytes(bytes(data))
    assert _check_problems(dev_out, capsys) == [f"{path}: differs from a fresh build"]


def test_dev_check_fails_on_a_changed_record_field(
    dev_out: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    path = dev_out / "bundled.json"
    record = json.loads(path.read_bytes())
    record["min_client_version"] = "1.0.1"
    path.write_bytes(canonical_bytes(record))
    assert _check_problems(dev_out, capsys) == [f"{path}: differs from a fresh build"]


def test_dev_check_fails_on_missing_and_unexpected_files(
    dev_out: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    (dev_out / "bundled.json").unlink()
    (dev_out / "core-2.json.gz").write_bytes(b"x")
    assert _check_problems(dev_out, capsys) == [
        f"{dev_out / 'bundled.json'}: missing",
        f"{dev_out / 'core-2.json.gz'}: unexpected file",
    ]


def test_dev_check_names_a_foreign_file_that_bundle_leaves_alone(
    dev_out: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    (dev_out / ".gitkeep").write_text("")
    assert _check_problems(dev_out, capsys) == [
        f"{dev_out / '.gitkeep'}: unexpected file, which `bundle` leaves alone"
    ]
    assert main(["bundle", "dev", "--out", str(dev_out)]) == 0
    assert (dev_out / ".gitkeep").exists(), "bundle removes only files it writes"


def test_dev_refuses_a_golden_without_its_checksums(tmp_path: Path) -> None:
    golden = tmp_path / "golden.json"
    golden.write_text('{"version": 1}')
    with pytest.raises(bundle.BundleError, match="sha256 and size"):
        bundle.dev_bundle(EXAMPLES / "sample", golden)


def test_dev_check_fails_on_a_missing_directory(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    out = tmp_path / "nowhere"
    assert _check_problems(out, capsys) == [
        f"{out / 'bundled.json'}: missing",
        f"{out / 'core-1.json.gz'}: missing",
    ]


# Release mode: content/source at its pack.json version, checked against
# production's release record.

_PACKS_URL = "https://packs.test/packs/"
_STAGES = ("content_rules", "references", "review", "schema", "size", "solver")


@pytest.fixture
def source(tmp_path: Path) -> Path:
    """A copy of the sample, as a promotion of version 7 leaves content/source."""
    layout = tmp_path / "source"
    shutil.copytree(EXAMPLES / "sample", layout)
    meta = json.loads((layout / "pack.json").read_text())
    (layout / "pack.json").write_text(json.dumps({**meta, "version": 7}))
    return layout


def _packed(layout: Path) -> bytes:
    tree, findings = read_layout(layout)
    assert not findings
    return build_pack_file(canonical_bytes(assemble_pack(tree, 7)))


def _record(packed: bytes, **changes: object) -> bytes:
    """Production's release record for [packed], in canonical JSON."""
    record: dict[str, object] = {
        "built_at": "2026-11-02T10:00:00Z",
        "min_client_version": "1.0.0",
        "pack_id": "core",
        "published_at": "2026-11-02T10:05:00Z",
        "schema_version": "1.0",
        "sha256": sha256_hex(packed),
        "size": len(packed),
        "solver": {"stand_in": True, "trips": []},
        "stages": dict.fromkeys(_STAGES, "passed"),
        "version": 7,
        "warnings": [],
    }
    record.update(changes)
    return canonical_bytes(record)


def _release(
    layout: Path, out: Path, monkeypatch: pytest.MonkeyPatch, record: bytes, *extra: str
) -> int:
    fetched: list[str] = []

    def fetch(url: str) -> bytes:
        fetched.append(url)
        return record

    monkeypatch.setattr(bundle, "fetch_record", fetch)
    code = main(
        [
            "bundle",
            "release",
            "--source",
            str(layout),
            "--packs-url",
            _PACKS_URL,
            "--out",
            str(out),
            *extra,
        ]
    )
    if code == 0 and "--check" not in extra:
        assert fetched == [f"{_PACKS_URL}core-7.release.json"]
    return code


@pytest.fixture
def release_out(tmp_path: Path, source: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    out = tmp_path / "release"
    out.mkdir()
    (out / "README.md").write_text("# Bundled content pack: staging and prod\n")
    (out / "core-3.json.gz").write_bytes(b"an older pack")
    assert _release(source, out, monkeypatch, _record(_packed(source))) == 0
    return out


def test_release_writes_the_pack_its_record_and_bundled_json(
    release_out: Path, source: Path
) -> None:
    assert sorted(p.name for p in release_out.iterdir()) == [
        "bundled.json",
        "core-7.json.gz",
        "core-7.release.json",
    ]
    packed = _packed(source)
    record = _record(packed)
    assert (release_out / "core-7.json.gz").read_bytes() == packed
    assert (release_out / "core-7.release.json").read_bytes() == record
    assert (release_out / "bundled.json").read_bytes() == canonical_bytes(
        {
            "file": "core-7.json.gz",
            "min_client_version": "1.0.0",
            "pack_id": "core",
            "release_record_sha256": sha256_hex(record),
            "sha256": sha256_hex(packed),
            "size": len(packed),
            "source": "content_source",
            "version": 7,
        }
    )


def test_release_accepts_size_and_solver_warnings(
    tmp_path: Path, source: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    stages = {**dict.fromkeys(_STAGES, "passed"), "size": "warning", "solver": "warning"}
    record = _record(_packed(source), stages=stages)
    assert _release(source, tmp_path / "out", monkeypatch, record) == 0


def _refused(
    capsys: pytest.CaptureFixture[str],
    layout: Path,
    out: Path,
    monkeypatch: pytest.MonkeyPatch,
    record: bytes,
    message: str,
    *extra: str,
) -> None:
    capsys.readouterr()
    assert _release(layout, out, monkeypatch, record, *extra) == 1
    assert message in capsys.readouterr().out


def test_release_needs_a_promoted_pack(
    tmp_path: Path,
    source: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    record = _record(_packed(source))
    meta = json.loads((source / "pack.json").read_text())
    (source / "pack.json").write_text(json.dumps({**meta, "version": 0}))
    _refused(capsys, source, tmp_path / "out", monkeypatch, record, "version 0")
    empty = tmp_path / "empty"
    empty.mkdir()
    (empty / "README.md").write_text("# content/source\n")
    _refused(capsys, empty, tmp_path / "out", monkeypatch, record, "pack.json")


def test_release_refuses_layout_findings(
    tmp_path: Path,
    source: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    record = _record(_packed(source))
    (source / "rooms" / "salon.json").write_text("{}\n")
    _refused(capsys, source, tmp_path / "out", monkeypatch, record, "findings")


def test_release_needs_an_https_packs_url(
    tmp_path: Path,
    source: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    capsys.readouterr()
    monkeypatch.setattr(bundle, "fetch_record", lambda url: pytest.fail("fetched"))
    args = ["bundle", "release", "--source", str(source), "--out", str(tmp_path / "out")]
    for url in (
        "http://packs.test/packs/",
        "https://user@packs.test/packs/",
        "https://packs.test/packs/?v=1",
        "https://packs.test/packs/#top",
        "https:///packs/",
        "https://[x/",
    ):
        assert main([*args, "--packs-url", url]) == 1, url
        assert "https" in capsys.readouterr().out
    assert main(args) == 2, "release needs --packs-url"


def test_release_refuses_an_unreachable_record(
    tmp_path: Path,
    source: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    def unreachable(url: str) -> bytes:
        raise OSError("connection refused")

    monkeypatch.setattr(bundle, "fetch_record", unreachable)
    capsys.readouterr()
    code = main(
        [
            "bundle",
            "release",
            "--source",
            str(source),
            "--packs-url",
            _PACKS_URL,
            "--out",
            str(tmp_path / "out"),
        ]
    )
    assert code == 1
    assert "release record" in capsys.readouterr().out
    assert not (tmp_path / "out").exists()


@pytest.mark.parametrize(
    ("change", "message"),
    [
        ({"pack_id": "other"}, "pack_id"),
        ({"version": 8}, "version"),
        ({"sha256": "0" * 64}, "sha256"),
        ({"size": 1}, "size"),
        ({"stages": {**dict.fromkeys(_STAGES, "passed"), "review": "failed"}}, "review"),
        ({"stages": {**dict.fromkeys(_STAGES, "passed"), "schema": "warning"}}, "schema"),
        ({"min_client_version": "1.0"}, "min_client_version"),
        ({"min_client_version": "0.9.0"}, "below the schema floor 1.0.0"),
        ({"stages": dict.fromkeys(_STAGES[:-1], "passed")}, "no solver stage"),
        ({"stages": "passed"}, "no stages"),
    ],
)
def test_release_refuses_a_record_that_disagrees(
    tmp_path: Path,
    source: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    change: dict[str, object],
    message: str,
) -> None:
    record = _record(_packed(source), **change)
    _refused(capsys, source, tmp_path / "out", monkeypatch, record, message)


def test_release_refuses_an_oversized_or_loose_record(
    tmp_path: Path,
    source: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    packed = _packed(source)
    padded = _record(packed, warnings=[{"message": "x" * 70000}])
    _refused(capsys, source, tmp_path / "out", monkeypatch, padded, "64 KiB")
    loose = _record(packed).replace(b'"version":7', b'"version":7.0')
    _refused(capsys, source, tmp_path / "out", monkeypatch, loose, "release record")


def _check_release(
    capsys: pytest.CaptureFixture[str], layout: Path, out: Path
) -> tuple[int, list[str]]:
    capsys.readouterr()
    code = main(["bundle", "release", "--check", "--source", str(layout), "--out", str(out)])
    lines = [line for line in capsys.readouterr().out.splitlines() if line.startswith(str(out))]
    return code, lines


def test_check_release_passes_on_fresh_output(
    release_out: Path, source: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert _check_release(capsys, source, release_out) == (0, [])


def test_check_release_fails_on_a_changed_byte_or_record(
    release_out: Path, source: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    pack = release_out / "core-7.json.gz"
    original = pack.read_bytes()
    pack.write_bytes(original[:-9] + bytes([original[-9] ^ 1]) + original[-8:])
    assert _check_release(capsys, source, release_out) == (
        1,
        [f"{pack}: differs from a fresh build"],
    )
    pack.write_bytes(original)

    record = release_out / "bundled.json"
    fresh = record.read_bytes()
    changed = json.loads(fresh)
    changed["release_record_sha256"] = "0" * 64
    record.write_bytes(canonical_bytes(changed))
    assert _check_release(capsys, source, release_out) == (
        1,
        [f"{record}: differs from a fresh build"],
    )
    record.write_bytes(fresh)

    copy = release_out / "core-7.release.json"
    copy.write_bytes(_record(original, sha256="0" * 64))
    code, lines = _check_release(capsys, source, release_out)
    assert code == 1
    assert any("sha256" in line for line in lines), lines


def test_check_release_without_a_promoted_pack(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    layout = tmp_path / "source"
    layout.mkdir()
    (layout / "README.md").write_text("# content/source\n")
    out = tmp_path / "release"
    out.mkdir()
    (out / "README.md").write_text("# release\n")
    assert _check_release(capsys, layout, out) == (0, [])
    (out / "bundled.json").write_text("{}")
    assert _check_release(capsys, layout, out) == (1, [f"{out / 'bundled.json'}: unexpected file"])


def test_check_release_on_the_repository(capsys: pytest.CaptureFixture[str]) -> None:
    out = REPO_ROOT / "apps" / "mobile" / "assets" / "content" / "release"
    assert main(["bundle", "release", "--check", "--out", str(out)]) == 0


# The record fetcher (T051).


class _Response(io.BytesIO):
    status = 200


class _Opener:
    """Records each request; answers with [body]."""

    def __init__(self, body: bytes) -> None:
        self.body = body
        self.calls: list[tuple[str, float]] = []
        self.reads: list[int | None] = []

    def open(self, url: str, timeout: float) -> _Response:
        self.calls.append((url, timeout))
        response = _Response(self.body)
        read = response.read

        def capped(size: int | None = -1) -> bytes:
            self.reads.append(size)
            return read(size)

        response.read = capped  # type: ignore[method-assign]
        return response


def test_fetch_refuses_a_non_https_url_before_any_request() -> None:
    opener = _Opener(b"{}")
    for url in ("http://packs.test/core-7.release.json", "file:///etc/passwd", "ftp://x/y"):
        with pytest.raises(bundle.BundleError, match="https"):
            bundle.fetch_record(url, opener=opener)
    assert opener.calls == []


def test_fetch_reads_at_most_64_kib_with_a_10_s_timeout() -> None:
    url = "https://packs.test/core-7.release.json"
    exact = _Opener(b"x" * bundle.RECORD_MAX_BYTES)
    assert bundle.fetch_record(url, opener=exact) == b"x" * bundle.RECORD_MAX_BYTES
    assert exact.calls == [(url, 10)]
    assert exact.reads == [bundle.RECORD_MAX_BYTES + 1]
    with pytest.raises(bundle.BundleError, match="64 KiB"):
        bundle.fetch_record(url, opener=_Opener(b"x" * (bundle.RECORD_MAX_BYTES + 1)))


class _Found(urllib.response.addinfourl):
    msg = "Found"  # an http.client response carries its reason here


class _Redirecting(urllib.request.HTTPSHandler):
    """An HTTPS handler that answers every request with a 302."""

    def https_open(self, req: urllib.request.Request) -> _Found:  # type: ignore[override]
        headers = email.message.Message()
        headers["Location"] = "https://elsewhere.test/core-7.release.json"
        return _Found(io.BytesIO(b""), headers, req.full_url, 302)


class _Broken(_Opener):
    """Answers with a malformed response."""

    def open(self, url: str, timeout: float) -> _Response:
        raise http.client.IncompleteRead(b"x", 10)


def test_fetch_turns_a_malformed_response_into_a_refusal() -> None:
    with pytest.raises(bundle.BundleError, match="unreachable"):
        bundle.fetch_record("https://packs.test/core-7.release.json", opener=_Broken(b""))


def test_fetch_refuses_redirects() -> None:
    opener = bundle.make_opener(_Redirecting())
    with pytest.raises(bundle.BundleError, match="302"):
        bundle.fetch_record("https://packs.test/core-7.release.json", opener=opener)
