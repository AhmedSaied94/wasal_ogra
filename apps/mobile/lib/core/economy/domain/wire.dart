// Wire names of the generated content enums the economy stores and sends.
// The generated enums keep them only in `@JsonValue` annotations, so they are
// spelled out here; `wire_test.dart` checks each against content_models'
// own JSON.
import 'package:content_models/content_models.dart';

const skuKindWire = <SkuKind, String>{
  SkuKind.item: 'item',
  SkuKind.vehicle: 'vehicle',
  SkuKind.chapter: 'chapter',
  SkuKind.booster: 'booster',
  SkuKind.fuel: 'fuel',
  SkuKind.revive: 'revive',
  SkuKind.fuelUnlimited: 'fuel_unlimited',
};

const boosterWire = <BoosterId, String>{
  BoosterId.changeBag: 'change_bag',
  BoosterId.wakeAll: 'wake_all',
  BoosterId.ledgerPeek: 'ledger_peek',
  BoosterId.trafficJam: 'traffic_jam',
  BoosterId.revive: 'revive',
  BoosterId.refuelFull: 'refuel_full',
  BoosterId.fuelUnlimited1h: 'fuel_unlimited_1h',
};

const vehicleWire = <VehicleId, String>{
  VehicleId.tuktuk: 'tuktuk',
  VehicleId.microOld: 'micro_old',
  VehicleId.microNew: 'micro_new',
  VehicleId.microSafar: 'micro_safar',
};

const chapterWire = <ChapterId, String>{
  ChapterId.ch1FirstJob: 'ch1_first_job',
  ChapterId.ch2HerFather: 'ch2_her_father',
  ChapterId.ch3Shabka: 'ch3_shabka',
  ChapterId.ch4Salon: 'ch4_salon',
  ChapterId.ch5Kitchen: 'ch5_kitchen',
  ChapterId.ch6Bedroom: 'ch6_bedroom',
  ChapterId.ch7Wedding: 'ch7_wedding',
};

/// The key of [map] whose wire name is [wire], or null.
T? fromWire<T>(Map<T, String> map, Object? wire) {
  for (final MapEntry(:key, :value) in map.entries) {
    if (value == wire) return key;
  }
  return null;
}
