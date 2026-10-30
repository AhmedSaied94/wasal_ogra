/// The trip rules engine (constitution I): pure Dart, deterministic, and the
/// only place a trip's outcome is decided. The rules are in `RULES.md`, and
/// the surface is `specs/004-m01-trip-engine/contracts/engine-api.md`.
library;

export 'src/capabilities.dart';
export 'src/commands.dart';
export 'src/engine.dart' hide TripEngineDebug;
export 'src/events.dart';
export 'src/fixture.dart';
export 'src/model/choices.dart';
export 'src/model/counters.dart' hide CountersUpdate, reputationLostJson;
export 'src/model/passenger.dart' hide PassengerStateUpdate, makePassengerState;
export 'src/model/result.dart' hide makeTripResult;
export 'src/model/state.dart' hide makeTripState;
export 'src/model/station.dart' hide StationStateUpdate, makeStationState;
export 'src/model/token.dart' hide MoneyTokenUpdate, makeMoneyToken;
export 'src/money.dart' show Pieces;
export 'src/params.dart';
// The rider comments' deterministic pick (specs/015-m10-apartment-story,
// research R15): a fresh generator seeded from the trip seed, never the
// engine's PRNG state. Exported so the app doesn't copy the algorithm; no
// rule, fixture or parity change.
export 'src/prng.dart' show Xorshift32;
export 'src/replay.dart' hide playLog, replayEngine, startReplay;
export 'src/validation.dart' show Refusal, RefusalCode, TripRefused;
