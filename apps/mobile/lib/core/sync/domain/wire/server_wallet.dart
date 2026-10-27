// The wallet in every answer (B03 contracts/api.md): fuel recounted to the
// server's now, with its countdown start.
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/sync/domain/wire/iso_time.dart';
import 'package:wassal/core/sync/domain/wire/reader.dart';

/// `{jenehat, bonat, fuel, fuel_max, fuel_updated_at, fuel_unlimited_until}`.
final class ServerWallet {
  const ServerWallet({
    required this.jenehat,
    required this.bonat,
    required this.fuel,
    required this.fuelMax,
    required this.fuelUpdatedAtMs,
    this.fuelUnlimitedUntilMs,
  });

  factory ServerWallet.fromJson(Object? json, [String path = 'wallet']) {
    final o = WireObject.of(json, path);
    return ServerWallet(
      jenehat: o.integer('jenehat'),
      bonat: o.integer('bonat'),
      fuel: o.integer('fuel'),
      fuelMax: o.integer('fuel_max'),
      fuelUpdatedAtMs: o.time('fuel_updated_at'),
      fuelUnlimitedUntilMs: o.optionalTime('fuel_unlimited_until'),
    );
  }

  final int jenehat;
  final int bonat;
  final int fuel;

  /// Not used: the tank's size stays the tunables' until M17 (research R11).
  final int fuelMax;
  final int fuelUpdatedAtMs;
  final int? fuelUnlimitedUntilMs;

  /// The economy's tank: the liters, counted from `fuel_updated_at`, which
  /// is M05's `countedFrom` (research R11).
  FuelState get fuelState => FuelState(
    liters: fuel,
    countedFromMs: fuelUpdatedAtMs,
    unlimitedUntilMs: fuelUnlimitedUntilMs,
  );

  @override
  String toString() => 'ServerWallet(J $jenehat, B $bonat, $fuelState)';
}
