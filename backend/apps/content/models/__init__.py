"""The content app's models (data-model.md)."""

from django.db import models

from apps.content.models.base import PermanentModel
from apps.content.models.lines import Line, Seat, Station, Vehicle
from apps.content.models.packs import (
    ContentAuditRecord,
    ContentChannel,
    ContentPack,
    PackPriceIndex,
    PackTripIndex,
    PublishedIdentifier,
)
from apps.content.models.solver import SolverRun
from apps.content.models.speech_economy import (
    CatalogPrice,
    DailyRewardDay,
    SpeechLine,
    SpeechPool,
    TaskTemplate,
)
from apps.content.models.story import (
    Chapter,
    FamilyRequest,
    Item,
    ItemVariant,
    Room,
    Scene,
    SceneLine,
)
from apps.content.models.trips import Trip, TripEvent, TripPassenger, TripStation

# Every model whose identifier becomes permanent once published (FR-016).
PERMANENT_MODELS: tuple[type[PermanentModel], ...] = (
    Line,
    Station,
    Vehicle,
    Seat,
    Trip,
    Chapter,
    Scene,
    Room,
    Item,
    ItemVariant,
    FamilyRequest,
    SpeechPool,
    TaskTemplate,
)
# The authored content, which the content_author group may add, change and delete (R9).
AUTHORING_MODELS: tuple[type[models.Model], ...] = (
    *PERMANENT_MODELS,
    TripStation,
    TripPassenger,
    TripEvent,
    SceneLine,
    SpeechLine,
    CatalogPrice,
    DailyRewardDay,
)

__all__ = [
    "AUTHORING_MODELS",
    "PERMANENT_MODELS",
    "CatalogPrice",
    "Chapter",
    "ContentAuditRecord",
    "ContentChannel",
    "ContentPack",
    "DailyRewardDay",
    "FamilyRequest",
    "Item",
    "ItemVariant",
    "Line",
    "PackPriceIndex",
    "PackTripIndex",
    "PermanentModel",
    "PublishedIdentifier",
    "Room",
    "Scene",
    "SceneLine",
    "Seat",
    "SolverRun",
    "SpeechLine",
    "SpeechPool",
    "Station",
    "TaskTemplate",
    "Trip",
    "TripEvent",
    "TripPassenger",
    "TripStation",
    "Vehicle",
]
