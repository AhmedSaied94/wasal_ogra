# drift schemas

Every version of the app database's schema, as drift exports it
(`drift_schema_v1.json`, `drift_schema_v2.json`, …). The migration tests in
`test/drift/` are generated from these files.

- Only `fvm dart run drift_dev make-migrations` writes here. Never edit a file
  by hand.
- Run it after every table change, in `apps/mobile`, and commit the new schema
  together with the generated step helper and tests.
- Keep every version committed: the tests upgrade from each one.

See `specs/007-m05-local-economy/contracts/storage.md`.
