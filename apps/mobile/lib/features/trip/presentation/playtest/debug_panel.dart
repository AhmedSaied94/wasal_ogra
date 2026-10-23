// Internal builds' debug panel (research R21): the top bar's icon opens it
// and pauses the trip. It shows the trip id, revision, seed, the engine's
// clock and status, reputation and counters, and copies the replay
// record's JSON to the clipboard. Since 008.5 it also switches which seats
// Rive draws, for the session, and lists what the Rive file's contract
// check found (research R18). Values are identifiers, read left to right.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/application/art_tier.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class DebugPanel extends ConsumerStatefulWidget {
  const DebugPanel({
    required this.state,
    required this.record,
    required this.onClose,
    super.key,
  });

  final TripState state;
  final ReplayRecord record;
  final VoidCallback onClose;

  static const copyKey = ValueKey('trip-debug-copy');
  static const closeKey = ValueKey('trip-debug-close');
  static Key tierKey(ArtTier tier) => ValueKey('trip-debug-tier-${tier.name}');

  @override
  ConsumerState<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends ConsumerState<DebugPanel> {
  var _copied = false;

  Future<void> _copy() async {
    final record = jsonEncode(widget.record.toJson());
    await Clipboard.setData(ClipboardData(text: record));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    final definition = widget.record.definition;
    final problems = ref.watch(riveArtProvider).value?.problems ?? const [];
    return TripCard(
      title: l10n.tripDebugTitle,
      children: [
        for (final (label, value) in [
          (l10n.tripDebugTrip, definition.tripId),
          (l10n.tripDebugRev, '${definition.rev}'),
          (l10n.tripDebugSeed, '${widget.record.seed}'),
          (l10n.tripDebugClock, '${state.tMs} ms'),
          (l10n.tripDebugStatus, state.status.wire),
          (l10n.tripDebugReputation, '${state.reputation}'),
          (l10n.tripDebugCounters, jsonEncode(state.counters.toJson())),
        ])
          _Row(label: label, value: value),
        _Label(l10n.tripDebugArtTier),
        Segmented<ArtTier>(
          value: ref.watch(artTierSettingProvider),
          segments: [for (final tier in ArtTier.values) (tier, _wire(tier))],
          onChanged: ref.read(artTierSettingProvider.notifier).select,
          segmentKey: DebugPanel.tierKey,
        ),
        _Row(
          label: l10n.tripDebugArtProblems,
          value: problems.isEmpty ? l10n.tripDebugArtFine : problems.join('\n'),
        ),
        AppButton.primary(
          key: DebugPanel.copyKey,
          label: l10n.tripDebugCopy,
          size: AppButtonSize.l,
          onTap: () => unawaited(_copy()),
        ),
        if (_copied) CardNote(l10n.tripDebugCopied),
        AppButton.secondary(
          key: DebugPanel.closeKey,
          label: l10n.tripDebugClose,
          onTap: widget.onClose,
        ),
      ],
    );
  }

  /// The tier as research R18 names it.
  static String _wire(ArtTier tier) => switch (tier) {
    ArtTier.rive => 'rive',
    ArtTier.nearRive => 'near_rive',
    ArtTier.static => 'static',
  };
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TypeTokens.label.copyWith(color: ColorTokens.ink2));
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: SpaceTokens.s8,
    children: [
      _Label(label),
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
