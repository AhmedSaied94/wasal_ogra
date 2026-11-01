// The family's requests (specs/015-m10-apartment-story, contracts/
// apartment.md "Family requests", research R11, HANDOFF `Requests`): the open
// and done ones, done first, and «خد» to take a done one's reward.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/apartment_art.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/progress/domain/requests.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/application/request_claim.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class RequestsSheet extends ConsumerStatefulWidget {
  const RequestsSheet({super.key});

  static const closeKey = Key('RequestsSheet.close');
  static const emptyKey = Key('RequestsSheet.empty');

  static Key rowKey(String requestId) =>
      ValueKey('RequestsSheet.row.$requestId');

  static Key claimKey(String requestId) =>
      ValueKey('RequestsSheet.claim.$requestId');

  @override
  ConsumerState<RequestsSheet> createState() => _RequestsSheetState();
}

/// A row the sheet keeps in its place while its claim is in flight, and while
/// it collapses after the answer.
typedef _Held = ({FamilyRequest request, int place, bool collapsing});

class _RequestsSheetState extends ConsumerState<RequestsSheet> {
  /// The economy drops a claimed request from the list at once, so the sheet
  /// holds its row until the collapse ends.
  final _held = <String, _Held>{};

  Future<void> _claim(FamilyRequest request, int place) async {
    final id = request.requestId;
    if (_held.containsKey(id)) return;
    setState(
      () => _held[id] = (request: request, place: place, collapsing: false),
    );
    final view = ref.read(economyViewProvider);
    var claimed = false;
    try {
      final result = await ref
          .read(requestClaimProvider)
          .claim(
            request,
            progress: ref.read(playerProgressProvider),
            variantOf: view.variantOf,
            requestsClaimed: view.requestsClaimed,
          );
      claimed = result is RequestClaimed;
    } finally {
      if (mounted) {
        setState(() {
          if (claimed) {
            _held[id] = (request: request, place: place, collapsing: true);
          } else {
            _held.remove(id);
          }
        });
      }
    }
    if (!mounted || !claimed) return;
    final l10n = AppLocalizations.of(context);
    final reward = ref
        .read(numberFormatterProvider)
        .integer(request.rewardBonat);
    final offline = ref.read(serverStatusProvider).reach == Reach.offline;
    showAppToast(
      context,
      offline
          ? l10n.requestsClaimToastOffline(reward)
          : l10n.requestsClaimToast(reward),
    );
  }

  void _gone(String requestId) {
    if (!mounted) return;
    setState(() => _held.remove(requestId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = ref.watch(contentSourceProvider);
    final numbers = ref.watch(numberFormatterProvider);
    final progress = ref.watch(playerProgressProvider);
    final view = ref.watch(economyViewProvider);
    final listed = <(FamilyRequest, RequestState)>[
      for (final (request, state) in requestStates(
        content,
        progress,
        view.variantOf,
        view.requestsClaimed,
      ))
        if ((state == RequestState.open || state == RequestState.done) &&
            !_held.containsKey(request.requestId))
          (request, state),
    ];
    // A row being taken stays where it was.
    final held = _held.values.toList()..sort((a, b) => a.place - b.place);
    for (final row in held) {
      listed.insert(row.place < listed.length ? row.place : listed.length, (
        row.request,
        RequestState.done,
      ));
    }
    final rows = <Widget>[
      for (var i = 0; i < listed.length; i++)
        _CollapsingRow(
          key: RequestsSheet.rowKey(listed[i].$1.requestId),
          collapsing: _held[listed[i].$1.requestId]?.collapsing ?? false,
          onGone: () => _gone(listed[i].$1.requestId),
          child: _RequestRow(
            request: listed[i].$1,
            done: listed[i].$2 == RequestState.done,
            content: content,
            numbers: numbers,
            onClaim: _held.containsKey(listed[i].$1.requestId)
                ? null
                : () => unawaited(_claim(listed[i].$1, i)),
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s2),
      child: ConstrainedBox(
        // The board's sheet is 620 high whatever it lists.
        constraints: const BoxConstraints(
          minHeight: DesignExtras.requestsSheetHeight - _sheetChrome,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: SpaceTokens.s14),
            _Header(
              title: l10n.requestsTitle,
              subtitle: l10n.requestsSubtitle,
              closeLabel: l10n.closeLabel,
            ),
            const SizedBox(height: SpaceTokens.s12),
            if (rows.isEmpty)
              _EmptyCard(
                key: RequestsSheet.emptyKey,
                message: l10n.requestsEmpty,
              )
            else
              Flexible(
                child: SingleChildScrollView(child: Column(children: rows)),
              ),
          ],
        ),
      ),
    );
  }

  /// The sheet's grabber (8 + 5) and its bottom padding (14) around the
  /// child, so the child's least height makes the whole 620.
  static const double _sheetChrome = 8 + 5 + 14;
}

/// The title over its line, and ✕ at the end (`Requests` block 1).
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.closeLabel,
  });

  final String title;
  final String subtitle;
  final String closeLabel;

  @override
  Widget build(BuildContext context) => Row(
    spacing: SpaceTokens.s12,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: SpaceTokens.s2,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: DesignExtras.requestsTitle.copyWith(
                  color: ColorTokens.ink,
                ),
              ),
            ),
            Text(
              subtitle,
              style: DesignExtras.requestsSubtitle.copyWith(
                color: ColorTokens.inkMuted,
              ),
            ),
          ],
        ),
      ),
      IconCircleButton(
        key: RequestsSheet.closeKey,
        icon: 'close',
        semanticLabel: closeLabel,
        inSheet: true,
        onTap: () => unawaited(Navigator.of(context).maybePop()),
      ),
    ],
  );
}

/// One row, closing its height and fading over 200 ms once [collapsing]
/// (the toast's timing); under reduced motion it only fades.
class _CollapsingRow extends StatefulWidget {
  const _CollapsingRow({
    required this.collapsing,
    required this.onGone,
    required this.child,
    super.key,
  });

  final bool collapsing;
  final VoidCallback onGone;
  final Widget child;

  @override
  State<_CollapsingRow> createState() => _CollapsingRowState();
}

class _CollapsingRowState extends State<_CollapsingRow>
    with SingleTickerProviderStateMixin {
  // `preserve`: under reduced motion it still takes its 200 ms, as a fade.
  late final _factor = AnimationController(
    vsync: this,
    value: 1,
    duration: MotionTokens.toast,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void initState() {
    super.initState();
    if (widget.collapsing) _start();
  }

  @override
  void didUpdateWidget(_CollapsingRow old) {
    super.didUpdateWidget(old);
    if (widget.collapsing && !old.collapsing) _start();
  }

  void _start() => unawaited(
    _factor.reverse().whenComplete(() {
      if (mounted) widget.onGone();
    }),
  );

  @override
  void dispose() {
    _factor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _factor,
      curve: MotionTokens.toastCurve,
    );
    final faded = FadeTransition(opacity: curved, child: widget.child);
    if (MediaQuery.disableAnimationsOf(context)) return faded;
    return SizeTransition(sizeFactor: curved, child: faded);
  }
}

/// `Requests` 2a and 2b: the asker's face, what they said and what it takes,
/// and, once the piece is in, «خد».
class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.done,
    required this.content,
    required this.numbers,
    required this.onClaim,
  });

  final FamilyRequest request;
  final bool done;
  final ContentSource content;
  final NumberFormatter numbers;

  /// Null while the row is leaving.
  final VoidCallback? onClaim;

  String _condition(AppLocalizations l10n) {
    final item = content.item(request.itemId);
    final itemName = item?.name.arEg ?? request.itemId;
    final wanted = request.variantId;
    if (wanted == null) return l10n.requestCondition(itemName);
    final variant = item?.variants
        .where((v) => v.variantId == wanted)
        .firstOrNull;
    return l10n.requestConditionVariant(itemName, variant?.name.arEg ?? wanted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asker = l10n.sceneSpeaker(storyCharacterArt(request.character));
    final reward = numbers.integer(request.rewardBonat);
    final condition = _condition(l10n);
    final text = request.text.arEg;
    final gap = done ? DesignExtras.requestLineGapDone : SpaceTokens.s4;
    final lines = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: gap,
      children: [
        Text(
          asker,
          style: DesignExtras.requestAsker.copyWith(color: ColorTokens.ink2),
        ),
        Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DesignExtras.requestText.copyWith(color: ColorTokens.ink),
        ),
        if (done)
          Text(
            l10n.requestsDone(reward),
            style: DesignExtras.requestStatus.copyWith(
              color: ColorTokens.primary,
            ),
          )
        else
          Row(
            spacing: SpaceTokens.s8,
            children: [
              Expanded(
                child: Text(
                  condition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignExtras.requestAsker.copyWith(
                    color: ColorTokens.ink,
                  ),
                ),
              ),
              Text(
                l10n.requestsReward(reward),
                style: DesignExtras.requestStatus.copyWith(
                  color: ColorTokens.ink,
                ),
              ),
            ],
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignExtras.requestRowGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: done ? ColorTokens.sunSoft : ColorTokens.ground,
          borderRadius: BorderRadius.circular(RadiusTokens.l),
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignExtras.requestRowPadding),
          child: Row(
            spacing: SpaceTokens.s12,
            children: [
              ExcludeSemantics(
                child: _Face(
                  character: storyCharacterArt(request.character),
                  happy: done,
                ),
              ),
              Expanded(
                child: Semantics(
                  container: true,
                  label: l10n.requestsRowA11y(asker, text, condition, reward),
                  child: ExcludeSemantics(child: lines),
                ),
              ),
              if (done)
                AppButton.primary(
                  key: RequestsSheet.claimKey(request.requestId),
                  label: l10n.requestsClaim,
                  size: AppButtonSize.compact,
                  expand: false,
                  height: LayoutTokens.touchMin,
                  radius: RadiusTokens.tray,
                  sidePadding: DesignExtras.requestClaimInset,
                  labelStyle: DesignExtras.requestClaimLabel,
                  onTap: onClaim,
                  enabled: onClaim != null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The asker's face: a circle of 52 on `paper`, the head cropped in.
class _Face extends StatelessWidget {
  const _Face({required this.character, required this.happy});

  final String character;
  final bool happy;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: DesignExtras.requestAvatar,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: ColorTokens.paper,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: FittedBox(
          fit: BoxFit.cover,
          child: CharacterAvatar(character, happy: happy),
        ),
      ),
    ),
  );
}

/// Nothing open or waiting (`RequestsEmpty` 13 to 15): a ringed card with the
/// tea tray over one line.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(DesignExtras.dialogPadding),
    decoration: BoxDecoration(
      color: ColorTokens.paper,
      borderRadius: BorderRadius.circular(RadiusTokens.xl),
      border: RingTokens.locked.border,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: SpaceTokens.s10,
      children: [
        ExcludeSemantics(
          child: SvgPicture.asset(
            ApartmentArt.teaTray,
            width: DesignExtras.requestsEmptyArt.width,
            height: DesignExtras.requestsEmptyArt.height,
          ),
        ),
        Text(
          message,
          textAlign: TextAlign.center,
          style: DesignExtras.requestsEmptyText.copyWith(
            color: ColorTokens.ink,
          ),
        ),
      ],
    ),
  );
}
