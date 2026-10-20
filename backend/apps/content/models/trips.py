"""Trips and their stations, passengers and events (data-model.md "Trip", FR-004, FR-023)."""

from __future__ import annotations

import secrets
from typing import Any, ClassVar

from django.contrib.postgres.fields import ArrayField
from django.contrib.postgres.validators import ArrayMaxLengthValidator, ArrayMinLengthValidator
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator, RegexValidator
from django.db import models
from django.db.models import F, Q
from django.db.models.functions import Mod
from django.db.models.lookups import Exact
from wassal_content.models import (
    Archetype,
    Denomination,
    EventId,
    StarRuleThree,
    StarRuleTwo,
    TripKind,
)

from apps.content.models.base import PermanentModel, TimestampedModel, choices
from apps.content.models.lines import Line, Seat, Station, Vehicle

SEED_MAX = 4_294_967_295  # xorshift32 needs a non-zero 32-bit seed
COIN_PIASTERS = 50
PAYMENT_MAX = 10
GROUP_SIZE_MIN, GROUP_SIZE_MAX = 2, 12
DENOMINATIONS = tuple(int(d) for d in Denomination)


def random_seed() -> int:
    return secrets.randbelow(SEED_MAX) + 1


def parent_trip(row: models.Model) -> Trip | None:
    """The row's trip, also while an admin form adds both and the trip has no row yet."""
    try:
        return row.trip  # type: ignore[attr-defined, no-any-return]
    except Trip.DoesNotExist:
        return None


def multiple_of_coin(field: str) -> Q:
    return Q(Exact(Mod(F(field), COIN_PIASTERS), 0))


class Trip(PermanentModel):
    """`trip_id` is `<line_id>.<number:02d>`. Line and number together are permanent."""

    permanent_kind = "trip"
    identifier_lookups = ("line__line_id", "number")

    line = models.ForeignKey(Line, on_delete=models.PROTECT, related_name="trips")
    number = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(99)]
    )
    vehicle = models.ForeignKey(Vehicle, on_delete=models.PROTECT, related_name="trips")
    kind = models.CharField(
        max_length=16, choices=choices(TripKind), default=TripKind.REGULAR.value
    )
    seed = models.BigIntegerField(
        default=random_seed, validators=[MinValueValidator(1), MaxValueValidator(SEED_MAX)]
    )
    rev = models.PositiveIntegerField(default=1, editable=False)
    max_earnings_jenehat = models.PositiveIntegerField()
    star_two = models.CharField(max_length=32, choices=choices(StarRuleTwo))
    star_three = models.CharField(max_length=32, choices=choices(StarRuleThree))
    student_discount_pct = models.PositiveSmallIntegerField(validators=[MaxValueValidator(100)])
    bag_fare_piasters = models.PositiveIntegerField(default=0)
    child_free_age = models.PositiveSmallIntegerField(validators=[MaxValueValidator(18)])
    max_break_requests = models.PositiveSmallIntegerField(validators=[MaxValueValidator(2)])
    tray_50 = models.PositiveSmallIntegerField(default=0)
    tray_100 = models.PositiveSmallIntegerField(default=0)
    tray_500 = models.PositiveSmallIntegerField(default=0)
    tray_1000 = models.PositiveSmallIntegerField(default=0)
    tray_2000 = models.PositiveSmallIntegerField(default=0)
    tray_5000 = models.PositiveSmallIntegerField(default=0)
    tray_10000 = models.PositiveSmallIntegerField(default=0)
    tray_20000 = models.PositiveSmallIntegerField(default=0)
    author_notes = models.TextField(blank=True)

    class Meta:
        ordering: ClassVar[list[str]] = ["line", "number"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(fields=["line", "number"], name="content_trip_number_per_line"),
            models.CheckConstraint(
                condition=Q(number__gte=1, number__lte=99), name="content_trip_number_range"
            ),
            models.CheckConstraint(
                condition=Q(seed__gte=1, seed__lte=SEED_MAX), name="content_trip_seed_range"
            ),
            models.CheckConstraint(condition=Q(rev__gte=1), name="content_trip_rev_positive"),
            models.CheckConstraint(
                condition=multiple_of_coin("bag_fare_piasters"), name="content_trip_bag_fare_coins"
            ),
        ]

    @classmethod
    def format_identifier(cls, parts: tuple[Any, ...]) -> str:
        line_id, number = parts
        return f"{line_id}.{number:02d}"

    @property
    def trip_id(self) -> str:
        return self.permanent_identifier()

    def __str__(self) -> str:
        return self.trip_id

    def clean(self) -> None:
        super().clean()
        if self.bag_fare_piasters % COIN_PIASTERS:
            raise ValidationError(
                {"bag_fare_piasters": f"Use a multiple of {COIN_PIASTERS} piasters."}
            )


class TripStation(TimestampedModel):
    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name="trip_stations")
    station = models.ForeignKey(Station, on_delete=models.PROTECT, related_name="+")
    at_seconds = models.PositiveSmallIntegerField(validators=[MinValueValidator(1)])
    fare_piasters = models.PositiveIntegerField(validators=[MinValueValidator(COIN_PIASTERS)])

    class Meta:
        ordering: ClassVar[list[str]] = ["trip", "at_seconds"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(fields=["trip", "station"], name="content_trip_station_once"),
            models.CheckConstraint(condition=Q(at_seconds__gte=1), name="content_trip_station_at"),
            models.CheckConstraint(
                condition=Q(fare_piasters__gte=COIN_PIASTERS) & multiple_of_coin("fare_piasters"),
                name="content_trip_station_fare_coins",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.station}"

    def clean(self) -> None:
        super().clean()
        if self.fare_piasters is not None and self.fare_piasters % COIN_PIASTERS:
            raise ValidationError({"fare_piasters": f"Use a multiple of {COIN_PIASTERS} piasters."})
        trip = parent_trip(self)
        if trip is not None and self.station_id and self.station.line_id != trip.line_id:
            raise ValidationError({"station": "Choose a station on the trip's line."})


class TripPassenger(TimestampedModel):
    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name="passengers")
    passenger_id = models.CharField(
        max_length=4, validators=[RegexValidator(r"^p[0-9]{1,3}$", "Use p and 1-3 digits: p1.")]
    )
    archetype = models.CharField(max_length=32, choices=choices(Archetype))
    skin = models.CharField(
        max_length=48,
        validators=[
            RegexValidator(
                r"^[a-z][a-z0-9_]{1,47}$",
                "Use 2-48 lowercase letters, digits or underscores, starting with a letter.",
            )
        ],
    )
    seat = models.ForeignKey(Seat, on_delete=models.PROTECT, related_name="+")
    board_station = models.ForeignKey(
        Station, null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    dest_station = models.ForeignKey(Station, on_delete=models.PROTECT, related_name="+")
    pays_at_seconds = models.PositiveSmallIntegerField(null=True, blank=True)
    payment = ArrayField(
        models.IntegerField(choices=[(d, str(d)) for d in DENOMINATIONS]),
        size=PAYMENT_MAX,
        validators=[ArrayMinLengthValidator(1), ArrayMaxLengthValidator(PAYMENT_MAX)],
    )
    group_id = models.CharField(
        max_length=3,
        blank=True,
        validators=[RegexValidator(r"^g[0-9]{1,2}$", "Use g and 1-2 digits: g1.")],
    )
    group_size = models.PositiveSmallIntegerField(
        null=True,
        blank=True,
        validators=[MinValueValidator(GROUP_SIZE_MIN), MaxValueValidator(GROUP_SIZE_MAX)],
    )
    # None when the pack has no `speech_keys`, so an empty map survives a round trip.
    speech_keys = models.JSONField(null=True, blank=True, default=None)
    order = models.PositiveSmallIntegerField()

    class Meta:
        ordering: ClassVar[list[str]] = ["trip", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(
                fields=["trip", "passenger_id"], name="content_passenger_id_per_trip"
            ),
            models.CheckConstraint(
                condition=(
                    Q(group_id="", group_size__isnull=True)
                    | (
                        ~Q(group_id="")
                        & Q(group_size__gte=GROUP_SIZE_MIN, group_size__lte=GROUP_SIZE_MAX)
                    )
                ),
                name="content_passenger_group_set_together",
            ),
            models.CheckConstraint(
                condition=Q(payment__len__gte=1, payment__len__lte=PAYMENT_MAX),
                name="content_passenger_payment_length",
            ),
            models.CheckConstraint(
                condition=Q(payment__contained_by=list(DENOMINATIONS)),
                name="content_passenger_payment_denominations",
            ),
        ]

    def __str__(self) -> str:
        return self.passenger_id

    def clean(self) -> None:
        super().clean()
        if (self.group_id == "") != (self.group_size is None):
            raise ValidationError("Set the group and its size together.")
        trip = parent_trip(self)
        if trip is not None and self.seat_id and self.seat.vehicle_id != trip.vehicle_id:
            raise ValidationError({"seat": "Choose a seat of the trip's vehicle."})


class TripEvent(TimestampedModel):
    """A first cut of the event fields for M01 (research "Handed to later features")."""

    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name="events")
    event_id = models.CharField(max_length=32, choices=choices(EventId))
    at_seconds = models.PositiveSmallIntegerField()
    passenger_ids = ArrayField(models.CharField(max_length=4), default=list, blank=True)
    station_id = models.CharField(max_length=32, blank=True)
    amount_piasters = models.IntegerField(null=True, blank=True)
    seconds = models.SmallIntegerField(
        null=True, blank=True, validators=[MinValueValidator(-60), MaxValueValidator(60)]
    )
    order = models.PositiveSmallIntegerField()

    class Meta:
        ordering: ClassVar[list[str]] = ["trip", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.CheckConstraint(
                condition=Q(amount_piasters__isnull=True) | multiple_of_coin("amount_piasters"),
                name="content_event_amount_coins",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.event_id}@{self.at_seconds}"
