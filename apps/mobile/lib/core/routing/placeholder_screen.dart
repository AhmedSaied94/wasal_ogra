import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/components/sticker_card.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Stands in for a destination whose real content arrives in a later
/// feature: its title, a «still being built» note, its parameters, sample
/// numbers in the current digit style, and a link to each onward
/// destination (FR-017a). Later features replace it route by route.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.destination,
    this.params = const {},
    this.extra,
    super.key,
  });

  final Destination destination;
  final Map<String, String> params;

  /// Real content shown above the links, such as the settings control.
  final Widget? extra;

  static Key linkKey(String name) => ValueKey('placeholder-link-$name');

  @override
  Widget build(BuildContext context) {
    final content = _Content(
      destination: destination,
      params: params,
      extra: extra,
    );
    return switch (destination.presentation) {
      Presentation.sheet => _SheetLayout(child: content),
      Presentation.tab => _TabLayout(child: content),
      _ when destination.name == RouteNames.trip => _TripLayout(child: content),
      _ => _PageLayout(child: content),
    };
  }
}

class _TabLayout extends StatelessWidget {
  const _TabLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SpaceTokens.l),
          child: StickerCard(child: child),
        ),
      ),
    );
  }
}

/// A full-screen page with the back control at the top right (FR-019).
class _PageLayout extends StatelessWidget {
  const _PageLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                // Icons.arrow_back mirrors itself, so it points right in RTL.
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.backLabel,
                color: context.tokens.hibr,
                // A page opened on its own has nothing under it.
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  SpaceTokens.l,
                  0,
                  SpaceTokens.l,
                  SpaceTokens.l,
                ),
                child: StickerCard(child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The trip keeps every control in the bottom third, for one-handed play,
/// and has no top-right back control: back opens the pause instead
/// (constitution XI, FR-020).
class _TripLayout extends StatelessWidget {
  const _TripLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(SpaceTokens.l),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 2 * SpaceTokens.l,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [StickerCard(child: child)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sheet content, with a close button at the top right (FR-018).
class _SheetLayout extends StatelessWidget {
  const _SheetLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          SpaceTokens.l,
          SpaceTokens.s,
          SpaceTokens.l,
          SpaceTokens.l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.closeLabel,
                color: context.tokens.hibr,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.destination,
    required this.params,
    required this.extra,
  });

  final Destination destination;
  final Map<String, String> params;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ink = context.tokens.hibr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            destination.title(l10n),
            style: TypeTokens.headline.copyWith(color: ink),
          ),
        ),
        const SizedBox(height: SpaceTokens.s),
        Text(l10n.placeholderNote, style: TypeTokens.body.copyWith(color: ink)),
        for (final MapEntry(:key, :value) in params.entries)
          // Parameters are Latin identifiers; read them left to right.
          Text(
            '$key: $value',
            textDirection: TextDirection.ltr,
            style: TypeTokens.body.copyWith(color: ink),
          ),
        const SizedBox(height: SpaceTokens.s),
        const _SampleNumbers(),
        if (extra case final extra?) ...[
          const SizedBox(height: SpaceTokens.l),
          extra,
        ],
        for (final name in destination.links) ...[
          const SizedBox(height: SpaceTokens.m),
          _Link(from: destination, to: destinationNamed(name)),
        ],
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.from, required this.to});

  final Destination from;
  final Destination to;

  @override
  Widget build(BuildContext context) {
    return SecondaryButton(
      key: PlaceholderScreen.linkKey(to.name),
      label: to.title(AppLocalizations.of(context)),
      onPressed: () => _open(context),
    );
  }

  void _open(BuildContext context) {
    final location = to.location;
    // A tab, or a tab's sheet from a root page, starts over from that tab.
    if (to.presentation == Presentation.tab ||
        (from.section == Section.none && to.section != Section.none)) {
      NavGuard.go(context, location);
    } else if (from.name == RouteNames.trip ||
        (from.presentation == Presentation.sheet &&
            to.presentation == Presentation.page)) {
      // Hand-offs that back should not return to: the pre-trip card to the
      // trip, and the trip to its result.
      NavGuard.pushReplacement(context, location);
    } else {
      NavGuard.push(context, location);
    }
  }
}

/// Shows the digit setting on every placeholder (US3).
class _SampleNumbers extends ConsumerWidget {
  const _SampleNumbers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(numberFormatterProvider);
    return Text(
      AppLocalizations.of(context).sampleNumbers(
        format.integer(1250),
        format.piasters(850),
        format.ratio(4, 5),
        format.countdown(const Duration(seconds: 750)),
      ),
      style: TypeTokens.body.copyWith(color: context.tokens.hibr),
    );
  }
}
