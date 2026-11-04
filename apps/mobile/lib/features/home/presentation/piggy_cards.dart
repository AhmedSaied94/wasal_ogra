// The morning piggy's reward dialog (specs/018-m11-ads, the owner's
// `PiggyArrived` board): the pig and its coins, «الحصّالة وصلت!», the
// amounts as two chips, and «تمام». It opens at once when the server
// granted the reward, and for a late reward on the next arrival at Home
// (`PiggyArrival`). The wallet's pills move when the sync pass rebases
// them. `PiggyUsed` and `PiggyLater` are toasts (`showAppToastOn`) led by
// `PiggyToastIcon`.
import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class PiggyArrivedDialog extends ConsumerStatefulWidget {
  const PiggyArrivedDialog({
    required this.jenehat,
    required this.bonat,
    super.key,
  });

  final int jenehat;
  final int bonat;

  static const okKey = ValueKey('piggy-arrived-ok');
  static const chipsKey = ValueKey('piggy-arrived-chips');
  static const art = 'assets/illustrations/screens/PiggyArrived_01.svg';
  static const artSize = Size(200, 128);
  static const double okHeight = 60;

  @override
  ConsumerState<PiggyArrivedDialog> createState() => _PiggyArrivedDialogState();
}

class _PiggyArrivedDialogState extends ConsumerState<PiggyArrivedDialog> {
  @override
  void initState() {
    super.initState();
    // Said once when the dialog opens (`PiggyArrived` box 18).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final numbers = ref.read(numberFormatterProvider);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(context).piggyArrivedA11y(
            numbers.integer(widget.jenehat),
            numbers.integer(widget.bonat),
          ),
          Directionality.of(context),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    return AppDialog(
      semanticLabel: l10n.piggyArrivedTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s12,
        children: [
          Center(
            child: ExcludeSemantics(
              child: SvgPicture.asset(
                PiggyArrivedDialog.art,
                width: PiggyArrivedDialog.artSize.width,
                height: PiggyArrivedDialog.artSize.height,
              ),
            ),
          ),
          Text(
            l10n.piggyArrivedTitle,
            textAlign: TextAlign.center,
            style: DesignExtras.piggyArrivedTitle.copyWith(
              color: ColorTokens.ink,
            ),
          ),
          DecoratedBox(
            key: PiggyArrivedDialog.chipsKey,
            decoration: BoxDecoration(
              color: ColorTokens.ground,
              borderRadius: BorderRadius.circular(RadiusTokens.l),
            ),
            child: Padding(
              // `PiggyArrived` box 22: 16 under the chips, for their lip.
              padding: const EdgeInsets.fromLTRB(
                SpaceTokens.s12,
                SpaceTokens.s12,
                SpaceTokens.s12,
                SpaceTokens.s16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: SpaceTokens.s10,
                children: [
                  _AmountChip(
                    label: l10n.piggyJenehatChip(
                      numbers.integer(widget.jenehat),
                    ),
                    icon: 'coin',
                  ),
                  _AmountChip(
                    label: l10n.piggyBonatChip(numbers.integer(widget.bonat)),
                    icon: 'bonat',
                  ),
                ],
              ),
            ),
          ),
          AppButton.primary(
            key: PiggyArrivedDialog.okKey,
            label: l10n.piggyArrivedOk,
            labelStyle: TypeTokens.displayM,
            height: PiggyArrivedDialog.okHeight,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// «+٣٠ ج» with its coin: a `paper` pill on a card lip (`PiggyArrived` 23).
class _AmountChip extends StatelessWidget {
  const _AmountChip({required this.label, required this.icon});

  final String label;
  final String icon;

  static const double _height = 48;
  static const double _icon = 28;

  @override
  Widget build(BuildContext context) => Container(
    height: _height,
    padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s16),
    decoration: BoxDecoration(
      color: ColorTokens.paper,
      borderRadius: BorderRadius.circular(RadiusTokens.pill),
      boxShadow: const [LipTokens.cardSmall],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SpaceTokens.s8,
      children: [
        Text(
          label,
          style: TypeTokens.displayS.copyWith(color: ColorTokens.ink),
        ),
        AppIcon(icon, size: _icon),
      ],
    ),
  );
}

/// The piggy toasts' icon: the pig, with a sun clock badge for «later»
/// (`PiggyLater`).
class PiggyToastIcon extends StatelessWidget {
  const PiggyToastIcon({this.later = false, super.key});

  final bool later;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: DesignExtras.piggyToastIcon,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        const AppIcon('piggy', size: DesignExtras.piggyToastIcon),
        if (later)
          PositionedDirectional(
            end: -DesignExtras.piggyToastBadgeOut,
            bottom: -DesignExtras.piggyToastBadgeDrop,
            child: Container(
              width: DesignExtras.piggyToastBadge,
              height: DesignExtras.piggyToastBadge,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: ColorTokens.sun,
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                'clock',
                size: DesignExtras.piggyToastBadgeIcon,
              ),
            ),
          ),
      ],
    ),
  );
}
