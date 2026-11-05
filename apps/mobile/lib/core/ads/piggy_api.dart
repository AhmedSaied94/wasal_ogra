// The morning piggy's lookup (specs/018-m11-ads, contracts/economy-ops.md
// "The piggy's lookup"; B07's `GET /v1/ads/rewards/{nonce}`): whether the
// server has Google's callback for this reference yet. Only the server
// grants the piggy's BONAT (constitution IV); the answer's `wallet` is read
// but not applied, since the requested sync pass rebases the wallet
// (research R12).
import 'package:wassal/core/account/authorized_api.dart';
import 'package:wassal/core/network/api_client.dart';

/// A lookup is one of three asks in 7 s, so it waits no longer than this.
const piggyLookupTimeout = Duration(seconds: 3);

sealed class PiggyLookup {
  const PiggyLookup();
}

/// The server granted the reward: its amounts, for the card.
final class PiggyGranted extends PiggyLookup {
  const PiggyGranted({required this.jenehat, required this.bonat});

  final int jenehat;
  final int bonat;

  @override
  bool operator ==(Object other) =>
      other is PiggyGranted && other.jenehat == jenehat && other.bonat == bonat;

  @override
  int get hashCode => Object.hash(jenehat, bonat);
}

/// The server refused it (`cap_reached`, `not_server_placement`,
/// `expired`): today's piggy is used.
final class PiggyRefused extends PiggyLookup {
  const PiggyRefused(this.reason);

  final String reason;

  @override
  bool operator ==(Object other) =>
      other is PiggyRefused && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// Not known yet (404), or no answer: ask again.
final class PiggyNotYet extends PiggyLookup {
  const PiggyNotYet();
}

final class PiggyApi {
  const PiggyApi(this._api);

  final AuthorizedApi _api;

  Future<PiggyLookup> lookup(String nonce) async {
    final result = await _api.send(
      ApiRequest.get(
        '/v1/ads/rewards/${Uri.encodeComponent(nonce)}',
        receiveTimeout: piggyLookupTimeout,
      ),
    );
    return switch (result) {
      ApiOk(:final json) => _read(json),
      // 404, 5xx, the network: not yet. 401, 426 and 503 went through
      // the session and server-state handling inside `send`.
      ApiFailure() || ApiUnreachable() => const PiggyNotYet(),
    };
  }

  static PiggyLookup _read(Map<String, Object?> json) =>
      switch ((json['status'], json['jenehat'], json['bonat'])) {
        ('granted', final int jenehat, final int bonat)
            when jenehat >= 0 && bonat >= 0 =>
          PiggyGranted(jenehat: jenehat, bonat: bonat),
        ('refused', _, _) => PiggyRefused(switch (json['reason']) {
          final String reason => reason,
          _ => '',
        }),
        _ => const PiggyNotYet(),
      };
}
