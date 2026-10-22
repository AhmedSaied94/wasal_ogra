# Specification Quality Checklist: Local Economy (M05)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-21
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

- Iteration 1 (2026-10-21): one marker open, FR-029 (mobile §24.5, replaying a completed trip). The
  delivery plan requires M05 to resolve it, and B03 must agree, so it goes to the owner.
- Iteration 2 (2026-10-22): the owner chose A. Every start costs a liter, replays included. FR-029,
  US1 scenario 2, the B03 hand-over and the Clarifications section are updated. All items pass.
- `/speckit-clarify` (2026-10-22) added the clock rule (FR-025, FR-026) and the backup exclusion
  (FR-006). `/speckit-plan` aligned FR-026 with that answer (a restart re-anchors at the latest
  recorded time) and made FR-027 exact (a tunable change applies to the time since the last
  operation). All items still pass.
- Named identifiers (`trip_start`, `spend_bonat`, `fuel_max`, UUIDv7, the `ContentSource`) are the
  Shared Contract Glossary's, backend §7.4's and the constitution's, not design choices made here.
  The project's specs name them, as M04's does, so B03 and M06 can check this one against theirs.
  drift and the native-assets `sqlite3` appear only in the Input and Assumptions, as the locked
  stack and M03's hand-over.
- The audience is the project owner, who reads the architecture docs. The user stories and success
  criteria stay in player terms.
- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`.
