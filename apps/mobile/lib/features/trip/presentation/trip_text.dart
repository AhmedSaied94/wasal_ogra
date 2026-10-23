// The trip's words: the view carries ARB keys, labels and amounts, and these
// turn them into the player's text (contracts/trip-view.md "Player text").
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

extension TripText on AppLocalizations {
  /// The station letter of [slot] (0–3): أ ب ج د.
  String stationLetter(int slot) => switch (slot % 4) {
    0 => tripStationLetter1,
    1 => tripStationLetter2,
    2 => tripStationLetter3,
    _ => tripStationLetter4,
  };

  /// A `tripLook*` label by its key; an unknown key is the neutral label.
  String lookLabel(String key) => switch (key) {
    'tripLookEffendi' => tripLookEffendi,
    'tripLookStudent' => tripLookStudent,
    'tripLookWorker' => tripLookWorker,
    'tripLookHajja' => tripLookHajja,
    'tripLookYoung' => tripLookYoung,
    'tripLookGroup' => tripLookGroup,
    _ => tripLookPassenger,
  };

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

  /// A booster's name.
  String boosterName(BoosterId booster) => switch (booster) {
    BoosterId.changeBag => tripBoosterChangeBag,
    BoosterId.wakeAll => tripBoosterWakeAll,
    BoosterId.ledgerPeek => tripBoosterLedgerPeek,
    _ => tripBoosterTrafficJam,
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
}
