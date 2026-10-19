# content/source

The content of every pack promoted to production, as the publisher's export of that pack
(FR-040). Nothing else goes here: authors write on staging, not in this folder.

- **How a pack lands here.** After a promotion, the publisher exports the promoted pack from
  either admin ("Export content" on the pack's page), unzips it here, replacing the previous
  export, and opens a pull request. The runbook is `docs/runbooks/content-publishing.md`.
- **What CI does.** It validates every file against the schemas and the content rules
  (`wassal-content validate-source content/source`). From B05 on, it also re-solves every trip.
- **The breaking-change check.** Once `pack.json` exists here, a production pack exists, and CI
  refuses a breaking schema change unless the schema set's major version goes up
  (`wassal-content schema-diff`, research R3).
- **The layout** is `specs/003-b04-content-pipeline/contracts/content-source.md`. The same layout
  is used by `content/examples/sample/` and by the admin's zip import and export.
