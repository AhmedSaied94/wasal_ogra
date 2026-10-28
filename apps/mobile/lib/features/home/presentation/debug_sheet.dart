// The testers' tools on internal builds (specs/013-m08-home-result, US6,
// research R21): a debug button at the scene card's top-start corner,
// opening a sheet with every trip of the pack, the sync card, the first
// session's card and the components gallery. Prod builds neither.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/dev/gallery/gallery_entry.dart';
import 'package:wassal/features/dev/onboarding_card.dart';
import 'package:wassal/features/dev/sync_status_card.dart';
import 'package:wassal/features/trip/presentation/playtest/trip_list.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// M02's debug glyph, 44 pt, on Home's scene card.
class HomeDebugButton extends StatelessWidget {
  const HomeDebugButton({super.key});

  static const buttonKey = Key('HomeDebugButton');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconCircleButton(
      key: buttonKey,
      icon: 'tasks',
      semanticLabel: l10n.tripDebugOpen,
      onTap: () => unawaited(
        showAppSheet<void>(
          context: context,
          title: l10n.tripDebugOpen,
          builder: (_) => const HomeDebugSheet(),
        ),
      ),
    );
  }
}

/// The sheet's tools. Each trip opens `/trip/<id>` directly: no card, no
/// checkpoint.
class HomeDebugSheet extends StatelessWidget {
  const HomeDebugSheet({super.key});

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s16,
      children: [
        TripList(),
        SyncStatusCard(),
        OnboardingCard(),
        GalleryEntry(),
      ],
    ),
  );
}
