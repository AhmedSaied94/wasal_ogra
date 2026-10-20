"""Admin forms for authoring (contracts/admin.md "Authoring pages", FR-013, FR-016).

Errors are shown on their field and nothing is saved. Rules that span a trip's inlines (stations
in line order, passengers' stations among the trip's) are checked in the trip's formsets, which
read the stations the same request submits.
"""

from __future__ import annotations

from itertools import pairwise
from typing import Any

from django import forms
from django.core.exceptions import ValidationError
from django.forms.models import BaseInlineFormSet

from apps.content.models import PermanentModel, Station, Trip
from apps.content.services import permanence

MAX_TRIP_STATIONS = 4


def identifier_fields(model: type[Any]) -> set[str]:
    """The form fields that make up a model's permanent identifier."""
    if not issubclass(model, PermanentModel):
        return set()
    return {lookup.split("__")[0] for lookup in model.identifier_lookups}


def published_version(instance: Any) -> int | None:
    if not isinstance(instance, PermanentModel) or instance._state.adding:
        return None
    stored = instance.stored_identifier()
    return None if stored is None else permanence.published_version(instance.permanent_kind, stored)


class ContentForm(forms.ModelForm):  # type: ignore[type-arg]
    """Freezes the identifier fields of a row a published pack contains (FR-016)."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        version = published_version(self.instance)
        if version is None:
            return
        for name in identifier_fields(type(self.instance)) & set(self.fields):
            self.fields[name].disabled = True
            self.fields[
                name
            ].help_text = f"In published pack version {version}, so it can't change."


class PermanenceFormSet(BaseInlineFormSet):  # type: ignore[type-arg]
    """Refuses removing a nested row whose identifier a published pack contains."""

    def clean(self) -> None:
        super().clean()
        problems = []
        for form in self.deleted_forms:
            version = published_version(form.instance)
            if version is not None:
                identifier = form.instance.stored_identifier()
                problems.append(
                    f"{form.instance.permanent_kind} {identifier} is in published pack version "
                    f"{version}, so it can't be deleted."
                )
        # Django ignores the errors of a form marked for deletion, so refuse the whole formset.
        if problems:
            raise forms.ValidationError(problems)


def _kept(formset: BaseInlineFormSet) -> list[forms.Form]:  # type: ignore[type-arg]
    """The rows the save keeps: not deleted, and not an untouched extra row."""
    return [
        form for form in formset.forms if form not in formset.deleted_forms and form.cleaned_data
    ]


class TripStationFormSet(PermanenceFormSet):
    """1 to 4 stations of the trip's line, in line order, with increasing `at_seconds`."""

    def clean(self) -> None:
        super().clean()
        if any(form.errors for form in self.forms):
            return
        stops = [
            (form, form.cleaned_data["station"], form.cleaned_data["at_seconds"])
            for form in _kept(self)
            if form.cleaned_data.get("station") is not None
        ]
        if not 1 <= len(stops) <= MAX_TRIP_STATIONS:
            raise forms.ValidationError(f"A trip has 1 to {MAX_TRIP_STATIONS} stations.")
        stops.sort(key=lambda stop: stop[1].order)
        for (_, before, at_before), (form, station, at) in pairwise(stops):
            if station == before:
                form.add_error("station", "This station is already on the trip.")
            elif at <= at_before:
                form.add_error(
                    "at_seconds",
                    f"Arrive after {before} (at {at_before} s): stations follow the line.",
                )


class TripPassengerFormSet(PermanenceFormSet):
    """Passengers board and leave at the trip's own stations."""

    def clean(self) -> None:
        super().clean()
        stations = posted_trip_stations(self.data, self.instance)
        for form in _kept(self):
            data = form.cleaned_data
            dest, board = data.get("dest_station"), data.get("board_station")
            if dest is not None and dest not in stations:
                form.add_error("dest_station", "Choose one of the trip's stations.")
            if board is not None and board not in stations:
                form.add_error("board_station", "Choose one of the trip's stations.")


def posted_trip_stations(data: Any, trip: Trip) -> set[Station]:
    """The trip's stations as the same request submits them, or as stored when it doesn't."""
    prefix = "trip_stations"
    total = data.get(f"{prefix}-TOTAL_FORMS")
    if total is None:
        return {stop.station for stop in trip.trip_stations.all()} if trip.pk else set()
    ids = []
    for index in range(int(total)):
        if data.get(f"{prefix}-{index}-DELETE"):
            continue
        value = data.get(f"{prefix}-{index}-station")
        if value:
            ids.append(value)
    try:
        return set(Station.objects.filter(pk__in=ids))
    except ValidationError:  # a tampered id: the station formset reports it on its field
        return set()
