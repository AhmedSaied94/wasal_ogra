# tools/content_kit/CLAUDE.md

Content, from **B04** (`specs/003-b04-content-pipeline/`): the schemas in `content/schemas/` (JSON Schema 2020-12 for packs: trip, line, item, catalog, …), with valid and invalid examples and a sample pack in `content/examples/`; this kit; and the models it generates for the server (Pydantic) and the app (`packages/content_models`, freezed). `content/engine/capabilities.json` says what the engine supports (archetypes, events and their parameters, speech slots, change-request notes), and the kit validates trips against it. `content/README.md` describes the layout. The project-wide rules are in the root `CLAUDE.md`.

## Commands

The schemas in `content/schemas/` are the only definition of content. `tools/content_kit` (the uv project `wassal-content`, Python pinned by its `.python-version`) generates both model sets from them and validates content. CI runs the same commands in the backend workflow's `content-kit` job and in the mobile `packages` job.

| Purpose | Command |
| --- | --- |
| First setup (in `tools/content_kit`) | `uv sync` |
| Regenerate after a schema change | `uv run wassal-content codegen` |
| Generated files match the schemas (CI) | `uv run wassal-content codegen --check` |
| Validate one document | `uv run wassal-content validate <file> [--part trip]` |
| Validate a content layout | `uv run wassal-content validate-source ../../content/examples/sample` |
| Breaking schema changes | `uv run wassal-content schema-diff --base origin/master` |
| Sample pack checksums | `uv run wassal-content golden` (check) / `golden --update` (rewrite, then review) |
| Bundle the sample into dev builds / check it (CI) | `uv run wassal-content bundle dev --out ../../apps/mobile/assets/content/dev` / `bundle dev --check --out …` |
| Bundle production's promoted pack into staging and prod / check it offline (CI) | `uv run wassal-content bundle release --packs-url https://api.193-122-74-125.sslip.io/packs/ --out ../../apps/mobile/assets/content/release` / `bundle release --check --out …` |
| Lint, types, tests | `uv run ruff check . && uv run ruff format --check . && uv run mypy . && uv run pytest --cov --cov-fail-under=80` |
| App models: build (in `packages/content_models`) | `fvm dart pub get && fvm dart run build_runner build -d` |
| App models: analyze and test | `fvm dart analyze --fatal-infos && fvm dart test --coverage=coverage` |
| App models: coverage gate | `fvm dart run coverage:format_coverage --lcov --report-on=lib --in=coverage --out=coverage/lcov.info && fvm dart run ../../apps/mobile/tool/check_coverage.dart --min 80 --lcov coverage/lcov.info` |

- After editing a schema: run `codegen`, then `build_runner` in `packages/content_models`, and commit the schema with `_generated.py`, `src/wassal_content/schemas/*.json` and `lib/src/generated/*.dart`. The `*.freezed.dart` and `*.g.dart` parts are gitignored, so after a fresh checkout build `packages/content_models` before the app or the engine.
- The backend's image carries its own copy of `tools/content_kit` (and `tools/solver`). After a schema change, rebuild the dev stack's image (`docker compose … build`, then `up -d --wait`): until then its worker checks packs against the old schemas, and a build fails with "not an allowed property".
- Never edit a generated file by hand: `codegen --check` fails on any difference.
- The schemas follow a restricted profile (research R3 of B04): closed objects, integers only, no `null`, no `default`, no combinators, and every object and enum named in `$defs`. `codegen` refuses anything else.
- A line's `whats_new` and `display_fare_piasters` and a vehicle's `short_name` (M09) are required display fields. A pack built before them no longer reads: after a deploy that adds a required field, staging builds and publishes a fresh pack (`docs/runbooks/content-publishing.md`).
- `content/source/` holds only exports of packs promoted to production. Until its `pack.json` exists, schemas may change freely; after that, a breaking change needs a major bump in `content/schemas/schema-set.json`.
