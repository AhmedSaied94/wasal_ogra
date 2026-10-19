# Specification Quality Checklist: Content Pipeline (B04)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-19
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Iteration 1: one marker is open, an owner decision with no safe default:
  - FR-039: where authors write content, and how a pack reaches production.
- Iteration 1 fixes:
  - FR-036 said how the mobile build picks its bundled pack, which B04 can't test. That part moved
    to Assumptions ("Bundling (M04)").
  - FR-041's coverage target now covers the backend and every package this feature adds.
- Iteration 2: the owner resolved the marker (Clarifications, 2026-10-19). Authors write on staging,
  and the tested pack is promoted to production unchanged. This changed or added:
  - US5 (promotion) and FR-039, FR-039a, FR-039b and FR-039c;
  - rollbacks are built on staging and promoted (FR-028), and production never builds (FR-020);
  - separate pack storage per environment (FR-037);
  - promotions in the audit log (FR-038), and promoted packs in `content/source` (FR-040);
  - SC-007, SC-008 and the new SC-013;
  - edge cases for a staging rebuild, staging being down during a rollback, a production restore,
    and out-of-order promotion.

  All items pass.
- Named technologies come from the constitution and the source sections, and are project vocabulary
  rather than implementation choices: JSON Schema 2020-12 (constitution VII), gzip and sha256 (the
  pack format and manifest fields in backend §9.1 and §6.4), `core-<version>.json.gz`,
  `GET /v1/content/manifest` and `contracts/openapi.yaml`. Requirements say "app models" and
  "server models", not the languages. OCI Object Storage appears only in the Assumptions, because
  backend §15 already fixes it.
- Defaults taken instead of markers (the owner can change them in `/speckit-clarify`):
  - Until B05 supplies the solver stage, staging and production can't publish (FR-022). This keeps
    constitution VII without an exception, and no consumer needs a published pack before B05.
  - Until B02, the manifest needs no player token (FR-033).
  - The manifest offers old apps the newest pack they can read (FR-030).
  - Player-visible pack text is stored per locale, `ar-EG` required and `ar` optional (FR-006).
  - Speech lines carry a review state, and an unreviewed line blocks the build (FR-017,
    constitution XII).
- Backend §22.3 (a CDN for packs) is a lookup within known limits (USD 0, HTTPS, separate from the B2
  backup keys), so FR-037 hands it to the plan's research instead of adding a marker, as B01 did for
  §22.1.
