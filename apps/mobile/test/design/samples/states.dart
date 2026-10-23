import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';

import '../boxes.dart';
import 'board.dart';

// The `States` board as the app draws it (contracts/design-checks.md
// "Surfaces"): 390×1400 on `ground`, each component where States.html puts
// it, with the board's texts. The spend confirmation is the trip cards'
// `TripDialog` (008.5 research R13).

void _noop() {}

class StatesSample extends StatelessWidget {
  const StatesSample({required this.board, required this.digits, super.key});

  final DesignBoard board;
  final DigitStyle digits;

  static const size = Size(390, 1400);

  /// `States` box 7: a fuel offer used up for the day.
  static const usedUpLabel = 'خلصت النهارده';

  @override
  Widget build(BuildContext context) {
    /// The board's text, in [digits].
    String t(String text) => inDigits(text, digits);
    Widget at(int id, Widget child, {bool fullWidth = false}) {
      final b = board.byId(id);
      return Positioned(
        left: fullWidth ? 0 : b.x,
        top: b.y,
        width: fullWidth ? size.width : b.w,
        child: child,
      );
    }

    const fuelLabel = TextStyle(
      fontFamily: TypeTokens.readexPro,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      fontVariations: [FontVariation('wght', 700)],
      height: 1.2,
    );
    return SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: ColorTokens.ground,
        child: Stack(
          children: [
            at(
              1,
              const OfflineBanner(
                message:
                    'انت أوفلاين، المشاوير شغالة والتقدم هيتحفظ لما النت يرجع',
              ),
            ),
            at(
              3,
              InlineAlert(
                message: 'الإعلان مش جاهز دلوقتي، جرّب كمان شوية',
                icon: 'ad_not_ready',
                action: t('بـ٨ بونات'),
                onAction: _noop,
              ),
            ),
            at(
              7,
              const AppButton.secondary(
                label: usedUpLabel,
                onTap: _noop,
                enabled: false,
                leading: AppIcon('clock', size: 20),
                height: 56,
                radius: DesignExtras.dialogSecondaryRadius,
                labelStyle: fuelLabel,
              ),
            ),
            at(
              9,
              AppButton.secondary(
                label: t('فوّل بـ٣٠ بون'),
                onTap: _noop,
                height: 56,
                radius: DesignExtras.dialogSecondaryRadius,
                labelStyle: fuelLabel,
              ),
            ),
            at(
              10,
              fullWidth: true,
              TripDialog(
                title: t('هتصرف ٨٠ بون؟'),
                art: const AppIcon('bonat', size: DesignExtras.confirmArt),
                children: [
                  CardText(t('بنزين مفتوح ساعة · معاك ٨٥ بون')),
                  const CardActions(
                    confirm: CardConfirm(label: 'أيوه', onTap: _noop),
                    dismiss: CardTile(label: 'لأ', onTap: _noop),
                  ),
                ],
              ),
            ),
            at(
              16,
              UndoToast(
                message: t('اتشرى كيس فكة بـ١٠ بون'),
                icon: 'booster_change_bag',
                seconds: (n) => ar('$n', digits),
                onUndo: _noop,
                onExpired: _noop,
              ),
            ),
            at(
              20,
              const StatusCard.error(
                title: 'الدفع ما تمّش',
                message:
                    'وما اتخصمش منك حاجة. جرّب تاني أو اختار طريقة دفع تانية.',
                actions: [
                  AppButton.primary(
                    label: 'جرّب تاني',
                    size: AppButtonSize.compact,
                    onTap: _noop,
                  ),
                  AppButton.secondary(
                    label: 'طريقة تانية',
                    size: AppButtonSize.compact,
                    onTap: _noop,
                  ),
                ],
              ),
            ),
            at(
              26,
              const StatusCard.update(
                title: 'فيه نسخة جديدة',
                message: 'فيها خطوط جديدة. حدّث عشان تكمّل.',
                picture: AppIcon('upgrade_cassette', size: 64),
                actions: [
                  AppButton.primary(
                    label: 'حدّث من المتجر',
                    size: AppButtonSize.compact,
                    onTap: _noop,
                  ),
                ],
              ),
            ),
            at(
              31,
              StatusCard.maintenance(
                title: 'الموقف بيتصلّح',
                message: t('راجعين الساعة ٤. المشاوير شغالة أوفلاين.'),
                picture: const AppIcon(
                  'clock',
                  size: 72,
                  color: ColorTokens.sun,
                ),
              ),
            ),
            at(
              35,
              const StatusCard.empty(
                message: 'لسه ما دعيتش حد. ابعت كودك لصاحبك.',
                picture: AppIcon('requests_list', size: 60),
                actions: [
                  AppButton.sun(
                    label: 'ابعت الكود',
                    onTap: _noop,
                    height: 48,
                    labelStyle: fuelLabel,
                    sidePadding: 20,
                  ),
                ],
              ),
            ),
            at(39, const MicrobusLoader(label: 'بنحمّل الخط..')),
          ],
        ),
      ),
    );
  }
}
