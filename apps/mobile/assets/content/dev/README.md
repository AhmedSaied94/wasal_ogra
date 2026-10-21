# Bundled content pack: dev

The dev flavor bundles this directory. It holds the sample content (`content/examples/sample/`)
built as version 1, which matches `content/examples/sample.golden.json`.

- `core-1.json.gz` and `bundled.json` are generated. Never edit them by hand.
- Regenerate them from `tools/content_kit` after the sample changes:

  ```bash
  uv run wassal-content bundle dev --out ../../apps/mobile/assets/content/dev
  ```

- CI checks them with `bundle dev --check`, and the app's `test/repo/bundled_pack_test.dart`.

Details: `specs/006-m04-content-loader/contracts/bundling.md`.
