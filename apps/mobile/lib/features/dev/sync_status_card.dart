// Internal builds' sync card (specs/011-m06-identity-sync, US6): where the
// account and the queue stand, and «sync now». Labels and values are
// identifiers, as the trip's debug panel's; no token or install id is ever
// shown. It sits below Home's links, so they stay where they were. Prod
// never builds it (router.dart).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/sync/sync_engine.dart';
import 'package:wassal/core/sync/sync_providers.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

class SyncStatusCard extends ConsumerStatefulWidget {
  const SyncStatusCard({super.key});

  static const syncNowKey = ValueKey('sync-status-now');

  /// The visible part of a player id.
  static const playerIdShown = 8;

  @override
  ConsumerState<SyncStatusCard> createState() => _SyncStatusCardState();
}

class _SyncStatusCardState extends ConsumerState<SyncStatusCard> {
  StreamSubscription<Object?>? _events;
  StreamSubscription<Object?>? _pending;

  @override
  void initState() {
    super.initState();
    // Every pass and every operation recorded redraws it.
    ref
      ..listenManual(syncEngineProvider, (_, next) {
        unawaited(_events?.cancel());
        _events = next.value?.events.listen((_) => _redraw());
      }, fireImmediately: true)
      ..listenManual(economyProvider, (_, next) {
        unawaited(_pending?.cancel());
        _pending = next.value?.pendingCounts.listen((_) => _redraw());
      }, fireImmediately: true);
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_pending?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountStatusProvider);
    final engine = ref.watch(syncEngineProvider).value;
    final economy = ref.watch(economyProvider).value;
    final account = ref.watch(accountServiceProvider).value;
    if (engine == null || economy == null || account == null) {
      return const SizedBox.shrink();
    }
    final sync = engine.snapshot;
    final player = account.playerId;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s8,
        children: [
          Text(
            // Developer text, as the playtest tools'.
            'sync',
            textDirection: TextDirection.ltr,
            style: TypeTokens.displayS.copyWith(color: ColorTokens.ink),
          ),
          for (final (label, value) in [
            ('account', account.status.name),
            (
              'player_id',
              player == null
                  ? _none
                  : '${player.substring(0, SyncStatusCard.playerIdShown)}…',
            ),
            ('providers', account.profile?.providers.join(', ') ?? _none),
            ('pending', '${economy.pendingCount}'),
            ('state_version', '${economy.baseInfo.stateVersion ?? _none}'),
            ('last_pass', _outcome(sync.lastOutcome)),
            (
              'pass_ms',
              sync.lastDurationMs == null ? _none : '${sync.lastDurationMs}',
            ),
            (
              'ended_at',
              switch (sync.lastEndedAtMs) {
                null => _none,
                final ms => 'uptime ${(ms / 1000).toStringAsFixed(1)} s',
              },
            ),
            ('last_error', sync.lastError ?? _none),
            ('set_aside', '${sync.setAsideSinceLaunch} (this launch)'),
            if (sync.heldUntilLaunch) ('held', 'until the next launch'),
          ])
            _Row(label: label, value: value),
          AppButton.secondary(
            key: SyncStatusCard.syncNowKey,
            label: 'sync now',
            size: AppButtonSize.compact,
            onTap: () => unawaited(engine.syncNow()),
          ),
        ],
      ),
    );
  }

  /// No value yet: a word, which the contrast check can measure.
  static const _none = 'none';

  static String _outcome(PassOutcome? outcome) => switch (outcome) {
    null => _none,
    PassIdle() => 'idle',
    // Set-asides have their own row.
    PassDone(:final batches, :final accepted, :final rejected) =>
      'done: $batches batches, $accepted accepted, $rejected rejected',
    PassHeld(:final reason) => 'held: ${reason.name}',
    PassFailed(:final code) => 'failed: $code',
  };
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    textDirection: TextDirection.ltr,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: SpaceTokens.s8,
    children: [
      Text(
        label,
        textDirection: TextDirection.ltr,
        style: TypeTokens.label.copyWith(color: ColorTokens.ink2),
      ),
      Expanded(
        child: Text(
          value,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.end,
          style: TypeTokens.caption.copyWith(color: ColorTokens.ink),
        ),
      ),
    ],
  );
}
