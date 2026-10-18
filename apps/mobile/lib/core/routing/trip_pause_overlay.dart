import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/components/sticker_card.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Shows the trip pause (ux-spec «نافذة الإيقاف») over the trip. It has no
/// URL; phone back closes it (FR-020).
Future<void> showTripPause(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  barrierColor: context.tokens.hibr.withValues(alpha: 0.6),
  builder: (_) => const TripPauseOverlay(),
);

class TripPauseOverlay extends StatelessWidget {
  const TripPauseOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SpaceTokens.l),
          child: StickerCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.pauseTitle,
                    textAlign: TextAlign.center,
                    style: TypeTokens.headline.copyWith(
                      color: context.tokens.hibr,
                    ),
                  ),
                ),
                const SizedBox(height: SpaceTokens.l),
                PrimaryButton(
                  label: l10n.pauseResume,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: SpaceTokens.m),
                SecondaryButton(
                  label: l10n.pauseHome,
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.go('/home');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Back on the trip never leaves it; it opens the pause (FR-020).
class TripBackGuard extends StatelessWidget {
  const TripBackGuard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(showTripPause(context));
      },
      child: child,
    );
  }
}
