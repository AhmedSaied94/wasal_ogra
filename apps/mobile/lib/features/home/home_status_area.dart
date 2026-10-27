// Home's server states (specs/011-m06-identity-sync, contracts/
// server-states.md "Placements", research R17, R19): the offline banner or
// the maintenance card above Home's content, and nothing otherwise.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// A column above Home's [child]: [OfflineBanner] while offline, else
/// [StatusCard.maintenance] during maintenance, with no height of its own
/// otherwise. Offline wins (HANDOFF `States` "Several states at once").
/// M08 puts it on the real Home.
class HomeStatusArea extends ConsumerWidget {
  const HomeStatusArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final card = switch (ref.watch(serverStatusProvider)) {
      ServerStatusState(reach: Reach.offline) => OfflineBanner(
        message: l10n.homeOffline,
      ),
      ServerStatusState(:final maintenance?) => _MaintenanceCard(maintenance),
      _ => null,
    };
    return ColoredBox(
      color: ColorTokens.ground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (card != null)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  LayoutTokens.gutter,
                  SpaceTokens.s8,
                  LayoutTokens.gutter,
                  0,
                ),
                child: card,
              ),
            ),
          // The last child either way, so Home keeps its state when a card
          // comes or goes.
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: card != null,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// `States` box 31: the clock, the title, and when it ends, as the device's
/// local time in the player's digits.
class _MaintenanceCard extends ConsumerWidget {
  const _MaintenanceCard(this.maintenance);

  final Maintenance maintenance;

  static const double _picture = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final message = switch (maintenance.untilMs) {
      final untilMs? => l10n.maintenanceMessageAt(
        _clock(ref.watch(numberFormatterProvider), untilMs),
      ),
      null => l10n.maintenanceMessage,
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: StatusCard.maintenance(
        title: l10n.maintenanceTitle,
        message: message,
        picture: const AppIcon('clock', size: _picture, color: ColorTokens.sun),
      ),
    );
  }

  static String _clock(NumberFormatter numbers, int ms) {
    final local = DateTime.fromMillisecondsSinceEpoch(ms);
    return numbers.clockTime(local.hour, local.minute);
  }
}
