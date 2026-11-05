// The morning piggy (specs/018-m11-ads, research R12, FR-015–FR-019): the
// ad with server-side verification, then up to three asks for the server's
// grant, then the outcome the banner shows. The phone never grants it:
// the server's callback does, and the requested sync pass brings the
// wallet (constitution IV).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:wassal/core/ads/ads_gateway.dart';
import 'package:wassal/core/ads/ads_service.dart';
import 'package:wassal/core/ads/domain/piggy_plan.dart';
import 'package:wassal/core/ads/piggy_api.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/sync/domain/pass.dart' show SyncTrigger;

/// What the banner shows once the asking ends.
sealed class PiggyOutcome {
  const PiggyOutcome();
}

/// The grant arrived: the `PiggyArrived` card, with its amounts.
final class PiggyArrivedNow extends PiggyOutcome {
  const PiggyArrivedNow({
    required this.nonce,
    required this.jenehat,
    required this.bonat,
  });

  final String nonce;
  final int jenehat;
  final int bonat;
}

/// The server refused it: today's piggy is used (`PiggyUsed`).
final class PiggyUsedToday extends PiggyOutcome {
  const PiggyUsedToday();
}

/// No answer in 7 s: it comes later, through bootstrap's `unseen`
/// (`PiggyLater`).
final class PiggyComesLater extends PiggyOutcome {
  const PiggyComesLater();
}

/// The custom data the server's callback reads: compact, in this key order
/// (research R12).
String piggyCustomData(String nonce) =>
    jsonEncode({'placement': AdPlacement.morningPiggy.wire, 'nonce': nonce});

final class PiggyService {
  PiggyService({
    required this._ads,
    required this._api,
    required this._economy,
    required this._playerId,
    required this._requestSync,
    Future<void> Function(Duration wait)? wait,
    String Function()? newNonce,
  }) : _wait = wait ?? Future<void>.delayed,
       _newNonce = newNonce ?? _uuid4;

  final AdsService _ads;
  final PiggyApi _api;
  final Economy _economy;
  final String? Function() _playerId;
  final void Function(SyncTrigger trigger) _requestSync;
  final Future<void> Function(Duration wait) _wait;
  final String Function() _newNonce;

  static String _uuid4() => const Uuid().v4();

  final _asking = ValueNotifier(false);
  final _lastNonce = ValueNotifier<String?>(null);
  final _outcomes = StreamController<PiggyOutcome>.broadcast();
  Future<PiggyOutcome?>? _running;

  /// True from the reward until the asking ends (the chip's wheel).
  ValueListenable<bool> get asking => _asking;

  /// The last watch's reference, for the debug panel's `ads_dev_callback`
  /// line (T032).
  ValueListenable<String?> get lastNonce => _lastNonce;

  /// Each outcome, for the card the banner opens.
  Stream<PiggyOutcome> get outcomes => _outcomes.stream;

  /// The banner's tap. Null when nothing was earned (the ad closed early,
  /// it wasn't offered, or there is no player yet): the banner stays.
  Future<PiggyOutcome?> watch() => _running ??= _watch().whenComplete(() {
    _running = null;
  });

  Future<PiggyOutcome?> _watch() async {
    final player = _playerId();
    if (player == null) return null;
    await _ads.ensureReady();
    if (_ads.offer(AdPlacement.morningPiggy) is! Offered) return null;
    final nonce = _newNonce();
    _lastNonce.value = nonce;
    final earned = await _ads.showRewarded(
      AdPlacement.morningPiggy,
      verification: PiggyVerification(
        userId: player,
        customData: piggyCustomData(nonce),
      ),
    );
    if (!earned) return null;
    // Whatever the server answers, the banner hides for the game day.
    _ads.markPiggyAttempted();
    _asking.value = true;
    final PiggyOutcome outcome;
    try {
      outcome = await _ask(nonce);
    } finally {
      _asking.value = false;
    }
    // A failed ask marks the app offline, and only a finished pass clears it.
    if (outcome is PiggyComesLater) _requestSync(SyncTrigger.adReward);
    if (!_outcomes.isClosed) _outcomes.add(outcome);
    return outcome;
  }

  Future<PiggyOutcome> _ask(String nonce) async {
    for (final (i, waitMs) in piggyWaitsMs.indexed) {
      await _wait(Duration(milliseconds: waitMs));
      switch (await _api.lookup(nonce)) {
        case PiggyGranted(:final jenehat, :final bonat):
          await _seen(nonce);
          _requestSync(SyncTrigger.adReward);
          return PiggyArrivedNow(nonce: nonce, jenehat: jenehat, bonat: bonat);
        case PiggyRefused():
          await _seen(nonce);
          return const PiggyUsedToday();
        case PiggyNotYet():
          if (piggyStep(PiggyAnswer.notYet, ask: i + 1) == PiggyStep.gaveUp) {
            return const PiggyComesLater();
          }
      }
    }
    return const PiggyComesLater();
  }

  /// So the late-reward card never shows it (research R13).
  Future<void> _seen(String nonce) async {
    await _economy.markAdRewardSeen(_economy.newRequestId(), nonce: nonce);
  }

  void dispose() {
    _asking.dispose();
    _lastNonce.dispose();
    unawaited(_outcomes.close());
  }
}
