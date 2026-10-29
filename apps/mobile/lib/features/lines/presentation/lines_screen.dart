// الخطوط (specs/014-m09-lines-vehicles, contracts/lines.md, HANDOFF
// `Lines`): the balances, the vehicle strip and the line map. Everything
// is local; only the BONAT pill's shop needs the network (FR-015).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/features/lines/application/lines_model.dart';
import 'package:wassal/features/lines/application/lines_seen.dart';
import 'package:wassal/features/lines/domain/line_standing.dart';
import 'package:wassal/features/lines/presentation/line_card.dart';
import 'package:wassal/features/lines/presentation/line_map.dart';
import 'package:wassal/features/lines/presentation/lines_links.dart';
import 'package:wassal/features/lines/presentation/vehicle_strip.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class LinesScreen extends ConsumerStatefulWidget {
  const LinesScreen({super.key});

  static const coinsKey = Key('LinesScreen.coins');
  static const bonatKey = Key('LinesScreen.bonat');

  /// HANDOFF `Lines` block 1: 52 high.
  static const double headerHeight = 52;

  /// The gaps between the header, the strip and the map (y 88–98, 194–204).
  static const double gap = SpaceTokens.s10;

  @override
  ConsumerState<LinesScreen> createState() => _LinesScreenState();
}

class _LinesScreenState extends ConsumerState<LinesScreen> {
  late final _router = ref.read(routerProvider);

  @override
  void initState() {
    super.initState();
    // What Lines shows is seen: on the first frame, on every return to the
    // tab (the screen stays mounted while away), and on every change while
    // Lines or one of its sheets is on top, so a purchase made here raises
    // no dot (research R8).
    WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());
    _router.routerDelegate.addListener(_seenLater);
    ref.listenManual(linesNewsKeysProvider, (_, _) => _seenLater());
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_seenLater);
    super.dispose();
  }

  void _seenLater() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());

  void _markSeen() {
    if (!mounted) return;
    final location = _router.routerDelegate.currentConfiguration.uri.path;
    if (!location.startsWith('/lines')) return;
    ref
        .read(linesSeenProvider.notifier)
        .markSeen(ref.read(linesNewsKeysProvider));
  }

  void _start(String tripId) => unawaited(
    startNextTrip(context, ref, tripId: tripId, from: StartFrom.lines),
  );

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(linesModelProvider);
    final content = ref.watch(contentSourceProvider);
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: ColorTokens.ground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              LayoutTokens.gutter,
              top,
              LayoutTokens.gutter,
              0,
            ),
            child: _Header(model: model),
          ),
          const SizedBox(height: LinesScreen.gap),
          VehicleStrip(tiles: model.tiles),
          const SizedBox(height: LinesScreen.gap),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: LineMap(
                cards: model.cards,
                focus: model.focus,
                cardOf: (standing) => _card(context, content, standing),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    ContentSource content,
    LineStanding standing,
  ) {
    final l10n = AppLocalizations.of(context);
    final state = standing.state;
    final reason = switch (state) {
      LineLocked(reason: NeedsVehicle(:final vehicle)) =>
        l10n.linesNeedsVehicle(content.vehicle(vehicle)?.name.arEg ?? ''),
      LineLocked(reason: AfterLine(:final line)) => l10n.linesAfterLine(
        content.line(line)?.name.arEg ?? '',
      ),
      _ => null,
    };
    // A line behind a vehicle opens that vehicle's sheet; any other card
    // its line's details (contracts/lines.md "Actions").
    final open = switch (state) {
      LineLocked(reason: NeedsVehicle(:final vehicle)) => vehicleLocation(
        vehicle,
      ),
      _ => lineLocation(standing.line),
    };
    return LineCard(
      standing: standing,
      reason: reason,
      onOpen: () => NavGuard.go(context, open),
      onContinue: switch (state) {
        LineCurrent(:final next) => () => _start(next.tripId),
        _ => null,
      },
    );
  }
}

/// «الخطوط» and the coins and BONAT pills (HANDOFF `Lines` block 1). The
/// coins pill isn't a link; the BONAT pill opens the shop when online.
class _Header extends ConsumerWidget {
  const _Header({required this.model});

  final LinesModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final bonat = numbers.integer(model.bonat);
    return Container(
      constraints: const BoxConstraints(minHeight: LinesScreen.headerHeight),
      alignment: AlignmentDirectional.centerStart,
      // The header's whole width, so the pills go to its end.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: SpaceTokens.s8,
          runSpacing: SpaceTokens.s6,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.linesTitle,
                style: TypeTokens.displayL.copyWith(color: ColorTokens.ink),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: SpaceTokens.s6,
              children: [
                CurrencyPill(
                  key: LinesScreen.coinsKey,
                  kind: CurrencyKind.coin,
                  height: CurrencyPill.compactHeight,
                  value: numbers.integer(model.jenehat),
                  semanticLabel: l10n.homeA11yCoins(
                    numbers.integer(model.jenehat),
                  ),
                ),
                if (model.online)
                  CurrencyPill(
                    key: LinesScreen.bonatKey,
                    kind: CurrencyKind.bonat,
                    height: CurrencyPill.compactHeight,
                    value: bonat,
                    onTap: () => NavGuard.go(context, '/shop'),
                    semanticLabel: l10n.homeA11yBonat(bonat),
                  )
                else
                  // The shop needs the network: not a link, and said so.
                  Semantics(
                    button: true,
                    enabled: false,
                    label: l10n.homeA11yBonatOffline(bonat),
                    child: ExcludeSemantics(
                      child: CurrencyPill(
                        key: LinesScreen.bonatKey,
                        kind: CurrencyKind.bonat,
                        height: CurrencyPill.compactHeight,
                        value: bonat,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
