# Contract: CI Checks Added or Changed by B04 (FR-007, FR-009, FR-010, FR-040, FR-041)

There is no new workflow. The checks go into the two required ones, `backend.yml` and
`mobile.yml`, so branch protection doesn't change (research R13). Every job keeps
`timeout-minutes: 15`.

## Path rules

| Workflow | Today | Becomes |
| --- | --- | --- |
| `backend.yml` `changes` | `^(backend/\|contracts/\|\.github/workflows/backend[^/]*\.yml$)` | adds `content/`, `tools/content_kit/`, `packages/content_models/` and `.dockerignore` |
| `mobile.yml` `changes` | `^(apps/mobile/\|packages/\|\.fvmrc$\|\.github/workflows/mobile\.yml$)` | adds `content/` |

`backend.yml` includes `packages/content_models/`, because its generated sources come from the
Python generator, and the drift job checks them.

## `backend.yml`: new job `content-kit`

The job runs on ubuntu-24.04, in `tools/content_kit/`, using `setup-uv` and `uv sync --locked`. It
runs these steps in order:

| Step | Command (from `tools/content_kit/`) | Fails when |
| --- | --- | --- |
| Lint and format | `uv run ruff check . && uv run ruff format --check .` | any issue. `_generated.py` is excluded. |
| Types | `uv run mypy .` (`strict = true`) | any error, generated models included |
| Tests and coverage | `uv run pytest --cov --cov-fail-under=80` | a failing test, including: the profile check over `content/schemas`, valid and invalid examples with their expected paths (`content/examples/invalid/expected.json`), the Pydantic round trip, the golden checksums, the validator rules, schema-diff fixtures and zip safety. Coverage under 80%. |
| Codegen drift | `uv run wassal-content codegen --check` | regenerating the server models, the packaged schema copy or the Dart sources under `packages/content_models/lib/src/generated/` would change any file, including a hand edit (FR-007) |
| `content/source` and the sample | `uv run wassal-content validate-source ../../content/source` and `… ../../content/examples/sample` | any finding at error level in stages 1–3. An empty `content/source/` (README only) passes. |
| Breaking changes | `uv run wassal-content schema-diff --base "$(git merge-base origin/master HEAD)"` | a breaking change without a major-version bump, but only once `content/source/pack.json` exists (research R3). On `push` to `master` the base is `github.event.before`. |

`fetch-depth: 0` is needed for the merge base. The `backend` aggregate job and `image-manifest`
add `content-kit` to their `needs`, so a `sha-<commit>` image tag still means every check passed.

## `backend.yml`: changed jobs

| Job | Change |
| --- | --- |
| `lint`, `types`, `test`, `contract` | Unchanged commands. `uv sync --locked` now also installs `wassal-content` from its path. |
| `test` | Adds the `apps/content` suite (real PostgreSQL and Valkey). The 80% gate stays. |
| `contract` | The committed `contracts/openapi.yaml` gains `/v1/content/manifest`, and B01's diff and `schemathesis` cover it |
| `image` | The build context becomes the repository root: `docker build -f backend/docker/Dockerfile .`, with the root `.dockerignore` (research R13) |
| `smoke` | `compose.dev.yml` uses `context: ../..`. It also checks that the dev API serves `GET /packs/<missing>` as a `404`, and that `GET /v1/content/manifest` answers `{"version": 0, "packs": []}`. |

## `mobile.yml`: `content_models` steps in the `check` job

`mobile.yml` has no aggregate job: M03 made `check` and `build-android` the required checks. A
separate job would need a new required check, and making `check` wait for it would not work,
because a skipped required check counts as passing. So these steps run at the end of `check`, in
`packages/content_models/`, with the Flutter that job already set up from `.fvmrc`.

| Step | Command | Fails when |
| --- | --- | --- |
| Dependencies | `dart pub get` | resolution fails |
| Build | `dart run build_runner build -d` | a generator error |
| Format | `dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')` | a hand-written file isn't formatted. Generated files carry `// dart format off`. |
| Analyze | `dart analyze --fatal-infos` | any issue |
| Tests | `dart test --coverage=coverage`, then `dart run coverage:format_coverage --lcov --report-on=lib --in=coverage --out=coverage/lcov.info`, then M03's existing gate, `dart run ../../apps/mobile/tool/check_coverage.dart --min 80 --lcov coverage/lcov.info` | a failing round trip over `content/examples/valid/**`, or coverage under 80%. The gate excludes the generated `.freezed.dart` and `.g.dart` parts (research R1). |

M03's gate script (`apps/mobile/tool/check_coverage.dart`) gains the `*.freezed.dart` exclusion,
next to `*.g.dart`. The app's own steps don't change in B04: the app starts depending on
`content_models` in M04.

## Not in B04

| Check | Arrives with |
| --- | --- |
| Re-solving every trip in `content/source` | B05 (constitution CI gate) |
| Parity fixtures | M01 and B05 |
| The app's DTO check against `contracts/openapi.yaml` | M06 |
