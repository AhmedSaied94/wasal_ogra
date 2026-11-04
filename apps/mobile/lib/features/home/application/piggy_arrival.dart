// The late piggy reward, an arrival item (specs/018-m11-ads, research R14,
// contracts/seams.md "`PiggyArrival`"): a grant the server made while the
// phone wasn't asking (bootstrap's `ads.unseen`) opens the reward dialog on
// arrival at Home, the newest first and one per arrival. Closing it records
// `ad_reward_seen`, so it never shows twice, even before that op syncs.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/sync/domain/wire/bootstrap.dart';
import 'package:wassal/core/sync/sync_providers.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/features/home/application/arrival_queue.dart';
import 'package:wassal/features/home/presentation/piggy_cards.dart';

part 'piggy_arrival.g.dart';

/// The cached bootstrap's unseen grants the phone hasn't recorded as seen,
/// the newest first. Read again when the block changes or one is seen.
@Riverpod(keepAlive: true)
Future<List<PiggyGrant>> unseenPiggies(Ref ref) async {
  final unseen = ref.watch(adsBlockProvider)?.unseen ?? const [];
  if (unseen.isEmpty) return const [];
  final economy = await ref.watch(economyProvider.future);
  final left = [
    for (final grant in unseen)
      if (!await economy.adRewardSeen(grant.nonce)) grant,
  ]..sort((a, b) => b.grantedAtMs.compareTo(a.grantedAtMs));
  return left;
}

/// Rank 40, after the due scene and the name sheet.
final class PiggyArrival implements ArrivalItem {
  const PiggyArrival();

  @override
  int get rank => 40;

  /// Not due until the log has been read (the first arrival starts it).
  @override
  bool isDue(ProviderContainer container) =>
      container.read(unseenPiggiesProvider).value?.isNotEmpty ?? false;

  @override
  Future<void> open(BuildContext context, ProviderContainer container) async {
    final grant = container.read(unseenPiggiesProvider).value?.firstOrNull;
    if (grant == null) return;
    await showAppDialog<void>(
      context: context,
      builder: (_) =>
          PiggyArrivedDialog(jenehat: grant.jenehat, bonat: grant.bonat),
    );
    // However it closed, it was shown.
    final economy = container.read(economyProvider).requireValue;
    await economy.markAdRewardSeen(economy.newRequestId(), nonce: grant.nonce);
    container.invalidate(unseenPiggiesProvider);
  }
}
