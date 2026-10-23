// Internal builds' debug panel (research R21): the top bar's icon opens it
// and pauses the trip. It shows the trip id, revision, seed, the engine's
// clock and status, reputation and counters, and copies the replay
// record's JSON to the clipboard. Values are identifiers, read left to
// right.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class DebugPanel extends StatefulWidget {
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

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
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
        const SizedBox(height: SpaceTokens.m),
        PrimaryButton(
          key: DebugPanel.copyKey,
          label: l10n.tripDebugCopy,
          onPressed: () => unawaited(_copy()),
        ),
        if (_copied) CardNote(l10n.tripDebugCopied),
        const SizedBox(height: SpaceTokens.m),
        SecondaryButton(
          key: DebugPanel.closeKey,
          label: l10n.tripDebugClose,
          onPressed: widget.onClose,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ink = context.tokens.hibr;
    return Padding(
      padding: const EdgeInsets.only(bottom: SpaceTokens.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TypeTokens.label.copyWith(color: ink)),
          const SizedBox(width: SpaceTokens.s),
          Expanded(
            child: Text(
              value,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.end,
              style: TypeTokens.caption.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
