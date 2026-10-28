// Sharing the result (specs/013-m08-home-result, contracts/result.md
// "Sharing", research R16): the share button beside «مشوار تاني». A tap
// renders the `ShareCard` off screen at 3× and hands the PNG, with its
// caption, to the phone's share sheet. Nothing is fetched, so it works
// offline. A failure says so in a toast and changes nothing else.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/platform/share_gateway.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/avatars.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/application/quote_provider.dart';
import 'package:wassal/features/result/domain/result_args.dart';
import 'package:wassal/features/result/domain/summary.dart';
import 'package:wassal/features/result/presentation/quote_card.dart';
import 'package:wassal/features/result/presentation/share_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The picture couldn't be drawn.
final class ShareRenderException implements Exception {
  const ShareRenderException(this.message);

  final String message;

  @override
  String toString() => 'ShareRenderException: $message';
}

/// 360 × 3 = 1080.
const double _pixelRatio = 3;

/// Frames before the capture: the first builds the card and starts its
/// pictures, which arrive, already loaded, for the second.
const int _framesBeforeCapture = 2;

/// [spec]'s picture as a PNG: the card, built off screen over [context]'s
/// overlay for a frame or two, then captured at [_pixelRatio] and removed.
Future<Uint8List> renderSharePicture(
  BuildContext context,
  ShareSpec spec,
) async {
  await _loadPictures(context, spec);
  if (!context.mounted) {
    throw const ShareRenderException('the screen closed');
  }
  final boundary = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Off screen, beside it.
      left: -ShareCard.side * 2,
      top: 0,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: RepaintBoundary(
            key: boundary,
            child: ShareCard(spec: spec),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  try {
    final binding = WidgetsBinding.instance;
    for (var i = 0; i < _framesBeforeCapture; i++) {
      binding.scheduleFrame();
      await binding.endOfFrame;
    }
    final render = boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) {
      throw const ShareRenderException('the card was not laid out');
    }
    final image = await render.toImage(pixelRatio: _pixelRatio);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw const ShareRenderException('no PNG');
      return png.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// Loads the card's SVGs, as its icons and face will ask for them, so the
/// card's first frame finds them.
Future<void> _loadPictures(BuildContext context, ShareSpec spec) {
  final loaders = [
    for (final (name, color) in ShareCard.icons)
      SvgAssetLoader(AppIcon.path(name), theme: SvgTheme(currentColor: color)),
    if (spec.quote case final quote?)
      SvgAssetLoader(PassengerAvatar.path(quote.look.id)),
  ];
  return Future.wait([
    for (final loader in loaders)
      svg.cache.putIfAbsent(
        loader.cacheKey(context),
        () => loader.loadBytes(context),
      ),
  ]);
}

/// `Result` box 58: «شارك النتيجة», a `sun` square with the share glyph.
/// A tap while a share is under way does nothing.
class ShareResultButton extends ConsumerStatefulWidget {
  const ShareResultButton({
    required this.summary,
    required this.args,
    super.key,
  });

  final ResultSummary summary;
  final ResultArgs args;

  static const buttonKey = Key('ShareResultButton');

  /// `Result` boxes 58–59.
  static const double size = 60;
  static const double _icon = 26;

  @override
  ConsumerState<ShareResultButton> createState() => _ShareResultButtonState();
}

class _ShareResultButtonState extends ConsumerState<ShareResultButton> {
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    _busy = true;
    final l10n = AppLocalizations.of(context);
    try {
      // Everything read from `ref` and the tree before the first await.
      final numbers = ref.read(numberFormatterProvider);
      final gateway = ref.read(shareGatewayProvider);
      final summary = widget.summary;
      final spec = _spec(l10n, numbers);
      final box = context.findRenderObject();
      final origin = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      final png = await renderSharePicture(context, spec);
      // The player left while it was drawn: no sheet over another screen.
      if (!mounted) return;
      // M15: share {kind: result_image}
      await gateway.shareImage(
        png,
        fileName: 'wassal_result_${summary.tripId}.png',
        text: l10n.shareCaption(
          numbers.integer(spec.payJenehat),
          summary.lineName,
        ),
        origin: origin,
      );
    } on Exception catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'result'),
      );
      if (mounted) showAppToast(context, l10n.shareFailed);
    } finally {
      _busy = false;
    }
  }

  /// The picture's content: the summary, and the quote when it has a line.
  ShareSpec _spec(AppLocalizations l10n, NumberFormatter numbers) {
    final summary = widget.summary;
    final quote = ref.read(resultQuoteProvider(widget.args)).value;
    final line = quote == null
        ? null
        : quoteLineOf(
            l10n,
            ref.read(contentSourceProvider),
            numbers,
            quote,
            widget.args.replay.definition,
          );
    return ShareSpec(
      heading: summary.heading,
      stars: summary.stars,
      payJenehat: summary.payJenehat,
      quote: switch ((quote, line)) {
        (final quote?, final line?) => (
          look: quote.look,
          line: line,
          labelKey: quote.labelKey,
        ),
        _ => null,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.l);
    return Pressable(
      key: ShareResultButton.buttonKey,
      onTap: () => unawaited(_share()),
      lip: LipTokens.sun,
      borderRadius: radius,
      semanticLabel: AppLocalizations.of(context).resultA11yShare,
      child: Container(
        width: ShareResultButton.size,
        height: ShareResultButton.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: ColorTokens.sun, borderRadius: radius),
        child: const AppIcon(
          'share',
          size: ShareResultButton._icon,
          color: ColorTokens.ink,
        ),
      ),
    );
  }
}
