// Economy test helpers (specs/007-m05-local-economy/tasks.md T003): fake
// uptime, device clock and tunables, a real economy over real SQLite, and
// trip results. Only the platform edges are faked.
import 'dart:convert';
import 'dart:io';

import 'package:content_models/content_models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/config/bundled_config_source.dart';
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/tunable.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/fold.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/core/economy/domain/trusted_time.dart';
import 'package:wassal/core/economy/domain/txn_id.dart';
import 'package:wassal/core/economy/drift_economy_store.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/economy/economy_service.dart';
import 'package:wassal/core/economy/trusted_clock.dart';
import 'package:wassal/core/platform/uptime.dart';
import 'package:wassal/core/storage/app_database.dart';
import 'package:wassal/core/storage/connection.dart';

import 'content.dart';

/// 2026-10-22T00:00:00Z, the tests' first open.
const testEpochMs = 1792627200000;

/// One hour of uptime before the tests' first open.
const testBootElapsedMs = 3600000;

const minute = Duration(minutes: 1);

/// The phone's uptime counter and boot count, moved by hand.
final class FakeUptimeSource implements UptimeSource {
  FakeUptimeSource({
    this.elapsedRealtimeMs = testBootElapsedMs,
    this.bootCount = 1,
    this.available = true,
  });

  int elapsedRealtimeMs;
  int? bootCount;

  /// False makes [snapshot] return null, as a platform with no channel.
  bool available;

  final _stopwatches = <FakeStopwatch>[];

  @override
  Future<BootSnapshot?> snapshot() async => available
      ? BootSnapshot(elapsedRealtimeMs: elapsedRealtimeMs, bootCount: bootCount)
      : null;

  /// Time passes with the app in the foreground: the counter and every
  /// stopwatch move.
  void advance(Duration by) {
    elapsedRealtimeMs += by.inMilliseconds;
    for (final stopwatch in _stopwatches) {
      stopwatch.advance(by);
    }
  }

  /// Time passes while the CPU sleeps: the counter moves, stopwatches don't.
  void sleep(Duration by) => elapsedRealtimeMs += by.inMilliseconds;

  /// The phone restarts: the counter starts over at [uptime], and the boot
  /// count goes up unless [countBoot] is false.
  void restart({Duration uptime = minute, bool countBoot = true}) {
    elapsedRealtimeMs = uptime.inMilliseconds;
    final boot = bootCount;
    if (countBoot && boot != null) bootCount = boot + 1;
  }

  /// A stopwatch that moves with [advance], for [UptimeTrustedClock].
  FakeStopwatch newStopwatch() {
    final stopwatch = FakeStopwatch();
    _stopwatches.add(stopwatch);
    return stopwatch;
  }
}

/// A [Stopwatch] that moves only when told.
final class FakeStopwatch implements Stopwatch {
  int _elapsedMs = 0;
  bool _running = false;

  void advance(Duration by) {
    if (_running) _elapsedMs += by.inMilliseconds;
  }

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;

  @override
  void reset() => _elapsedMs = 0;

  @override
  int get elapsedMilliseconds => _elapsedMs;

  @override
  int get elapsedMicroseconds => _elapsedMs * 1000;

  @override
  int get elapsedTicks => elapsedMicroseconds;

  @override
  int get frequency => 1000000;

  @override
  Duration get elapsed => Duration(milliseconds: _elapsedMs);

  @override
  bool get isRunning => _running;
}

/// The device clock, in UTC milliseconds, set by hand.
final class FakeDeviceClock {
  FakeDeviceClock([this.nowMs = testEpochMs]);

  int nowMs;

  DateTime call() => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);

  void advance(Duration by) => nowMs += by.inMilliseconds;
}

/// The bundled tunables, read from disk.
Map<String, Object?> bundledTunables() => (jsonDecode(
  File('assets/config/tunables.json').readAsStringSync(),
) as Map<String, dynamic>).cast<String, Object?>();

/// Fuel tunables a test sets, and the bundled default for every other key.
final class FakeTunables implements ConfigSource {
  FakeTunables({this.fuelMax = 5, this.fuelRegenMinutes = 20});

  int fuelMax;
  int fuelRegenMinutes;
  final _bundled = BundledConfigSource(bundledTunables());

  @override
  T read<T extends Object>(Tunable<T> key) {
    if (identical(key, Tunable.fuelMax)) return fuelMax as T;
    if (identical(key, Tunable.fuelRegenMinutes)) return fuelRegenMinutes as T;
    return _bundled.read(key);
  }
}

/// [FakeTunables] with these fuel values.
FakeTunables fixedFuelTunables({int fuelMax = 5, int fuelRegenMinutes = 20}) =>
    FakeTunables(fuelMax: fuelMax, fuelRegenMinutes: fuelRegenMinutes);

ContentSource? _sample;

/// The sample pack, decoded once per test file.
ContentSource sampleContent() => _sample ??= sampleActiveContent().source;

/// A real economy and everything under it.
final class TestEconomy {
  TestEconomy._({
    required this.db,
    required this.store,
    required this.clock,
    required this.service,
    required this.uptime,
    required this.device,
    required this.tunables,
    required this.content,
    required this.dbFile,
  });

  final AppDatabase db;
  final DriftEconomyStore store;
  final UptimeTrustedClock clock;
  final EconomyService service;
  final FakeUptimeSource uptime;
  final FakeDeviceClock device;
  final FakeTunables tunables;
  ContentSource content;
  final File? dbFile;

  bool _closed = false;

  /// Time passes with the phone on and the app open.
  void passTime(Duration by) {
    uptime.advance(by);
    device.advance(by);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    service.dispose();
    await db.close();
  }
}

/// Opens an economy over a real database: in memory, or [dbFile].
///
/// [firstState] replaces the new player as the base of a new file, for
/// tests that need balances to spend (nothing adds BONAT on the device) or
/// progress the pack lacks. It is written the way M06 writes a server
/// snapshot, through the store's rebuild. [executor] wraps the connection,
/// for injected failures.
Future<TestEconomy> testEconomy({
  ContentSource? content,
  FakeTunables? tunables,
  FakeUptimeSource? uptime,
  FakeDeviceClock? device,
  File? dbFile,
  Rules rules = const ProductionRules(),
  EconomyState Function(int nowMs)? firstState,
  QueryExecutor Function(QueryExecutor inner)? executor,
  void Function(EconomyKillPoint point)? onKillPoint,
  int contentVersion = 1,
}) async {
  final source = content ?? sampleContent();
  final fuel = tunables ?? FakeTunables();
  final up = uptime ?? FakeUptimeSource();
  final clock = device ?? FakeDeviceClock();
  final snapshot = await up.snapshot();
  final inner = dbFile == null
      ? NativeDatabase.memory()
      : NativeDatabase(dbFile, setup: configureConnection);
  final db = AppDatabase(
    executor == null ? inner : executor(inner),
    firstOpen: () {
      final anchor = firstAnchor(snapshot, clock.nowMs);
      return FirstOpen(
        state: EconomyState.newPlayer(
          fuelMax: fuel.fuelMax,
          nowMs: anchor.anchorMs,
        ),
        anchor: anchor,
      );
    },
    openCheck: (db) => DriftEconomyStore(db).checkProjection(rules),
  );
  final store = DriftEconomyStore(db, onKillPoint: onKillPoint);
  if (firstState != null) {
    final anchor = await store.loadAnchor();
    await store.rebuild(
      (base, ops) => fold(base, ops, rules),
      newBase: ProjectionBase(
        state: firstState(anchor.anchorMs),
        afterSeq: 0,
        kind: BaseKind.newPlayer,
        takenAtMs: anchor.anchorMs,
      ),
    );
  }
  late final TestEconomy economy;
  final trusted = await UptimeTrustedClock.open(
    uptime: up,
    device: clock.call,
    store: store,
    snapshot: snapshot,
    stopwatch: up.newStopwatch,
  );
  final service = await EconomyService.open(
    store: store,
    clock: trusted,
    content: () => economy.content,
    contentVersion: () => contentVersion,
    tunables: () => fuel,
    rules: rules,
  );
  economy = TestEconomy._(
    db: db,
    store: store,
    clock: trusted,
    service: service,
    uptime: up,
    device: clock,
    tunables: fuel,
    content: source,
    dbFile: dbFile,
  );
  addTearDown(economy.close);
  return economy;
}

/// Closes [economy] and opens its file again, as a relaunch does, with the
/// same fakes unless others are given.
Future<TestEconomy> reopen(
  TestEconomy economy, {
  ContentSource? content,
  FakeUptimeSource? uptime,
  FakeDeviceClock? device,
  void Function(EconomyKillPoint point)? onKillPoint,
}) async {
  final file = economy.dbFile;
  if (file == null) throw StateError('Only a file database can be reopened.');
  await economy.close();
  return testEconomy(
    content: content ?? economy.content,
    tunables: economy.tunables,
    uptime: uptime ?? economy.uptime,
    device: device ?? economy.device,
    dbFile: file,
    onKillPoint: onKillPoint,
  );
}

/// The app database's tables.
const economyTables = [
  'ledger_ops',
  'wallet',
  'inventory',
  'ownership',
  'trip_progress',
  'trip_session',
  'projection_base',
  'clock_anchor',
];

/// Every row of every table, for comparing a database before and after.
Future<Map<String, List<Map<String, Object?>>>> dumpTables(
  AppDatabase db,
) async => {
  for (final table in economyTables)
    table: [
      for (final row
          in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
        row.data,
    ],
};

/// SQLITE_FULL: "database or disk is full".
const sqliteFull = 13;

/// Fails the statements a test arms, as a full disk does: before anything
/// is written, inside the transaction that then rolls back.
final class FailingInterceptor extends QueryInterceptor {
  bool failInserts = false;
  bool failUpdates = false;
  bool failCommits = false;

  /// How many statements failed.
  int failures = 0;

  Never _fail() {
    failures++;
    throw SqliteException(
      extendedResultCode: sqliteFull,
      message: 'database or disk is full',
    );
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (failInserts) _fail();
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (failUpdates) _fail();
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    if (failCommits) _fail();
    return super.commitTransaction(inner);
  }
}

/// Stores [count] ops, [batch] rows to a transaction, then materializes
/// them through [store]'s rebuild, so the file is one the app could have
/// written. The ops are trips on line_hay.01, a start and a result a minute
/// apart, made by the rules from a tank with fuel to spare, and [bonat].
/// Committing them one by one would take half a minute. Returns the last
/// state.
Future<EconomyState> seedOps(
  AppDatabase db,
  DriftEconomyStore store, {
  required int count,
  int batch = 500,
  int bonat = 0,
  ContentSource? content,
}) async {
  const rules = ProductionRules();
  final first = (await store.load()).state;
  final base = first.copyWith(
    bonat: bonat,
    fuel: FuelState(liters: count, countedFromMs: first.fuel.countedFromMs),
  );
  var state = base;
  final ops = <Op>[];
  TxnId? start;
  for (var n = 1; n <= count; n++) {
    final open = start;
    final op = validatedOp(
      rules.validate(
        state,
        open == null
            ? const StartTripRequest('line_hay.01')
            : RecordResultRequest(
                start: open,
                result: tripResult(tripId: 'line_hay.01'),
              ),
        ruleContext(nowMs: testEpochMs + n * 60000, id: n, content: content),
      ),
    );
    state = rules.apply(state, op);
    ops.add(op);
    start = open == null ? op.txnId : null;
  }
  for (var from = 0; from < count; from += batch) {
    await db.batch((b) {
      b.insertAll(db.ledgerOps, [
        for (final op in ops.skip(from).take(batch))
          LedgerOpsCompanion.insert(
            txnId: op.txnId.value,
            opType: op.type.wire,
            payload: canonicalJson(op.payload),
            jenehatDelta: Value(op.jenehatDelta),
            bonatDelta: Value(op.bonatDelta),
            fuelDelta: Value(op.fuelDelta),
            reason: Value(op.reason?.wire),
            ref: Value(op.ref?.value),
            occurredAtMs: op.occurredAtMs,
            contentVersion: op.contentVersion,
            fuelMax: op.fuelMax,
            fuelRegenMinutes: op.fuelRegenMinutes,
            maxEarningsJenehat: Value(op.maxEarningsJenehat),
          ),
      ]);
    });
  }
  await store.rebuild(
    (base, ops) => fold(base, ops, rules),
    newBase: ProjectionBase(
      state: base,
      afterSeq: 0,
      kind: BaseKind.newPlayer,
      takenAtMs: testEpochMs,
    ),
  );
  await store.saveAnchor(
    (await store.loadAnchor()).withLatest(ops.last.occurredAtMs),
  );
  return state;
}

/// A temp database file, deleted after the test.
File tempDbFile() {
  final dir = Directory.systemTemp.createTempSync('economy_db');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return File('${dir.path}/$databaseFileName');
}

/// The [n]th fixed request id: they sort in [n]'s order.
TxnId txnIdOf(int n) => TxnId.parse(
  '0192f3a1-7b2c-7d4e-8f00-${n.toRadixString(16).padLeft(12, '0')}',
);

/// What a request validates against in the rule tests: the sample pack at
/// version 1, `fuel_max` 5 and `fuel_regen_minutes` 20 unless given.
RuleContext ruleContext({
  int nowMs = testEpochMs,
  int id = 1,
  ContentSource? content,
  int contentVersion = 1,
  int fuelMax = 5,
  int fuelRegenMinutes = 20,
}) => RuleContext(
  nowMs: nowMs,
  content: content ?? sampleContent(),
  contentVersion: contentVersion,
  fuelMax: fuelMax,
  fuelRegenMinutes: fuelRegenMinutes,
  txnId: txnIdOf(id),
);

/// The op [decision] validated, failing the test on a refusal.
Op validatedOp(Decision decision) => switch (decision) {
  Validated(:final op) => op,
  Declined(:final code) => fail('Refused with ${code.wire}'),
};

/// The code [decision] refused with, failing the test on an op.
EconomyRefusal declinedCode(Decision decision) => switch (decision) {
  Declined(:final code) => code,
  Validated(:final op) => fail('Validated as $op'),
};

/// A [TripResult] with these values and every other field zero or empty.
TripResult tripResult({
  required String tripId,
  TripOutcome outcome = TripOutcome.finished,
  int stars = 3,
  int earnings = 15,
  int durationMs = 90000,
  bool revived = false,
}) => TripResult.fromJson({
  'trip_id': tripId,
  'rev': 1,
  'outcome': outcome.wire,
  'stars': stars,
  'star_flags': {'reached': true, 'no_fights': true, 'no_mistakes': true},
  'fares_collected_piasters': 0,
  'overpaid_piasters': 0,
  'tips_piasters': 0,
  'earnings_jenehat': earnings,
  'fights': 0,
  'lost_fares': 0,
  'missed_stops': 0,
  'impatient': 0,
  'caught_liars': 0,
  'mistakes': <Object>[],
  'reputation': 100,
  'reputation_lost': <String, Object>{},
  'duration_ms': durationMs,
  'boosters_used': <Object>[],
  'revived': revived,
  'command_log_hash': '0' * 64,
});

/// The economy seams every test of the whole app needs: the database in
/// memory and a fake uptime channel.
List<Override> economyTestOverrides({FakeUptimeSource? uptime}) => [
  uptimeSourceProvider.overrideWithValue(uptime ?? FakeUptimeSource()),
  databaseOpenerProvider.overrideWithValue(() async => NativeDatabase.memory()),
];
