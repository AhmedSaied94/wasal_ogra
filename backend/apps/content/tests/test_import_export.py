"""Import and export in the `content/source` layout (tasks.md T059, contracts/content-source.md)."""

from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path
from typing import Any

import pytest
from django.core.exceptions import PermissionDenied
from django.core.management import CommandError, call_command
from pytest_django import Settings
from wassal_content.canonical import canonical_bytes
from wassal_content.packfile import build_pack_file, sha256_hex
from wassal_content.source import assemble_pack, read_layout

from apps.accounts.models import User
from apps.content.models import Line, SpeechLine, Station, Trip
from apps.content.models.packs import Status
from apps.content.services import exporter, importer, permanence, review
from apps.content.tests import factories as make
from apps.content.tests.conftest import SAMPLE

pytestmark = pytest.mark.django_db

MiB = 1024 * 1024


def sample_files() -> dict[str, bytes]:
    return {
        path.relative_to(SAMPLE).as_posix(): path.read_bytes()
        for path in SAMPLE.rglob("*")
        if path.is_file()
    }


def zipped(files: dict[str, bytes]) -> bytes:
    return exporter.zip_bytes(files)


def unzipped(data: bytes) -> dict[str, bytes]:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        return {name: archive.read(name) for name in archive.namelist()}


def edited(files: dict[str, bytes], name: str, change: Any) -> dict[str, bytes]:
    document = json.loads(files[name])
    change(document)
    return {**files, name: (json.dumps(document, ensure_ascii=False) + "\n").encode()}


def codes(refused: importer.ImportRefused) -> list[str]:
    return [finding.code for finding in refused.findings]


# -- round trip (US2-4) ---------------------------------------------------------------------------


def test_the_sample_round_trips_byte_for_byte(author: User) -> None:
    result = importer.import_zip(zipped(sample_files()), author)

    assert len(result.added) == 41
    assert unzipped(exporter.export_current(author)) == sample_files()


def test_importing_the_same_content_again_changes_nothing(sample_imported: User) -> None:
    result = importer.import_dir(SAMPLE, sample_imported)

    assert (result.added, result.changed, result.unchanged) == ([], [], 41)


def test_a_zip_of_the_layout_folder_is_accepted(author: User) -> None:
    wrapped = {f"sample/{name}": data for name, data in sample_files().items()}

    assert len(importer.import_zip(zipped(wrapped), author).added) == 41


# -- all or nothing (US2-3) -----------------------------------------------------------------------


def test_one_invalid_file_refuses_the_whole_import(author: User) -> None:
    trip = "trips/line_gamaa/line_gamaa.02.json"
    broken = edited(sample_files(), trip, lambda t: t["stations"][0].update(fare_piasters=475))

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(zipped(broken), author)

    (finding,) = refused.value.findings
    assert (finding.file, finding.path, finding.code) == (
        trip,
        "$.stations[0].fare_piasters",
        "V-SC",
    )
    assert not Line.objects.exists()


def test_a_reference_problem_names_its_file(author: User) -> None:
    trip = "trips/line_gamaa/line_gamaa.02.json"
    broken = edited(
        sample_files(), trip, lambda t: t["passengers"][0].update(dest_station_id="midan")
    )

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(zipped(broken), author)

    assert [(f.file, f.code, f.path) for f in refused.value.findings] == [
        (trip, "V-T4", "$.passengers[0].dest_station_id")
    ]


def test_a_refused_import_leaves_stored_content_unchanged(sample_imported: User) -> None:
    before = exporter.current_files(sample_imported)
    files = edited(sample_files(), "lines/line_hay.json", lambda line: line.update(order=9))
    files = edited(files, "catalog.json", lambda c: c["prices"][0].update(currency="JENEHAT"))

    with pytest.raises(importer.ImportRefused):
        importer.import_zip(zipped(files), sample_imported)

    assert exporter.current_files(sample_imported) == before


# -- zip safety -----------------------------------------------------------------------------------


def raw_zip(entries: list[tuple[zipfile.ZipInfo | str, bytes]]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for info, data in entries:
            archive.writestr(info, data)
    return buffer.getvalue()


def symlink(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name)
    info.external_attr = 0o120777 << 16
    return info


@pytest.mark.parametrize(
    ("entries", "message"),
    [
        ([("../evil.json", b"{}")], "'..'"),
        ([("lines/../../evil.json", b"{}")], "'..'"),
        ([("/etc/evil.json", b"{}")], "absolute"),
        ([("lines\\evil.json", b"{}")], "backslashes"),
        ([(symlink("lines/line_hay.json"), b"/etc/passwd")], "symlinks"),
        ([(f"x{n}.json", b"") for n in range(2001)], "2000 entries"),
        ([(f"x{n}.json", b"\0" * MiB) for n in range(9)], "8 MiB uncompressed"),
        ([("tasks.json", b" " * (MiB + 1))], "over 1 MiB"),
    ],
)
def test_unsafe_zips_are_refused(author: User, entries: Any, message: str) -> None:
    with pytest.raises(importer.ImportRefused, match="refused") as refused:
        importer.import_zip(raw_zip(entries), author)

    assert codes(refused.value) == ["V-ZP"]
    assert message in refused.value.findings[0].message


def _patched(data: bytes, local: tuple[int, int], central: tuple[int, int]) -> bytes:
    """`data` with one byte of the first local header and of the central entry replaced."""
    raw = bytearray(data)
    start = raw.find(b"PK\x03\x04")
    raw[start + local[0]] = local[1]
    start = raw.find(b"PK\x01\x02")
    raw[start + central[0]] = central[1]
    return bytes(raw)


@pytest.mark.parametrize(
    ("local", "central"),
    [
        ((6, 1), (8, 1)),  # encrypted
        ((8, 99), (10, 99)),  # a compression method zipfile can't read
    ],
)
def test_unreadable_entries_are_refused_not_crashed(
    author: User, local: tuple[int, int], central: tuple[int, int]
) -> None:
    data = _patched(raw_zip([("tasks.json", b"[]")]), local, central)

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(data, author)

    assert codes(refused.value) == ["V-ZP"]
    assert "can't be read" in refused.value.findings[0].message


def test_corrupt_entry_data_is_refused_not_crashed(author: User) -> None:
    raw = bytearray(raw_zip([("tasks.json", b"[1, 2, 3, 4, 5, 6, 7, 8]" * 20)]))
    start = raw.find(b"PK\x03\x04")
    name_length = int.from_bytes(raw[start + 26 : start + 28], "little")
    raw[start + 30 + name_length + 2] ^= 0xFF

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(bytes(raw), author)

    assert codes(refused.value) == ["V-ZP"]


def test_two_entries_with_one_name_are_refused(author: User) -> None:
    with pytest.warns(UserWarning, match="Duplicate name"):
        data = raw_zip([("tasks.json", b"[]"), ("tasks.json", b"[1]")])

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(data, author)

    assert "two entries" in refused.value.findings[0].message


def test_an_upload_over_4_mib_is_refused_before_reading(author: User) -> None:
    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(b"PK" + b"\0" * (4 * MiB), author)

    assert "over 4 MiB" in refused.value.findings[0].message


def test_something_that_isnt_a_zip_is_refused(author: User) -> None:
    with pytest.raises(importer.ImportRefused, match="refused") as refused:
        importer.import_zip(b"not a zip", author)

    assert "not a zip" in refused.value.findings[0].message


def test_an_unknown_folder_is_refused(author: User) -> None:
    files = {**sample_files(), "extras/notes.json": b"{}"}

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(zipped(files), author)

    assert [(f.file, f.code) for f in refused.value.findings] == [("extras/notes.json", "V-LY")]


# -- nested replacement and permanence (FR-016) ---------------------------------------------------


def without_sour(line: dict[str, Any]) -> None:
    line["stations"] = [s for s in line["stations"] if s["station_id"] != "sour"]


def test_a_nested_replacement_drops_an_unpublished_identifier(sample_imported: User) -> None:
    files = edited(sample_files(), "lines/line_gamaa.json", without_sour)

    result = importer.import_zip(zipped(files), sample_imported)

    assert result.changed == ["line line_gamaa"]
    assert not Station.objects.filter(station_id="sour").exists()


def test_a_nested_replacement_cant_drop_a_published_identifier(sample_imported: User) -> None:
    make.published("station", "line_gamaa/sour", version=2)
    files = edited(sample_files(), "lines/line_gamaa.json", without_sour)

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(zipped(files), sample_imported)

    assert codes(refused.value) == ["V-PM"]
    assert "station line_gamaa/sour is in published pack version 2" in str(
        refused.value.findings[0].message
    )
    assert Station.objects.filter(station_id="sour").exists()


def test_orders_can_swap(sample_imported: User) -> None:
    files = edited(sample_files(), "lines/line_hay.json", lambda line: line.update(order=2))
    files = edited(files, "lines/line_gamaa.json", lambda line: line.update(order=1))

    importer.import_zip(zipped(files), sample_imported)

    assert dict(Line.objects.values_list("line_id", "order")) == {"line_hay": 2, "line_gamaa": 1}


def test_an_order_clash_with_untouched_content_is_refused(sample_imported: User) -> None:
    make.line("line_souq", order=3)
    files = edited(sample_files(), "lines/line_hay.json", lambda line: line.update(order=3))

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(zipped(files), sample_imported)

    assert codes(refused.value) == ["V-DB"]
    assert "content_line_order" in refused.value.findings[0].message or "unique" in str(
        refused.value.findings[0].message
    )


# -- reviews (FR-017) -----------------------------------------------------------------------------


def test_unchanged_lines_keep_their_review_and_changed_lines_lose_it(
    sample_reviewed: User,
) -> None:
    pool = "speech/passenger.pays.json"
    files = edited(
        sample_files(), pool, lambda p: p["lines"][1]["text"].update({"ar-EG": "changed text"})
    )

    importer.import_zip(zipped(files), sample_reviewed)

    lines = SpeechLine.objects.filter(pool__speech_key="passenger.pays").order_by("order")
    assert [line.reviewed_by for line in lines] == ["author1", ""]
    assert (
        SpeechLine.objects.exclude(pool__speech_key="passenger.pays").filter(reviewed_by="").count()
        == 0
    )


def test_reviews_are_never_exported(sample_reviewed: User) -> None:
    assert exporter.current_files(sample_reviewed) == sample_files()


# -- access (FR-019) ------------------------------------------------------------------------------


def test_import_needs_the_permission(plain_staff: User, publisher: User) -> None:
    for actor in (plain_staff, publisher):
        with pytest.raises(PermissionDenied, match="import_content"):
            importer.import_dir(SAMPLE, actor)


def test_import_is_refused_on_the_target(author: User, settings: Settings) -> None:
    settings.CONTENT_ROLE = "target"

    with pytest.raises(PermissionDenied, match="CONTENT_ROLE=target"):
        importer.import_dir(SAMPLE, author)


def test_exporting_current_content_needs_the_permission_and_the_source(
    sample_imported: User, publisher: User, settings: Settings
) -> None:
    with pytest.raises(PermissionDenied, match="export_content"):
        exporter.export_current(publisher)
    settings.CONTENT_ROLE = "target"
    with pytest.raises(PermissionDenied, match="CONTENT_ROLE=target"):
        exporter.export_current(sample_imported)


def test_an_inactive_author_is_refused_everywhere(inactive_author: User) -> None:
    pack = stored_sample_pack(3)
    with pytest.raises(PermissionDenied):
        importer.import_dir(SAMPLE, inactive_author)
    with pytest.raises(PermissionDenied):
        exporter.export_current(inactive_author)
    with pytest.raises(PermissionDenied):
        exporter.export_pack(pack, inactive_author)


# -- exporting a published pack -------------------------------------------------------------------


def stored_sample_pack(version: int) -> Any:
    tree, _ = read_layout(SAMPLE)
    data = build_pack_file(canonical_bytes(assemble_pack(tree, version)))
    return make.pack(version, Status.PUBLISHED, file=data, sha256=sha256_hex(data), size=len(data))


@pytest.mark.parametrize("role", ["source", "target"])
def test_a_published_pack_exports_from_its_stored_file(
    plain_staff: User, settings: Settings, role: str
) -> None:
    settings.CONTENT_ROLE = role
    pack = stored_sample_pack(3)

    files = unzipped(exporter.export_pack(pack, plain_staff))

    expected = sample_files()
    assert (
        files.pop("pack.json")
        == b'{\n  "pack_id": "core",\n  "schema_version": "1.0",\n  "version": 3\n}\n'
    )
    expected.pop("pack.json")
    assert files == expected
    assert not Trip.objects.exists()  # nothing was read from the authoring tables


# -- commands -------------------------------------------------------------------------------------


def test_content_import_imports_a_directory_or_a_zip(author: User, tmp_path: Path) -> None:
    out = io.StringIO()
    call_command("content_import", str(SAMPLE), "--actor", "author1", stdout=out)
    assert "41 added" in out.getvalue()

    archive = tmp_path / "sample.zip"
    archive.write_bytes(zipped(sample_files()))
    out = io.StringIO()
    call_command("content_import", str(archive), "--actor", "author1", stdout=out)
    assert "41 unchanged" in out.getvalue()


def test_content_import_reports_every_problem(author: User, tmp_path: Path) -> None:
    archive = tmp_path / "broken.zip"
    archive.write_bytes(zipped({**sample_files(), "extras/notes.json": b"{}"}))
    err = io.StringIO()

    with pytest.raises(CommandError, match="refused"):
        call_command("content_import", str(archive), "--actor", "author1", stderr=err)

    assert "extras/notes.json: $ [V-LY]" in err.getvalue()


def test_content_export_writes_current_content_or_a_published_pack(
    sample_imported: User, plain_staff: User, tmp_path: Path
) -> None:
    call_command("content_export", str(tmp_path / "current"), "--actor", "author1")
    _, findings = read_layout(tmp_path / "current")
    assert findings == []
    assert {
        p.relative_to(tmp_path / "current").as_posix(): p.read_bytes()
        for p in (tmp_path / "current").rglob("*")
        if p.is_file()
    } == sample_files()

    stored_sample_pack(3)
    call_command("content_export", str(tmp_path / "v3"), "--version", "3", "--actor", "staff1")
    assert json.loads((tmp_path / "v3" / "pack.json").read_text())["version"] == 3


def test_the_commands_check_the_actor_like_the_admin(
    sample_imported: User, plain_staff: User, tmp_path: Path, settings: Settings
) -> None:
    with pytest.raises(CommandError, match="import_content"):
        call_command("content_import", str(SAMPLE), "--actor", "staff1")
    with pytest.raises(CommandError, match="export_content"):
        call_command("content_export", str(tmp_path / "out"), "--actor", "staff1")
    with pytest.raises(CommandError, match="no published or retired pack 7"):
        call_command("content_export", str(tmp_path / "out"), "--version", "7", "--actor", "staff1")
    assert not (tmp_path / "out").exists()


@pytest.mark.parametrize("command", ["content_import", "content_export"])
def test_without_an_actor_nothing_is_read_or_written(
    author: User, tmp_path: Path, command: str
) -> None:
    target = tmp_path / "out"
    source = str(SAMPLE) if command == "content_import" else str(target)

    with pytest.raises(CommandError, match="--actor"):
        call_command(command, source)

    assert not Line.objects.exists()
    assert not target.exists()


def test_an_unknown_actor_stops_the_command(tmp_path: Path) -> None:
    with pytest.raises(CommandError, match="no user 'nobody'"):
        call_command("content_import", str(SAMPLE), "--actor", "nobody")
    with pytest.raises(CommandError, match="no user 'nobody'"):
        call_command("content_export", str(tmp_path / "out"), "--actor", "nobody")
    assert not (tmp_path / "out").exists()


def test_review_is_refused_without_the_permission(sample_imported: User, publisher: User) -> None:
    with pytest.raises(PermissionDenied, match="review_speech"):
        review.review_lines(SpeechLine.objects.all(), publisher)


def test_publishing_freezes_what_the_import_may_drop(sample_imported: User) -> None:
    tree, _ = read_layout(SAMPLE)
    permanence.record_published(assemble_pack(tree, 1), 1)
    files = edited(sample_files(), "items/salon.nish.json", lambda i: i["variants"].pop())

    with pytest.raises(importer.ImportRefused) as refused:
        importer.import_zip(zipped(files), sample_imported)

    assert "variant salon.nish/modern is in published pack version 1" in str(
        refused.value.findings[0].message
    )
