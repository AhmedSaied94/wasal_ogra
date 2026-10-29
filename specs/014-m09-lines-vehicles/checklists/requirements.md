# Specification Quality Checklist: Lines Map, Line Details and Vehicle Purchase (M09)

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

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`
- **No [NEEDS CLARIFICATION] marker remains.** The owner answered both on 2026-10-29
  (Clarifications):
  - **FR-007**: a story trip opens once its chapter's goal is met, regular trips never wait for it,
    and Home, the card and the result switch to the rule.
  - **FR-016**: Lines shows only the installed pack's lines and vehicles; later ones come with their
    pack.
  - Two more were settled in the same session: «كمّل» on a current line's card starts its next trip
    (FR-019), and the impact line is reworded to «فاضل {amount} ج على {goal}» (FR-032).
- As in the earlier specs, the project's own identifiers are part of the product here: the line, trip
  and vehicle ids from the glossary and the release draft, the unlock kinds of the line schema, the
  artboard names (the design-check rule, HANDOFF §10, requires each artboard's golden and layout
  test), and the merged features and research it builds on (M05's purchase path, M06's rollback, B03
  research R6). Since the 2026-10-28 update it also names the merged M08 code it must reuse or change
  (the rules' folder, `startNextTrip`, `savingsTarget`, `nextTrip`, the pre-trip card's route, M03's
  tab dot), as constraints of the existing app, not design choices; it names no new package,
  provider, table or storage mechanism. FR-011's phone-only rule tests and FR-042's schema fields are
  requirements on what the phone and the content must agree on, not on how.
- Defaults chosen without the owner are listed under Assumptions, "Resolved here without the owner",
  so `/speckit-clarify` can raise any of them: vehicles sold in pack order, the owned vehicle sheet,
  the grid's visible range, a done line with no button, a
  locked line's details, the pre-trip card returning to the line's details, Home's line card still
  opening Lines, the impact line using M08's savings target, no extra purchase confirmation, and the
  display fare as a content field.
- **Updated 2026-10-28** against master after M07, M22 and M08 merged: the rules restated as M08's
  port with only the phone-only rules added (FR-001–FR-013, SC-003, SC-003a); starts through M08's
  `startNextTrip`, with the card returning to its opener (US2, FR-026); the map opening on Home's
  line and Home's line card kept on Lines (FR-010, FR-020, US1 #7); the impact line from M08's
  savings target (US3 #4, FR-032); the BONAT balance disabled offline (FR-015); the tab dot's
  persistence (FR-041); the existing routes (FR-053); the dependencies, the changes to M08's code and
  the hand-overs rewritten. Every item above still passes except the clarification markers.
- Validation took two passes. The first moved the FR-016 marker into a requirement of its own (it sat
  inside the vehicle strip's sentence), gave story-done cells their stars (the artboard's label reads
  «مشوار قصة، تلات نجوم»), added the "no catalog price" case to FR-003 and FR-035, and replaced
  "the dev stack" in SC-003 with an end-to-end sync against a real server.
