# Specification Quality Checklist: Animated Scenes (M22)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-28
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

- As in the earlier specs, the project's own identifiers are part of the product here: the artboard,
  state machine, view model and Boolean names come from the file and the delivery plan's contract,
  the slugs from the content, and Rive from the constitution, which locks it for animation. The spec
  names no package, provider or code structure.
- One marker was needed: what «يلا» does on an animated panel before its last turn has started. The
  owner answered on 2026-10-28 (Clarifications): the first tap shows the rest and the next moves on.
  FR-016 and Story 1 scenarios 5–6 now say so.
- Claude Design's report on the file, pasted by the owner, is recorded under Assumptions, "What
  Claude Design reported". One owner item stays outside the app: rename the Rive source from
  «Untitled» to `wassal_scenes`.
- Owner decisions, 2026-10-28, recorded in Clarifications:
  - The draft's بلية line in `ch1_usta_dreams` goes to the usta. The draft was edited in the
    `content-core-r1` worktree and validated with the current schemas, so the recorded gap is
    closed and SC-005 counts 13 of 13.
  - The panels' usta wins. The owner updated the canvas and `wassal.riv`; only `look` 18 changed,
    and the file passes its contract. That added FR-023 and SC-007, widened FR-020, and narrowed
    FR-022 and SC-004 to M07's scene goldens.
- The board «حركة المشاهد», read from the canvas, is summarised under Assumptions. Its note about a
  2.4 s Rive splash doesn't match the app's runtime; SC-001's device check covers it.
- The file was checked as delivered by decoding and rendering it with the app's Rive runtime:
  artboards, machines and view models, the loop, and each Boolean on and off in each panel. The
  findings are in Assumptions, "The file as delivered", including the one gap (بلية in the draft's
  `ch1_usta_dreams`).
- Validation took one fix: SC-005 miscounted the spoken lines (13 lines in 9 panels).
