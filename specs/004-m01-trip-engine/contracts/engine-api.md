# Contract: Engine API (`package:trip_engine`)

The public Dart surface of `packages/trip_engine`. M02's `TripController` uses it, and so do the
fixture tool and the tests. Rules are in [rules.md](./rules.md), types in
[data-model.md](../data-model.md), and wire formats in
[replay-and-fixtures.md](./replay-and-fixtures.md). Everything not exported from
`lib/trip_engine.dart` is private to the package.

## Entry points

```dart
import 'package:content_models/content_models.dart' show TripDefinition, LineId;

final class TripEngine {
  /// Starts a trip. Throws [TripRefused] listing every problem (rules.md §2).
  /// [seed] defaults to definition.seed.
  factory TripEngine.start(TripDefinition definition, TripParams params, {int? seed});

  /// Rebuilds a trip from its replay record (rules.md, research R10). The events
  /// produced along the way are discarded. A running trip comes back paused.
  /// Throws [RebuildRefused].
  factory TripEngine.rebuild(ReplayRecord record);

  TripState get state;                 // immutable; read freely
  TripStatus get status;               // shorthand for state.status
  TripResult? get result;              // set when finished, failed or abandoned
  List<LoggedCommand> get commandLog;  // unmodifiable, accepted commands only
  ReplayRecord get replayRecord;       // definition, seed, params, log, state.tMs

  /// Advances one 33 ms logic step. Returns [] when the trip isn't running.
  List<DomainEvent> step();

  /// Steps until state.tMs ≥ tMs or the trip stops running. Returns all events.
  List<DomainEvent> stepTo(int tMs);

  /// Applies [command] at the current clock (rules.md §4).
  CommandOutcome apply(Command command);

  /// running → paused, and paused → running. No-ops otherwise. Never logged.
  void pause();
  void resume();
}

/// Replays a log to its end: it applies each command at its time, then steps
/// until the trip finishes or is abandoned, or until the log is exhausted and
/// the trip has failed. Throws [RebuildRefused] if any command is rejected.
TripResult replay(TripDefinition definition, TripParams params, int seed,
    List<LoggedCommand> log);
```

`TripEngine` is the only stateful object. It is not thread-safe and has no async API. M02 calls it
from the trip scene's update, one step for each 33 ms of accumulated frame time.

## Commands

```dart
sealed class Command { const Command(); }

final class PickFromTray extends Command { const PickFromTray(this.denomination); final int denomination; }
final class ReturnHand extends Command { const ReturnHand(); }
final class SendHand extends Command { const SendHand(this.passengerId); final String passengerId; }
final class UndoLastSend extends Command { const UndoLastSend(); }
final class Tap extends Command { const Tap(this.passengerId); final String passengerId; }
final class ResolveClaim extends Command { const ResolveClaim(this.passengerId, {required this.insist}); … }
final class ResolveDispute extends Command { const ResolveDispute(this.disputeId, this.paidPassengerId); … }
final class ResolveChangeRequest extends Command { const ResolveChangeRequest(this.passengerId, {required this.agree}); … }
final class RequestBreak extends Command { const RequestBreak(this.denomination); final int denomination; }
final class CollectDropped extends Command { const CollectDropped(this.tokenId); final int tokenId; }
final class UseBooster extends Command { const UseBooster(this.booster); final BoosterId booster; }
final class Revive extends Command { const Revive(); }
final class Abandon extends Command { const Abandon(); }

sealed class CommandOutcome { const CommandOutcome(); }
final class Accepted extends CommandOutcome { final List<DomainEvent> events; }
final class Rejected extends CommandOutcome { final Rejection rejection; }

final class Rejection { final RejectionCode code; final String message; }
```

Denominations are `int` piasters. Anything outside glossary §3.2 is rejected with `bad_argument`.
`BoosterId` is the generated `content_models` enum. Only `changeBag`, `wakeAll`, `ledgerPeek` and
`trafficJam` are accepted.

**Rejection codes** (`RejectionCode`, wire names in snake_case):

| Code | Meaning |
| --- | --- |
| `wrong_status` | The command isn't allowed in this status (data-model.md "Commands"). |
| `command_limit` | 1,200 commands have already been accepted. Never for `Abandon`. |
| `bad_argument` | Not a denomination, not a booster, or the passenger isn't part of that choice. |
| `tray_empty` | The tray has none of that denomination. |
| `hand_empty` | The hand is empty. |
| `not_aboard` | The passenger isn't aboard. |
| `undo_unavailable` | Nothing to undo, the window passed, or the first hop finished. |
| `no_effect` | The tap or collect would do nothing: the passenger is waking, has an open claim, or the token isn't dropped. |
| `no_choice` | No such open claim, dispute or change request. |
| `cannot_make_change` | The tray can't make the note's total (rules.md §14.4). |
| `break_limit` | No break requests left, or that note can't be broken. |
| `booster_limit` | `traffic_jam` has been used `booster_traffic_jam_max_per_trip` times this trip. |
| `not_revivable` | Not failed, already revived, or failed by a story-trip fight. |

The message is English and for developers only. Player text comes from M02's ARB file, keyed by the
code (constitution VII).

## Domain events

```dart
sealed class DomainEvent {
  int get tMs;                         // clock when it happened
  String get name;                     // wire name, as below
  Map<String, Object> toJson();        // {"name": …, "t_ms": …, …payload}
}
```

| Event | Payload |
| --- | --- |
| `PassengerBoarded` | `passenger_id`, `seat_id` |
| `PassengerSpeaks` | `passenger_id`, `slot`, `speech_key`, `variant`, `amount_piasters`?, `station_id`? |
| `PassengerWaking` / `PassengerWoke` / `PassengerFellAsleep` | `passenger_id` |
| `PassengerCalled` | `passenger_id`, `taps` |
| `PassengerAttentive` / `PassengerMuted` | `passenger_id` |
| `PatienceRanOut` | `passenger_id` |
| `StopChanged` | `passenger_id`, `deadline_ms` |
| `PassengerAlighted` | `passenger_id`, `outcome` (`thanked`, `fight`, `left_unpaid`, `missed_stop`) |
| `FareSent` | `passenger_id`, `token_id`, `amount_piasters` |
| `ChangeSent` | `passenger_id`, `token_id`, `amount_piasters` |
| `SendUndone` | `token_id` |
| `TokenHopStarted` | `token_id`, `from`, `to`, `duration_ms` (`DRIVER` or a passenger id) |
| `TokenBlocked` | `token_id`, `by` |
| `TokenUnblocked` | `token_id` |
| `MoneyArrivedAtDriver` | `token_id`, `kind`, `amount_piasters` |
| `ChangeDelivered` | `token_id`, `passenger_id`, `result` (`exact`, `short`, `over`, `not_owed`), `amount_piasters` |
| `ExcessReturned` | `passenger_id`, `amount_piasters` |
| `MoneyDropped` / `DroppedCollected` / `DroppedLost` | `token_id` |
| `BreakRequested` | `denomination`, `completes_at_ms` |
| `BreakCompleted` | `denomination`, `pieces` |
| `ClaimRaised` | `passenger_id` |
| `ClaimAccepted` / `LiarCaught` / `FalseAccusation` | `passenger_id` |
| `DisputeRaised` | `dispute_id`, `passenger_ids` [a, b] |
| `DisputeResolved` | `dispute_id`, `right` |
| `ChangeRequestRaised` | `passenger_id`, `amount_piasters` |
| `ChangeRequestResolved` | `passenger_id`, `agreed` |
| `ChangeRequestCompleted` | `passenger_id` |
| `EventStarted` / `EventSkipped` | `index`, `event_id` |
| `FareIncreased` | `amount_piasters`, `total_increase_piasters` |
| `ScheduleShifted` | `delta_ms` |
| `StationWarning` | `station_id`, `at_ms`, `alighting` [ids], `owed` [ids] |
| `StationReached` | `station_id` |
| `ReputationChanged` | `delta`, `cause`, `value` |
| `MistakeMade` | `passenger_id`, `kind`, `amount_piasters` |
| `BoosterUsed` | `booster_id` |
| `LedgerPeekStarted` | `until_ms` |
| `LedgerPeekEnded` | none |
| `TripFailed` | `reputation_lost`, `revivable` |
| `TripRevived` | `reputation` |
| `TripFinished` / `TripAbandoned` | `result` |

Some events, such as `FareSent` and `ChangeDelivered`, show who has paid. The engine reports them
anyway, and M02 decides what to show: the ux-spec's «اللاعب يفتكر، والشاشة ما تفضحش» is
presentation.

## State

`TripState`, `PassengerState`, `MoneyToken`, `StationState`, `Pieces`, `Claim`, `Dispute`,
`ChangeRequest`, `Counters`, `Mistake` and `TripResult` are immutable. Their fields follow
data-model.md, in camelCase. Each has `toJson()` in the canonical wire form, and `TripState.toJson()`
is what the rebuild test compares (SC-009). There are no setters, and no `copyWith` is exported.

Read-only helpers M02 needs, so it never re-derives a rule:

| Getter | Meaning |
| --- | --- |
| `TripState.ledgerPeekActive` | `ledgerPeekUntilMs != null && tMs < ledgerPeekUntilMs` |
| `TripState.undoAvailableUntilMs` | The undo deadline, or null when undo would be rejected |
| `TripState.nextStation` | The next unprocessed `StationState`, or null |
| `TripState.breaksLeft` | `rules.maxBreakRequests − breaksUsed` |
| `PassengerState.isAble`, `.isOwed` | As data-model.md |
| `PassengerState.patiencePermille` | Remaining patience × 1000 ~/ starting patience, or null. Drives the Rive `mood` input. |
| `MoneyToken.progressPermille` | `elapsed × 1000 ~/ duration` while hopping, for the scene to interpolate |

## Params, records, results

```dart
final class TripParams {
  const TripParams({required int tripHopMs, required int tripUndoWindowMs, /* … every field … */});
  factory TripParams.fromJson(Map<String, Object?> json);          // wire form, throws FormatException
  factory TripParams.fromTunables(Map<String, Object?> values, LineId line); // resolves trip_hop_ms_<line>
  Map<String, Object> toJson();
}

final class LoggedCommand { final int tMs; final Command command; /* toJson / fromJson */ }
final class ReplayRecord { /* definition, seed, params, commandLog, tMs; toJson / fromJson */ }
final class TripResult { /* data-model.md; toJson / fromJson */ }
final class ParityFixture { /* five keys; fromJson / toJson */ }

String commandLogHash(List<LoggedCommand> log); // replay-and-fixtures.md §3
```

## Errors

| Type | When |
| --- | --- |
| `TripRefused` | `start` finds problems. It carries `List<Refusal>`, each `{code, path, message}` (data-model.md "Validation"). |
| `RebuildRefused` | `rebuild` or `replay` meets a refused trip, commands out of order, `t_ms` before the last command, or a command rejected on replay. It carries the reason and the log index. |
| `FormatException` | Malformed JSON for params, a record, a log or a fixture. |

The engine never throws during `step` or `apply` on a started trip. Invalid commands are rejected,
not thrown.

## Capabilities

```dart
abstract final class EngineCapabilities {
  static const Set<Archetype> archetypes;      // the 12 of spec FR-004
  static const Set<EventId> events;            // all 8
  static const List<SpeechSlot> speechSlots;   // 23, in content-contract.md §2 order
}

enum SpeechSlot { pays, paysGroup, /* … */; String get wire; String get defaultKey; Set<String> get placeholders; }
```

`capabilities_test.dart` checks these against `content/engine/capabilities.json`.
