// The fare-increase banner (layer 8, ux-spec «الأجرة زادت!»): an orange
// strip that comes down from the top of the scene with the new fare and
// the old, holds, and goes back up, on the trip clock; a fade under
// reduced motion.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/tokens/shape.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

typedef _Shown = ({BannerView banner, int elapsedMs});

class FareBanner extends StatelessWidget {
  const FareBanner({super.key});

  static const bannerKey = ValueKey('trip-fare-banner');

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
        final strip = _Strip(key: bannerKey, banner: shown.banner);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            child: MediaQuery.disableAnimationsOf(context)
                ? Opacity(opacity: placed, child: strip)
                : FractionalTranslation(
                    translation: Offset(0, placed - 1),
                    child: strip,
                  ),
          ),
        );
      },
    );
  }
}

class _Strip extends ConsumerWidget {
  const _Strip({required this.banner, super.key});

  final BannerView banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final numbers = ref.watch(numberFormatterProvider);
    final text = AppLocalizations.of(context).tripBannerFareUp(
      numbers.piasters(banner.newPiasters),
      numbers.piasters(banner.oldPiasters),
    );
    return Padding(
      padding: const EdgeInsets.all(SpaceTokens.s),
      child: Semantics(
        liveRegion: true,
        label: text,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.danger,
            border: Border.all(
              color: tokens.hibr,
              width: ShapeTokens.borderCard,
            ),
            borderRadius: BorderRadius.circular(ShapeTokens.radiusControl),
            boxShadow: [
              BoxShadow(
                color: tokens.hibr,
                offset: const Offset(0, ShapeTokens.badgeOutline),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpaceTokens.l,
              vertical: SpaceTokens.s,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TypeTokens.title.copyWith(color: tokens.hibr),
            ),
          ),
        ),
      ),
    );
  }
}
