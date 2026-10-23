import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../boxes.dart';
import 'board.dart';

// The `Components` board as the app draws it (contracts/design-checks.md
// "Surfaces"): 1200×1700, each shared component where Components.html
// places it, over the board's headings, notes and section grounds.
//
// The trip's sections (HUD, station tags, bubbles, money, dashboard,
// ledger and choices) show only their grounds here: those components are
// checked on the trip's own artboards (C-Trip, TripEvents, StoryTrip).

void _noop() {}

class ComponentsSample extends StatefulWidget {
  const ComponentsSample({
    required this.board,
    required this.digits,
    super.key,
  });

  final DesignBoard board;
  final DigitStyle digits;

  static const size = Size(1200, 1700);

  /// Box 6, «primary · pressed»: held down for the golden. Its label tells
  /// it from box 3, which has the same text.
  static const pressedKey = Key('ComponentsSample.pressed');
  static const pressedLabel = 'primary, pressed';

  /// The rewarded button's lines (box 10), for its pairing.
  static (String, String) rewarded(DigitStyle digits) =>
      (ar('اقبض ×2', digits), ar('+170 بدل 85', digits));

  @override
  State<ComponentsSample> createState() => _ComponentsSampleState();
}

class _ComponentsSampleState extends State<ComponentsSample> {
  final _name = TextEditingController(text: 'حمادة');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  DesignBox _box(int id) => widget.board.byId(id);

  String _ar(String western) => ar(western, widget.digits);

  /// [child] at box [id]'s place and width.
  Widget _at(int id, Widget child, {double? height}) {
    final b = _box(id);
    return Positioned(
      left: b.x,
      top: b.y,
      width: b.w,
      height: height,
      child: child,
    );
  }

  /// [child], at its own width, from box [id]'s right (start) edge, its
  /// middle on the box's middle when it is [tall].
  Widget _fromStart(int id, Widget child, {double? tall}) {
    final b = _box(id);
    return Positioned(
      right: ComponentsSample.size.width - b.x - b.w,
      top: tall == null ? b.y : b.y + (b.h - tall) / 2,
      child: child,
    );
  }

  /// The board's documentation: headings, notes and section grounds.
  bool _chrome(DesignBox b) =>
      b.parent == 0 &&
      (b.tag == 'h2' ||
          b.tag == 'h3' ||
          (b.role == 'text' && b.bg == null) ||
          (b.role == 'box' && b.tag == 'div' && b.radius == '18px'));

  @override
  Widget build(BuildContext context) {
    final digits = widget.digits;
    final (rewardTitle, rewardBenefit) = ComponentsSample.rewarded(digits);
    return SizedBox.fromSize(
      size: ComponentsSample.size,
      child: ColoredBox(
        color: ColorTokens.paper,
        child: Stack(
          children: [
            for (final b in widget.board.boxes)
              if (_chrome(b)) boardBox(b, digits),
            // Buttons.
            _at(
              3,
              AppButton.primary(
                label: 'يلا نطلع!',
                onTap: _noop,
                trailing: CostChip(amount: _ar('−1'), large: true),
              ),
            ),
            _at(
              6,
              const AppButton.primary(
                key: ComponentsSample.pressedKey,
                label: 'يلا نطلع!',
                semanticLabel: ComponentsSample.pressedLabel,
                onTap: _noop,
              ),
            ),
            _at(
              8,
              const AppButton.secondary(label: 'مشوار تاني', onTap: _noop),
            ),
            _at(
              10,
              RewardedAdButton(
                ready: true,
                title: rewardTitle,
                benefit: rewardBenefit,
                onTap: _noop,
              ),
            ),
            _at(15, const AppButton.danger(label: 'البنزين خلص', onTap: _noop)),
            _at(
              17,
              AppButton.sun(
                label: 'حد معاه فكة؟',
                semanticLabel: _ar('حد معاه فكة؟ ×2'),
                trailing: Text(
                  _ar('×2'),
                  style: DesignExtras.chipLabel.copyWith(
                    color: ColorTokens.ink,
                  ),
                ),
                onTap: _noop,
              ),
            ),
            _at(
              19,
              const AppButton.primary(
                label: 'اشتريها',
                size: AppButtonSize.l,
                enabled: false,
                onTap: _noop,
              ),
            ),
            _fromStart(
              21,
              const AppButton.tertiary(label: 'ارجع الموقف', onTap: _noop),
            ),
            _at(
              22,
              const IconCircleButton(
                icon: 'pause',
                semanticLabel: 'إيقاف مؤقت',
                onTap: _noop,
              ),
            ),
            _at(
              24,
              const IconCircleButton(
                icon: 'close',
                semanticLabel: 'قفل',
                inSheet: true,
                onTap: _noop,
              ),
            ),
            // Pills, badges, chips.
            _fromStart(
              28,
              CurrencyPill(kind: CurrencyKind.coin, value: _ar('1,240')),
            ),
            _fromStart(
              30,
              CurrencyPill(kind: CurrencyKind.bonat, value: _ar('85')),
            ),
            _fromStart(
              32,
              CurrencyPill(
                kind: CurrencyKind.fuel,
                value: _ar('4/5'),
                timer: _ar('12:30'),
              ),
            ),
            _fromStart(
              36,
              CurrencyPill(
                kind: CurrencyKind.fuel,
                value: _ar('0/5'),
                timer: _ar('12:30'),
                empty: true,
              ),
            ),
            _at(
              40,
              SizedBox.square(
                dimension: _box(40).w,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        color: ColorTokens.paper,
                        shape: BoxShape.circle,
                        boxShadow: [LipTokens.bubble],
                      ),
                      child: SizedBox.expand(),
                    ),
                    Positioned(
                      left: _box(41).x - _box(40).x,
                      top: _box(41).y - _box(40).y,
                      child: const NewDot(),
                    ),
                  ],
                ),
              ),
            ),
            _fromStart(42, CountBadge(text: _ar('2/3'))),
            _fromStart(
              43,
              const StatusChip.new_(label: 'جديد'),
              tall: StatusChip.height,
            ),
            _fromStart(
              44,
              const StatusChip.story(label: 'مشوار قصة'),
              tall: StatusChip.height,
            ),
            _fromStart(
              45,
              const StatusChip.done(label: 'خلص'),
              tall: StatusChip.height,
            ),
            _fromStart(
              46,
              const StatusChip.offline(label: 'محتاج نت'),
              tall: StatusChip.height,
            ),
            // Controls.
            _at(50, AppSwitch(label: 'الصوت', value: true, onChanged: (_) {})),
            _at(
              55,
              Segmented<int>(
                value: 0,
                style: SegmentedStyle.sun,
                segments: const [(0, 'الصالة'), (1, 'المطبخ')],
                onChanged: (_) {},
              ),
            ),
            _at(
              58,
              Segmented<int>(
                value: 0,
                segments: const [(0, 'الترقيات'), (1, 'الزينة')],
                onChanged: (_) {},
              ),
            ),
            _at(61, AppTextField(controller: _name, semanticLabel: 'الاسم')),
            // Banners, toasts, sheets.
            _at(
              163,
              EventBanner(
                title: 'الأجرة زادت!',
                subtitle: _ar('المستشفى بقت 8 بدل 7'),
                hideAfter: null,
              ),
            ),
            _at(
              166,
              const OfflineBanner(message: 'انت أوفلاين، المشاوير شغالة'),
            ),
            _at(
              167,
              UndoToast(
                message: 'اتشرى كيس فكة',
                seconds: (n) => _ar('$n'),
                onUndo: _noop,
                onExpired: _noop,
              ),
            ),
            _at(
              169,
              const ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: double.infinity,
                  child: AppSheet(title: 'عنوان اللوح', child: SizedBox()),
                ),
              ),
              height: _box(169).h,
            ),
            // Bottom navigation.
            _at(
              175,
              BottomNav(
                currentIndex: 0,
                onTap: (_) {},
                newDots: const [false, false, true, false],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
