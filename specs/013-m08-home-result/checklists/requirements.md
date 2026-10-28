# Specification Quality Checklist: Home, Pre-trip Card and Result Screen (M08)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-27
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

- Two markers remain, for the owner at `/speckit-clarify`:
  - FR-010: which line Home follows and what «يلا نطلع!» plays once a line is done.
  - FR-034: whether «عيد المشوار» goes through the pre-trip card (handed over by 008.5).
- As in the earlier mobile specs, the project's shared vocabulary is named because the design-check
  rule (HANDOFF §10) and the merged contracts require it: the artboard names, the shared components
  (in Assumptions only), the `pre_trip_card_mode` tunable and the server's `not_unlocked` refusal.
  The spec names no package, provider, table or widget class, and leaves storage (the card setting,
  the "met" set's derivation) to the plan.
- Rules the docs already decide are recorded under Assumptions, "Settled from the docs, not asked",
  each with its source: merged decisions over HANDOFF (station letters and colours, the story trip's
  chip, fuel per start, who charges the liter), the offline BONAT spend, the in-place booster buy,
  the fuel pill's destination, the untappable vehicle, the barker's call, where the new card's and
  the mistakes' wording lives, the share image's pay, and HANDOFF §9.3 #4 left open.
- Seams with unmerged or unbuilt features (M07, M09–M15) are slots or links with a named owner, so
  each requirement is testable now with nothing shown or a placeholder.
- Validation: one iteration. Every item passes except the open markers.
