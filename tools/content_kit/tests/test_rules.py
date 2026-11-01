"""The rules beyond shape (contracts/content-schemas.md "Rules beyond shape", T040).

Each case breaks one copy of the sample pack and expects one finding, named by code, entity,
identifier and the path inside that entity.
"""

import copy
from collections.abc import Callable
from typing import Any

import pytest

from tests.paths import EXAMPLES
from wassal_content.findings import Report
from wassal_content.loader import load_json_file
from wassal_content.schemas import SchemaSet
from wassal_content.validate import SIZE_WARNING_BYTES, validate_pack

PACK: dict[str, Any] = load_json_file(EXAMPLES / "valid" / "pack" / "core.json")
EXPECTED: dict[str, Any] = load_json_file(EXAMPLES / "invalid" / "expected.json")
Mutation = Callable[[dict[str, Any]], None]

# Indexes into the sample pack, whose arrays are sorted by identifier.
TRIP_GAMAA_02, TRIP_HAY_01, TRIP_HAY_02 = 1, 2, 3
LINE_GAMAA, LINE_HAY = 0, 1
VEHICLE_TUKTUK = 1
ITEM_NISH, ITEM_SITARA = 0, 1


def _price(pack: dict[str, Any], kind: str, sku: str) -> dict[str, Any]:
    return next(p for p in pack["catalog"]["prices"] if (p["sku_kind"], p["sku_id"]) == (kind, sku))


def _drop_price(kind: str, sku: str) -> Mutation:
    def apply(pack: dict[str, Any]) -> None:
        pack["catalog"]["prices"].remove(_price(pack, kind, sku))

    return apply


def _set(*path: str | int, value: Any) -> Mutation:
    def apply(pack: dict[str, Any]) -> None:
        target: Any = pack
        for key in path[:-1]:
            target = target[key]
        target[path[-1]] = value

    return apply


def _text(*path: str | int, edit: Callable[[str], str]) -> Mutation:
    def apply(pack: dict[str, Any]) -> None:
        target: Any = pack
        for key in path[:-1]:
            target = target[key]
        target[path[-1]] = edit(target[path[-1]])

    return apply


def _swap_trip_stations(pack: dict[str, Any]) -> None:
    stations = pack["trips"][TRIP_HAY_02]["stations"]
    first, second = stations[0]["station_id"], stations[1]["station_id"]
    stations[0]["station_id"], stations[1]["station_id"] = second, first


def _third_member(pack: dict[str, Any]) -> None:
    pack["trips"][TRIP_HAY_02]["passengers"][2].update(group_id="g1", group_size=2)


def _drop_trip(pack: dict[str, Any]) -> None:
    del pack["trips"][TRIP_HAY_02]


def _add_starter_price(pack: dict[str, Any]) -> None:
    pack["catalog"]["prices"].append(
        {"sku_kind": "vehicle", "sku_id": "tuktuk", "currency": "JENEHAT", "amount": 100}
    )


def _duplicate_price(pack: dict[str, Any]) -> None:
    pack["catalog"]["prices"].append(dict(_price(pack, "item", "salon.nish")))


def _drop_day_seven(pack: dict[str, Any]) -> None:
    pack["daily_rewards"] = [d for d in pack["daily_rewards"] if d["day_index"] != 7]


def _empty_day_one(pack: dict[str, Any]) -> None:
    pack["daily_rewards"][0].update(jenehat=0, bonat=0)


def _empty_task(pack: dict[str, Any]) -> None:
    pack["tasks"][0].update(reward_jenehat=0, reward_bonat=0)


def _jenehat_booster(pack: dict[str, Any]) -> None:
    _price(pack, "booster", "change_bag")["currency"] = "JENEHAT"


# The story fields (specs/015-m10-apartment-story, contracts/content-fields.md "Rules").
CHAPTER_CH1, CHAPTER_CH2 = 0, 1
TRIP_HAY_03 = 4


def _riders(pack: dict[str, Any]) -> list[dict[str, Any]]:
    riders: list[dict[str, Any]] = pack["chapters"][CHAPTER_CH1]["story_trip_info"]["riders"]
    return riders


def _set_rider_seat(seat: str, index: int = 0) -> Mutation:
    def apply(pack: dict[str, Any]) -> None:
        _riders(pack)[index]["seat"] = seat

    return apply


def _story_info_without_trip(pack: dict[str, Any]) -> None:
    # ch2 has no story_trip_id, so its info has nothing to describe (V-C6).
    pack["chapters"][CHAPTER_CH2]["story_trip_info"] = copy.deepcopy(
        pack["chapters"][CHAPTER_CH1]["story_trip_info"]
    )


def _two_riders_in_one_seat(pack: dict[str, Any]) -> None:
    riders = _riders(pack)
    riders.append({"character": "salma", "seat": riders[0]["seat"]})


def _comment_naming_no_pool(pack: dict[str, Any]) -> None:
    _riders(pack)[0]["comments"] = {"impatient": "story.nobody.gone"}


def _comment_pool_with_amount(pack: dict[str, Any]) -> None:
    # passenger.short_change's lines carry {amount}: a rider's comment can't.
    _riders(pack)[0]["comments"] = {"impatient": "passenger.short_change"}


def _fail_reason_without_no_fights(pack: dict[str, Any]) -> None:
    pack["trips"][TRIP_HAY_03]["rules"]["no_fights_required"] = False


def _second_scene_without_plays(pack: dict[str, Any]) -> None:
    scene = copy.deepcopy(pack["chapters"][CHAPTER_CH1]["scenes"][0])
    scene["scene_id"] = "the_wait"
    scene["title"] = {"ar-EG": "الانتظار"}
    pack["chapters"][CHAPTER_CH1]["scenes"].append(scene)


def _duplicate_scene_id(pack: dict[str, Any]) -> None:
    # The phone records a scene by (chapter_id, scene_id), so a scene_id is unique in the pack.
    scene = copy.deepcopy(pack["chapters"][CHAPTER_CH1]["scenes"][0])
    pack["chapters"][CHAPTER_CH2]["scenes"].append(scene)


def _three_speakers(pack: dict[str, Any]) -> None:
    lines = pack["chapters"][CHAPTER_CH1]["scenes"][0]["panels"][0]["lines"]
    lines.extend(
        [
            {"speaker": "salma", "text": {"ar-EG": "طب والأجرة؟"}},
            {"speaker": "usta", "text": {"ar-EG": "على الله"}},
        ]
    )


def _set_slot(**slot: int) -> Mutation:
    def apply(pack: dict[str, Any]) -> None:
        pack["items"][ITEM_NISH]["slot"].update(slot)

    return apply


def _replace_amount(new: str) -> Mutation:
    # By key: the pack has a pool per engine slot (specs/004), so the index would shift.
    def apply(pack: dict[str, Any]) -> None:
        [pool] = [p for p in pack["speech_pools"] if p["speech_key"] == "passenger.wants_change"]
        text = pool["lines"][0]["text"]
        text["ar-EG"] = text["ar-EG"].replace("{amount}", new)

    return apply


_trip = ("trips", TRIP_HAY_02)
_hay_02 = ("trip", "line_hay.02")

CASES: list[tuple[str, Mutation, str, tuple[str, str], str]] = [
    # (case, mutation, code, (entity, id), path)
    ("V-T1", _set("trips", TRIP_HAY_01, "trip_id", value="line_gamaa.03"), "V-T1",
     ("trip", "line_gamaa.03"), "$.trip_id"),
    ("V-T2 unknown station", _set("trips", TRIP_HAY_01, "stations", 0, "station_id", value="souq"),
     "V-T2", ("trip", "line_hay.01"), "$.stations[0].station_id"),
    ("V-T2 line order", _swap_trip_stations, "V-T2", _hay_02, "$.stations[1].station_id"),
    ("V-T2 times", _set(*_trip, "stations", 1, "at_seconds", value=25), "V-T2", _hay_02,
     "$.stations[1].at_seconds"),
    ("V-T2 unknown line", _set("lines", LINE_HAY, "line_id", value="line_souq"), "V-T2",
     ("trip", "line_hay.01"), "$.line_id"),
    ("V-T3 layout",
     _set("trips", TRIP_HAY_01, "seats", value=PACK["trips"][TRIP_HAY_01]["seats"][:2]),
     "V-T3", ("trip", "line_hay.01"), "$.seats"),
    ("V-T3 derived",
     _set("vehicles", VEHICLE_TUKTUK, "seats", 0, "reachable_by_driver", value=False),
     "V-T3", ("vehicle", "tuktuk"), "$.seats[0].reachable_by_driver"),
    ("V-T4 seat", _set(*_trip, "passengers", 0, "seat_id", value="B_r"), "V-T4", _hay_02,
     "$.passengers[0].seat_id"),
    ("V-T4 destination", _set(*_trip, "passengers", 0, "dest_station_id", value="midan"), "V-T4",
     _hay_02, "$.passengers[0].dest_station_id"),
    ("V-T4 boarding", _set(*_trip, "passengers", 2, "board_station_id", value="mahatta"), "V-T4",
     _hay_02, "$.passengers[2].board_station_id"),
    ("V-T5 size", _set(*_trip, "passengers", 1, "group_size", value=3), "V-T5", _hay_02,
     "$.passengers[1].group_size"),
    ("V-T5 count", _third_member, "V-T5", _hay_02, "$.passengers[2].group_id"),
    ("V-T5 together", _set(*_trip, "passengers", 2, "group_id", value="g2"), "V-T5", _hay_02,
     "$.passengers[2].group_size"),
    ("V-T6 speech",
     _set(*_trip, "passengers", 0, "speech_keys", "pays_group", value="passenger.gone"),
     "V-T6", _hay_02, "$.passengers[0].speech_keys.pays_group"),
    ("V-T6 event passenger", _set(*_trip, "events", 1, "passenger_ids", value=["p9"]), "V-T6",
     _hay_02, "$.events[1].passenger_ids[0]"),
    ("V-T6 event station", _set(*_trip, "events", 0, "station_id", value="midan"), "V-T6", _hay_02,
     "$.events[0].station_id"),
    ("V-T7 duplicate", _set(*_trip, "trip_id", value="line_hay.01"), "V-T7",
     ("trip", "line_hay.01"), "$.trip_id"),
    ("V-T7 gap", _drop_trip, "V-T7", ("line", "line_hay"), "$"),
    ("V-L1 extra field",
     _set("lines", LINE_HAY, "unlock", value={"kind": "start", "vehicle_id": "tuktuk"}),
     "V-L1", ("line", "line_hay"), "$.unlock.vehicle_id"),
    ("V-L1 missing field", _set("lines", LINE_GAMAA, "unlock", value={"kind": "vehicle"}), "V-L1",
     ("line", "line_gamaa"), "$.unlock"),
    ("V-L1 unresolved", _set("lines", LINE_GAMAA, "unlock", "vehicle_id", value="micro_new"),
     "V-L1", ("line", "line_gamaa"), "$.unlock.vehicle_id"),
    ("V-L1 itself",
     _set("lines", LINE_HAY, "unlock", value={"kind": "line_complete", "line_id": "line_hay"}),
     "V-L1", ("line", "line_hay"), "$.unlock.line_id"),
    ("V-L2 band", _set("lines", LINE_HAY, "difficulty_band", value={"min": 40, "max": 30}), "V-L2",
     ("line", "line_hay"), "$.difficulty_band"),
    ("V-L2 station ids", _set("lines", LINE_HAY, "stations", 1, "station_id", value="midan"),
     "V-L2",
     ("line", "line_hay"), "$.stations[1].station_id"),
    ("V-C1 extra field", _set("chapters", 1, "goal", "line_id", value="line_hay"), "V-C1",
     ("chapter", "ch2_her_father"), "$.goal.line_id"),
    ("V-C1 missing field", _set("chapters", 1, "goal", value={"kind": "own_vehicle"}), "V-C1",
     ("chapter", "ch2_her_father"), "$.goal"),
    ("V-C1 unresolved", _set("chapters", 3, "goal", "room_id", value="kitchen"), "V-C1",
     ("chapter", "ch4_salon"), "$.goal.room_id"),
    ("V-C1 purchase price", _drop_price("chapter", "ch3_shabka"), "V-C1",
     ("chapter", "ch3_shabka"), "$.goal"),
    ("V-C2", _set("chapters", 0, "story_trip_id", value="line_hay.01"), "V-C2",
     ("chapter", "ch1_first_job"), "$.story_trip_id"),
    ("V-C6", _story_info_without_trip, "V-C6", ("chapter", "ch2_her_father"),
     "$.story_trip_info"),
    ("V-C7 seat not in the trip", _set_rider_seat("B_r"), "V-C7", ("chapter", "ch1_first_job"),
     "$.story_trip_info.riders[0].seat"),
    ("V-C7 seat a passenger names", _set_rider_seat("A_m"), "V-C7",
     ("chapter", "ch1_first_job"), "$.story_trip_info.riders[0].seat"),
    ("V-C7 two riders in one seat", _two_riders_in_one_seat, "V-C7",
     ("chapter", "ch1_first_job"), "$.story_trip_info.riders[1].seat"),
    ("V-C8 no such pool", _comment_naming_no_pool, "V-C8", ("chapter", "ch1_first_job"),
     "$.story_trip_info.riders[0].comments.impatient"),
    ("V-C8 pool with a placeholder", _comment_pool_with_amount, "V-C8",
     ("chapter", "ch1_first_job"), "$.story_trip_info.riders[0].comments.impatient"),
    ("V-C9 without no_fights_required", _fail_reason_without_no_fights, "V-C9",
     ("chapter", "ch1_first_job"), "$.story_trip_info.fail_reason"),
    ("V-C10", _second_scene_without_plays, "V-C10", ("chapter", "ch1_first_job"),
     "$.scenes[1].plays"),
    ("V-C11", _duplicate_scene_id, "V-C11", ("chapter", "ch2_her_father"),
     "$.scenes[0].scene_id"),
    ("V-C12", _three_speakers, "V-C12", ("chapter", "ch1_first_job"),
     "$.scenes[0].panels[0].lines[2].speaker"),
    ("V-R3 width", _set_slot(x=300, w=100), "V-R3", ("item", "salon.nish"), "$.slot"),
    ("V-R3 height", _set_slot(y=200, h=150), "V-R3", ("item", "salon.nish"), "$.slot"),
    ("V-R1 prefix", _set("items", ITEM_SITARA, "item_id", value="kitchen.sitara"), "V-R1",
     ("item", "kitchen.sitara"), "$.item_id"),
    ("V-R1 variants", _set("items", ITEM_NISH, "variants", 1, "variant_id", value="classic"),
     "V-R1",
     ("item", "salon.nish"), "$.variants[1].variant_id"),
    ("V-R1 room chapter", _set("rooms", 0, "chapter_id", value="ch5_kitchen"), "V-R1",
     ("room", "salon"), "$.chapter_id"),
    ("V-R2 variant", _set("family_requests", 0, "variant_id", value="plain"), "V-R2",
     ("family_request", "req_nish_crystal"), "$.variant_id"),
    ("V-R2 room", _set("family_requests", 0, "room_id", value="kitchen"), "V-R2",
     ("family_request", "req_nish_crystal"), "$.room_id"),
    ("V-R2 item", _set("family_requests", 0, "item_id", value="salon.kanaba"), "V-R2",
     ("family_request", "req_nish_crystal"), "$.item_id"),
    ("V-K1 missing", _drop_price("item", "salon.sitara"), "V-K1", ("item", "salon.sitara"), "$"),
    ("V-K1 missing booster", _drop_price("booster", "wake_all"), "V-K1",
     ("catalog_price", "booster:wake_all"), "$"),
    ("V-K1 extra", _add_starter_price, "V-K1", ("catalog_price", "vehicle:tuktuk"), "$"),
    ("V-K1 duplicate", _duplicate_price, "V-K1", ("catalog_price", "item:salon.nish"), "$"),
    ("V-D1 missing day", _drop_day_seven, "V-D1", ("pack", "core"), "$.daily_rewards"),
    ("V-D1 empty day", _empty_day_one, "V-D1", ("daily_reward", "1"), "$"),
    ("V-D1 empty task", _empty_task, "V-D1", ("task", "task_exact_change"), "$"),
    ("V-U1 item", _set("items", ITEM_SITARA, "item_id", value="salon.nish"), "V-U1",
     ("item", "salon.nish"), "$.item_id"),
    ("V-U1 passenger", _set(*_trip, "passengers", 1, "passenger_id", value="p1"), "V-U1", _hay_02,
     "$.passengers[1].passenger_id"),
    ("V-U1 day", _set("daily_rewards", 1, "day_index", value=1), "V-U1", ("daily_reward", "1"),
     "$.day_index"),
    ("V-M1", _jenehat_booster, "V-M1", ("catalog_price", "booster:change_bag"), "$.currency"),
    ("V-X1 trailing space", _text("lines", LINE_HAY, "name", "ar-EG", edit=lambda t: t + " "),
     "V-X1", ("line", "line_hay"), "$.name.ar-EG"),
    ("V-X1 line whats_new digit", _text("lines", LINE_GAMAA, "whats_new", "ar-EG",
                                        edit=lambda t: t + "2"),
     "V-X1", ("line", "line_gamaa"), "$.whats_new.ar-EG"),
    ("V-X1 vehicle short_name space", _text("vehicles", VEHICLE_TUKTUK, "short_name", "ar-EG",
                                            edit=lambda t: t + " "),
     "V-X1", ("vehicle", "tuktuk"), "$.short_name.ar-EG"),
    ("V-X1 leading space", _text("tasks", 0, "text", "ar-EG", edit=lambda t: " " + t), "V-X1",
     ("task", "task_exact_change"), "$.text.ar-EG"),
    ("V-X1 ascii digit", _text("rooms", 0, "name", "ar-EG", edit=lambda t: t + "3"), "V-X1",
     ("room", "salon"), "$.name.ar-EG"),
    ("V-X1 arabic-indic digit", _text("rooms", 0, "name", "ar-EG", edit=lambda t: t + chr(0x663)),
     "V-X1", ("room", "salon"), "$.name.ar-EG"),
    ("V-X1 extended digit", _text("items", ITEM_NISH, "variants", 0, "name", "ar-EG",
                                  edit=lambda t: t + chr(0x6F3)),
     "V-X1", ("item", "salon.nish"), "$.variants[0].name.ar-EG"),
    ("V-X1 scene line", _text("chapters", 0, "scenes", 0, "panels", 0, "lines", 0, "text", "ar-EG",
                              edit=lambda t: t + "1"),
     "V-X1", ("chapter", "ch1_first_job"), "$.scenes[0].panels[0].lines[0].text.ar-EG"),
    ("V-X2 unknown name", _replace_amount("{amout}"), "V-X2",
     ("speech_pool", "passenger.wants_change"), "$.lines[0].text.ar-EG"),
    ("V-X2 unbalanced", _replace_amount("{amount"), "V-X2",
     ("speech_pool", "passenger.wants_change"), "$.lines[0].text.ar-EG"),
    ("V-X2 task placeholder in speech", _replace_amount("{target}"), "V-X2",
     ("speech_pool", "passenger.wants_change"), "$.lines[0].text.ar-EG"),
    ("V-X2 placeholder in a name", _text("items", ITEM_NISH, "name", "ar-EG",
                                         edit=lambda t: t + "{amount}"),
     "V-X2", ("item", "salon.nish"), "$.name.ar-EG"),
]  # fmt: skip


def _keys(report: Report) -> set[tuple[str, str, str, str]]:
    return {(f.code, f.entity, f.id, f.path) for f in report.errors}


@pytest.mark.parametrize(
    ("mutate", "code", "entity", "path"),
    [pytest.param(m, c, e, p, id=name) for name, m, c, e, p in CASES],
)
def test_each_rule_names_what_it_refuses(
    schema_set: SchemaSet, mutate: Mutation, code: str, entity: tuple[str, str], path: str
) -> None:
    pack = copy.deepcopy(PACK)
    mutate(pack)
    report = validate_pack(pack, file_size=None, schema_set=schema_set)
    assert report.stages["schema"] == "passed", report.to_dict()
    assert (code, *entity, path) in _keys(report), sorted(_keys(report))
    stage = "content_rules" if code in ("V-M1", "V-X1", "V-X2") else "references"
    assert report.stages[stage] == "failed"
    assert not report.passed


def test_every_rule_code_has_a_case() -> None:
    # V-C3 to V-C5 (M07) and a V-X1 (M09) are cases of the example set: invalid/expected.json
    # gives their codes.
    codes = {code for _, _, code, _, _ in CASES} | {
        entry["code"] for entry in EXPECTED.values() if isinstance(entry, dict)
    }
    assert codes == {
        *(f"V-T{n}" for n in range(1, 8)),
        "V-L1",
        "V-L2",
        "V-C1",
        "V-C2",
        "V-C3",
        "V-C4",
        "V-C5",
        "V-C6",
        "V-C7",
        "V-C8",
        "V-C9",
        "V-C10",
        "V-C11",
        "V-C12",
        "V-R1",
        "V-R2",
        # V-R4 is V-R2's case: a request's variant_id must be one of its item's.
        "V-R3",
        "V-K1",
        "V-D1",
        "V-U1",
        "V-M1",
        "V-X1",
        "V-X2",
    }


def test_the_sample_pack_has_no_findings(schema_set: SchemaSet) -> None:
    report = validate_pack(PACK, file_size=2582, schema_set=schema_set)
    assert report.findings == []
    assert report.stages == {
        "schema": "passed",
        "references": "passed",
        "content_rules": "passed",
        "size": "passed",
    }


def test_a_group_may_list_fewer_members_than_its_size(schema_set: SchemaSet) -> None:
    # The backend §9.3 trip lists only the payer of a group of three.
    trip = PACK["trips"][TRIP_GAMAA_02]
    [payer] = [p for p in trip["passengers"] if "group_id" in p]
    assert payer["group_size"] == 3
    assert validate_pack(PACK, file_size=None, schema_set=schema_set).passed


def test_a_big_pack_is_only_a_warning(schema_set: SchemaSet) -> None:
    report = validate_pack(PACK, file_size=SIZE_WARNING_BYTES + 1, schema_set=schema_set)
    assert report.stages["size"] == "warning"
    assert report.passed
    assert [(f.code, f.severity) for f in report.findings] == [("V-S1", "warning")]


def test_rules_wait_for_a_valid_schema(schema_set: SchemaSet) -> None:
    pack = copy.deepcopy(PACK)
    pack["trips"][TRIP_HAY_01]["stations"][0]["fare_piasters"] = 475
    report = validate_pack(pack, file_size=None, schema_set=schema_set)
    assert report.stages == {
        "schema": "failed",
        "references": "not_available",
        "content_rules": "not_available",
    }
    assert {f.code for f in report.findings} == {"V-SC"}
