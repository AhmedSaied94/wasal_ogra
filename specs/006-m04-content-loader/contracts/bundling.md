# Contract: Bundling a Pack into the App (FR-001, FR-033 to FR-035)

Which pack each build carries, how it gets there, and what refuses a wrong one. Decisions: research
R2 and R13, and the spec's Clarifications.

## Which pack each flavor bundles

| Flavor | Asset directory | Pack | `min_client_version` |
| --- | --- | --- | --- |
| `dev` | `apps/mobile/assets/content/dev/` | `content/examples/sample/` built as version 1, equal to `content/examples/sample.golden.json` | the schema set's floor for major 1 (`1.0.0`) |
| `staging`, `prod` | `apps/mobile/assets/content/release/` | the newest pack production has promoted: `content/source/` at its `pack.json` version, byte-identical to production's `core-<v>.json.gz` | production's release record |

`pubspec.yaml` declares both as flavor-scoped directories, as `tunables.dev.json` is:

```yaml
    - path: assets/content/dev/
      flavors: [dev]
    - path: assets/content/release/
      flavors: [staging, prod]
```

The loader reads `assets/content/<dev|release>/bundled.json` (data-model.md), then the file it
names.

**Before production's first promotion**, `assets/content/release/` holds only a `README.md`, which
says what goes there and links this contract. Until then, only dev builds can be made.

## `wassal-content bundle` (`tools/content_kit`)

```text
uv run wassal-content bundle dev     --out ../../apps/mobile/assets/content/dev
uv run wassal-content bundle release --packs-url https://api.193-122-74-125.sslip.io/packs/ \
                                     --out ../../apps/mobile/assets/content/release
uv run wassal-content bundle dev     --check --out ../../apps/mobile/assets/content/dev
uv run wassal-content bundle release --check --out ../../apps/mobile/assets/content/release
```

| Mode | Reads | Writes | Fails when |
| --- | --- | --- | --- |
| `dev` | `content/examples/sample/` | `core-1.json.gz`, `bundled.json` (`source: sample`) | the sample has findings, or the file's sha256 differs from `sample.golden.json` |
| `release` | `content/source/` and `<packs-url>core-<v>.release.json` | `core-<v>.json.gz`, `core-<v>.release.json` (byte copy), `bundled.json` (`source: content_source`); removes any other `core-*` and `README.md` | `content/source/pack.json` is missing or has version 0; the layout has findings; the URL isn't `https`; the record is unreachable, over 64 KiB or doesn't parse strictly; the record's `pack_id`, `version`, `sha256` or `size` differ from the rebuilt file; a stage isn't `passed` (or a `size` or `solver` `warning`) |
| `--check` | the same inputs, offline | nothing | the committed file differs from a fresh build; `bundled.json` differs from what the mode would write; for `release`, the record copy's `sha256` field differs from the file, or `release_record_sha256` differs from the copy's bytes; `validate-source` reports an error (V-T10 included) |

- **The record is fetched once.** The publisher fetches it over HTTPS (10 s timeout, no
  redirects). From then on, CI checks the committed copy offline.
- **`--check release` with no promoted pack** (no `content/source/pack.json`) passes only if the
  directory holds nothing but `README.md`.
- **Exit codes** follow the other content-kit commands: `0` on success, `1` with each problem on
  its own line.
- **Building** reuses `read_layout`, `assemble_pack`, `canonical_bytes` and `build_pack_file`. No
  second builder exists.

## What refuses a wrong build

| Check | Where | Refuses |
| --- | --- | --- |
| Gradle `checkBundledPack` | `android/app/build.gradle.kts`, before `preBuild` of every staging and prod variant | `assets/content/release/bundled.json` is missing: "No promoted pack is bundled. Run `wassal-content bundle release` (docs/runbooks/content-publishing.md §3)." |
| `test/repo/bundled_pack_test.dart` | `flutter test`, every CI run | a `bundled.json` that disagrees with its file's size or sha256; dev's sha256 ≠ `sample.golden.json`'s; the release version ≠ `content/source/pack.json`'s (or one exists without the other); `min_client_version` above the pubspec version; a pubspec version below the schema-set floor or not `MAJOR.MINOR.PATCH+BUILD` |
| `bundle --check dev` and `--check release` | backend workflow, `content-kit` job | the cases in the table above |
| The loader at launch | the device | a bundled file that fails `decodePackFile` against `bundled.json` (damaged install, FR-008) |

## The publisher's step (runbook `content-publishing.md` §3)

After the export of a newly promoted pack is unzipped into `content/source/`, the publisher runs
`bundle release` with production's packs URL. The export, the three asset files and nothing else go
in one pull request. CI then checks the whole chain:

- the export validates and re-solves (B04, B05);
- the rebuilt bytes equal the bundled file;
- the bundled file equals the release record.

## The app version (research R2)

- `pubspec.yaml`: `version: 1.0.0+2`.
- Every app release raises the build number. It raises the version when the store needs it.
- A pack's `min_client_version` never exceeds the version of the app that bundles it. The guard
  test enforces this.
