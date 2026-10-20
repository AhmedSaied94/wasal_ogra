"""The validator's rules beyond shape (contracts/content-schemas.md "Rules beyond shape").

`engine_findings` adds the engine's rules, V-T8 to V-T11 (specs/004 contracts/content-contract.md
§3), and `trip_engine_findings` the two of them that need only a trip. `trip_local_findings` is
the reference rules a trip can break without a pack.
"""

from wassal_content.rules.content_rules import JENEHAT_KINDS, content_rule_findings
from wassal_content.rules.engine import engine_findings, trip_engine_findings
from wassal_content.rules.references import (
    BONAT_SKUS,
    reference_findings,
    trip_local_findings,
)
from wassal_content.rules.size import SIZE_WARNING_BYTES, size_findings

__all__ = [
    "BONAT_SKUS",
    "JENEHAT_KINDS",
    "SIZE_WARNING_BYTES",
    "content_rule_findings",
    "engine_findings",
    "reference_findings",
    "size_findings",
    "trip_engine_findings",
    "trip_local_findings",
]
