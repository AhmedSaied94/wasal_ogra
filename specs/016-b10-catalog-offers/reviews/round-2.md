# Implementation review: 016-b10-catalog-offers, round 2

- Date: 2026-11-02 · Reviewer: Claude Code, Opus 5.5 (layer reviewers on Sonnet 5.5; every finding re-checked on Opus)
- Branch: 016-b10-catalog-offers · Base: origin/master (merge base dce3f64) · Head: 5a225f9, plus 120 uncommitted files
- Change: 1 commit, 131 files, +9382 −414
- Verdict: **CHANGES REQUESTED** · CRITICAL 0 · HIGH 1

## Checks

CI's `changes` job sets `backend=true` for this change set, which triggers `lint`, `types`, `test`, `contract`, `content-kit`, `solver`, `image` and `smoke`.

| Check | Command (in `backend/`) | Result |
| --- | --- | --- |
| Lint | `uv run ruff check .` | exit 0, all checks passed |
| Format | `uv run ruff format --check .` | exit 0, 394 files already formatted |
| Types | `uv run mypy .` | exit 0, no issues in 393 files |
| Missing migrations | `uv run manage.py makemigrations --check --dry-run` | exit 0, no changes detected |
| OpenAPI drift | `uv run manage.py spectacular --file <tmp> --validate --fail-on-warn && diff -u ../contracts/openapi.yaml <tmp>` | exit 0 / exit 0, no diff |
| Tests + coverage | `uv run pytest -n 4 --cov --cov-fail-under=80` | exit 0, 2232 passed, total 95.73%. The first run had 2 failures (`tests/test_contract.py::test_each_reason_conforms[unknown_trip]`, `apps/economy/tests/test_privacy_scan.py`). It shared the test Postgres and Valkey with the property test and the reviewers' runs. Both tests pass alone (32 passed), and the rerun with nothing else running is clean. |
| `liveops/services/` and `permissions.py` at 100% (T062) | same run | **fails**: `services/catalog.py` 97% (lines 138–139); everything else 100% (R2-1) |
| Economy property test, 10,000 examples | `HYPOTHESIS_PROFILE=thorough uv run pytest apps/economy/tests/test_properties.py` | exit 0, 1 passed in 1114 s |
| Bypass scan (skip/xfail, new `noqa`/`type: ignore`, coverage/ruff/mypy/CI config) | added lines of `git diff HEAD` plus untracked files | same set as round 1: the django-stubs admin and form generics, two `S105` false positives, two test-line ignores; no config change |
| `content-kit`, `solver` jobs | — | NOT RUN: no file under `tools/`, `content/`, `fixtures/` or `packages/` changed |
| `image`, `smoke` jobs | — | NOT RUN: these need the CI image build (ARM64) and the edge stack |
| Quickstart §1–§5 by hand | — | NOT RUN: walked through the code instead |

## Previous round

| Finding | Now |
| --- | --- |
| R1-1 add forms broken (`pk` on a new UUIDv7 row) | fixed: `_state.adding` (`admin.py:430`, `:492`), and admin-client tests add and edit a product and an offer (`test_admin_catalog.py`) |
| R1-2 invalid BONAT amount gives 500 | fixed: `StoreProductForm.clean` stops on field errors (`admin.py:435`), and `_amount` refuses `None` (`catalog.py:132`). Tested with −5 and `abc`. The new `except` branch is untested (R2-1). |
| R1-3 admin writes under the wrong permission | fixed: the action takes `permissions=("change",)` (`admin.py:364`), the versions confirm needs `has_change_permission` (`:306`), and the maintenance rows need `switch_maintenance` (`:224-232`, `:366-370`). Tested with a view-only user, a change-only user and the other groups. |
| R1-4 batch reads the settings more than once | fixed: `validate_display_name` and `lookups.supported` take the batch's values (`ops/profile.py:57`, `batch.py:221`). `test_a_batch_reads_one_snapshot` covers a name op and an older pack. |
| R1-5 `unused` rows never revived | fixed: `seed.py:24`, with a test in `test_migrations.py` |
| R1-6 wallet index not concurrent | fixed: `AddIndexConcurrently` with `atomic = False` |

## Findings

### HIGH

#### R2-1: The R1-2 fix added an untested branch, so `liveops/services/` misses its 100% line gate
- Layer: tests · Source: T062 ("confirm 100% line coverage of `apps/liveops/services/`"), the tasks.md Tests header, T071 · Location: `backend/apps/liveops/services/catalog.py:138-139` · CONFIRMED (coverage report of the clean run)
- Problem: `_amount`'s `except (TypeError, ValueError)` branch never runs. The admin now stops before `check_product` when a field fails, and no service test passes a non-numeric amount.
- Failure scenario:
  - The feature's own gate reads 97% for `catalog.py`, while T062 and T071 are ticked.
  - Removing the `try/except` would let `save_product(bonat="abc")` raise a bare `ValueError` with Python's message, and no test would notice.
- Fix direction: add a non-numeric case such as `{"bonat": "abc"}` to `test_the_save_validates_the_platforms_and_the_amounts` in `test_catalog.py`, expecting "whole number", then rerun coverage.

Fixed in round 2 by the reviewer: added the `"abc"` case. `uv run pytest apps/liveops --cov=apps.liveops.services --cov=apps.liveops.permissions` → exit 0, 228 passed, every file at 100%. `ruff check` and `ruff format --check` on the file are clean.

## Requirements

Unchanged from round 1 except as below. Every row round 1 marked wrong or partly done is now built and tested:

| Requirement | Built in | Proven by | Status |
| --- | --- | --- | --- |
| FR-007 one snapshot per batch | `sync.py:191`, `profile.py`, `batch.py`, `names.py`, `lookups.py` | `test_a_batch_reads_one_snapshot` | built |
| FR-010 `live_ops` only | admin permissions | `test_admin_settings` (view-only, change-only, other groups), `test_admin_catalog` | built |
| FR-023 catalog history (admin path) | `StoreProductAdmin.save_model` → `catalog.save_product` | `test_admin_catalog` | built |
| FR-025/026 offers in admin | `OfferForm`, `OfferAdmin` | `test_admin_catalog` | built |
| US1 AS6 no permission | admin | `test_other_groups_see_no_live_ops_page` | built |
| US3 AS4 edit grants | admin + service | `test_admin_catalog` | built |
| US5 AS4 unknown rule refused on save | `OfferForm.clean_rules` | `test_an_unknown_rule_is_refused_naming_it` | built |

## Task audit

Ticked 71, verified 69, partly done 2, not done 0. T066–T069 are owner tasks and are correctly unticked.

| Task | Mismatch |
| --- | --- |
| T062 | The 100% bar for `liveops/services/` doesn't hold after the round-1 fixes (R2-1) |
| T071 | Its new `catalog.py` branch has no test (R2-1) |

## Outside this change

Nothing in the change set is outside the feature.

Below the bar, so not findings and no tasks. These are new this round, for the implementer's judgement (round 1's list still applies):
- The Maintenance page's on/off POST (`admin.py:337-361`) has no test. A probe showed it works. US4 is P2.
- The "drifted" filter and the drift column (`admin.py:155-157`, `:257`) have no test. The mark itself is tested through `remote_config.latest_marks()`.
- `HistoryMixin.change_view` filters `pk=object_id` before the permission check, so a non-UUID id answers 500 (staff only).
- On add, `save_model` saves through the service and never saves the admin's own `obj`. The admin LogEntry and "Save and continue" then point at a pk that doesn't exist. The data is correct.
- `LiveopsChangeAdmin` has no `actor` filter, although contracts/admin.md names one.
- `REMOTE_CONFIG_SERVICE_ACCOUNT` doesn't match Django's DEBUG scrubber pattern, and the env file gives it to the api and admin containers as well as the worker.
- A key that doesn't parse raises out of `check_remote_config` instead of recording `unreachable`. Sentry still alerts.

## Not reviewed

- The CI `image` and `smoke` jobs, and quickstart §3–§4 on the phone, were not run.
- SC-001 (staging timing) and the Remote Config call against the real API (owner action T066) were not checked.
- Docs were checked in round 1. They were not re-read this round, because no doc changed after round 1.
