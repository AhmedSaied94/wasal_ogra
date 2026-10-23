// The fare-increase banner (layer 8, HANDOFF `TripEvents` block 3): the
// `EventBanner` look over the back window, 10 pt in from the scene's sides
// and 8 down, with the warning triangle and M02's line. On the trip clock it
// slides 12 pt down as it fades in, holds 4 s, and leaves the same way, so
// it stops with the trip; under reduced motion it only fades. It is
// announced once, as a live region.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

typedef _Shown = ({BannerView banner, int elapsedMs});

/// The banner's place in the scene.
const _inset = EdgeInsets.fromLTRB(
  SpaceTokens.s10,
  SpaceTokens.s8,
  SpaceTokens.s10,
  0,
);

/// How far it slides in.
const _slide = 12.0;

class FareBanner extends StatelessWidget {
  const FareBanner({super.key});

  static const bannerKey = ValueKey('trip-fare-banner');
  static const iconKey = ValueKey('trip-fare-banner-icon');

  @override
  Widget build(BuildContext context) {
    return TripSelector<_Shown?>(
      select: (model) {
        final view = model.view;
        final banner = view?.banner;
        if (view == null || banner == null) return null;
        return (banner: banner, elapsedMs: view.tMs - banner.shownAtMs);
      },
      builder: (context, shown) {
        if (shown == null) return const SizedBox.shrink();
        final edge = TripMotion.bannerIn.inMilliseconds;
        final t = shown.elapsedMs;
        // 0 out of sight, 1 in place.
        final placed = (t < edge ? t / edge : (bannerMs - t) / edge)
            .clamp(0.0, 1.0)
            .toDouble();
        final banner = Opacity(
          opacity: placed,
          child: _Banner(key: bannerKey, banner: shown.banner),
        );
        return Padding(
          padding: _inset,
          child: Align(
            alignment: Alignment.topCenter,
            child: MediaQuery.disableAnimationsOf(context)
                ? banner
                : Transform.translate(
                    offset: Offset(0, -_slide * (1 - placed)),
                    child: banner,
                  ),
          ),
        );
      },
    );
  }
}

class _Banner extends ConsumerWidget {
  const _Banner({required this.banner, super.key});

  final BannerView banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final text = AppLocalizations.of(context).tripBannerFareUp(
      numbers.piasters(banner.newPiasters),
      numbers.piasters(banner.oldPiasters),
    );
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: EventBannerCard(
        title: text,
        leading: const SizedBox.square(
          key: FareBanner.iconKey,
          dimension: _WarningGlyph.size,
          child: CustomPaint(painter: _WarningGlyph()),
        ),
      ),
    );
  }
}

/// `TripEvents`' warning triangle on `danger`: an ink triangle with the
/// glyph cut in `danger` (the `warning` icon's colours swapped).
class _WarningGlyph extends CustomPainter {
  const _WarningGlyph();

  static const double size = 26;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on the icon's 24-unit grid.
    canvas.scale(size.width / 24);
    final glyph = Paint()
      ..color = ColorTokens.danger
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawPath(
        Path()
          ..moveTo(12, 3)
          ..lineTo(22, 20)
          ..lineTo(2, 20)
          ..close(),
        Paint()..color = ColorTokens.ink,
      )
      ..drawLine(const Offset(12, 9), const Offset(12, 14), glyph)
      ..drawCircle(const Offset(12, 17), 1.3, glyph);
  }

  @override
  bool shouldRepaint(_WarningGlyph oldDelegate) => false;
}
