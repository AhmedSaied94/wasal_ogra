# Specification Quality Checklist: Solver and Parity (B05)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-20
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

- Validated in two passes on 2026-10-20. The first pass tightened three requirements:
  - FR-017's reaction time now says what it counts from;
  - FR-031's reuse of unchanged trips is a MUST, since SC-007's 2-minute rebuild depends on it;
  - FR-042 says a failing sample trip may be fixed by changing the trip or its line's band.
- **Implementation details.** The spec names Python and Dart, `tools/solver`, `RULES.md`, the
  fixture form and path, `capabilities.json` and the command names. They are fixed by the
  constitution (I, III), backend §10 and §23, and the M01 and B04 hand-overs, so they are
  requirements, not design choices, as in M01's spec. How the mirror, the search and the score are
  built (types, algorithms, weights, the tap time, the effort budget's unit, where the stage's
  results are cached) is left to the plan. No framework, task queue or test runner is named.
- **Audience.** The direct users are authors, the publisher, the owner and developers. The solver's
  behavior is written in game terms (decisions, stars, fights, the band), so the owner can check it
  against the product spec.
- **Success criteria.** SC-005 to SC-008 and SC-011 name where they are measured (the CI runner, the
  staging host), not how the solver is built.
- **No clarification markers.** Every open point has a default from the sources:
  - out-of-band scores block the pack (B04 FR-021);
  - the idealized player never forgets;
  - the mirror leaves out events and speech (`RULES.md` §12 and §13, and no result field depends on
    them);
  - the balancing report's slower players react in 900 and 1,200 ms.

  Each is listed under "Defaults this feature sets" in Assumptions, for `/speckit-clarify` to
  confirm.
