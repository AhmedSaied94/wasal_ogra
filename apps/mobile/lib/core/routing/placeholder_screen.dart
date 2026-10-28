import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
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
    this.footer,
    super.key,
  });

  final Destination destination;
  final Map<String, String> params;

  /// Real content shown above the links, such as the settings control.
  final Widget? extra;

  /// Content shown below the links, such as internal builds' sync card.
  final Widget? footer;

  static Key linkKey(String name) => ValueKey('placeholder-link-$name');

  @override
  Widget build(BuildContext context) {
    final content = _Content(
      destination: destination,
      params: params,
      extra: extra,
      footer: footer,
    );
    final title = destination.title(AppLocalizations.of(context));
    return switch (destination.presentation) {
      Presentation.sheet => _SheetLayout(child: content),
      Presentation.tab => _PageLayout(title: title, child: content),
      _ when destination.name == RouteNames.trip => _TripLayout(child: content),
      _ => _PageLayout(
        title: title,
        // A page opened on its own has nothing under it.
        onBack: () => context.canPop() ? context.pop() : context.go('/home'),
        child: content,
      ),
    };
  }
}

/// A page or a tab on the `ground`: the `ScreenHeader` (with the back
/// control at the top right on a page, M03 FR-019; none on a tab), then the
/// content.
class _PageLayout extends StatelessWidget {
  const _PageLayout({required this.title, required this.child, this.onBack});

  final String title;
  final VoidCallback? onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHeader(title: title, onBack: onBack),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              LayoutTokens.gutter,
              SpaceTokens.s8,
              LayoutTokens.gutter,
              SpaceTokens.s24,
            ),
            child: child,
          ),
        ),
      ],
    ),
  );
}

/// The trip keeps every control in the bottom third, for one-handed play,
/// and has no top-right back control: back opens the pause instead
/// (constitution XI, M03 FR-020).
class _TripLayout extends StatelessWidget {
  const _TripLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(LayoutTokens.gutter),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 2 * LayoutTokens.gutter,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [AppCard(child: child)],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Sheet content. `AppSheet` draws the title and the close button
/// (M03 FR-018).
class _SheetLayout extends StatelessWidget {
  const _SheetLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: SpaceTokens.s8),
    child: child,
  );
}

/// The «still being built» note, the parameters, the sample numbers, any
/// real content, and the links. The title is the header's or the sheet's.
class _Content extends StatelessWidget {
  const _Content({
    required this.destination,
    required this.params,
    required this.extra,
    required this.footer,
  });

  final Destination destination;
  final Map<String, String> params;
  final Widget? extra;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = TypeTokens.body.copyWith(color: ColorTokens.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: SpaceTokens.s12,
      children: [
        EmptyState(message: l10n.placeholderNote),
        for (final MapEntry(:key, :value) in params.entries)
          // Parameters are Latin identifiers; read them left to right.
          Text('$key: $value', textDirection: TextDirection.ltr, style: style),
        const _SampleNumbers(),
        ?extra,
        for (final name in destination.links)
          PlaceholderLink(from: destination, to: destinationNamed(name)),
        ?footer,
      ],
    );
  }
}

/// A link from [from] to [to] as placeholders draw it. Also what tests put
/// in a slot a later feature fills (Home's daily row, M13).
class PlaceholderLink extends StatelessWidget {
  const PlaceholderLink({required this.from, required this.to, super.key});

  final Destination from;
  final Destination to;

  @override
  Widget build(BuildContext context) {
    return AppButton.secondary(
      key: PlaceholderScreen.linkKey(to.name),
      label: to.title(AppLocalizations.of(context)),
      onTap: () => _open(context),
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
      textAlign: TextAlign.center,
      style: TypeTokens.body.copyWith(color: ColorTokens.ink),
    );
  }
}
