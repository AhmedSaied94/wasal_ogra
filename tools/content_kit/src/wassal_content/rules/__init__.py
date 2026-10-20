"""The validator's rules beyond shape (contracts/content-schemas.md "Rules beyond shape")."""

from wassal_content.rules.content_rules import JENEHAT_KINDS, content_rule_findings
from wassal_content.rules.references import BONAT_SKUS, reference_findings
from wassal_content.rules.size import SIZE_WARNING_BYTES, size_findings

__all__ = [
    "BONAT_SKUS",
    "JENEHAT_KINDS",
    "SIZE_WARNING_BYTES",
    "content_rule_findings",
    "reference_findings",
    "size_findings",
]
