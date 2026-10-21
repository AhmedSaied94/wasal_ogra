// How every feature reads game content
// (specs/006-m04-content-loader/contracts/content-source.md). Pure Dart over
// the generated models: a guard test allows only content_models here
// (constitution I).
import 'package:content_models/content_models.dart';

/// The active pack, read-only.
///
/// An unknown id gives null or an empty list and never throws: after a
/// fallback to the bundled pack, progress may name a trip this pack lacks.
/// Every list is unmodifiable and built once per pack. No method reads
/// files, the network or the clock.
abstract interface class ContentSource {
  /// The pack's version, which ledger and sync operations declare (M05, M06).
  int get version;

  /// Lines in `order`, ascending.
  List<Line> get lines;
  Line? line(LineId id);

  /// A line's trips by trip number: `line_hay.01`, `line_hay.02`, …
  /// Empty for a line with no trips.
  List<TripDefinition> tripsOf(LineId line);
  TripDefinition? trip(String tripId);

  /// Vehicles in `order`, ascending.
  List<Vehicle> get vehicles;
  Vehicle? vehicle(VehicleId id);

  /// The catalog price of one SKU, or null when it has none (a starter
  /// vehicle, say). Amounts are integers (constitution II).
  CatalogPrice? price(SkuKind kind, String skuId);

  SpeechPool? speechPool(String speechKey);

  /// Chapters, rooms and a room's items, each in `order`, ascending.
  List<Chapter> get chapters;
  Chapter? chapter(ChapterId id);
  List<Room> get rooms;
  Room? room(RoomId id);
  List<Item> itemsOf(RoomId room);
  Item? item(String itemId);

  /// Family requests in authored order.
  List<FamilyRequest> get familyRequests;

  /// The 7 days, by `day_index` 1 to 7.
  List<DailyRewardDay> get dailyRewards;

  /// Task templates in authored order.
  List<TaskTemplate> get tasks;
}
