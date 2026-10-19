"""`wassal-content`: the content commands CI and developers run.

| Command | What it does |
| --- | --- |
| `codegen [--check]` | Write (or drift-check) the server models, app models and schema copy |
| `validate <file> [--part P]` | Validate one document against its part's schema |
| `validate-source <dir>` | Validate a `content/source` layout as files, then as a whole pack |
| `schema-diff --base <ref>` | Refuse a breaking schema change without a major-version bump |
| `golden [--update]` | Check (or rewrite) the sample pack's golden checksums |

Exit codes: 0 clean, 1 findings or differences, 2 usage errors. The repository root is the
nearest directory above the working directory that holds `.fvmrc`.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path, PurePath

from wassal_content.codegen import CodegenError, check_outputs, outputs_for, write_outputs
from wassal_content.findings import Finding
from wassal_content.golden import golden_bytes
from wassal_content.loader import ContentLoadError, load_json_file
from wassal_content.schema_diff import check_sets, read_tree_at
from wassal_content.schemas import PARTS, default_schema_set
from wassal_content.source import FOLDERS, assemble_pack, read_layout
from wassal_content.validate import validate_pack

__all__ = ["main"]

OK, FINDINGS, USAGE = 0, 1, 2
_GOLDEN = Path("content/examples/sample.golden.json")
_SAMPLE = Path("content/examples/sample")


class UsageError(Exception):
    """A command was called wrongly."""


def find_repo_root(start: Path) -> Path:
    for directory in (start, *start.parents):
        if (directory / ".fvmrc").is_file():
            return directory
    raise UsageError(f"no repository root (a directory with .fvmrc) above {start}")


def _print_findings(findings: Sequence[Finding]) -> None:
    for finding in findings:
        where = f"{finding.file}: " if finding.file else ""
        entity = f" {finding.entity} {finding.id}".rstrip() if finding.entity else ""
        print(f"{where}{finding.path} [{finding.code}]{entity}: {finding.message}")


def _codegen(args: argparse.Namespace) -> int:
    outputs = outputs_for(find_repo_root(Path.cwd()))
    if args.check:
        differing = check_outputs(outputs)
        for path in differing:
            print(f"out of date: {path}")
        if differing:
            print("run `uv run wassal-content codegen` in tools/content_kit and commit the result")
            return FINDINGS
        print(f"codegen: {len(outputs.files)} files up to date")
        return OK
    for path in write_outputs(outputs):
        print(f"wrote {path}" if path in outputs.files else f"removed {path}")
    return OK


def _infer_part(path: Path) -> str:
    folder = path.parent.name
    if folder in PARTS:
        return folder
    if folder in FOLDERS:
        return FOLDERS[folder][1]
    if path.parent.parent.name == "trips":
        return "trip"
    raise UsageError(f"can't tell the part of {path}: pass --part ({', '.join(PARTS)})")


def _validate(args: argparse.Namespace) -> int:
    path = Path(args.file)
    part = args.part or _infer_part(path)
    if part not in PARTS:
        raise UsageError(f"unknown part {part!r}: one of {', '.join(PARTS)}")
    try:
        document = load_json_file(path)
    except ContentLoadError as error:
        print(f"{path}: {error}")
        return FINDINGS
    findings = default_schema_set().validate_document(part, document, file=str(PurePath(path)))
    _print_findings(findings)
    if not findings:
        print(f"{path}: valid {part}")
    return FINDINGS if findings else OK


def _validate_source(args: argparse.Namespace) -> int:
    root = Path(args.directory)
    try:
        tree, findings = read_layout(root)
    except FileNotFoundError as error:
        raise UsageError(str(error)) from None
    if tree.is_empty and not findings:
        print(f"{root}: no pack.json, nothing to validate")
        return OK
    if not findings and tree.meta is not None:
        pack = assemble_pack(tree, max(int(tree.meta["version"]), 1))
        report = validate_pack(pack, file_size=None)
        findings = report.findings
    _print_findings(findings)
    errors = [finding for finding in findings if finding.severity == "error"]
    print(f"{root}: {len(errors)} error(s), {len(findings) - len(errors)} warning(s)")
    return FINDINGS if errors else OK


def _schema_diff(args: argparse.Namespace) -> int:
    root = find_repo_root(Path.cwd())
    try:
        base = read_tree_at(args.base, root)
    except ValueError as error:
        raise UsageError(str(error)) from None
    schemas = root / "content" / "schemas"
    new = {path.name: path.read_bytes() for path in sorted(schemas.iterdir()) if path.is_file()}
    active = (root / "content" / "source" / "pack.json").is_file()
    try:
        result = check_sets(base, new, active=active)
    except ValueError as error:
        print(f"wassal-content schema-diff: {error}", file=sys.stderr)
        return FINDINGS
    for change in result.breaking:
        print(f"breaking: {change}")
    if not active:
        print(
            "schema-diff: content/source/pack.json doesn't exist yet, so schemas may change freely"
        )
    elif result.major_bumped:
        print(
            "schema-diff: the schema set's major version went up, so breaking changes are allowed"
        )
    elif result.breaking:
        print("schema-diff: breaking changes need a major-version bump in schema-set.json (FR-010)")
    else:
        print("schema-diff: no breaking change")
    return OK if result.ok else FINDINGS


def _golden(args: argparse.Namespace) -> int:
    root = find_repo_root(Path.cwd())
    expected = golden_bytes(root / _SAMPLE)
    path = root / _GOLDEN
    if args.update:
        path.write_bytes(expected)
        print(f"wrote {path}")
        return OK
    if not path.is_file() or path.read_bytes() != expected:
        print(f"{path} doesn't match the sample. Expected:\n{expected.decode()}")
        return FINDINGS
    print("golden: the sample's checksums match")
    return OK


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="wassal-content", description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    codegen = commands.add_parser("codegen", help="write or check the generated models")
    codegen.add_argument("--check", action="store_true", help="only report differences")
    codegen.set_defaults(run=_codegen)
    validate = commands.add_parser("validate", help="validate one document")
    validate.add_argument("file")
    validate.add_argument("--part", help="the part; by default, from the file's folder")
    validate.set_defaults(run=_validate)
    source = commands.add_parser("validate-source", help="validate a content/source layout")
    source.add_argument("directory")
    source.set_defaults(run=_validate_source)
    diff = commands.add_parser("schema-diff", help="refuse unannounced breaking schema changes")
    diff.add_argument("--base", required=True, help="the git revision to compare against")
    diff.set_defaults(run=_schema_diff)
    golden = commands.add_parser("golden", help="check the sample pack's golden checksums")
    golden.add_argument("--update", action="store_true", help="rewrite the golden file")
    golden.set_defaults(run=_golden)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Run one command and return its exit code."""
    parser = _parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exit_:
        return int(exit_.code or 0) and USAGE
    try:
        return int(args.run(args))
    except UsageError as error:
        print(f"wassal-content: {error}", file=sys.stderr)
        return USAGE
    except CodegenError as error:
        print(f"wassal-content codegen: {error}", file=sys.stderr)
        return FINDINGS
    except ContentLoadError as error:
        print(f"wassal-content: {error}", file=sys.stderr)
        return FINDINGS
    except OSError as error:
        print(f"wassal-content: {error}", file=sys.stderr)
        return USAGE


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
