// The failure (ux-spec «فشل المشوار», FR-039, FR-040; 008.5 `Fail`,
// research R13): up to three angry faces, «المشوار باظ», a chip of what lost
// the reputation (a broken story rule first), the BONAT revive and its
// once-a-trip line when the rules offer one (faded, with what is missing,
// when short), then «عيد المشوار» with its liter and «ارجع الموقف». Above
// the revive, the room the rewarded-ad revive takes in M11 stays empty. A
// revive whose save failed says so here, and the next tap sends the same
// request. Back and the scrim do nothing.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/dispute_card.dart';
import 'package:wassal/features/trip/presentation/cards/restart_button.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/presentation/trip_text.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class FailureCard extends ConsumerWidget {
  const FailureCard({
    required this.summary,
    required this.retry,
    required this.restartEnabled,
    required this.onRevive,
    required this.onRestart,
    required this.onHome,
    super.key,
  });

  final FailSummary summary;

  /// A revive that failed to save, or null.
  final TripRetry? retry;
  final bool restartEnabled;
  final VoidCallback onRevive;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  static const facesKey = ValueKey('trip-fail-faces');
  static const reasonKey = ValueKey('trip-fail-reason');
  static const adSlotKey = ValueKey('trip-fail-ad-slot');
  static const reviveKey = ValueKey('trip-fail-revive');
  static const onceKey = ValueKey('trip-fail-once');
  static const restartKey = ValueKey('trip-fail-restart');
  static const homeKey = ValueKey('trip-fail-home');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final causes = l10n.failCauses(summary, numbers);
    final reasons = [
      // The chapter's own line replaces M02's (M10, story-trip.md).
      if (summary.brokeStoryRule) summary.failReason ?? l10n.tripFailStoryRule,
      if (causes.isNotEmpty) causes,
    ];
    final revive = summary.revive;
    return TripCard(
      title: l10n.tripFailTitle,
      titleStyle: DesignExtras.failTitle,
      art: _AngryFaces(key: facesKey, ids: summary.angryFaces),
      scrim: ColorTokens.scrimFail,
      designTop: DesignExtras.failTop,
      padding: DesignExtras.failPadding,
      children: [
        if (reasons.isNotEmpty)
          Center(
            child: _Reason(key: reasonKey, lines: reasons),
          ),
        if (retry case final retry?) CardText(l10n.retryMessage(retry)),
        if (revive != null) ...[
          // M11's rewarded-ad revive goes here.
          const SizedBox(key: adSlotKey, height: DesignExtras.rewardedHeight),
          AppButton.secondary(
            key: reviveKey,
            label: l10n.tripFailRevive(numbers.integer(revive.priceBonat)),
            onTap: onRevive,
            enabled: revive.affordable,
            leading: const AppIcon('bonat', size: _reviveIcon),
            height: LayoutTokens.buttonH.first,
            radius: DesignExtras.dialogSecondaryRadius,
            labelStyle: DesignExtras.dialogSecondaryLabel,
          ),
          if (!revive.affordable)
            CardNote(switch (math.max(
              1,
              revive.priceBonat - ref.watch(economyViewProvider).bonat,
            )) {
              final missing => l10n.tripBoosterShort(
                missing,
                numbers.integer(missing),
              ),
            }),
          CardNote(l10n.tripReviveOnce, key: onceKey),
        ],
        CardRow(
          children: [
            RestartButton(
              buttonKey: restartKey,
              enabled: restartEnabled,
              onRestart: onRestart,
              tile: true,
            ),
            CardTile(
              key: homeKey,
              label: l10n.pauseHome,
              onTap: onHome,
              height: DesignExtras.failTileHeight,
              radius: DesignExtras.failTileRadius,
            ),
          ],
        ),
      ],
    );
  }

  /// `Fail` box 17: the BONAT icon beside the revive's label.
  static const _reviveIcon = 22.0;
}

/// `Fail` box 11: what lost the reputation, on a `danger.soft` pill.
class _Reason extends StatelessWidget {
  const _Reason({required this.lines, super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: ColorTokens.dangerSoft,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
    ),
    child: Padding(
      padding: DesignExtras.failReasonPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lines)
            Text(
              line,
              textAlign: TextAlign.center,
              style: DesignExtras.failReason.copyWith(color: ColorTokens.ink),
            ),
        ],
      ),
    ),
  );
}

/// `Fail` box 9: the first angry face in the middle, bigger; the second at
/// the start side, the third at the end. Each is the passenger's head as
/// the scene draws it now (the trip failed, so they frown), cut a little
/// wider than the face, for hair and hats, as a tilted head is.
class _AngryFaces extends StatelessWidget {
  const _AngryFaces({required this.ids, super.key});

  final List<String> ids;

  /// The cut's radius over the head's.
  static const _cut = (rigHeadRadius + 8) / rigHeadRadius;

  @override
  Widget build(BuildContext context) => TripSelector<List<PassengerView>>(
    select: (model) => [for (final id in ids) ?model.view?.passenger(id)],
    equals: listEquals,
    builder: (context, faces) {
      if (faces.isEmpty) return const SizedBox.shrink();
      final start = Directionality.of(context) == TextDirection.rtl ? 1 : -1;
      final middle = DesignExtras.failFaces.width / 2;
      Widget face(PassengerView p, Offset centre, double radius) {
        final cut = radius * _cut;
        return Positioned(
          left: centre.dx - cut,
          top: centre.dy - cut,
          width: 2 * cut,
          height: 2 * cut,
          child: ClipOval(
            child: Padding(
              padding: EdgeInsets.all(cut - radius),
              child: PassengerPortrait(passenger: p),
            ),
          ),
        );
      }

      Widget side(PassengerView p, int towards) => face(
        p,
        Offset(
          middle + towards * DesignExtras.failFaceSideX,
          DesignExtras.failFaceSideY,
        ),
        DesignExtras.failFaceSide,
      );

      return SizedBox.fromSize(
        size: DesignExtras.failFaces,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (faces.length > 2) side(faces[2], -start),
            if (faces.length > 1) side(faces[1], start),
            face(
              faces[0],
              Offset(middle, DesignExtras.failFaceMiddleY),
              DesignExtras.failFaceMiddle,
            ),
          ],
        ),
      );
    },
  );
}
