"""Shared test settings: property tests draw the same examples on every run (research R9)."""

from hypothesis import settings

settings.register_profile("ci", derandomize=True, deadline=None, print_blob=True)
settings.load_profile("ci")
