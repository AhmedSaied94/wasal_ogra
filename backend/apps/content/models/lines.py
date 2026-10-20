"""Lines, their stations, and vehicles with their seats (data-model.md)."""

from __future__ import annotations

from typing import ClassVar

from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, RegexValidator
from django.db import models
from django.db.models import F, Q
from wassal_content.models import LineId, UnlockKind, VehicleId

from apps.content.models.base import PermanentModel, choices, slug_validator

DIFFICULTY_MAX = 100
SEAT_PATTERN = r"^(front|[A-D])_(r|m|l)$"


class Line(PermanentModel):
    permanent_kind = "line"
    identifier_lookups = ("line_id",)

    line_id = models.CharField(max_length=32, unique=True, choices=choices(LineId))
    name_ar_eg = models.TextField()
    name_ar = models.TextField(blank=True)
    order = models.PositiveSmallIntegerField(unique=True)
    unlock_kind = models.CharField(max_length=16, choices=choices(UnlockKind))
    unlock_vehicle = models.ForeignKey(
        "content.Vehicle", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    unlock_after_line = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    difficulty_min = models.PositiveSmallIntegerField(
        validators=[MaxValueValidator(DIFFICULTY_MAX)]
    )
    difficulty_max = models.PositiveSmallIntegerField(
        validators=[MaxValueValidator(DIFFICULTY_MAX)]
    )

    class Meta:
        ordering: ClassVar[list[str]] = ["order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.CheckConstraint(
                condition=Q(
                    difficulty_min__lte=F("difficulty_max"), difficulty_max__lte=DIFFICULTY_MAX
                ),
                name="content_line_difficulty_band",
            ),
            models.CheckConstraint(
                condition=(
                    Q(
                        unlock_kind="start",
                        unlock_vehicle__isnull=True,
                        unlock_after_line__isnull=True,
                    )
                    | Q(
                        unlock_kind="vehicle",
                        unlock_vehicle__isnull=False,
                        unlock_after_line__isnull=True,
                    )
                    | Q(
                        unlock_kind="line_complete",
                        unlock_vehicle__isnull=True,
                        unlock_after_line__isnull=False,
                    )
                ),
                name="content_line_unlock_matches_kind",
            ),
            models.CheckConstraint(
                condition=~Q(unlock_after_line=F("id")), name="content_line_unlock_not_itself"
            ),
        ]

    def __str__(self) -> str:
        return self.line_id

    def clean(self) -> None:
        super().clean()
        errors: dict[str, str] = {}
        wants_vehicle = self.unlock_kind == UnlockKind.VEHICLE.value
        wants_line = self.unlock_kind == UnlockKind.LINE_COMPLETE.value
        if wants_vehicle and self.unlock_vehicle_id is None:
            errors["unlock_vehicle"] = "Choose the vehicle that unlocks this line."
        if not wants_vehicle and self.unlock_vehicle_id is not None:
            errors["unlock_vehicle"] = f"An unlock of kind {self.unlock_kind} has no vehicle."
        if wants_line and self.unlock_after_line_id is None:
            errors["unlock_after_line"] = "Choose the line to complete first."
        if not wants_line and self.unlock_after_line_id is not None:
            errors["unlock_after_line"] = f"An unlock of kind {self.unlock_kind} has no line."
        if self.unlock_after_line_id is not None and self.unlock_after_line_id == self.pk:
            errors["unlock_after_line"] = "A line can't unlock itself."
        if errors:
            raise ValidationError(errors)


class Station(PermanentModel):
    permanent_kind = "station"
    identifier_lookups = ("line__line_id", "station_id")

    line = models.ForeignKey(Line, on_delete=models.CASCADE, related_name="stations")
    station_id = models.CharField(max_length=32, validators=[slug_validator])
    name_ar_eg = models.TextField()
    name_ar = models.TextField(blank=True)
    order = models.PositiveSmallIntegerField()

    class Meta:
        ordering: ClassVar[list[str]] = ["line", "order"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(
                fields=["line", "station_id"], name="content_station_id_per_line"
            ),
            models.UniqueConstraint(
                fields=["line", "order"], name="content_station_order_per_line"
            ),
        ]

    def __str__(self) -> str:
        return self.station_id


class Vehicle(PermanentModel):
    permanent_kind = "vehicle"
    identifier_lookups = ("vehicle_id",)

    vehicle_id = models.CharField(max_length=32, unique=True, choices=choices(VehicleId))
    name_ar_eg = models.TextField()
    name_ar = models.TextField(blank=True)
    starter = models.BooleanField(default=False)
    order = models.PositiveSmallIntegerField(unique=True)

    class Meta:
        ordering: ClassVar[list[str]] = ["order"]

    def __str__(self) -> str:
        return self.vehicle_id


class Seat(PermanentModel):
    """A seat's row and column, and whether the driver reaches it, come from `seat_id`."""

    permanent_kind = "seat"
    identifier_lookups = ("vehicle__vehicle_id", "seat_id")

    vehicle = models.ForeignKey(Vehicle, on_delete=models.CASCADE, related_name="seats")
    seat_id = models.CharField(
        max_length=8, validators=[RegexValidator(SEAT_PATTERN, "Use a row and a column: A_l.")]
    )

    class Meta:
        ordering: ClassVar[list[str]] = ["vehicle", "seat_id"]
        constraints: ClassVar[list[models.BaseConstraint]] = [
            models.UniqueConstraint(
                fields=["vehicle", "seat_id"], name="content_seat_id_per_vehicle"
            ),
        ]

    def __str__(self) -> str:
        return self.seat_id
