import 'dart:async';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// One component of contracts/components.md "The set" in every variant and
/// state, on its [background].
final class GallerySection {
  const GallerySection(
    this.name,
    this.build, {
    this.background = ColorTokens.ground,
  });

  final String name;
  final Widget Function(BuildContext context, NumberFormatter numbers) build;
  final Color background;

  static Key keyOf(String name) => ValueKey('gallery.section.$name');
}

/// The components page: every section, one under another. Not lazy, so a
/// test finds every section without scrolling.
class ComponentsPage extends StatelessWidget {
  const ComponentsPage({required this.numbers, super.key});

  final NumberFormatter numbers;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      LayoutTokens.gutter,
      SpaceTokens.s8,
      LayoutTokens.gutter,
      SpaceTokens.s24 + MediaQuery.viewPaddingOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s24,
      children: [
        for (final section in gallerySections)
          GallerySectionView(section: section, numbers: numbers),
      ],
    ),
  );
}

/// A section's name over its demos. The goldens pump these one by one.
class GallerySectionView extends StatelessWidget {
  GallerySectionView({required this.section, required this.numbers})
    : super(key: GallerySection.keyOf(section.name));

  final GallerySection section;
  final NumberFormatter numbers;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: SpaceTokens.s8,
    children: [
      Text(
        section.name,
        textDirection: TextDirection.ltr,
        style: TypeTokens.row.copyWith(color: ColorTokens.ink2),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: section.background,
          borderRadius: BorderRadius.circular(RadiusTokens.m),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SpaceTokens.s12),
          child: section.build(context, numbers),
        ),
      ),
    ],
  );
}

AppLocalizations _l10n(BuildContext context) => AppLocalizations.of(context);

void _noop() {}

Widget _wrap(List<Widget> children) => Wrap(
  spacing: SpaceTokens.s12,
  runSpacing: SpaceTokens.s12,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: children,
);

Widget _column(List<Widget> children) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  spacing: SpaceTokens.s12,
  children: children,
);

/// Every section, in contracts/components.md's order.
final gallerySections = <GallerySection>[
  GallerySection(
    'Pressable',
    (context, _) => _wrap([
      for (final enabled in [true, false])
        Pressable(
          onTap: _noop,
          enabled: enabled,
          lip: LipTokens.card,
          borderRadius: BorderRadius.circular(RadiusTokens.card),
          child: Container(
            width: 140,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ColorTokens.paper,
              borderRadius: BorderRadius.circular(RadiusTokens.card),
            ),
            child: Text(
              enabled ? 'Pressable' : 'Disabled',
              style: TypeTokens.row.copyWith(color: ColorTokens.ink),
            ),
          ),
        ),
    ]),
  ),
  GallerySection('AppButton', (context, numbers) {
    final l10n = _l10n(context);
    return _column([
      AppButton.primary(
        label: l10n.pauseResume,
        onTap: _noop,
        trailing: CostChip(amount: numbers.integer(-1), large: true),
      ),
      AppButton.primary(
        label: l10n.tripBoosterBuy,
        size: AppButtonSize.l,
        onTap: _noop,
      ),
      AppButton.secondary(label: l10n.pauseHome, onTap: _noop),
      AppButton.sun(label: l10n.tripBreakButton, onTap: _noop),
      AppButton.danger(
        label: l10n.tripFailRevive(numbers.integer(30)),
        onTap: _noop,
      ),
      AppButton.tertiary(label: l10n.tripBoosterClose, onTap: _noop),
      AppButton.primary(label: l10n.pauseResume, onTap: _noop, enabled: false),
      AppButton.primary(label: l10n.pauseResume, onTap: _noop, loading: true),
    ]);
  }),
  GallerySection('RewardedAdButton', (context, numbers) {
    final l10n = _l10n(context);
    return _column([
      for (final ready in [true, false])
        RewardedAdButton(
          ready: ready,
          title: l10n.tripBoosterTrafficJam(numbers.integer(10)),
          benefit: '+${numbers.integer(170)}',
          onTap: _noop,
        ),
    ]);
  }),
  GallerySection('IconCircleButton', (context, _) {
    final label = _l10n(context).closeLabel;
    return _wrap([
      for (final icon in ['close', 'back', 'pause', 'edit', 'copy'])
        IconCircleButton(icon: icon, semanticLabel: label, onTap: _noop),
      DecoratedBox(
        decoration: BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: BorderRadius.circular(RadiusTokens.m),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SpaceTokens.s8),
          child: IconCircleButton(
            icon: 'close',
            semanticLabel: label,
            inSheet: true,
            onTap: _noop,
          ),
        ),
      ),
    ]);
  }),
  GallerySection(
    'CurrencyPill',
    (context, numbers) => _wrap([
      CurrencyPill(kind: CurrencyKind.coin, value: numbers.integer(1240)),
      CurrencyPill(
        kind: CurrencyKind.bonat,
        value: numbers.integer(35),
        onTap: _noop,
      ),
      CurrencyPill(
        kind: CurrencyKind.fuel,
        value: numbers.ratio(4, 5),
        timer: numbers.countdown(const Duration(minutes: 12, seconds: 30)),
        onTap: _noop,
      ),
      CurrencyPill(
        kind: CurrencyKind.fuel,
        value: numbers.ratio(0, 5),
        timer: numbers.countdown(const Duration(minutes: 4)),
        empty: true,
      ),
      CurrencyPill(
        kind: CurrencyKind.coin,
        value: numbers.integer(1240),
        height: CurrencyPill.compactHeight,
      ),
    ]),
  ),
  GallerySection(
    'CountBadge',
    (context, numbers) => _wrap([
      CountBadge(text: numbers.ratio(2, 3)),
      CountBadge(text: numbers.integer(5), onTap: _noop),
    ]),
  ),
  GallerySection('NewDot', (context, _) => _wrap([const NewDot()])),
  GallerySection(
    'PriceTag',
    (context, numbers) => _wrap([
      PriceTag(value: numbers.integer(3200), kind: CurrencyKind.coin),
      PriceTag(value: numbers.integer(30), kind: CurrencyKind.bonat),
      PriceTag(value: numbers.integer(49)),
    ]),
  ),
  GallerySection(
    'Stars',
    (context, _) => _wrap([for (var i = 0; i <= 3; i++) Stars(earned: i)]),
  ),
  GallerySection('StatusChip', (context, _) {
    final l10n = _l10n(context);
    return _wrap([
      StatusChip.new_(label: l10n.newBadgeLabel),
      StatusChip.story(label: l10n.destStory),
      StatusChip.done(label: l10n.tripPlaytestFinished),
      StatusChip.offline(label: l10n.adNotReady),
    ]);
  }),
  GallerySection('AppSwitch', (context, _) {
    final l10n = _l10n(context);
    return _column([
      _Held<bool>(
        initial: true,
        builder: (on, set) =>
            AppSwitch(label: l10n.tripPauseSound, value: on, onChanged: set),
      ),
      _Held<bool>(
        initial: false,
        builder: (on, set) =>
            AppSwitch(label: l10n.tripPauseHaptics, value: on, onChanged: set),
      ),
      AppSwitch(
        label: l10n.tripPauseHaptics,
        value: true,
        enabled: false,
        onChanged: (_) {},
      ),
    ]);
  }),
  GallerySection('Segmented', (context, _) {
    final l10n = _l10n(context);
    return _column([
      for (final style in SegmentedStyle.values)
        _Held<int>(
          initial: 0,
          builder: (value, set) => Segmented<int>(
            value: value,
            style: style,
            segments: [
              (0, l10n.tabHome),
              (1, l10n.tabLines),
              (2, l10n.tabApartment),
            ],
            onChanged: set,
          ),
        ),
    ]);
  }),
  GallerySection('AppTextField', (context, _) => const _FieldDemo()),
  GallerySection('AppCard', (context, _) {
    final l10n = _l10n(context);
    return _column([
      for (final locked in [false, true])
        AppCard(
          locked: locked,
          child: Text(
            l10n.destLineDetail,
            style: TypeTokens.row.copyWith(
              color: locked ? ColorTokens.ink2 : ColorTokens.ink,
            ),
          ),
        ),
    ]);
  }),
  GallerySection('ListRow', (context, numbers) {
    final l10n = _l10n(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListRow(
            title: l10n.destSettings,
            trailing: const ListRowChevron(),
            onTap: _noop,
          ),
          ListRow(
            title: l10n.tripBoosterChangeBag,
            caption: l10n.tripBoosterCardBalance(35, numbers.integer(35)),
            trailing: PriceTag(
              value: numbers.integer(10),
              kind: CurrencyKind.bonat,
            ),
          ),
          ListRow(
            title: l10n.settingsDigitStyle,
            trailing: _Held<bool>(
              initial: true,
              builder: (on, set) => AppSwitch(
                label: '',
                value: on,
                framed: false,
                onChanged: set,
              ),
            ),
          ),
        ],
      ),
    );
  }),
  GallerySection(
    'ProgressBar',
    (context, _) => _column([
      const ProgressBar(value: 0.3),
      const ProgressBar(value: 0.6, color: ProgressColor.gold),
      const ProgressBar(value: 0.9, color: ProgressColor.sun),
    ]),
  ),
  GallerySection(
    'ScreenHeader',
    (context, numbers) => MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: ScreenHeader(
        title: _l10n(context).destSettings,
        onBack: _noop,
        trailing: [
          CurrencyPill(kind: CurrencyKind.bonat, value: numbers.integer(35)),
        ],
      ),
    ),
  ),
  GallerySection(
    'EmptyState',
    (context, _) => EmptyState(
      message: _l10n(context).placeholderNote,
      picture: const AppIcon(
        'house_filled',
        size: 48,
        color: ColorTokens.iconOff,
      ),
    ),
  ),
  GallerySection('AppSheet', (context, _) {
    final l10n = _l10n(context);
    return _column([
      IgnorePointer(
        child: AppSheet(
          title: l10n.destFuel,
          child: Text(
            l10n.tripNoFuelTitle,
            style: TypeTokens.body.copyWith(color: ColorTokens.ink),
          ),
        ),
      ),
      AppButton.secondary(
        label: 'Open a sheet',
        onTap: () => unawaited(
          showAppSheet<void>(
            context: context,
            title: l10n.destFuel,
            builder: (context) => AppButton.primary(
              label: l10n.tripNoFuelShop,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    ]);
  }, background: ColorTokens.scrim),
  GallerySection('AppDialog', (context, _) {
    final l10n = _l10n(context);
    Widget dialog(VoidCallback close) => AppDialog(
      semanticLabel: l10n.pauseTitle,
      child: _column([
        Text(
          l10n.pauseTitle,
          textAlign: TextAlign.center,
          style: TypeTokens.displayM.copyWith(color: ColorTokens.ink),
        ),
        AppButton.primary(label: l10n.pauseResume, onTap: close),
        AppButton.secondary(label: l10n.pauseHome, onTap: close),
      ]),
    );
    return _column([
      IgnorePointer(child: dialog(_noop)),
      AppButton.secondary(
        label: 'Open a dialog its buttons alone close',
        onTap: () => unawaited(
          showAppDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (context) => dialog(() => Navigator.of(context).pop()),
          ),
        ),
      ),
    ]);
  }, background: ColorTokens.scrim),
  GallerySection('EventBanner', (context, numbers) {
    final l10n = _l10n(context);
    return _Held<int>(
      initial: 0,
      builder: (run, set) => _column([
        EventBanner(
          key: ValueKey(run),
          title: l10n.tripStoryNoFights,
          subtitle: l10n.tripBannerFareUp(
            numbers.integer(8),
            numbers.integer(7),
          ),
        ),
        AppButton.tertiary(label: 'Replay', onTap: () => set(run + 1)),
      ]),
    );
  }),
  GallerySection(
    'OfflineBanner',
    (context, _) => OfflineBanner(message: _l10n(context).tripRetryStart),
  ),
  GallerySection('UndoToast', (context, numbers) {
    final l10n = _l10n(context);
    return _Held<int>(
      initial: 0,
      builder: (run, set) => _column([
        UndoToast(
          key: ValueKey(run),
          message: l10n.tripBoosterChangeBag,
          icon: 'booster_change_bag',
          seconds: numbers.integer,
          onUndo: _noop,
          onExpired: _noop,
        ),
        AppButton.tertiary(label: 'Replay', onTap: () => set(run + 1)),
      ]),
    );
  }),
  GallerySection('AppToast', (context, _) {
    final message = _l10n(context).pressBackAgainToExit;
    return _column([
      AppToast(message: message),
      AppButton.secondary(
        label: 'Show a toast',
        onTap: () => showAppToast(context, message),
      ),
    ]);
  }),
  GallerySection('InlineAlert', (context, numbers) {
    final l10n = _l10n(context);
    return InlineAlert(
      message: l10n.adNotReady,
      icon: 'ad_screen',
      action: l10n.tripBoosterCardPrice(numbers.integer(8)),
      onAction: _noop,
    );
  }),
  GallerySection('StatusCard', (context, _) {
    final l10n = _l10n(context);
    return _column([
      StatusCard.error(
        title: l10n.tripRetryPurchase,
        message: l10n.bootErrorMessage,
        actions: [
          AppButton.primary(
            label: l10n.tripRetryAction,
            size: AppButtonSize.compact,
            onTap: _noop,
          ),
          AppButton.secondary(
            label: l10n.tripRetryHome,
            size: AppButtonSize.compact,
            onTap: _noop,
          ),
        ],
      ),
      StatusCard.update(
        title: l10n.appName,
        message: l10n.placeholderNote,
        picture: const AppIcon('upgrade_cassette', size: 64),
        actions: [
          AppButton.primary(
            label: l10n.tripRetryAction,
            size: AppButtonSize.compact,
            onTap: _noop,
          ),
        ],
      ),
      StatusCard.maintenance(
        title: l10n.appName,
        message: l10n.placeholderNote,
        picture: const AppIcon('clock', size: 72, color: ColorTokens.sun),
      ),
      StatusCard.empty(
        message: l10n.placeholderNote,
        picture: const AppIcon('requests_list', size: 60),
        actions: [AppButton.sun(label: l10n.tripRetryAction, onTap: _noop)],
      ),
    ]);
  }),
  GallerySection(
    'BottomNav',
    (context, _) => _Held<int>(
      initial: 0,
      builder: (tab, set) => MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: BottomNav(
          currentIndex: tab,
          onTap: set,
          newDots: const [false, false, true, false],
        ),
      ),
    ),
  ),
  GallerySection('DailyCircle', (context, numbers) {
    final l10n = _l10n(context);
    return _wrap([
      DailyCircle(
        icon: 'gift',
        label: l10n.destDailyReward,
        isNew: true,
        onTap: _noop,
      ),
      DailyCircle(
        icon: 'tasks',
        label: l10n.destDailyTasks,
        count: numbers.ratio(2, 3),
        onTap: _noop,
      ),
      DailyCircle(
        icon: 'lantern',
        label: l10n.destStory,
        event: true,
        onTap: _noop,
      ),
    ]);
  }),
  GallerySection('ComicPanel', (context, _) {
    final l10n = _l10n(context);
    return SizedBox(
      height: 360,
      child: ComicPanel(
        art: Align(
          alignment: Alignment.bottomCenter,
          child: SvgPicture.asset(
            'assets/illustrations/characters/moallem.svg',
            height: 220,
          ),
        ),
        caption: l10n.destHome,
        speaker: l10n.tripLookHajja,
        line: l10n.tripHintHonest,
      ),
    );
  }),
  GallerySection('CoachMark', (context, _) {
    const target = Rect.fromLTWH(120, 150, 87, 44);
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: target,
            child: AppButton.sun(
              label: _l10n(context).tripTrayHalf,
              onTap: _noop,
            ),
          ),
          const Positioned.fill(child: CoachMark(target: target)),
        ],
      ),
    );
  }),
  GallerySection(
    'MicrobusLoader',
    (context, _) => MicrobusLoader(label: _l10n(context).destTrip),
  ),
];

/// A demo that holds one value, so a switch or a tab can be played with.
class _Held<T> extends StatefulWidget {
  const _Held({required this.initial, required this.builder});

  final T initial;
  final Widget Function(T value, ValueChanged<T> set) builder;

  @override
  State<_Held<T>> createState() => _HeldState<T>();
}

class _HeldState<T> extends State<_Held<T>> {
  late T _value = widget.initial;

  @override
  Widget build(BuildContext context) =>
      widget.builder(_value, (v) => setState(() => _value = v));
}

class _FieldDemo extends StatefulWidget {
  const _FieldDemo();

  @override
  State<_FieldDemo> createState() => _FieldDemoState();
}

class _FieldDemoState extends State<_FieldDemo> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTextField(
    controller: _controller,
    semanticLabel: _l10n(context).destOnboardingName,
    maxLength: 20,
  );
}
