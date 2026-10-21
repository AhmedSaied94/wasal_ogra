import 'package:content_models/content_models.dart';
import 'package:wassal/core/content/domain/content_source.dart';

/// The [ContentSource] over one decoded [Pack].
///
/// Every map and sorted list is built here, once. The constructor runs in
/// the decode isolate (research R4), so the UI isolate does no indexing.
final class PackContentSource implements ContentSource {
  PackContentSource(Pack pack)
    : version = pack.version,
      lines = _sorted(pack.lines, (l) => l.order),
      _lines = {for (final l in pack.lines) l.lineId: l},
      _tripsByLine = _tripsByLineOf(pack.trips),
      _trips = {for (final t in pack.trips) t.tripId: t},
      vehicles = _sorted(pack.vehicles, (v) => v.order),
      _vehicles = {for (final v in pack.vehicles) v.vehicleId: v},
      _prices = {for (final p in pack.catalog.prices) (p.skuKind, p.skuId): p},
      _speechPools = {for (final s in pack.speechPools) s.speechKey: s},
      chapters = _sorted(pack.chapters, (c) => c.order),
      _chapters = {for (final c in pack.chapters) c.chapterId: c},
      rooms = _sorted(pack.rooms, (r) => r.order),
      _rooms = {for (final r in pack.rooms) r.roomId: r},
      _itemsByRoom = _itemsByRoomOf(pack.items),
      _items = {for (final i in pack.items) i.itemId: i},
      familyRequests = List.unmodifiable(pack.familyRequests),
      dailyRewards = _sorted(pack.dailyRewards, (d) => d.dayIndex),
      tasks = List.unmodifiable(pack.tasks);

  @override
  final int version;

  @override
  final List<Line> lines;
  final Map<LineId, Line> _lines;

  final Map<LineId, List<TripDefinition>> _tripsByLine;
  final Map<String, TripDefinition> _trips;

  @override
  final List<Vehicle> vehicles;
  final Map<VehicleId, Vehicle> _vehicles;

  final Map<(SkuKind, String), CatalogPrice> _prices;
  final Map<String, SpeechPool> _speechPools;

  @override
  final List<Chapter> chapters;
  final Map<ChapterId, Chapter> _chapters;

  @override
  final List<Room> rooms;
  final Map<RoomId, Room> _rooms;

  final Map<RoomId, List<Item>> _itemsByRoom;
  final Map<String, Item> _items;

  @override
  final List<FamilyRequest> familyRequests;

  @override
  final List<DailyRewardDay> dailyRewards;

  @override
  final List<TaskTemplate> tasks;

  @override
  Line? line(LineId id) => _lines[id];

  @override
  List<TripDefinition> tripsOf(LineId line) =>
      _tripsByLine[line] ?? const <TripDefinition>[];

  @override
  TripDefinition? trip(String tripId) => _trips[tripId];

  @override
  Vehicle? vehicle(VehicleId id) => _vehicles[id];

  @override
  CatalogPrice? price(SkuKind kind, String skuId) => _prices[(kind, skuId)];

  @override
  SpeechPool? speechPool(String speechKey) => _speechPools[speechKey];

  @override
  Chapter? chapter(ChapterId id) => _chapters[id];

  @override
  Room? room(RoomId id) => _rooms[id];

  @override
  List<Item> itemsOf(RoomId room) => _itemsByRoom[room] ?? const <Item>[];

  @override
  Item? item(String itemId) => _items[itemId];
}

List<T> _sorted<T>(List<T> values, int Function(T) key) => List<T>.unmodifiable(
  <T>[...values]..sort((T a, T b) => key(a).compareTo(key(b))),
);

// `line_hay.07` → 7. The schemas fix the form, so a parse failure can only
// come from a hand-made pack; it sorts last instead of throwing.
int _tripNumber(TripDefinition trip) =>
    int.tryParse(trip.tripId.substring(trip.tripId.lastIndexOf('.') + 1)) ??
    1 << 31;

Map<LineId, List<TripDefinition>> _tripsByLineOf(List<TripDefinition> trips) {
  final byLine = <LineId, List<TripDefinition>>{};
  for (final trip in trips) {
    (byLine[trip.lineId] ??= []).add(trip);
  }
  return {
    for (final MapEntry(:key, :value) in byLine.entries)
      key: _sorted(value, _tripNumber),
  };
}

Map<RoomId, List<Item>> _itemsByRoomOf(List<Item> items) {
  final byRoom = <RoomId, List<Item>>{};
  for (final item in items) {
    (byRoom[item.roomId] ??= []).add(item);
  }
  return {
    for (final MapEntry(:key, :value) in byRoom.entries)
      key: _sorted(value, (i) => i.order),
  };
}
