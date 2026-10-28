// The trip's words: the view carries ARB keys, labels and amounts, and these
// turn them into the player's text (contracts/trip-view.md "Player text").
import 'package:content_models/content_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/station_tag.dart';
import 'package:wassal/features/onboarding/domain/tutorial_coach.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

extension TripText on AppLocalizations {
  /// The station letter of [slot] (0–3): أ ب ج د.
  String stationLetter(int slot) => stationLetterOf(this, slot);

  /// A `tripLook*` label by its key; an unknown key is the neutral label.
  String lookLabel(String key) => switch (key) {
    'tripLookEffendi' => tripLookEffendi,
    'tripLookStudent' => tripLookStudent,
    'tripLookHajja' => tripLookHajja,
    'tripLookHeadphones' => tripLookHeadphones,
    'tripLookGroup' => tripLookGroup,
    _ => tripLookPassenger,
  };

  /// A passenger's screen-reader label (spec FR-036): their look, seat and
  /// stop, and «ليه باقي» while their stop is next and they're still owed.
  /// Never what they do (M02 research R10).
  String passengerLabel({
    required String lookKey,
    required SeatRow row,
    required SeatCol col,
    required int? slot,
    required String? stopName,
    required bool owed,
  }) {
    final look = lookLabel(lookKey);
    final where = seatName(row, col);
    if (slot == null) return tripSemanticsPassengerNoStation(look, where);
    final letter = stationLetter(slot);
    final stop = switch (stopName) {
      final name? => tripSemanticsStopNamed(name, letter),
      null => tripSemanticsStop(letter),
    };
    return owed
        ? tripSemanticsPassengerOwed(look, where, stop)
        : tripSemanticsPassenger(look, where, stop);
  }

  String speaker(SpeakerLabel label) => switch (label.slot) {
    final slot? => tripLogSpeakerSlot(
      lookLabel(label.labelKey),
      stationLetter(slot),
    ),
    null => lookLabel(label.labelKey),
  };

  /// A «آخر كلام» line.
  String logLine(LogLine line, NumberFormatter numbers) {
    final amount = numbers.piasters(line.amountPiasters ?? 0);
    final who = switch (line.speaker) {
      final s? => speaker(s),
      null => tripLookPassenger,
    };
    return switch (line.kind) {
      LogKind.speech => tripLogSpeech(who, line.text ?? ''),
      LogKind.fareArrived => tripLogFareArrived(amount, who),
      LogKind.breakDone => tripLogBreakDone(amount),
      LogKind.dropped => tripLogDropped(amount),
      LogKind.lost => tripLogLost(amount),
      LogKind.fareUp => tripLogFareUp(amount),
    };
  }

  /// The words of a spoken rejection, or null for one that only shakes.
  String? rejection(RejectionCode code) => switch (code) {
    RejectionCode.cannotMakeChange => tripRejectNoChange,
    RejectionCode.breakLimit => tripRejectBreakLimit,
    RejectionCode.boosterLimit => tripRejectBoosterLimit,
    RejectionCode.commandLimit => tripRejectCommandLimit,
    _ => null,
  };

  String retryMessage(TripRetry retry) => switch (retry) {
    TripRetry.start => tripRetryStart,
    TripRetry.result => tripRetryResult,
    TripRetry.purchase => tripRetryPurchase,
    TripRetry.revive => tripRetryRevive,
  };

  /// A seat's spoken name: «الصف الأول يمين», or the front seat.
  String seatName(SeatRow row, SeatCol col) {
    final rowName = switch (row) {
      SeatRow.front => null,
      SeatRow.a => tripSeatRowA,
      SeatRow.b => tripSeatRowB,
      SeatRow.c => tripSeatRowC,
      SeatRow.d => tripSeatRowD,
    };
    if (rowName == null) return tripSeatFront;
    final side = switch (col) {
      SeatCol.r => tripSeatRight,
      SeatCol.m => tripSeatMiddle,
      SeatCol.l => tripSeatLeft,
    };
    return tripSeatAt(rowName, side);
  }

  /// A booster's name; the traffic jam's says its [jamSeconds].
  String boosterName(BoosterId booster, {required String jamSeconds}) =>
      switch (booster) {
        BoosterId.changeBag => tripBoosterChangeBag,
        BoosterId.wakeAll => tripBoosterWakeAll,
        BoosterId.ledgerPeek => tripBoosterLedgerPeek,
        _ => tripBoosterTrafficJam(jamSeconds),
      };

  /// بلية's line by its `tripHint*` key, or null for an unknown key.
  /// One failure cause, counted: «خناقتين».
  String failCause(FailCause cause, NumberFormatter numbers) {
    final count = cause.count ?? 1;
    final n = numbers.integer(count);
    return switch (cause.cause) {
      RepCause.fight => tripCauseFight(count, n),
      RepCause.falseAccusation => tripCauseFalseAccusation(count, n),
      RepCause.missedStop => tripCauseMissedStop(count, n),
      RepCause.shortChange => tripCauseShortChange(count, n),
      RepCause.impatient => tripCauseImpatient(count, n),
      RepCause.changeRequestDeclined => tripCauseChangeRequestDeclined(
        count,
        n,
      ),
      // Gains are never causes.
      RepCause.exactChange || RepCause.liarCaught || RepCause.revive => '',
    };
  }

  /// The failure card's line: «خناقتين وراكب فاتته محطته».
  String failCauses(FailSummary summary, NumberFormatter numbers) =>
      switch ([for (final c in summary.causes) failCause(c, numbers)]) {
        [] => '',
        [final one] => one,
        [final first, final second, ...] => tripFailCauses(first, second),
      };

  /// The ledger's word over a passenger.
  String ledgerWord(LedgerBadge badge) => switch (badge) {
    LedgerBadge.paid => tripLedgerPaid,
    LedgerBadge.unpaid => tripLedgerUnpaid,
    LedgerBadge.onFriend => tripLedgerOnFriend,
  };

  String? hintText(String key) => switch (key) {
    'tripHintOwed' => tripHintOwed,
    'tripHintSleeper' => tripHintSleeper,
    'tripHintHeadphones' => tripHintHeadphones,
    'tripHintHajja' => tripHintHajja,
    'tripHintHurry' => tripHintHurry,
    'tripHintBigNote' => tripHintBigNote,
    'tripHintStudent' => tripHintStudent,
    'tripHintGroupPayer' => tripHintGroupPayer,
    'tripHintChatty' => tripHintChatty,
    'tripHintFalseClaimer' => tripHintFalseClaimer,
    'tripHintHonest' => tripHintHonest,
    'tripHintRegularCustomer' => tripHintRegularCustomer,
    _ => null,
  };

  /// The drawer's label of a denomination: «نص» for 50 piasters, else the
  /// pounds.
  String trayLabel(int denomination, NumberFormatter numbers) =>
      denomination == 50 ? tripTrayHalf : numbers.piasters(denomination);

  /// What بلية says for a coach [line] (M07 contracts/coach.md "Lines");
  /// [station] names a stop by its id.
  String coachLine(
    CoachLine line,
    NumberFormatter numbers,
    String Function(String stationId) station,
  ) => switch (line) {
    FareArrivedLine() => coachFareArrived,
    GiveChangeLine(:final amountPiasters, :final coin?, :final count?) =>
      coachGiveChange(
        numbers.piasters(amountPiasters),
        coachCoinName('v$coin'),
        count,
        numbers.integer(count),
      ),
    GiveChangeLine(:final amountPiasters) => coachGiveChangeAny(
      numbers.piasters(amountPiasters),
    ),
    TapRiderLine() => coachTapRider,
    StopNearLine(:final stationId) => coachStopNear(station(stationId)),
    WakeSleeperLine() => coachWakeSleeper,
  };
}

/// The trip's text scale (research R8): the HUD, the strip, the dashboard,
/// the tags and the notes follow the system's up to 1.15×, where their
/// fixed cells still hold it. Bubbles aren't scaled; cards, banners and
/// dialogs follow M03's 1.3.
abstract final class TripTextScale {
  static const double max = 1.15;

  /// The system's scale, clamped to 1.0–1.15.
  static TextScaler clamp(BuildContext context) =>
      MediaQuery.textScalerOf(context)
          .clamp(minScaleFactor: 1, maxScaleFactor: max);

  /// [child] with its text clamped to 1.0–1.15.
  static Widget scope(BuildContext context, {required Widget child}) =>
      MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: clamp(context)),
        child: child,
      );
}
