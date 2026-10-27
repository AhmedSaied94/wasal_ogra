import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Overlays (HANDOFF §3.3, §6.5; research R5): sheets, dialogs, banners,
/// toasts and status cards. Reduced motion drops every slide and scale and
/// keeps fades of at most 150 ms.

/// The text style under an overlay, which has no screen's [Scaffold] above
/// it to give one.
const _overlayText = DesignExtras.overlayText;

/// Opens [builder]'s content in an [AppSheet] titled [title].
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
}) => Navigator.of(context).push(
  _AppSheetRoute<T>(
    title: title,
    builder: builder,
    reducedMotion: MediaQuery.disableAnimationsOf(context),
    barrierLabel: AppLocalizations.of(context).closeLabel,
  ),
);

/// A sheet as a router page, so sheets keep a name and a URL (M03 research
/// R4).
class AppSheetPage<T> extends Page<T> {
  const AppSheetPage({
    required this.title,
    required this.child,
    super.key,
    super.name,
    super.arguments,
  });

  final String title;
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _AppSheetRoute<T>(
    settings: this,
    title: title,
    builder: (_) => child,
    reducedMotion: MediaQuery.disableAnimationsOf(context),
    barrierLabel: AppLocalizations.of(context).closeLabel,
  );
}

/// Rises from the bottom over 280 ms easeOutCubic and leaves over 200 ms
/// easeInCubic, over the `scrim`, which closes it.
class _AppSheetRoute<T> extends PopupRoute<T> {
  _AppSheetRoute({
    required this.title,
    required this.builder,
    required this.reducedMotion,
    required this.barrierLabel,
    super.settings,
  });

  final String title;
  final WidgetBuilder builder;
  final bool reducedMotion;

  @override
  final String barrierLabel;

  CurvedAnimation? _curve;

  static final _slide = Tween(begin: const Offset(0, 1), end: Offset.zero);

  @override
  Color get barrierColor => ColorTokens.scrim;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      reducedMotion ? DesignExtras.reducedFade : MotionTokens.sheetIn;

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? DesignExtras.reducedFade : MotionTokens.sheetOut;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AppSheet(
        title: title,
        child: Builder(builder: builder),
      ),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reducedMotion) return FadeTransition(opacity: animation, child: child);
    final curve = _curve ??= CurvedAnimation(
      parent: animation,
      curve: MotionTokens.sheetInCurve,
      reverseCurve: MotionTokens.sheetOutCurve,
    );
    return SlideTransition(position: _slide.animate(curve), child: child);
  }

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }
}

/// A sheet's frame: white with the 28 top radius, the grabber, the title in
/// Marhey 22 and ✕ at the end side (`Components` boxes 169–172). A drag
/// down of more than a quarter of its height, or a fling, closes it; a
/// shorter one springs back. The phone's bottom inset is added under the
/// content (spec FR-018).
class AppSheet extends StatefulWidget {
  const AppSheet({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  static const grabberKey = Key('AppSheet.grabber');

  /// The share of the sheet's height a drag must pass to close it.
  static const dismissShare = 0.25;

  /// The downward speed, in points a second, of a fling that closes it.
  static const flingVelocity = 700.0;

  static const double _side = 14;
  static const double _grabberTop = SpaceTokens.s8;
  static const double _closeTop = 21;
  static const double _titleTop = 3;

  @override
  State<AppSheet> createState() => _AppSheetState();
}

class _AppSheetState extends State<AppSheet>
    with SingleTickerProviderStateMixin {
  /// How far the sheet is dragged down, in points.
  late final _drag = AnimationController.unbounded(vsync: this);

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _close() => unawaited(Navigator.of(context).maybePop());

  void _dragged(DragUpdateDetails details) =>
      _drag.value = math.max(0, _drag.value + details.delta.dy);

  void _released(DragEndDetails details) {
    final height = context.size?.height ?? 0;
    final speed = details.velocity.pixelsPerSecond.dy;
    if (speed > AppSheet.flingVelocity ||
        _drag.value > height * AppSheet.dismissShare) {
      _close();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _drag.value = 0;
      return;
    }
    unawaited(
      _drag.animateTo(
        0,
        duration: MotionTokens.sheetOut,
        curve: MotionTokens.sheetInCurve,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const grabber = DesignExtras.sheetGrabber;
    final maxHeight =
        MediaQuery.sizeOf(context).height - screenTopInset(context);
    final sheet = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      // It reaches the bottom edge, so it colours the navigation bar.
      child: SystemBars(
        bottom: ColorTokens.paper,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: ColorTokens.paper,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(RadiusTokens.sheet),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSheet._side,
              AppSheet._grabberTop,
              AppSheet._side,
              AppSheet._side + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    key: AppSheet.grabberKey,
                    width: grabber.width,
                    height: grabber.height,
                    decoration: BoxDecoration(
                      color: ColorTokens.outline,
                      borderRadius: BorderRadius.circular(RadiusTokens.pill),
                    ),
                  ),
                ),
                SizedBox(
                  height:
                      AppSheet._closeTop -
                      AppSheet._grabberTop -
                      grabber.height,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: SpaceTokens.s12,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSheet._titleTop),
                        child: Semantics(
                          header: true,
                          child: Text(
                            widget.title,
                            style: DesignExtras.sheetTitle.copyWith(
                              color: ColorTokens.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconCircleButton(
                      icon: 'close',
                      semanticLabel: AppLocalizations.of(context).closeLabel,
                      inSheet: true,
                      onTap: _close,
                    ),
                  ],
                ),
                const SizedBox(height: SpaceTokens.s12),
                Flexible(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: widget.title,
      child: DefaultTextStyle(
        style: _overlayText,
        child: GestureDetector(
          onVerticalDragUpdate: _dragged,
          onVerticalDragEnd: _released,
          child: AnimatedBuilder(
            animation: _drag,
            child: sheet,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _drag.value),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [builder]'s [AppDialog]. With [barrierDismissible] false, neither
/// the scrim nor the phone's back closes it, only its own buttons (spend
/// confirmations, the failure card).
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => Navigator.of(context).push(
  appDialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  ),
);

/// [showAppDialog]'s route, for an owner that pushes and removes it itself
/// (the update card, specs/011-m06-identity-sync).
Route<T> appDialogRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => _AppDialogRoute<T>(
  builder: builder,
  dismissible: barrierDismissible,
  reducedMotion: MediaQuery.disableAnimationsOf(context),
  barrierLabel: AppLocalizations.of(context).closeLabel,
);

/// Scales 0.92 → 1 with a fade over 220 ms easeOutBack(1.2); leaves with
/// the scrim's 200 ms fade.
class _AppDialogRoute<T> extends PopupRoute<T> {
  _AppDialogRoute({
    required this.builder,
    required this.dismissible,
    required this.reducedMotion,
    required this.barrierLabel,
  });

  final WidgetBuilder builder;
  final bool dismissible;
  final bool reducedMotion;

  @override
  final String barrierLabel;

  CurvedAnimation? _curve;

  static final _scale = Tween<double>(begin: 0.92, end: 1);

  @override
  Color get barrierColor => ColorTokens.scrim;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Duration get transitionDuration =>
      reducedMotion ? DesignExtras.reducedFade : MotionTokens.dialogIn;

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? DesignExtras.reducedFade : MotionTokens.sheetOut;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => PopScope(
    canPop: dismissible,
    child: DefaultTextStyle(
      style: _overlayText,
      child: Builder(builder: builder),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final faded = FadeTransition(opacity: animation, child: child);
    if (reducedMotion) return faded;
    final curve = _curve ??= CurvedAnimation(
      parent: animation,
      curve: MotionTokens.dialogInCurve,
      reverseCurve: MotionTokens.sheetOutCurve,
    );
    return ScaleTransition(scale: _scale.animate(curve), child: faded);
  }

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }
}

/// A centred white card: radius 26, the dialog lip, padding 18, at most
/// the frame's width less the gutters.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.child,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(DesignExtras.dialogPadding),
    super.key,
  });

  final Widget child;

  /// Names the dialog for a screen reader: its title.
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;

  static const double maxWidth = LayoutTokens.frameW - 2 * LayoutTokens.gutter;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gutter),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: semanticLabel,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ColorTokens.paper,
              borderRadius: BorderRadius.circular(DesignExtras.dialogRadius),
              boxShadow: const [LipTokens.dialog],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    ),
  );
}

/// A timed event's banner (`Components` boxes 163–165): `danger`, 54 high,
/// radius 18, an ink title in Marhey 17 over an optional 12/600 line. It
/// slides down on arrival, is announced once, and after [hideAfter] slides
/// away and calls [onHidden]. With [hideAfter] null its owner hides it. The
/// trip's banner, on the trip clock, uses [EventBannerCard].
class EventBanner extends StatefulWidget {
  const EventBanner({
    required this.title,
    this.subtitle,
    this.hideAfter = DesignExtras.bannerHold,
    this.onHidden,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Duration? hideAfter;
  final VoidCallback? onHidden;

  static const double minHeight = EventBannerCard.minHeight;

  @override
  State<EventBanner> createState() => _EventBannerState();
}

class _EventBannerState extends State<EventBanner>
    with SingleTickerProviderStateMixin {
  late final _show = AnimationController(
    vsync: this,
    duration: MotionTokens.toast,
  );
  late final _curve = CurvedAnimation(
    parent: _show,
    curve: MotionTokens.toastCurve,
  );
  Timer? _hold;
  var _announced = false;

  static final _slide = Tween(begin: const Offset(0, -1), end: Offset.zero);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _show.duration = MediaQuery.disableAnimationsOf(context)
        ? DesignExtras.reducedFade
        : MotionTokens.toast;
    if (_announced) return;
    _announced = true;
    unawaited(_show.forward());
    final subtitle = widget.subtitle;
    final message = subtitle == null
        ? widget.title
        : AppLocalizations.of(context).pairLabel(widget.title, subtitle);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
    if (widget.hideAfter case final hold?) _hold = Timer(hold, _hide);
  }

  Future<void> _hide() async {
    await _show.reverse();
    if (mounted) widget.onHidden?.call();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _curve.dispose();
    _show.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = EventBannerCard(
      title: widget.title,
      subtitle: widget.subtitle,
    );
    final faded = FadeTransition(opacity: _show, child: banner);
    final shown = MediaQuery.disableAnimationsOf(context)
        ? faded
        : SlideTransition(position: _slide.animate(_curve), child: faded);
    return Semantics(container: true, child: shown);
  }
}

/// [EventBanner]'s look without its timing, for owners that move it
/// themselves (the trip's banner runs on the trip clock): `danger`, at least
/// 54 high, radius 18, the [leading] icon 10 before an ink title in Marhey
/// over an optional 12/600 line.
class EventBannerCard extends StatelessWidget {
  const EventBannerCard({
    required this.title,
    this.subtitle,
    this.leading,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  static const double minHeight = 54;
  static const double _radius = 18;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          style: DesignExtras.bannerTitle.copyWith(color: ColorTokens.ink),
        ),
        if (subtitle case final subtitle?)
          Text(
            subtitle,
            maxLines: 2,
            style: TypeTokens.label.copyWith(color: ColorTokens.ink),
          ),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ColorTokens.danger,
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: const [DesignExtras.eventBannerLip],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpaceTokens.s14,
            vertical: SpaceTokens.s8,
          ),
          child: switch (leading) {
            final leading? => Row(
              spacing: SpaceTokens.s10,
              children: [
                leading,
                Expanded(child: text),
              ],
            ),
            null => text,
          },
        ),
      ),
    );
  }
}

/// «You're offline» (`States` box 1): `dashboard.bg`, radius 14, the
/// `wifi_off` icon in `sun` at the start and white 12.5/600 text.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({required this.message, super.key});

  final String message;

  static const double minHeight = 40;
  static const double _radius = 14;
  static const double _icon = 20;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s14,
        vertical: SpaceTokens.s8,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.dashboardBg,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        spacing: SpaceTokens.s8,
        children: [
          const AppIcon('wifi_off', size: _icon, color: ColorTokens.sun),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              style: DesignExtras.offlineText.copyWith(
                color: ColorTokens.paper,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A dark toast's frame (`States` box 16): `dashboard.bg`, 56 high,
/// radius 18, an optional icon, white 13/600 text and an optional action.
class _DarkToast extends StatelessWidget {
  const _DarkToast({required this.message, this.icon, this.action});

  final String message;
  final String? icon;
  final Widget? action;

  static const double height = 56;
  static const double _radius = 18;
  static const double _icon = 22;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: height),
    padding: const EdgeInsets.symmetric(
      horizontal: SpaceTokens.s14,
      vertical: SpaceTokens.s8,
    ),
    decoration: BoxDecoration(
      color: ColorTokens.dashboardBg,
      borderRadius: BorderRadius.circular(_radius),
    ),
    child: Row(
      spacing: SpaceTokens.s10,
      children: [
        if (icon case final icon?) AppIcon(icon, size: _icon),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            style: TypeTokens.caption
                .weight(600)
                .copyWith(color: ColorTokens.paper),
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// An undoable purchase's toast, built for M12 and not used in the trip
/// (spec FR-028): the message and «رجّع n» counting down the 3 s hold.
/// [onUndo] runs on a tap; [onExpired] when the hold runs out unused.
class UndoToast extends StatefulWidget {
  const UndoToast({
    required this.message,
    required this.seconds,
    required this.onUndo,
    required this.onExpired,
    this.icon,
    super.key,
  });

  final String message;

  /// Formats the seconds left in the player's digits.
  final String Function(int seconds) seconds;
  final VoidCallback onUndo;
  final VoidCallback onExpired;
  final String? icon;

  static const double _buttonHeight = 40;
  static const double _buttonRadius = 12;

  @override
  State<UndoToast> createState() => _UndoToastState();
}

class _UndoToastState extends State<UndoToast> {
  late int _left = MotionTokens.toastHold.inSeconds;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _second());
  }

  void _second() {
    setState(() => _left--);
    if (_left > 0) return;
    _tick?.cancel();
    widget.onExpired();
  }

  void _undo() {
    if (_tick?.isActive != true) return;
    _tick?.cancel();
    widget.onUndo();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DarkToast(
    message: widget.message,
    icon: widget.icon,
    action: AppButton.sun(
      label: AppLocalizations.of(context).undoCountdown(widget.seconds(_left)),
      onTap: _undo,
      expand: false,
      height: UndoToast._buttonHeight,
      radius: UndoToast._buttonRadius,
      labelStyle: DesignExtras.compactLabel,
      sidePadding: SpaceTokens.s14,
    ),
  );
}

/// A passing message with no action (the back-to-exit hint): the
/// [UndoToast]'s look without its button.
class AppToast extends StatelessWidget {
  const AppToast({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Semantics(liveRegion: true, child: _DarkToast(message: message));
}

/// The toast each overlay shows; a new one replaces it.
final _toasts = Expando<OverlayEntry>('AppToast');

/// Shows [message] in an [AppToast] above the bottom nav for [hold], fading
/// in and out over `toast`. A second call replaces the first.
void showAppToast(
  BuildContext context,
  String message, {
  Duration hold = MotionTokens.toastHold,
}) =>
    showAppToastOn(Overlay.of(context, rootOverlay: true), message, hold: hold);

/// [showAppToast] on [overlay], for code outside the widget tree (the sync's
/// rollback toast, on the navigator's overlay).
void showAppToastOn(
  OverlayState overlay,
  String message, {
  Duration hold = MotionTokens.toastHold,
}) {
  if (_toasts[overlay] case final shown?) _closeToast(overlay, shown);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastHost(
      message: message,
      hold: hold,
      onDone: () => _closeToast(overlay, entry),
    ),
  );
  _toasts[overlay] = entry;
  overlay.insert(entry);
}

void _closeToast(OverlayState overlay, OverlayEntry entry) {
  if (!identical(_toasts[overlay], entry)) return;
  _toasts[overlay] = null;
  entry
    ..remove()
    ..dispose();
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({
    required this.message,
    required this.hold,
    required this.onDone,
  });

  final String message;
  final Duration hold;
  final VoidCallback onDone;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  late final _show = AnimationController(
    vsync: this,
    duration: MotionTokens.toast,
  );
  late final _curve = CurvedAnimation(
    parent: _show,
    curve: MotionTokens.toastCurve,
  );
  Timer? _hold;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fade = MediaQuery.disableAnimationsOf(context)
        ? DesignExtras.reducedFade
        : MotionTokens.toast;
    _show.duration = fade;
    if (_started) return;
    _started = true;
    unawaited(_show.forward());
    // Counted from now, so the toast stays the fade plus [hold] whatever
    // the frame rate.
    _hold = Timer(fade + widget.hold, _end);
  }

  Future<void> _end() async {
    await _show.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _curve.dispose();
    _show.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom =
        MediaQuery.viewPaddingOf(context).bottom +
        LayoutTokens.bottomNav +
        SpaceTokens.s12;
    return Positioned(
      left: LayoutTokens.gutter,
      right: LayoutTokens.gutter,
      bottom: bottom,
      child: IgnorePointer(
        child: DefaultTextStyle(
          style: _overlayText,
          child: FadeTransition(
            opacity: _curve,
            child: AppToast(message: widget.message),
          ),
        ),
      ),
    );
  }
}

/// A note inside a screen (`States` box 3): white, radius 18, the card lip,
/// padding 10 12, a 26 icon, 13/600 text and an optional `primary.soft`
/// action.
class InlineAlert extends StatelessWidget {
  const InlineAlert({
    required this.message,
    this.icon,
    this.action,
    this.onAction,
    super.key,
  });

  final String message;
  final String? icon;
  final String? action;
  final VoidCallback? onAction;

  static const double _radius = 18;
  static const double _icon = 26;
  static const double _actionRadius = 14;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpaceTokens.s12,
        vertical: SpaceTokens.s10,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.paper,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: const [LipTokens.card],
      ),
      child: Row(
        spacing: SpaceTokens.s10,
        children: [
          if (icon case final icon?) AppIcon(icon, size: _icon),
          Expanded(
            child: Text(
              message,
              style: TypeTokens.caption
                  .weight(600)
                  .copyWith(color: ColorTokens.ink),
            ),
          ),
          if (action != null)
            Pressable(
              onTap: onAction,
              pressedOpacity: 0.7,
              semanticLabel: action,
              child: Container(
                height: LayoutTokens.touchMin,
                padding: const EdgeInsets.symmetric(
                  horizontal: SpaceTokens.s12,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ColorTokens.primarySoft,
                  borderRadius: BorderRadius.circular(_actionRadius),
                ),
                child: Text(
                  action,
                  style: TypeTokens.caption
                      .weight(700)
                      .copyWith(color: ColorTokens.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _StatusKind { error, update, maintenance, empty }

/// A whole-state card (`States` boxes 20, 26, 31, 35): an error on
/// `danger.soft` (padding 14: the warning and the title, the message, the
/// actions in a row from the start); an update on white with the card lip
/// and maintenance on `dashboard.bg` (padding 16: the [picture] at the
/// start beside the title, the message and the actions); an empty list on
/// white with an `outline` ring (padding 18, centred: the picture, the
/// message, the actions). Actions take their own width.
class StatusCard extends StatelessWidget {
  const StatusCard.error({
    required this.title,
    required this.message,
    this.actions = const [],
    super.key,
  }) : picture = null,
       _kind = _StatusKind.error;

  const StatusCard.update({
    required this.title,
    required this.message,
    this.picture,
    this.actions = const [],
    super.key,
  }) : _kind = _StatusKind.update;

  const StatusCard.maintenance({
    required this.title,
    required this.message,
    this.picture,
    this.actions = const [],
    super.key,
  }) : _kind = _StatusKind.maintenance;

  const StatusCard.empty({
    required this.message,
    this.picture,
    this.actions = const [],
    super.key,
  }) : title = null,
       _kind = _StatusKind.empty;

  final String? title;
  final String message;
  final Widget? picture;
  final List<Widget> actions;
  final _StatusKind _kind;

  static const double _errorRadius = 22;
  static const double _warning = 22;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final picture = this.picture;
    final row = actions.isEmpty
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: SpaceTokens.s8,
            children: [for (final a in actions) IntrinsicWidth(child: a)],
          );
    switch (_kind) {
      case _StatusKind.error:
        return Container(
          padding: const EdgeInsets.all(SpaceTokens.s14),
          decoration: BoxDecoration(
            color: ColorTokens.dangerSoft,
            borderRadius: BorderRadius.circular(_errorRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: SpaceTokens.s10,
            children: [
              if (title != null)
                Row(
                  spacing: SpaceTokens.s8,
                  children: [
                    const AppIcon(
                      'warning',
                      size: _warning,
                      color: ColorTokens.dangerInk,
                    ),
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: DesignExtras.errorTitle.copyWith(
                            color: ColorTokens.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              Text(
                message,
                style: TypeTokens.caption.copyWith(
                  color: ColorTokens.ink,
                  height: 1.6,
                ),
              ),
              ?row,
            ],
          ),
        );
      case _StatusKind.update || _StatusKind.maintenance:
        final dark = _kind == _StatusKind.maintenance;
        return Container(
          padding: const EdgeInsets.all(SpaceTokens.s16),
          decoration: BoxDecoration(
            color: dark ? ColorTokens.dashboardBg : ColorTokens.paper,
            borderRadius: BorderRadius.circular(RadiusTokens.xl),
            boxShadow: [if (!dark) LipTokens.card],
          ),
          child: Row(
            spacing: SpaceTokens.s12,
            children: [
              ?picture,
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: dark ? SpaceTokens.s4 : SpaceTokens.s6,
                  children: [
                    if (title != null)
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: DesignExtras.statusTitle.copyWith(
                            color: dark ? ColorTokens.sun : ColorTokens.ink,
                          ),
                        ),
                      ),
                    Text(
                      message,
                      style: DesignExtras.dialogSubtitle.copyWith(
                        color: dark
                            ? ColorTokens.dashboardText
                            : ColorTokens.ink2,
                      ),
                    ),
                    ?row,
                  ],
                ),
              ),
            ],
          ),
        );
      case _StatusKind.empty:
        return Container(
          padding: const EdgeInsets.all(DesignExtras.dialogPadding),
          decoration: BoxDecoration(
            color: ColorTokens.paper,
            borderRadius: BorderRadius.circular(RadiusTokens.xl),
            border: Border.all(
              color: RingTokens.empty.color,
              width: RingTokens.empty.width,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: SpaceTokens.s10,
            children: [
              ?picture,
              Text(
                message,
                textAlign: TextAlign.center,
                style: DesignExtras.emptyMessage.copyWith(
                  color: ColorTokens.ink,
                ),
              ),
              ?row,
            ],
          ),
        );
    }
  }
}
