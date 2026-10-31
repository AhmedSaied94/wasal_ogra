// What the trip screen draws (data-model.md "The view"). Built by
// `projectTripView` after every step and every accepted command. It holds
// only what the screen may show: no fare, payment, balance or debt of any
// passenger (research R10, FR-033).
import 'package:content_models/content_models.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/view_value.dart';

/// The controller's phase (data-model.md "TripPhase"). The engine runs only
/// in [running].
enum TripPhase {
  opening,
  noFuel,
  running,
  paused,
  disputeOpen,
  boosterCard,
  failed,
  ending,
  ended,
}

final class TripView extends ViewValue {
  const TripView({
    required this.tMs,
    required this.phase,
    required this.topBar,
    required this.strip,
    required this.passengers,
    required this.tokens,
    required this.dropped,
    required this.windows,
    required this.hand,
    required this.tray,
    required this.breakButton,
    required this.boosters,
    required this.undoUntilMs,
    required this.choices,
    required this.bubbles,
    required this.log,
    required this.hint,
    required this.banner,
    required this.storyCondition,
    required this.failSummary,
    required this.rejection,
    required this.breakMode,
    required this.controlsLocked,
    this.fastForward = false,
    this.storyStrip,
    this.riderBubble,
  });

  final int tMs;
  final TripPhase phase;
  final TopBarView topBar;
  final StationStripView strip;
  final List<PassengerView> passengers;
  final List<TokenView> tokens;
  final List<DroppedMoneyView> dropped;
  final WindowsView windows;
  final HandView hand;
  final List<TraySlotView> tray;
  final BreakButtonView breakButton;
  final List<BoosterSlotView> boosters;
  final int? undoUntilMs;
  final List<ChoiceView> choices;
  final List<BubbleView> bubbles;
  final List<LogLine> log;
  final HintView? hint;
  final BannerView? banner;

  /// A story trip's «من غير خناقات» rule: null when the trip has none, true
  /// while it holds, false once a fight broke it. The strip's visibility is
  /// [storyStrip]'s, which a content condition also sets.
  final bool? storyCondition;

  /// The story strip, or null when the trip shows none.
  final StoryStripView? storyStrip;

  /// A story rider's comment, while it shows.
  final RiderBubbleView? riderBubble;
  final FailSummary? failSummary;

  /// A rejection said in the log's place for a moment (trip-view.md
  /// "Rejections").
  final RejectionLine? rejection;

  /// «حد معاه فكة؟» is waiting for the note to break.
  final bool breakMode;

  /// The command limit was reached: only pause still responds.
  final bool controlsLocked;

  /// Nothing is left for the player, so the clock runs `settledSpeedUp`
  /// times faster to the end of the line.
  final bool fastForward;

  PassengerView? passenger(String passengerId) {
    for (final p in passengers) {
      if (p.passengerId == passengerId) return p;
    }
    return null;
  }

  @override
  Map<String, Object?> get fields => {
    'tMs': tMs,
    'phase': phase,
    'topBar': topBar,
    'strip': strip,
    'passengers': passengers,
    'tokens': tokens,
    'dropped': dropped,
    'windows': windows,
    'hand': hand,
    'tray': tray,
    'breakButton': breakButton,
    'boosters': boosters,
    'undoUntilMs': undoUntilMs,
    'choices': choices,
    'bubbles': bubbles,
    'log': log,
    'hint': hint,
    'banner': banner,
    'storyCondition': storyCondition,
    'storyStrip': storyStrip,
    'riderBubble': riderBubble,
    'failSummary': failSummary,
    'rejection': rejection,
    'breakMode': breakMode,
    'controlsLocked': controlsLocked,
    'fastForward': fastForward,
  };
}

final class TopBarView extends ViewValue {
  const TopBarView({
    required this.lineName,
    required this.tripNumber,
    required this.reputation,
    required this.reputationLow,
    this.storyTitle,
  });

  /// The line's name, or null when the pack no longer has the line.
  final String? lineName;

  /// The number after the dot in the trip id: `line_hay.01` → 1.
  final int tripNumber;

  /// 0–100.
  final int reputation;
  final bool reputationLow;

  /// A story trip's title from its chapter's `story_trip_info` (specs/015-
  /// m10-apartment-story): it takes the line and number's place under the
  /// «مشوار قصة» chip. Null for any other trip.
  final String? storyTitle;

  @override
  Map<String, Object?> get fields => {
    'lineName': lineName,
    'tripNumber': tripNumber,
    'reputation': reputation,
    'reputationLow': reputationLow,
    'storyTitle': storyTitle,
  };
}

/// A story trip's strip (specs/015-m10-apartment-story, contracts/
/// story-trip.md "What the screen shows"): present when the trip has a story
/// rule or its chapter words a condition.
final class StoryStripView extends ViewValue {
  const StoryStripView({this.text, this.broken});

  /// The chapter's condition as the content wrote it; null reads M02's
  /// «من غير خناقات».
  final String? text;

  /// The rule's state: true once a fight broke it, false while it holds,
  /// null when the trip has no rule (nothing can break).
  final bool? broken;

  @override
  Map<String, Object?> get fields => {'text': text, 'broken': broken};
}

/// A story rider's bubble in the character slot, over the rider's face.
final class RiderBubbleView extends ViewValue {
  const RiderBubbleView({
    required this.speaker,
    required this.seatId,
    required this.text,
  });

  final StoryCharacter speaker;

  /// The seat the rider sits in (`StoryRider.seat`), where the bubble anchors.
  final String seatId;
  final String text;

  @override
  Map<String, Object?> get fields => {
    'speaker': speaker,
    'seatId': seatId,
    'text': text,
  };
}

final class StationStripView extends ViewValue {
  const StationStripView({
    required this.chips,
    required this.vehiclePermille,
    required this.countdownMs,
    required this.warning,
  });

  final List<StationChip> chips;

  /// The vehicle's place along the strip, 0–1000; station i sits at
  /// (i + 1) × 1000 ÷ the number of stations.
  final int vehiclePermille;

  /// Until the next station, or null after the last.
  final int? countdownMs;
  final bool warning;

  @override
  Map<String, Object?> get fields => {
    'chips': chips,
    'vehiclePermille': vehiclePermille,
    'countdownMs': countdownMs,
    'warning': warning,
  };
}

final class StationChip extends ViewValue {
  const StationChip({
    required this.stationId,
    required this.slot,
    required this.name,
    required this.farePiasters,
    required this.basePiasters,
    required this.atMs,
    required this.studentIcon,
    required this.reached,
    required this.next,
  });

  final String stationId;

  /// 0–3: the station's color and letter.
  final int slot;
  final String? name;

  /// The fare to this station, with any fare increase.
  final int farePiasters;

  /// The fare before any increase: the strip strikes it through when
  /// [farePiasters] is higher.
  final int basePiasters;

  /// When the vehicle reaches it, shifted by any traffic jam: the strip
  /// places it at `atMs / the last station's atMs`.
  final int atMs;
  final bool studentIcon;
  final bool reached;
  final bool next;

  @override
  Map<String, Object?> get fields => {
    'stationId': stationId,
    'slot': slot,
    'name': name,
    'farePiasters': farePiasters,
    'basePiasters': basePiasters,
    'atMs': atMs,
    'studentIcon': studentIcon,
    'reached': reached,
    'next': next,
  };
}

/// Where a passenger is in the scene.
enum PresenceView { boarding, aboard, leaving, gone }

/// What the ledger peek shows over a passenger: they paid, not yet, or
/// their group's payer paid for them.
enum LedgerBadge { paid, unpaid, onFriend }

final class PassengerView extends ViewValue {
  const PassengerView({
    required this.passengerId,
    required this.seatId,
    required this.presence,
    required this.look,
    required this.slot,
    required this.mood,
    required this.talking,
    required this.asleep,
    required this.waking,
    required this.headphones,
    required this.attentive,
    required this.nearStopPulse,
    required this.dropMeHere,
    required this.ledgerBadge,
    required this.outcome,
    this.claimOpen = false,
  });

  final String passengerId;
  final String seatId;
  final PresenceView presence;
  final Look look;

  /// The destination's slot (color and letter), or null when it isn't on
  /// the schedule.
  final int? slot;

  /// 0 calm, 1 impatient, 2 frowning, 3 angry.
  final int mood;
  final bool talking;
  final bool asleep;
  final bool waking;
  final bool headphones;
  final bool attentive;

  /// Their station is next and they are still owed (the last warning).
  final bool nearStopPulse;

  /// They asked to get off here: the patch is the pulsing «هنا» star.
  final bool dropMeHere;

  /// Only during a ledger peek.
  final LedgerBadge? ledgerBadge;

  /// While leaving.
  final AlightOutcome? outcome;

  /// Their «أنا دافع!» waits for an answer (008.5): the pose's `claim`.
  final bool claimOpen;

  @override
  Map<String, Object?> get fields => {
    'passengerId': passengerId,
    'seatId': seatId,
    'presence': presence,
    'look': look,
    'slot': slot,
    'mood': mood,
    'talking': talking,
    'asleep': asleep,
    'waking': waking,
    'headphones': headphones,
    'attentive': attentive,
    'nearStopPulse': nearStopPulse,
    'dropMeHere': dropMeHere,
    'ledgerBadge': ledgerBadge,
    'outcome': outcome,
    'claimOpen': claimOpen,
  };
}

/// A token's color: a fare on its way to the driver, or change on its way
/// back. Every kind but a fare shows as change.
enum TokenTint { fare, change }

final class TokenView extends ViewValue {
  const TokenView({
    required this.tokenId,
    required this.kind,
    required this.amountPiasters,
    required this.from,
    required this.to,
    required this.progressPermille,
    required this.hopMs,
    required this.blocked,
    required this.dropped,
    required this.atHolder,
  });

  final int tokenId;
  final TokenTint kind;
  final int amountPiasters;

  /// The seat it is at or leaving; null for the driver.
  final String? from;

  /// The seat it is hopping to (null for the driver); [from] when resting.
  final String? to;

  /// Along the current hop, 0–1000.
  final int progressPermille;

  /// The current hop's length, for smooth movement between steps; 0 at rest.
  final int hopMs;

  /// A sleeper or a muted passenger holds it up: orange with «؟».
  final bool blocked;
  final bool dropped;

  /// Resting with its holder, not hopping.
  final bool atHolder;

  @override
  Map<String, Object?> get fields => {
    'tokenId': tokenId,
    'kind': kind,
    'amountPiasters': amountPiasters,
    'from': from,
    'to': to,
    'progressPermille': progressPermille,
    'hopMs': hopMs,
    'blocked': blocked,
    'dropped': dropped,
    'atHolder': atHolder,
  };
}

/// Money on the floor after a bump, until [untilMs]. It fell where it was:
/// between [from] and [to] at [progressPermille].
final class DroppedMoneyView extends ViewValue {
  const DroppedMoneyView({
    required this.tokenId,
    required this.amountPiasters,
    required this.from,
    required this.to,
    required this.progressPermille,
    required this.untilMs,
  });

  final int tokenId;
  final int amountPiasters;
  final String? from;
  final String? to;
  final int progressPermille;
  final int untilMs;

  @override
  Map<String, Object?> get fields => {
    'tokenId': tokenId,
    'amountPiasters': amountPiasters,
    'from': from,
    'to': to,
    'progressPermille': progressPermille,
    'untilMs': untilMs,
  };
}

/// The street in the windows: stopped cars in traffic, rushing on the open
/// road.
enum Road { normal, traffic, open }

final class WindowsView extends ViewValue {
  const WindowsView({required this.road, required this.waveAtMs});

  static const normal = WindowsView(road: Road.normal, waveAtMs: null);

  final Road road;

  /// Someone waving from the roadside since then, or null.
  final int? waveAtMs;

  @override
  Map<String, Object?> get fields => {'road': road, 'waveAtMs': waveAtMs};
}

final class HandView extends ViewValue {
  const HandView({required this.pieces, required this.totalPiasters});

  /// Denomination → count.
  final Map<int, int> pieces;
  final int totalPiasters;

  bool get isEmpty => pieces.isEmpty;

  @override
  Map<String, Object?> get fields => {
    'pieces': pieces,
    'totalPiasters': totalPiasters,
  };
}

final class TraySlotView extends ViewValue {
  const TraySlotView({
    required this.denomination,
    required this.count,
    required this.breakable,
  });

  final int denomination;
  final int count;

  /// Glows in break mode.
  final bool breakable;

  @override
  Map<String, Object?> get fields => {
    'denomination': denomination,
    'count': count,
    'breakable': breakable,
  };
}

final class BreakButtonView extends ViewValue {
  const BreakButtonView({required this.left, required this.enabled});

  final int left;
  final bool enabled;

  @override
  Map<String, Object?> get fields => {'left': left, 'enabled': enabled};
}

final class BoosterSlotView extends ViewValue {
  const BoosterSlotView({
    required this.booster,
    required this.count,
    required this.priceBonat,
    required this.enabled,
    required this.adOffered,
    this.activeUntilMs,
  });

  final BoosterId booster;
  final int count;

  /// The catalog price, shown when none is left.
  final int? priceBonat;
  final bool enabled;

  /// Always false until M11.
  final bool adOffered;

  /// While the booster works, when it stops: the ledger peek's end.
  final int? activeUntilMs;

  @override
  Map<String, Object?> get fields => {
    'booster': booster,
    'count': count,
    'priceBonat': priceBonat,
    'enabled': enabled,
    'adOffered': adOffered,
    'activeUntilMs': activeUntilMs,
  };
}

/// A question the scene asks next to a passenger.
sealed class ChoiceView extends ViewValue {
  const ChoiceView();
}

/// «دفعت!»: insist or give in.
final class ClaimChoice extends ChoiceView {
  const ClaimChoice({required this.passengerId});

  final String passengerId;

  @override
  Map<String, Object?> get fields => {'passengerId': passengerId};
}

/// «فكّله» or «معلش».
final class ChangeRequestChoice extends ChoiceView {
  const ChangeRequestChoice({
    required this.passengerId,
    required this.notePiasters,
  });

  final String passengerId;
  final int notePiasters;

  @override
  Map<String, Object?> get fields => {
    'passengerId': passengerId,
    'notePiasters': notePiasters,
  };
}

/// «مين اللي دفع؟» between two faces.
final class DisputeChoice extends ChoiceView {
  const DisputeChoice({
    required this.disputeId,
    required this.a,
    required this.b,
  });

  final int disputeId;
  final String a;
  final String b;

  @override
  Map<String, Object?> get fields => {'disputeId': disputeId, 'a': a, 'b': b};
}

/// A bubble's look (trip-view.md "Speech and bubbles").
enum BubbleStyle { plain, warning, fight, thanks }

final class BubbleView extends ViewValue {
  const BubbleView({
    required this.passengerId,
    required this.text,
    required this.style,
    required this.shownAtMs,
  });

  final String passengerId;
  final String text;
  final BubbleStyle style;
  final int shownAtMs;

  @override
  Map<String, Object?> get fields => {
    'passengerId': passengerId,
    'text': text,
    'style': style,
    'shownAtMs': shownAtMs,
  };
}

/// Who said or sent something: the look's label, with the station's slot
/// when two passengers aboard share the label.
final class SpeakerLabel extends ViewValue {
  const SpeakerLabel({required this.labelKey, this.slot});

  final String labelKey;
  final int? slot;

  @override
  Map<String, Object?> get fields => {'labelKey': labelKey, 'slot': slot};
}

/// What a «آخر كلام» line says (trip-view.md "«آخر كلام»").
enum LogKind { speech, fareArrived, breakDone, dropped, lost, fareUp }

/// A «آخر كلام» line. A passenger's line carries its resolved [text]; a
/// money line carries its amount, and the screen words it.
final class LogLine extends ViewValue {
  const LogLine({
    required this.kind,
    this.speaker,
    this.text,
    this.amountPiasters,
  });

  final LogKind kind;
  final SpeakerLabel? speaker;
  final String? text;
  final int? amountPiasters;

  @override
  Map<String, Object?> get fields => {
    'kind': kind,
    'speaker': speaker,
    'text': text,
    'amountPiasters': amountPiasters,
  };
}

/// بلية's hint: an ARB key, pointing at a passenger or at nobody.
final class HintView extends ViewValue {
  const HintView({required this.key, required this.targetPassengerId});

  final String key;
  final String? targetPassengerId;

  @override
  Map<String, Object?> get fields => {
    'key': key,
    'targetPassengerId': targetPassengerId,
  };
}

/// The fare-increase banner, from [shownAtMs].
final class BannerView extends ViewValue {
  const BannerView({
    required this.oldPiasters,
    required this.newPiasters,
    required this.shownAtMs,
  });

  final int oldPiasters;
  final int newPiasters;
  final int shownAtMs;

  @override
  Map<String, Object?> get fields => {
    'oldPiasters': oldPiasters,
    'newPiasters': newPiasters,
    'shownAtMs': shownAtMs,
  };
}

/// One reason the trip failed, and how many times it happened when the
/// engine counts it.
final class FailCause extends ViewValue {
  const FailCause({required this.cause, required this.count});

  final RepCause cause;
  final int? count;

  @override
  Map<String, Object?> get fields => {'cause': cause, 'count': count};
}

final class ReviveOffer extends ViewValue {
  const ReviveOffer({required this.priceBonat, required this.affordable});

  final int priceBonat;
  final bool affordable;

  @override
  Map<String, Object?> get fields => {
    'priceBonat': priceBonat,
    'affordable': affordable,
  };
}

final class FailSummary extends ViewValue {
  const FailSummary({
    required this.causes,
    required this.revive,
    this.brokeStoryRule = false,
    this.failReason,
    this.angryFaces = const [],
  });

  /// The top two, by reputation lost.
  final List<FailCause> causes;

  /// Null when no revive is offered.
  final ReviveOffer? revive;

  /// A story trip lost to a fight under `no_fights_required`.
  final bool brokeStoryRule;

  /// The chapter's own line for that failure (`story_trip_info.fail_reason`),
  /// which the card says in place of M02's rule line. Null without one.
  final String? failReason;

  /// Up to three passengers the card draws angry (008.5 `Fail`): those who
  /// fought, then those who missed their stop, then those still seated.
  final List<String> angryFaces;

  @override
  Map<String, Object?> get fields => {
    'causes': causes,
    'revive': revive,
    'brokeStoryRule': brokeStoryRule,
    'failReason': failReason,
    'angryFaces': angryFaces,
  };
}

/// A rejection shown in the log's place until [untilMs].
final class RejectionLine extends ViewValue {
  const RejectionLine({required this.code, required this.untilMs});

  final RejectionCode code;
  final int untilMs;

  @override
  Map<String, Object?> get fields => {'code': code, 'untilMs': untilMs};
}
