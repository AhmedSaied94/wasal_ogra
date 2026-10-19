# content_models

The app models for wassal's content packs: Dart classes for every part of a pack (trips, lines,
vehicles, chapters, rooms, items, speech pools, the catalog, daily rewards, tasks and the manifest).

- **Generated, never hand-edited.** Everything under `lib/src/generated/` is written by
  `wassal-content codegen` (in `tools/content_kit`) from `content/schemas/`. CI regenerates it and
  fails on any difference (constitution VII). To change a model, change the schema and run:

  ```bash
  cd tools/content_kit && uv run wassal-content codegen
  ```

- **Hand-written:** `lib/content_models.dart` (exports) and `lib/src/canonical_json.dart` (the
  canonical JSON form, research R4).
- **Build:** `dart pub get && dart run build_runner build -d` writes the `.freezed.dart` and
  `.g.dart` parts, which are gitignored.
- **Test:** `dart test` round-trips every file in `content/examples/valid/` through the models and
  checks the canonical form against `content/examples/canonical-vectors.json`.

The package is pure Dart: no Flutter import, so the engine (`packages/trip_engine`) can use it.
