# Bundled content pack: staging and prod

The staging and prod flavors bundle this directory. It holds the newest pack production has
promoted: `content/source/` at its `pack.json` version, byte-identical to production's file, with
a copy of production's release record.

- Until production's first promotion, this README is the only file here, and staging and prod
  builds are refused (the Gradle task `checkBundledPack`).
- The files are generated. Never edit them by hand. After a promotion, the publisher runs this in
  `tools/content_kit` (`docs/runbooks/content-publishing.md` §3):

  ```bash
  uv run wassal-content bundle release \
    --packs-url https://api.193-122-74-125.sslip.io/packs/ \
    --out ../../apps/mobile/assets/content/release
  ```

  That replaces this README with `core-<v>.json.gz`, `core-<v>.release.json` and `bundled.json`.
- CI checks them with `bundle release --check`, and the app's `test/repo/bundled_pack_test.dart`.

Details: `specs/006-m04-content-loader/contracts/bundling.md`.
